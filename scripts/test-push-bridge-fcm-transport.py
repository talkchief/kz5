#!/usr/bin/env python3
"""Real pinned Requests session/response machinery; fake adapter, no network/keys.

Run with the installed bridge venv under the offline validation network guard.
Unlike a mocked Session.post, these tests exercise Requests' redirect/body logic.
"""

import json
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


if __name__ == "__main__":
    unittest.main()
