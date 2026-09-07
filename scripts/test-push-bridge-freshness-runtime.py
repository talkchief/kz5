#!/usr/bin/env python3
"""Offline freshness integration, no keys, provider access or live sockets."""
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "services/push-bridge"))
import bridge
import freshness_runtime
from freshness import capture, FreshnessFailure


def clock_value(now=1000000, mono=100):
    return {"now_ms": now, "monotonic_ms": mono}


def body(lifetime=1000):
    return json.dumps({"Token-ID": "fixture-device", "Call-ID": "fixture-call",
                       "Push-Freshness": {"version": 1, "created_at_ms": 1000000,
                                          "deadline_ms": 1000000 + lifetime}})


def lease(lifetime=1000):
    return capture(json.loads(body(lifetime)), "unix-ms-v1", **clock_value())


def load_fixture(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class FreshnessRuntimeTests(unittest.TestCase):
    def runtime(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {"FRESHNESS": "unix-ms-v1"}
        runtime.fcm_url = "https://fcm.googleapis.com/v1/projects/fixture-project/messages:send"
        runtime.get_access_token = Mock(return_value="fixture-token")
        runtime._stop = Mock(is_set=Mock(return_value=False))
        runtime.requests = SimpleNamespace(RequestException=RuntimeError)
        return runtime

    def test_body_adapter_is_bounded_duplicate_safe_and_legacy_unchanged(self):
        with patch.object(freshness_runtime, "clocks", return_value=clock_value()):
            self.assertEqual(freshness_runtime.capture_body(body(), "unix-ms-v1").deadline_ms, 1001000)
            for raw in ('{"Push-Freshness":{},"Push-Freshness":{}}', "[1]", b"\xff", "x" * 32769):
                with self.assertRaisesRegex(FreshnessFailure, "^push_freshness_invalid$"):
                    freshness_runtime.capture_body(raw, "unix-ms-v1")
            self.assertIsNone(freshness_runtime.capture_body(object(), None))
            self.assertIsNone(freshness_runtime.capture_body(object(), "legacy"))

    def test_strict_direct_send_missing_lease_fails_before_auth_or_lifecycle(self):
        runtime = self.runtime()
        self.assertEqual(runtime.send_fcm("fixture", {}), (False, 0, "push_freshness_invalid"))
        runtime.get_access_token.assert_not_called()

    def test_expired_before_auth_never_posts(self):
        runtime, http, admitted = self.runtime(), Mock(), lease()
        with patch.object(freshness_runtime, "clocks", return_value=clock_value(1001000, 1100)):
            result = runtime._send_fcm_with_session(http, "fixture", {}, admitted)
        self.assertEqual(result, (False, 0, "push_freshness_expired"))
        runtime.get_access_token.assert_not_called(); http.post.assert_not_called()

    def test_expiry_during_auth_never_posts(self):
        runtime, http, admitted = self.runtime(), Mock(), lease()
        now = clock_value()
        def token():
            now.update(clock_value(1001000, 1100)); return "fixture-token"
        runtime.get_access_token.side_effect = token
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)):
            result = runtime._send_fcm_with_session(http, "fixture", {}, admitted)
        self.assertEqual(result, (False, 0, "push_freshness_expired"))
        runtime.get_access_token.assert_called_once(); http.post.assert_not_called()

    def test_fcm_remaining_ttl_and_timeout_shrink_after_auth_and_retry(self):
        runtime, http, admitted = self.runtime(), Mock(), lease()
        now, sent, responses = clock_value(), [], []
        def token():
            now["now_ms"] += 100; now["monotonic_ms"] += 100
            return "fixture-token"
        def post(_url, **kwargs):
            sent.append(json.loads(json.dumps({"message": kwargs["json"], "timeout": kwargs["timeout"]})))
            response = Mock(status_code=503 if len(sent) == 1 else 200)
            responses.append(response); return response
        def wait(_seconds):
            now["now_ms"] += 500; now["monotonic_ms"] += 500
        runtime.get_access_token.side_effect = token
        runtime._stop.wait.side_effect = wait
        http.post.side_effect = post
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)):
            self.assertEqual(runtime._send_fcm_with_session(http, "fixture", {}, admitted),
                             (True, 200, "provider_response"))
        self.assertEqual([s["message"]["message"]["android"]["ttl"] for s in sent], ["0.900s", "0.300s"])
        self.assertEqual([s["timeout"] for s in sent], [0.9, 0.3])
        for response in responses: response.close.assert_called_once()

    def test_broker_retry_mode_keeps_original_deadline_and_one_post_after_auth(self):
        runtime, http, admitted = self.runtime(), Mock(), lease()
        runtime._settings["RETRY"] = "quorum-counted-v1"
        now = clock_value()
        def token():
            now.update(clock_value(1000100, 200)); return "fixture-token"
        runtime.get_access_token.side_effect = token
        http.post.return_value = Mock(status_code=503, headers={})
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)):
            self.assertEqual(runtime._send_fcm_with_session(http, "fixture", {}, admitted),
                             (False, 503, "provider_response"))
        http.post.assert_called_once(); runtime._stop.wait.assert_not_called()
        self.assertEqual(http.post.call_args.kwargs["json"]["message"]["android"]["ttl"], "0.900s")
        self.assertEqual(http.post.call_args.kwargs["timeout"], 0.9)
        now.update(clock_value(1001000, 1100)); http.post.reset_mock()
        runtime.get_access_token.reset_mock(side_effect=True)
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)):
            self.assertEqual(runtime._send_fcm_with_session(http, "fixture", {}, admitted),
                             (False, 0, "push_freshness_expired"))
        http.post.assert_not_called(); runtime.get_access_token.assert_not_called()

    def test_retry_header_absence_must_be_known_and_values_are_never_inspected(self):
        class PrivateValue:
            def __str__(self):
                raise AssertionError("do not inspect provider header value")
        for headers in (None, [], {"Retry-After": PrivateValue()}, {"retry-after": "0"}, {1: "unknown"}):
            runtime, http = self.runtime(), Mock()
            runtime._settings["RETRY"] = "quorum-counted-v1"
            http.post.return_value = Mock(status_code=503, headers=headers)
            with patch.object(freshness_runtime, "clocks", return_value=clock_value()):
                self.assertEqual(runtime._send_fcm_with_session(http, "fixture", {}, lease()),
                                 (False, 503, "provider_retry_after_required"))
            http.post.assert_called_once(); http.post.return_value.close.assert_called_once()
            runtime._stop.wait.assert_not_called()

    def test_retry_after_deadline_is_not_dispatched(self):
        runtime, http, admitted = self.runtime(), Mock(), lease()
        now = clock_value()
        http.post.return_value = Mock(status_code=503)
        runtime._stop.wait.side_effect = lambda _seconds: now.update(clock_value(1001000, 1100))
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)):
            self.assertEqual(runtime._send_fcm_with_session(http, "fixture", {}, admitted),
                             (False, 0, "push_freshness_expired"))
        http.post.assert_called_once(); runtime.get_access_token.assert_called_once()

    def test_worker_queue_delay_does_not_recapture_creation_or_lifetime(self):
        runtime = self.runtime()
        runtime.send_fcm = Mock(side_effect=AssertionError("expired worker must not send"))
        admitted = lease()
        with patch.object(freshness_runtime, "clocks", return_value=clock_value(1001000, 1100)):
            self.assertEqual(runtime.deliver(body(), freshness=admitted),
                             (False, 0, "push_freshness_expired"))
        runtime.send_fcm.assert_not_called()

    def test_apns_expiry_during_token_or_connect_never_sends_push_headers(self):
        fixture = load_fixture("freshness_apns_fixture", "test-push-bridge-apns-transport.py")
        for phase in ("before_token", "during_token", "during_connect"):
            clock = fixture.Clock()
            sender, sock, conn = fixture.fixture(clock)
            now = clock_value()
            if phase == "before_token": now.update(clock_value(1001000, 1100))
            if phase == "during_token":
                sender._provider_token.get.side_effect = lambda **_kw: now.update(clock_value(1001000, 1100)) or "fixture-token"
            if phase == "during_connect":
                sender._open.side_effect = lambda *_args: now.update(clock_value(1001000, 1100)) or sock
            with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)), \
                    patch.object(fixture.apns.time, "monotonic", clock.monotonic):
                result = sender.send("ab" * 32, {"aps": {}}, freshness=lease())
            self.assertEqual(result, (False, 0, "push_freshness_expired"))
            conn.send_headers.assert_not_called(); conn.send_data.assert_not_called()
            if phase == "before_token": sender._provider_token.get.assert_not_called()
            if phase != "during_connect": sender._open.assert_not_called()
            else: self.assertEqual(sock.closed, 1)

    def test_actual_owner_loop_captures_before_worker_and_quarantines_expired(self):
        fixture = load_fixture("freshness_owner_fixture", "test-push-bridge-settlement.py")
        case = fixture.OwnerLoopTests()
        runtime, message, executor, connection, factory, callbacks = case.runtime(quorum=True, body=body())
        runtime._settings["FRESHNESS"] = "unix-ms-v1"
        runtime.deliver = bridge.BridgeRuntime.deliver.__get__(runtime)
        runtime.send_fcm = Mock(side_effect=AssertionError("expired push must not send"))
        executor.immediate = False
        now = clock_value()
        steps = [0]
        def dispatch(**_kwargs):
            steps[0] += 1
            if steps[0] == 1:
                callbacks[0](message)
                now.update(clock_value(1001000, 1100))
                worker, raw, future = executor.jobs[0]
                future.set_result(worker(raw))
            else: runtime._stop.set()
        connection.channel().process_data_events = dispatch
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)), \
                patch.object(bridge, "ThreadPoolExecutor", return_value=executor), \
                patch("amqp_management.verify_topology", return_value=True):
            runtime.run()
        self.assertEqual(message.rejections, [False]); self.assertEqual(message.acks, 0)
        runtime.send_fcm.assert_not_called(); self.assertEqual(factory.call_count, 1)

    def test_apns_fresh_success_keeps_immediate_only_header_and_caps_socket_life(self):
        fixture = load_fixture("freshness_apns_success", "test-push-bridge-apns-transport.py")
        clock = fixture.Clock()
        sender, sock, conn = fixture.fixture(clock, events=[fixture.headers(), fixture.ended()])
        with patch.object(freshness_runtime, "clocks", return_value=clock_value()), \
                patch.object(fixture.apns.time, "monotonic", clock.monotonic):
            self.assertEqual(sender.send("ab" * 32, {"aps": {}}, freshness=lease()),
                             (True, 200, "provider_response"))
        self.assertIn(("apns-expiration", "0"), conn.send_headers.call_args.args[1])
        self.assertTrue(all(0 < timeout <= 1 for timeout in sock.timeouts))
        self.assertEqual(sock.closed, 1)

    def test_apns_expiry_while_building_frame_stops_before_push_bytes(self):
        fixture = load_fixture("freshness_apns_frame", "test-push-bridge-apns-transport.py")
        clock = fixture.Clock()
        sender, sock, conn = fixture.fixture(clock)
        now = clock_value()
        conn.send_data.side_effect = lambda *_args, **_kwargs: now.update(clock_value(1001000, 1100))
        with patch.object(freshness_runtime, "clocks", side_effect=lambda: dict(now)), \
                patch.object(fixture.apns.time, "monotonic", clock.monotonic):
            self.assertEqual(sender.send("ab" * 32, {"aps": {}}, freshness=lease()),
                             (False, 0, "push_freshness_expired"))
        self.assertEqual(len(sock.send_timeouts), 1, "only connection preface may reach socket")
        self.assertEqual(sock.closed, 1)


if __name__ == "__main__":
    unittest.main()
