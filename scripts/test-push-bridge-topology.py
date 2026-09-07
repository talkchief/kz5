#!/usr/bin/env python3
"""Offline topology contracts; real pinned AMQP frame builders, no broker I/O.

Run only in the serialized offline test guard. This is not broker fault-injection
or proof of durable delivery, dispatch ceilings, stale-ring prevention or phones.
"""

from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
import threading
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch
from urllib.parse import urlsplit

SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import amqp_topology as topology
import bridge
import validate_config as config
from amqpstorm.queue import Queue
from amqpstorm.exchange import Exchange
from pamqp import specification


def settings(quorum=True):
    result = {"SA_FILE": "/fixture/not-real.json", "AMQP_HOST": "broker.example.invalid",
              "AMQP_USER": "fixture", "AMQP_PASS": "fixture-private-value", "AMQP_VHOST": "/fixture",
              "EXCHANGE": "fixture.pushes", "QUEUE": "fixture.mobile", "BINDING_KEY": "notification.push.*",
              "FCM_SCOPE": config.FCM_SCOPE, "FCM_URL_TEMPLATE": config.FCM_URL}
    if quorum:
        result.update(TOPOLOGY="quorum-v1", QUEUE="fixture.mobile.quorum-v1",
                      AMQP_MANAGEMENT_URL="https://broker.example.invalid:15671")
    return result


def errors(values):
    return config.validate({config.PREFIX + key: value for key, value in values.items()})


def connection():
    frames = []
    channel = SimpleNamespace(is_open=True, rpc_request=lambda frame: frames.append(frame))
    channel.queue, channel.exchange = Queue(channel), Exchange(channel)
    channel.basic = SimpleNamespace(qos=Mock(), consume=Mock())
    return SimpleNamespace(channel=Mock(return_value=channel), is_open=True, close=Mock()), channel, frames


class TopologyTests(unittest.TestCase):
    def test_opt_in_names_limits_and_legacy_default(self):
        self.assertEqual(errors(settings(False)), ())
        self.assertIsNone(topology.plan(settings(False)))
        self.assertEqual(errors(settings()), ())
        for mode in ("", "QUORUM-V1", "quorum", "other", None, 2):
            candidate = settings(); candidate["TOPOLOGY"] = mode
            self.assertTrue(errors(candidate))
        for name in ("AMQP_MANAGEMENT_URL", "AMQP_MANAGEMENT_CA_FILE", *config.TOPOLOGY_LIMITS):
            candidate = settings(False); candidate[name] = ""
            self.assertIn("TOPOLOGY:quorum_settings_require_opt_in", errors(candidate))
        for queue in ("fixture", ".quorum-v1", "amq.fixture.quorum-v1", "bad/queue.quorum-v1",
                      "q" * 242 + ".quorum-v1", "bad queue.quorum-v1"):
            candidate = settings(); candidate["QUEUE"] = queue
            self.assertIn("QUEUE:invalid_versioned_topology", errors(candidate))
        candidate = settings(); candidate["QUEUE"] = "q" * 241 + ".quorum-v1"
        self.assertEqual(errors(candidate), ())
        for exchange in (candidate["QUEUE"], candidate["QUEUE"] + ".dlx", candidate["QUEUE"] + ".dlq"):
            candidate["EXCHANGE"] = exchange
            self.assertIn("QUEUE:invalid_versioned_topology", errors(candidate))
        for name, (_default, low, high) in config.TOPOLOGY_LIMITS.items():
            for value in (str(low), str(high)):
                candidate = settings(); candidate[name] = value
                self.assertEqual(errors(candidate), ())
            for value in ("", "0", "01", "-1", "+1", " 1", "1.0", str(low - 1), str(high + 1), True, None):
                candidate = settings(); candidate[name] = value
                self.assertTrue(errors(candidate))

    def test_management_url_transport_and_ca_validation_is_offline(self):
        with patch("builtins.open", side_effect=AssertionError("unexpected file read")), \
                patch("socket.getaddrinfo", side_effect=AssertionError("unexpected DNS")):
            for url in ("https://remote.example.invalid", "https://remote.example.invalid:15671",
                        "http://localhost:15672", "http://127.0.0.1:15672", "http://[::1]:15672"):
                candidate = settings(); candidate["AMQP_MANAGEMENT_URL"] = url
                candidate["AMQP_HOST"] = urlsplit(url).hostname
                self.assertEqual(errors(candidate), ())
            for url in ("", "http://remote.example.invalid", "http://localhost.evil.invalid", "http://10.0.0.1",
                        "https://user:fixture-private-value@remote.example.invalid", "https://broker/api",
                        "https://broker/", "https://broker?", "https://broker#", "https://broker:0",
                        "https://broker:65536", "https://broker:", " https://broker", "HTTPS://broker"):
                candidate = settings(); candidate["AMQP_MANAGEMENT_URL"] = url
                self.assertIn("AMQP_MANAGEMENT_URL:invalid_format", errors(candidate))
                self.assertNotIn("fixture-private-value", repr(errors(candidate)))
            candidate = settings(); candidate["AMQP_MANAGEMENT_CA_FILE"] = "/etc/kazoo-push-bridge/management-ca.pem"
            self.assertEqual(errors(candidate), ())
            candidate["AMQP_MANAGEMENT_URL"] = "http://localhost:15672"
            self.assertIn("AMQP_MANAGEMENT_CA_FILE:requires_https", errors(candidate))
            for ca in ("", "relative", "/a/../b", "/a//b", "/a/fixture private"):
                candidate = settings(); candidate["AMQP_MANAGEMENT_CA_FILE"] = ca
                self.assertIn("AMQP_MANAGEMENT_CA_FILE:invalid_format", errors(candidate))
            candidate = settings(); candidate["AMQP_MANAGEMENT_URL"] = "https://different.example.invalid"
            self.assertIn("AMQP_MANAGEMENT_URL:broker_host_mismatch", errors(candidate))
            candidate["AMQP_MANAGEMENT_URL"] = "https://BROKER.EXAMPLE.INVALID:15671"
            self.assertEqual(errors(candidate), ())

    def test_plan_is_detached_immutable_and_explicitly_bounded(self):
        values = settings(); wanted = topology.plan(values)
        self.assertEqual(dict(wanted.work_arguments), {
            "x-queue-type": "quorum", "x-overflow": "reject-publish", "x-max-length": 1000,
            "x-max-length-bytes": 33554432, "x-delivery-limit": 3, "x-message-ttl": 60000,
            "x-dead-letter-strategy": "at-least-once", "x-dead-letter-exchange": "fixture.mobile.quorum-v1.dlx",
            "x-dead-letter-routing-key": "dead"})
        self.assertEqual(dict(wanted.dead_arguments), {"x-queue-type": "quorum", "x-overflow": "reject-publish",
                                                      "x-max-length": 10000, "x-max-length-bytes": 67108864})
        self.assertNotIn("x-message-ttl", wanted.dead_arguments)
        self.assertNotIn("x-dead-letter-exchange", wanted.dead_arguments)
        self.assertEqual(repr(wanted), "<TopologyPlan quorum-v1 redacted>")
        values["QUEUE"] = "changed"
        self.assertEqual(wanted.work_queue, "fixture.mobile.quorum-v1")
        with self.assertRaises(TypeError): wanted.work_arguments["x-delivery-limit"] = 99
        with self.assertRaises(FrozenInstanceError): wanted.work_queue = "changed"

    def test_real_pinned_amqp_builders_declare_then_verify_then_bind_ingress(self):
        conn, channel, frames = connection(); values = settings(); wanted = topology.plan(values)
        def verify(supplied, observed):
            self.assertIs(supplied, values); self.assertEqual(observed, wanted)
            self.assertEqual(len(frames), 5)
            self.assertEqual(frames[-1].queue, wanted.work_queue)
            self.assertEqual(frames[-1].arguments, dict(wanted.work_arguments))
            return True
        self.assertIs(topology.configure(conn, values, RuntimeError, verify), channel)
        self.assertEqual([type(frame) for frame in frames], [specification.Exchange.Declare,
            specification.Exchange.Declare, specification.Queue.Declare, specification.Queue.Bind,
            specification.Queue.Declare, specification.Queue.Bind])
        self.assertTrue(frames[0].passive)
        self.assertEqual((frames[1].exchange, frames[1].exchange_type, frames[1].durable, frames[1].auto_delete),
                         (wanted.dead_exchange, "direct", True, False))
        for frame in (frames[2], frames[4]):
            self.assertEqual((frame.durable, frame.exclusive, frame.auto_delete), (True, False, False))
        self.assertEqual(frames[2].arguments, dict(wanted.dead_arguments))
        self.assertEqual((frames[3].queue, frames[3].exchange, frames[3].routing_key),
                         (wanted.dead_queue, wanted.dead_exchange, "dead"))
        self.assertEqual((frames[5].queue, frames[5].exchange, frames[5].routing_key),
                         (wanted.work_queue, wanted.ingress_exchange, wanted.binding_key))

    def test_missing_or_nonexact_live_verification_never_binds_ingress(self):
        for verifier in (None, True, {}):
            conn, _channel, frames = connection()
            with self.assertRaisesRegex(topology.TopologyFailure, "^push_bridge_topology_unverified$"):
                topology.configure(conn, settings(), RuntimeError, verifier)
            self.assertEqual(frames, []); conn.channel.assert_not_called()
        for outcome in (None, False, 1, "true", {}, {"verified": True}):
            conn, _channel, frames = connection()
            with self.assertRaises(topology.TopologyFailure):
                topology.configure(conn, settings(), RuntimeError, lambda *_args: outcome)
            self.assertEqual(len(frames), 5)
        for step in range(6):
            conn, channel, frames = connection(); calls = [0]
            original = channel.rpc_request
            def fail(frame):
                current = calls[0]; calls[0] += 1
                if current == step: raise RuntimeError("fixture-private-value")
                return original(frame)
            channel.rpc_request = fail
            with self.assertRaisesRegex(topology.TopologyFailure, "^push_bridge_topology_unverified$"):
                topology.configure(conn, settings(), RuntimeError, lambda *_args: True)
            self.assertEqual(len(frames), step)
        conn, _channel, frames = connection()
        with self.assertRaisesRegex(topology.TopologyFailure, "^push_bridge_topology_unverified$"):
            topology.configure(conn, settings(), RuntimeError, Mock(side_effect=RuntimeError("fixture-private-value")))
        self.assertEqual(len(frames), 5)

    def test_verifier_is_called_again_on_each_connection_and_legacy_is_unchanged(self):
        verify = Mock(return_value=True)
        for _ in range(2):
            conn, _channel, _frames = connection()
            topology.configure(conn, settings(), RuntimeError, verify)
        self.assertEqual(verify.call_count, 2)
        conn, channel, frames = connection()
        topology.configure(conn, settings(False), RuntimeError, Mock(side_effect=AssertionError("legacy probe")))
        self.assertEqual(len(frames), 3)
        self.assertTrue(frames[0].passive); self.assertTrue(frames[1].durable)
        self.assertEqual(frames[1].arguments, {})
        first = SimpleNamespace(exchange=SimpleNamespace(declare=Mock(side_effect=RuntimeError())))
        conn.channel = Mock(side_effect=[first, channel]); frames.clear()
        self.assertIs(topology.configure(conn, settings(False), RuntimeError), channel)
        self.assertEqual(conn.channel.call_count, 2)
        self.assertEqual(frames[0].exchange_type, "topic"); self.assertFalse(frames[0].durable)

    def test_runtime_rejects_unverified_topology_before_consume_or_readiness(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {**settings(), "WORKERS": 1, "APNS_WORKERS": 1}
        runtime._stop = threading.Event(); runtime.mark_progress = Mock(); runtime.start_self_watchdog = Mock()
        conn, channel, frames = connection(); runtime._connect_amqp = Mock(return_value=conn)
        runtime.amqpstorm = SimpleNamespace(AMQPChannelError=RuntimeError)
        probe = ModuleType("amqp_management"); probe.verify_topology = Mock(return_value=False)
        executor = Mock()
        with patch.dict(sys.modules, {"amqp_management": probe}), \
                patch.object(bridge, "ThreadPoolExecutor", return_value=executor), \
                patch("service_notify.notify_consumer_ready") as ready:
            with self.assertRaises(topology.TopologyFailure): runtime.run()
        self.assertTrue(runtime._stop.is_set()); self.assertEqual(len(frames), 5)
        channel.basic.consume.assert_not_called(); ready.assert_not_called()
        conn.close.assert_called_once_with(); self.assertEqual(executor.shutdown.call_count, 2)
        runtime = SimpleNamespace(run=Mock(side_effect=topology.TopologyFailure()), close=Mock(), handle_term=Mock())
        with patch.object(bridge, "BridgeRuntime", return_value=runtime), patch.object(bridge.signal, "signal"), \
                self.assertLogs("push_bridge", level="ERROR") as logs:
            self.assertEqual(bridge.main([], {}), 78)
        self.assertEqual(logs.output, ["ERROR:push_bridge:push_bridge_topology_unverified"])

    def test_runtime_verified_topology_uses_configured_versioned_consumer_queue(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {**settings(), "WORKERS": 1, "APNS_WORKERS": 1}
        runtime._stop = threading.Event(); runtime.mark_progress = Mock(); runtime.start_self_watchdog = Mock()
        conn, channel, frames = connection(); runtime._connect_amqp = Mock(return_value=conn)
        runtime.amqpstorm = SimpleNamespace(AMQPChannelError=RuntimeError)
        channel.process_data_events = lambda **_kwargs: runtime._stop.set()
        probe = ModuleType("amqp_management"); probe.verify_topology = Mock(return_value=True)
        def ready():
            probe.verify_topology.assert_called_once()
            self.assertEqual(len(frames), 6)
            self.assertEqual(channel.basic.consume.call_args.kwargs,
                             {"queue": "fixture.mobile.quorum-v1", "no_ack": False})
        with patch.dict(sys.modules, {"amqp_management": probe}), \
                patch.object(bridge, "ThreadPoolExecutor", return_value=Mock()), \
                patch("service_notify.notify_consumer_ready", side_effect=ready) as notified:
            runtime.run()
        notified.assert_called_once_with(); conn.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
