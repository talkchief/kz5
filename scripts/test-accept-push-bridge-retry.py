#!/usr/bin/env python3
"""Offline acceptance-driver fixtures; simulated broker is NOT broker proof."""
from concurrent.futures import Future
import importlib.util
from pathlib import Path
import json
import socket
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

FILE = Path(__file__).resolve().with_name("accept-push-bridge-retry.py")
spec = importlib.util.spec_from_file_location("retry_acceptance", FILE)
proof = importlib.util.module_from_spec(spec); spec.loader.exec_module(proof)


class Clock:
    def __init__(self): self.value = 0.0
    def monotonic(self): return self.value
    def wall_ms(self): return 1000000 + int(self.value * 1000)
    def sleep(self, seconds): self.value += seconds


class Executor:
    """Synchronous join of a separate fixture thread, never a provider worker."""
    def __init__(self, **_kwargs): pass
    def __enter__(self): return self
    def __exit__(self, *_args): pass
    def submit(self, fn, body):
        future = Future()
        def execute():
            try: future.set_result(fn(body))
            except BaseException as error: future.set_exception(error)
        thread = threading.Thread(target=execute)
        thread.start(); thread.join(timeout=2)
        if thread.is_alive(): raise AssertionError("fixture worker did not finish")
        return future


class Broker:
    def __init__(self):
        self.work, self.dead, self.channels = [], [], []
        self.strip_counter = False
        self.reset_on_close = False
        self.lost_nack = False
        self.confirm = True
        self.nacks = 0

    def channel(self):
        channel = Channel(self); self.channels.append(channel); return channel


class Message:
    def __init__(self, channel, record):
        self.channel, self.record = channel, record
        self.body = record["body"]
        self.redelivered = record["redelivered"]
        self.properties = {} if record["count"] == 0 or channel.broker.strip_counter else {
            "headers": {"x-delivery-count": record["count"]}}
        channel.pending.append(self)

    def ack(self): self.channel.pending.remove(self)
    def nack(self, requeue=True):
        assert requeue is True
        self.channel.broker.nacks += 1
        if self.channel.broker.lost_nack: raise RuntimeError("fixture-private-nack")
        self.channel.pending.remove(self)
        self.record["count"] += 1; self.record["redelivered"] = True
        self.channel.broker.work.append(self.record)
    def reject(self, requeue=True):
        assert requeue is False
        self.channel.pending.remove(self); self.channel.broker.dead.append(self.record)


class Channel:
    def __init__(self, broker):
        self.broker, self.pending = broker, []
        self.basic = self
        self.queue = self
        self.is_open = True
    def confirm_deliveries(self): pass
    def qos(self, prefetch_count): assert prefetch_count == 2
    def publish(self, body, exchange, routing_key, properties):
        assert exchange == "fixture.pushes" and routing_key == "fixture.only" and properties == {"delivery_mode": 2}
        if not self.broker.confirm: return False
        self.broker.work.append({"body": body, "count": 0, "redelivered": False}); return True
    def get(self, queue, no_ack):
        assert no_ack is False
        records = self.broker.dead if queue.endswith(".dlq") else self.broker.work
        return Message(self, records.pop(0)) if records else None
    def declare(self, queue, passive):
        assert passive is True
        return {"message_count": len(self.broker.dead if queue.endswith(".dlq") else self.broker.work)}
    def close(self):
        self.is_open = False
        for message in list(self.pending):
            self.pending.remove(message)
            message.record["count"] = 0 if self.broker.reset_on_close else message.record["count"] + 1
            message.record["redelivered"] = True; self.broker.work.append(message.record)


def fixture():
    identity = "kz5-retry-proof-11111111-1111-4111-8111-111111111111"
    settings = {"TOPOLOGY": "quorum-v1", "RETRY": "quorum-counted-v1", "FRESHNESS": "unix-ms-v1",
                "AMQP_HOST": "127.0.0.1", "AMQP_PORT": 5672, "AMQP_USER": identity, "AMQP_PASS": "fixture-only",
                "AMQP_VHOST": identity, "AMQP_MANAGEMENT_URL": "http://127.0.0.1:15672",
                "EXCHANGE": "fixture.pushes", "QUEUE": "fixture.mobile.quorum-v1", "BINDING_KEY": "fixture.only"}
    receipt = {"owner": identity, "checks": [], "counter_observations": [], "provider_calls": 0}
    broker, clock, verify = Broker(), Clock(), Mock(return_value=True)
    driver = proof.RetryProof(broker, settings, RuntimeError, verify, receipt, monotonic=clock.monotonic,
                             wall_ms=clock.wall_ms, sleep=clock.sleep, executor_factory=Executor)
    def configure(connection, actual, _error, verification):
        assert connection is broker and actual == settings
        if verification(actual, proof.plan(actual)) is not True: raise RuntimeError("fixture verification failed")
        return connection.channel()
    return driver, broker, clock, receipt, verify, configure


class AcceptanceDriverTests(unittest.TestCase):
    def setUp(self):
        self.network = patch.object(socket, "create_connection", side_effect=AssertionError("offline sockets forbidden"))
        self.network.start(); self.addCleanup(self.network.stop)
        self.process = patch.object(proof.subprocess, "run", side_effect=AssertionError("offline brokerctl forbidden"))
        self.process.start(); self.addCleanup(self.process.stop)

    def test_entire_synthetic_case_driver_and_exact_counter_expectations(self):
        driver, broker, clock, receipt, verify, configure = fixture()
        with patch.object(proof, "configure", configure): driver.run()
        self.assertEqual(len(receipt["checks"]), 4)
        self.assertEqual(receipt["synthetic_dispatches"], {"retry-success": 2, "companion": 1, "exhaustion": 3, "channel-close": 2})
        self.assertEqual([row["counter"] for row in receipt["counter_observations"]], [None, None, 1, None, 1, 2, None, 1, 2, None])
        self.assertEqual([row["redelivered"] for row in receipt["counter_observations"]], [False, False, True, False, True, True, False, True, True, False])
        self.assertEqual(broker.work, []); self.assertEqual(broker.dead, []); self.assertEqual(broker.nacks, 4)
        self.assertTrue(all(not c.pending for c in broker.channels)); self.assertEqual(verify.call_count, 2)
        self.assertEqual(receipt["provider_calls"], 0); self.assertGreaterEqual(clock.value, 11)
        self.assertLess(clock.value, 20)

    def test_counter_reset_missing_redelivery_header_and_unconfirmed_publish_fail(self):
        for fault in ("strip_counter", "reset_on_close", "confirm"):
            driver, broker, _clock, receipt, _verify, configure = fixture()
            setattr(broker, fault, fault != "confirm")
            with patch.object(proof, "configure", configure), self.assertRaises(proof.ProofFailure): driver.run()
            self.assertNotIn("synthetic_dispatches", receipt)

    def test_uncertain_nack_stops_once_without_repeating_disposition(self):
        driver, broker, _clock, _receipt, _verify, configure = fixture(); broker.lost_nack = True
        with patch.object(proof, "configure", configure), self.assertRaises(Exception): driver.run()
        self.assertEqual(broker.nacks, 1)

    def test_unverified_channel_never_publishes_or_dispatches(self):
        driver, broker, _clock, _receipt, verify, configure = fixture(); verify.return_value = False
        with patch.object(proof, "configure", configure), self.assertRaises(Exception): driver.run()
        self.assertEqual(broker.channels, []); self.assertEqual(driver.dispatches, {})

    def test_receive_and_drain_deadlines_are_bounded(self):
        driver, _broker, clock, _receipt, _verify, configure = fixture()
        with patch.object(proof, "configure", configure): driver.open_channel()
        with self.assertRaises(proof.ProofFailure): driver.receive(driver.wanted.work_queue, "never published")
        self.assertLessEqual(clock.value, 10.1)
        owner = Mock(pending_count=1)
        with self.assertRaises(proof.ProofFailure): driver.drain(owner)
        self.assertLessEqual(clock.value, 22.2)

    def test_cleanup_only_own_created_exact_uuid_resources_even_after_partial_failure(self):
        identity = fixture()[3]["owner"]
        for created in ([], ["vhost"], ["vhost", "user"]):
            ctl = Mock(); removed, failed = proof.cleanup_created(ctl, identity, created)
            self.assertEqual(removed, created); self.assertEqual(failed, [])
            self.assertEqual(ctl.call_args_list, [unittest.mock.call("delete_" + kind, identity) for kind in created])
        ctl = Mock(side_effect=[RuntimeError("fixture-private-failure"), None])
        removed, failed = proof.cleanup_created(ctl, identity, ["vhost", "user"])
        self.assertEqual(removed, ["user"]); self.assertEqual(failed, ["vhost"]); self.assertEqual(ctl.call_count, 2)
        for bad in ("/", "guest", "production", identity + "/other", "kz5-retry-proof-not-a-uuid"):
            ctl = Mock()
            with self.assertRaises(proof.ProofFailure): proof.cleanup_created(ctl, bad, ["vhost", "user"])
            ctl.assert_not_called()
        for created in (["vhost", "vhost"], ["queue"], ["all"], "vhost"):
            ctl = Mock()
            with self.assertRaises(proof.ProofFailure): proof.cleanup_created(ctl, identity, created)
            ctl.assert_not_called()

    def test_cli_requires_explicit_flag_and_root_before_resource_setup(self):
        for argv, uid in (([], 0), (["--run-isolated-local-proof"], 1000), (["--broker", "remote"], 0)):
            with patch.object(proof.os, "geteuid", return_value=uid), \
                    patch.object(proof.Path, "mkdir", side_effect=AssertionError("no setup expected")), \
                    self.assertRaises(proof.ProofFailure):
                proof.main(argv)

    def test_control_failure_records_exact_step_and_only_allowlisted_diagnostics(self):
        secret = "SYNTHETIC_TEMP_PASSWORD_MUST_NOT_BE_RECORDED"
        receipt, snapshots = {}, []
        def save(): snapshots.append(json.loads(json.dumps(receipt)))
        def run(argv, **kwargs):
            self.assertEqual(argv, ["/usr/sbin/rabbitmqctl", "-q", "add_user", "fixture-user", secret])
            self.assertEqual(kwargs["timeout"], 30); self.assertFalse(kwargs["check"])
            self.assertEqual(snapshots[-1]["broker_commands"][0]["status"], "RUNNING")
            return SimpleNamespace(returncode=64, stdout=b"", stderr=("invalid option " + secret).encode())
        with self.assertRaises(proof.ProofFailure): proof.control_command(("add_user", "fixture-user", secret), receipt, save, run)
        self.assertEqual(receipt["broker_commands"], [{"command": "add_user", "status": "FAILED", "returncode": 64,
                                                      "output_category": "command_syntax"}])
        self.assertEqual(len(snapshots), 2); self.assertNotIn(secret, json.dumps(receipt))
        proof.control_command(("delete_vhost", "fixture-vhost"), receipt, save,
                              Mock(return_value=SimpleNamespace(returncode=0, stdout=b"", stderr=b"")))
        self.assertEqual([row["command"] for row in receipt["broker_commands"]], ["add_user", "delete_vhost"])
        self.assertEqual(receipt["broker_commands"][0]["status"], "FAILED")

    def test_control_exception_timeout_and_unknown_output_never_retain_private_text(self):
        secret = "SYNTHETIC_TEMP_PASSWORD_MUST_NOT_BE_RECORDED"
        errors = ((RuntimeError(secret), "LOCAL_ERROR", "local_execution"),
                  (proof.subprocess.TimeoutExpired(["rabbitmqctl", "add_user", secret], 30,
                                                   output=secret.encode(), stderr=secret.encode()), "TIMED_OUT", "deadline"))
        for error, status, category in errors:
            receipt = {}
            with self.assertRaises(proof.ProofFailure) as caught:
                proof.control_command(("add_user", "fixture-user", secret), receipt, Mock(), Mock(side_effect=error))
            self.assertEqual(str(caught.exception), "isolated_retry_proof_failed")
            self.assertEqual(receipt["broker_commands"][0]["status"], status)
            self.assertEqual(receipt["broker_commands"][0]["output_category"], category)
            self.assertNotIn(secret, json.dumps(receipt))
        for code in (1, -9, True, "secret", 999999):
            receipt = {}
            with self.assertRaises(proof.ProofFailure):
                proof.control_command(("add_user", "fixture-user", secret), receipt, Mock(),
                    Mock(return_value=SimpleNamespace(returncode=code, stdout=secret.encode(), stderr=secret.encode())))
            self.assertEqual(receipt["broker_commands"][0]["output_category"], "UNKNOWN")
            self.assertNotIn(secret, json.dumps(receipt))

    def test_control_categories_are_conservative_and_do_not_echo_matching_text(self):
        for text, category in ((b"password validation failed", "credential_policy"),
                               (b"user_already_exists", "already_exists"),
                               (b"nodedown", "node_unavailable_or_auth"),
                               (b"permission denied", "local_permission"),
                               (b"invalid option; permission denied", "UNKNOWN"),
                               (b"unclassified sensitive output", "UNKNOWN")):
            self.assertEqual(proof.control_output_category(b"", text), category)
        self.assertEqual(proof.control_output_category(None, "private"), "UNKNOWN")


if __name__ == "__main__":
    unittest.main()
