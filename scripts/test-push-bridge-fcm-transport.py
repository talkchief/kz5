#!/usr/bin/env python3
"""Real pinned Requests session/response machinery; fake adapter, no network/keys.

Run with the installed bridge venv under the offline validation network guard.
Unlike a mocked Session.post, these tests exercise Requests' redirect/body logic.
"""

import json
import queue
from pathlib import Path
import socket
import sys
import threading
import unittest
from unittest.mock import Mock, patch

import requests
from requests.adapters import BaseAdapter

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services/push-bridge"))
import bridge


class UnreadableBody:
    def __init__(self):
        self.closed = 0
        self.released = 0

    def read(self, *args, **kwargs):
        raise AssertionError("response body must not be read")

    def stream(self, *args, **kwargs):
        raise AssertionError("response body must not be streamed")

    def close(self):
        self.closed += 1

    def release_conn(self):
        self.released += 1


class Adapter(BaseAdapter):
    def __init__(self, statuses):
        self.statuses = list(statuses)
        self.calls = []
        self.bodies = []

    def send(self, request, **kwargs):
        self.calls.append((request, kwargs))
        status = self.statuses.pop(0)
        if isinstance(status, Exception):
            raise status
        response = requests.Response()
        response.status_code = status
        response.request = request
        response.url = request.url
        response.raw = UnreadableBody()
        # A hostile/oversized/chunked body must not be fetched for any status.
        response.headers["Location"] = "https://unapproved.invalid/private-token"
        response.headers["Content-Length"] = "999999999"
        self.bodies.append(response.raw)
        return response

    def close(self):
        pass


class FcmTransportTests(unittest.TestCase):
    def setUp(self):
        self.guard = patch.object(socket, "create_connection", side_effect=AssertionError("no sockets"))
        self.guard.start()
        self.addCleanup(self.guard.stop)

    def run_send(self, statuses):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime.requests = requests
        runtime.http = requests.Session()
        runtime.http.trust_env = False
        self.addCleanup(runtime.http.close)
        runtime.fcm_url = "https://fcm.googleapis.com/v1/projects/fixture-project/messages:send"
        runtime.get_access_token = Mock(return_value="fixture-token")
        runtime._stop = Mock(is_set=Mock(return_value=False))
        runtime._lifecycle_lock = threading.Lock()
        runtime._active_sends = 0
        runtime._closing = False
        runtime._http_closed = False
        runtime._http_sessions = [runtime.http]
        runtime._idle_http = [runtime.http]
        runtime._settings = {"WORKERS": 2}
        adapter = Adapter(statuses)
        runtime.http.mount("https://", adapter)
        result = runtime.send_fcm("fixture-device", {"call_id": "fixture-call", "absent": None})
        self.assertEqual(runtime._active_sends, 0)
        for request, kwargs in adapter.calls:
            self.assertEqual(request.url, runtime.fcm_url)
            self.assertEqual(request.method, "POST")
            self.assertEqual(request.headers["Authorization"], "Bearer fixture-token")
            self.assertEqual(json.loads(request.body)["message"]["data"], {"call_id": "fixture-call"})
            self.assertTrue(kwargs["stream"])
            self.assertTrue(kwargs["verify"])
            self.assertEqual(kwargs["timeout"], 5)
        for body in adapter.bodies:
            self.assertEqual(body.closed, 1)
            self.assertEqual(body.released, 1)
        return result, adapter, runtime

    def test_success_closes_without_eager_body_download(self):
        result, adapter, _ = self.run_send([200])
        self.assertEqual(result, (True, 200, "provider_response"))
        self.assertEqual(len(adapter.calls), 1)

    def test_redirects_rejected_without_follow_next_body_or_retry(self):
        for status in (300, 301, 302, 303, 304, 307, 308, 399):
            with self.subTest(status=status):
                result, adapter, runtime = self.run_send([status])
                self.assertEqual(result, (False, status, "provider_redirect_rejected"))
                self.assertEqual(len(adapter.calls), 1)
                runtime._stop.wait.assert_not_called()

    def test_nonretry_statuses_close_without_reading_body(self):
        for status in (400, 401, 403, 404, 429):
            with self.subTest(status=status):
                result, adapter, _ = self.run_send([status])
                self.assertEqual(result, (False, status, "provider_response"))
                self.assertEqual(len(adapter.calls), 1)

    def test_server_retry_still_bounded_to_two_and_closes_both(self):
        result, adapter, runtime = self.run_send([503, 502])
        self.assertEqual(result, (False, 502, "provider_response"))
        self.assertEqual(len(adapter.calls), 2)
        runtime._stop.wait.assert_called_once_with(0.5)

    def test_retry_can_succeed_without_consuming_either_body(self):
        result, adapter, _ = self.run_send([503, 200])
        self.assertEqual(result, (True, 200, "provider_response"))
        self.assertEqual(len(adapter.calls), 2)

    def test_transport_failure_is_fixed_category_and_bounded(self):
        result, adapter, _ = self.run_send([requests.Timeout("secret-provider-body"),
                                           requests.ConnectionError("secret-provider-url")])
        self.assertEqual(result, (False, -1, "provider_transport_error"))
        self.assertEqual(len(adapter.calls), 2)

    def isolated_runtime(self, session, workers=2):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime.requests = requests
        runtime.http = session
        runtime._http_sessions = [session]
        runtime._idle_http = [session]
        runtime._settings = {"WORKERS": workers}
        runtime.get_access_token = Mock(return_value="fixture-token")
        runtime.fcm_url = "https://fcm.googleapis.com/v1/projects/fixture-project/messages:send"
        runtime._stop = threading.Event()
        runtime._lifecycle_lock = threading.Lock()
        runtime._active_sends = 0
        runtime._closing = False
        runtime._http_closed = False
        self.addCleanup(runtime.close)
        return runtime

    def test_concurrent_sessions_are_exclusive_bounded_and_closed_after_last_send(self):
        entered = threading.Barrier(3)
        release = threading.Event()
        results = queue.Queue()

        class GatedAdapter(Adapter):
            def __init__(self):
                super().__init__([200])
                self.gate_lock = threading.Lock()
                self.in_use = False

            def send(self, request, **kwargs):
                with self.gate_lock:
                    if self.in_use:
                        raise AssertionError("concurrent session reuse")
                    self.in_use = True
                try:
                    entered.wait(timeout=5)
                    if not release.wait(5):
                        raise AssertionError("test release missing")
                    return super().send(request, **kwargs)
                finally:
                    with self.gate_lock:
                        self.in_use = False

        sessions = [requests.Session(), requests.Session()]
        for session in sessions:
            session.trust_env = False
            session.mount("https://", GatedAdapter())
            session.close = Mock(wraps=session.close)
            self.addCleanup(session.close)
        runtime = self.isolated_runtime(sessions[0])

        def send():
            try:
                results.put(runtime.send_fcm("fixture-device", {}))
            except BaseException as error:
                results.put(error)

        threads = [threading.Thread(target=send) for _ in range(2)]
        try:
            with patch.object(requests, "Session", return_value=sessions[1]) as factory:
                for thread in threads:
                    thread.start()
                entered.wait(timeout=5)
                factory.assert_called_once_with()
                self.assertEqual(runtime._active_sends, 2)
                self.assertEqual(runtime.send_fcm("excess-fixture", {}),
                                 (False, 0, "provider_capacity_exhausted"))
                self.assertEqual(len(runtime._http_sessions), 2)
                runtime.close()
                runtime.close()
                for session in sessions:
                    session.close.assert_not_called()
                self.assertEqual(runtime.send_fcm("queued-fixture", {}),
                                 (False, 0, "bridge_closing"))
        finally:
            release.set()
            for thread in threads:
                if thread.ident is not None:
                    thread.join(timeout=6)
        self.assertTrue(all(not thread.is_alive() for thread in threads))
        self.assertEqual([results.get_nowait() for _ in range(2)],
                         [(True, 200, "provider_response")] * 2)
        self.assertEqual(runtime._active_sends, 0)
        for session in sessions:
            session.close.assert_called_once_with()

    def test_pool_reuses_idle_session_and_returns_it_after_exception(self):
        session = requests.Session()
        session.trust_env = False
        adapter = Adapter([200, 200])
        session.mount("https://", adapter)
        runtime = self.isolated_runtime(session, workers=1)
        with patch.object(requests, "Session", side_effect=AssertionError("unneeded session")):
            with patch.object(runtime, "get_access_token", side_effect=ValueError("fixture")):
                with self.assertRaises(ValueError):
                    runtime.send_fcm("fixture-device", {})
            self.assertEqual(runtime._idle_http, [session])
            self.assertEqual(runtime._active_sends, 0)
            for _ in range(2):
                self.assertEqual(runtime.send_fcm("fixture-device", {}), (True, 200, "provider_response"))
        self.assertEqual(len(adapter.calls), 2)
        self.assertEqual(runtime._http_sessions, [session])
        self.assertEqual(runtime._idle_http, [session])

    def test_one_session_close_failure_does_not_skip_remaining_sessions(self):
        first, second = Mock(), Mock()
        first.close.side_effect = RuntimeError("private-provider-error")
        runtime = self.isolated_runtime(first)
        runtime._http_sessions.append(second)
        with self.assertLogs("push_bridge", level="ERROR") as messages:
            runtime.close()
        second.close.assert_called_once_with()
        self.assertEqual(messages.output, ["ERROR:push_bridge:bridge_http_close_failed"])


if __name__ == "__main__":
    unittest.main()
