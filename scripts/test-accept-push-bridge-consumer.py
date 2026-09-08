#!/usr/bin/env python3
"""Offline stateful broker fixtures: never evidence of actual broker delivery."""
from collections import deque
from concurrent.futures import Future
from contextlib import ExitStack
import importlib.util
import json
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

FILE = Path(__file__).resolve().with_name("accept-push-bridge-consumer.py")
spec = importlib.util.spec_from_file_location("consumer_acceptance", FILE)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)
import bridge
import delivery_settlement
import amqp_management


class FastEvent:
    """Shorten polling only; independent retry and lease clocks stay real."""
    def __init__(self): self.event = threading.Event()
    def set(self): self.event.set()
    def is_set(self): return self.event.is_set()
    def wait(self, timeout=None): return self.event.wait(min(timeout, .002) if timeout else timeout)


class InlineExecutor:
    def __init__(self, **_kwargs): pass
    def submit(self, fn, body):
        future = Future()
        try: future.set_result(fn(body))
        except BaseException as error: future.set_exception(error)
        return future
    def shutdown(self, **_kwargs): pass


class Broker:
    """AMQP queue ownership, prefetch, manual dispositions and redelivery."""
    def __init__(self, fault=None):
        self.lock = threading.RLock()
        self.work, self.dead = deque(), deque()
        self.connections, self.settlements, self.consumes, self.gets = [], [], [], []
        self.fault, self.reconnected, self.first_nack = fault, False, False
        self.swallowed = 0

    def connect(self, *args, **kwargs):
        assert args[0] == "127.0.0.1" and kwargs["virtual_host"].startswith("kz5-retry-proof-")
        assert kwargs.get("port") == 5672
        connection = Connection(self)
        self.connections.append(connection)
        return connection


class Connection:
    def __init__(self, broker):
        self.broker, self.owner = broker, threading.get_ident()
        self.is_open, self.channels = True, []
    def channel(self):
        assert self.owner == threading.get_ident()
        channel = Channel(self); self.channels.append(channel); return channel
    def close(self):
        assert self.owner == threading.get_ident()
        for channel in self.channels: channel.close()
        self.is_open = False


class Message:
    def __init__(self, channel, record):
        self.channel, self.record, self.body = channel, record, record["body"]
        self.redelivered = record["count"] > 0
        self.properties = {} if not record["count"] else {"headers": {"x-delivery-count": record["count"]}}
        if channel.broker.fault == "counter" and self.redelivered: self.properties = {}
        if channel.broker.fault in ("body", "swallowed"): self.body = "unrecognized synthetic body"
        channel.pending.append(self)
    def settle(self, action, requeue=None):
        channel, broker = self.channel, self.channel.broker
        assert channel.owner == threading.get_ident()
        with broker.lock:
            if broker.fault == "lost_ack" and action == "ack": return
            channel.pending.remove(self)
            broker.settlements.append((action, self.record["count"], requeue, threading.get_ident()))
            if action == "nack" and requeue:
                broker.first_nack = True
                self.record["count"] += 1
                broker.work.append(self.record)
            elif action != "ack":
                broker.dead.append(self.record)
    def ack(self): self.settle("ack")
    def nack(self, requeue=True): self.settle("nack", requeue)
    def reject(self, requeue=True): self.settle("reject", requeue)


class Channel:
    def __init__(self, connection):
        self.connection, self.broker, self.owner = connection, connection.broker, connection.owner
        self.basic = self.queue = self.exchange = self
        self.is_open, self.pending, self.callback, self.prefetch = True, [], None, 0
    def declare(self, **kwargs):
        assert self.owner == threading.get_ident()
        if "queue" in kwargs:
            with self.broker.lock:
                records = self.broker.dead if kwargs["queue"].endswith(".dlq") else self.broker.work
                return {"message_count": len(records)}
        return {}
    def bind(self, **_kwargs): pass
    def confirm_deliveries(self): pass
    def qos(self, prefetch_count): self.prefetch = prefetch_count
    def consume(self, callback, queue, no_ack):
        assert self.owner == threading.get_ident() and self.prefetch == 2 and no_ack is False
        self.callback = callback
        self.broker.consumes.append((queue, no_ack, self.owner))
        return "synthetic-consumer-tag"
    def publish(self, body, exchange, routing_key, properties):
        assert self.owner == threading.get_ident()
        assert exchange == "fixture.pushes" and routing_key == "fixture.only" and properties == {"delivery_mode": 2}
        if self.broker.fault == "unconfirmed": return False
        with self.broker.lock: self.broker.work.append({"body": body, "count": 0})
        return True
    def get(self, queue, no_ack):
        assert self.owner == threading.get_ident() and queue.endswith(".dlq") and no_ack is False
        self.broker.gets.append(queue)
        with self.broker.lock:
            return Message(self, self.broker.dead.popleft()) if self.broker.dead else None
    def process_data_events(self, to_tuple):
        assert self.owner == threading.get_ident() and to_tuple is False
        if self.broker.fault == "reconnect" and not self.broker.reconnected:
            self.broker.reconnected = True
            raise RuntimeError("synthetic one-time connection loss")
        while True:
            with self.broker.lock:
                if not self.broker.work or len(self.pending) >= self.prefetch: return
                record = self.broker.work[0]
                if (self.broker.fault == "companion_late" and not self.broker.first_nack and
                        json.loads(record["body"])["Call-ID"].endswith("-companion")):
                    return
                message = Message(self, self.broker.work.popleft())
            try: self.callback(message)
            except Exception:
                if self.broker.fault != "swallowed": raise
                self.broker.swallowed += 1
    def close(self):
        assert self.owner == threading.get_ident()
        with self.broker.lock:
            for message in list(self.pending):
                self.pending.remove(message)
                message.record["count"] += 1
                self.broker.work.append(message.record)
        self.is_open = False


class ConsumerCases(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(socket, "create_connection", side_effect=AssertionError("offline sockets forbidden")))
        self.stack.enter_context(patch.object(harness.proof.subprocess, "run", side_effect=AssertionError("offline subprocess forbidden")))
        self.stack.enter_context(patch.object(bridge.BridgeRuntime, "__init__", side_effect=AssertionError("credential construction forbidden")))
        self.stack.enter_context(patch.object(bridge.BridgeRuntime, "start_self_watchdog"))
        self.stack.enter_context(patch.object(bridge, "log", Mock()))
        self.stack.enter_context(patch.object(delivery_settlement, "DELAYS_MS", (40, 80)))
        self.stack.enter_context(patch.object(harness, "threading", SimpleNamespace(
            Event=FastEvent, Thread=threading.Thread, get_ident=threading.get_ident)))
        self.verify = self.stack.enter_context(patch.object(amqp_management, "verify_topology", return_value=True))

    def fixture(self, fault=None):
        identity = "kz5-retry-proof-11111111-1111-4111-8111-111111111111"
        settings = {"TOPOLOGY": "quorum-v1", "RETRY": "quorum-counted-v1", "FRESHNESS": "unix-ms-v1",
            "AMQP_HOST": "127.0.0.1", "AMQP_PORT": 5672, "AMQP_USER": identity, "AMQP_PASS": "synthetic-only",
            "AMQP_VHOST": identity, "AMQP_MANAGEMENT_URL": "http://127.0.0.1:15672",
            "EXCHANGE": "fixture.pushes", "QUEUE": "fixture.mobile.quorum-v1", "BINDING_KEY": "fixture.only"}
        broker = Broker(fault)
        self.stack.enter_context(patch.dict(sys.modules, {"amqpstorm": SimpleNamespace(
            Connection=broker.connect, AMQPChannelError=RuntimeError)}))
        connection = broker.connect("127.0.0.1", identity, "synthetic-only", virtual_host=identity, port=5672)
        receipt = {"owner": identity, "checks": [], "counter_observations": [], "provider_calls": 0}
        driver = harness.ConsumerProof(connection, settings, RuntimeError, self.verify, receipt)
        driver.limit = time.monotonic() + 1.0
        self.addCleanup(connection.close)
        return driver, broker, receipt

    def test_real_runtime_loop_and_settlements_with_stateful_offline_broker(self):
        driver, broker, receipt = self.fixture(); driver.run()
        self.assertTrue(receipt["registered_consumer_tested"])
        self.assertTrue(receipt["consumer_source_stable"])
        self.assertEqual({Path(name).name for name in receipt["consumer_source_sha256"]},
                         {"accept-push-bridge-consumer.py", "accept-push-bridge-retry.py", "bridge.py",
                          "push_payload.py", "service_notify.py"})
        self.assertEqual(receipt["consumer_counters"], {"retry-success": [0, 1], "companion": [0], "exhaustion": [0, 1, 2]})
        self.assertEqual(driver.dispatches, {"retry-success": 2, "companion": 1, "exhaustion": 3})
        self.assertEqual(len(broker.consumes), 1)
        self.assertTrue(broker.gets and all(name.endswith(".dlq") for name in broker.gets))
        self.assertEqual(receipt["work_queue_basic_get_calls"], 0)
        self.assertGreaterEqual(self.verify.call_count, 2)
        self.assertFalse(broker.connections[-1].is_open)
        self.assertEqual({record[3] for record in broker.settlements if record[0] == "nack"}, {driver.owner})
        self.assertNotEqual(driver.owner, threading.get_ident())

    def test_consumer_uses_production_tls_builder_for_its_settings(self):
        driver, _broker, receipt = self.fixture()
        driver.settings['AMQP_TLS'] = 'true'
        with patch.object(harness, 'amqp_tls_options', return_value={'ssl': True}) as options:
            driver.run()
        self.assertTrue(receipt['registered_consumer_tested'])
        options.assert_called_once()
        self.assertEqual(options.call_args.args[0]['AMQP_TLS'], 'true')

    def test_faults_cannot_produce_acceptance(self):
        for fault in ("counter", "body", "unconfirmed", "reconnect", "companion_late", "lost_ack"):
            with self.subTest(fault=fault):
                driver, broker, receipt = self.fixture(fault)
                with self.assertRaises(harness.proof.ProofFailure): driver.run()
                self.assertFalse(receipt["registered_consumer_tested"])
                self.assertTrue(all(not item.is_open for item in broker.connections[1:]))

    def test_swallowed_callback_failure_reaches_bounded_deadline(self):
        driver, broker, receipt = self.fixture("swallowed")
        with self.assertRaises(harness.proof.ProofFailure) as caught: driver.run()
        self.assertEqual(caught.exception.code, "consumer_case_deadline")
        self.assertGreater(broker.swallowed, 0)
        self.assertFalse(receipt["registered_consumer_tested"])

    def test_worker_on_owner_thread_is_rejected(self):
        driver, _broker, receipt = self.fixture()
        with patch.object(bridge, "ThreadPoolExecutor", InlineExecutor):
            with self.assertRaises(harness.proof.ProofFailure): driver.run()
        self.assertFalse(receipt["registered_consumer_tested"])
        self.assertEqual(driver.dispatches, {})

    def test_wrong_prefetch_is_not_accepted(self):
        original = bridge.BridgeRuntime.run
        def wrong(runtime, **kwargs):
            runtime._settings["WORKERS"] = 2
            return original(runtime, **kwargs)
        driver, broker, receipt = self.fixture()
        with patch.object(bridge.BridgeRuntime, "run", wrong):
            with self.assertRaises(harness.proof.ProofFailure): driver.run()
        self.assertFalse(receipt["registered_consumer_tested"])
        self.assertEqual(broker.consumes, [])

    def test_wrong_wire_disposition_cannot_be_accepted(self):
        original = bridge.OwnerSettlements
        class WrongNack(original):
            def submit(self, executor, worker, message, body, **kwargs):
                real_nack = message.nack
                message.nack = lambda requeue=True: real_nack(requeue=False)
                return super().submit(executor, worker, message, body, **kwargs)
        driver, broker, receipt = self.fixture()
        with patch.object(bridge, "OwnerSettlements", WrongNack):
            with self.assertRaises(harness.proof.ProofFailure): driver.run()
        self.assertTrue(any(record[:3] == ("nack", 0, False) for record in broker.settlements))
        self.assertFalse(receipt["registered_consumer_tested"])

    def test_every_additional_consumed_source_is_repinned(self):
        for name in ("accept-push-bridge-consumer.py", "accept-push-bridge-retry.py", "bridge.py", "push_payload.py", "service_notify.py"):
            with self.subTest(source=name):
                driver, _broker, receipt = self.fixture()
                original, reads = Path.read_bytes, []
                def changed(file):
                    value = original(file)
                    if file.name == name:
                        reads.append(file)
                        if len(reads) > 1: return value + b"\nsynthetic source drift\n"
                    return value
                with patch.object(Path, "read_bytes", changed):
                    with self.assertRaises(harness.proof.ProofFailure) as caught: driver.run()
                self.assertEqual(caught.exception.code, "consumer_source_changed")
                self.assertFalse(receipt["registered_consumer_tested"])

    def test_explicit_flag_and_notify_boundary_before_reused_main(self):
        for argv, notify in (([], ""), (["--run-isolated-local-proof"], ""),
                             (["--run-isolated-local-consumer-proof"], "/synthetic/socket")):
            with patch.dict(harness.os.environ, {"NOTIFY_SOCKET": notify}), patch.object(harness.proof, "main") as main:
                with self.assertRaises(harness.proof.ProofFailure): harness.main(argv)
                main.assert_not_called()
        with patch.dict(harness.os.environ, {"NOTIFY_SOCKET": ""}), patch.object(harness.proof, "main") as main:
            harness.main(["--run-isolated-local-consumer-proof"])
            main.assert_called_once_with(["--run-isolated-local-proof"])
            self.assertIs(harness.proof.RetryProof, harness.ConsumerProof)

    def test_actual_reused_main_rejects_non_root_before_any_broker_work(self):
        with patch.dict(harness.os.environ, {"NOTIFY_SOCKET": ""}), patch.object(harness.os, "geteuid", return_value=1000):
            with self.assertRaises(harness.proof.ProofFailure) as caught:
                harness.main(["--run-isolated-local-consumer-proof"])
        self.assertEqual(caught.exception.code, "explicit_root_development_proof_required")

    def test_actual_reused_main_records_consumer_failure_and_exact_cleanup(self):
        # Execute the original setup/finally/receipt flow against fake control
        # and transport, redirecting only its protected receipt parent.
        _driver, broker, _receipt = self.fixture()
        with tempfile.TemporaryDirectory(prefix="consumer-receipt-fixture-") as temporary:
            parent = Path(temporary); commands = []
            def path(value): return parent if value == "/var/log/kazoo-acceptance" else Path(value)
            def control(args, _receipt, save): commands.append(args); save()
            with patch.dict(harness.os.environ, {"NOTIFY_SOCKET": ""}), \
                    patch.object(harness.os, "geteuid", return_value=0), \
                    patch.object(harness.proof, "Path", path), \
                    patch.object(harness.proof, "control_command", control), \
                    patch.object(harness.ConsumerProof, "run", side_effect=harness.proof.ProofFailure("consumer_source_changed")), \
                    patch("builtins.print"):
                with self.assertRaises(harness.proof.ProofFailure):
                    harness.main(["--run-isolated-local-consumer-proof"])
            receipt_file, = parent.glob("*/receipt.json")
            receipt = json.loads(receipt_file.read_text())
            self.assertFalse(receipt["complete"])
            self.assertEqual(receipt["failure"], "consumer_source_changed")
            self.assertEqual(receipt["created"], ["vhost", "user"])
            self.assertEqual(receipt["removed"], ["vhost", "user"])
            self.assertEqual(commands[-2:], [("delete_vhost", receipt["owner"]), ("delete_user", receipt["owner"])])
            self.assertTrue(harness.proof.RESOURCE.fullmatch(receipt["owner"]))
            self.assertTrue(receipt["source_stable"])
            self.assertTrue(all(not connection.is_open for connection in broker.connections[1:]))


if __name__ == "__main__":
    unittest.main()
