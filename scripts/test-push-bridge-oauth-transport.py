#!/usr/bin/env python3
"""Offline pinned Requests + Google-auth transport/refresh tests; no real keys.

Use the installed bridge venv inside the serialized network-isolated guard.
The only HTTP replacement is a Requests adapter, below real Session and Google
Request handling. JWT signing uses an explicit synthetic Signer fixture.
"""

import gzip
from importlib.metadata import version
import io
import json
from pathlib import Path
import queue
import socket
import sys
import threading
import unittest
from unittest.mock import Mock, patch

import requests
from requests.adapters import BaseAdapter
from google.auth.crypt.base import Signer
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from urllib3.response import HTTPResponse

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services/push-bridge"))
import bridge


class SyntheticSigner(Signer):
    @property
    def key_id(self):
        return "synthetic-key-id"

    def sign(self, message):
        return b"synthetic-signature-no-key"


def credentials():
    return service_account.Credentials(
        signer=SyntheticSigner(), service_account_email="fixture@fixture.invalid",
        token_uri=bridge.OAUTH_TOKEN_URL, scopes=["https://www.googleapis.com/auth/firebase.messaging"],
        project_id="fixture-project")


class Body:
    def __init__(self, data=b"", unreadable=False):
        self.data = data
        self.unreadable = unreadable
        self.closed = 0
        self.released = 0
        self.yielded = 0

    def stream(self, size, decode_content=True):
        if self.unreadable:
            raise AssertionError("body must not be consumed")
        for at in range(0, len(self.data), size):
            chunk = self.data[at:at + size]
            self.yielded += len(chunk)
            yield chunk

    def read(self, *args, **kwargs):
        raise AssertionError("body must not be eagerly read")

    def close(self):
        self.closed += 1

    def release_conn(self):
        self.released += 1


class Adapter(BaseAdapter):
    def __init__(self, entries):
        self.entries = list(entries)
        self.calls = []
        self.responses = []

    def send(self, request, **kwargs):
        self.calls.append((request, kwargs))
        entry = self.entries.pop(0)
        if callable(entry):
            entry = entry()
        if isinstance(entry, Exception):
            raise entry
        status, body, headers = entry
        response = requests.Response()
        response.status_code = status
        response.url = request.url
        response.request = request
        response.raw = body
        response.headers.update(headers)
        self.responses.append(response)
        return response

    def close(self):
        pass


def success(token="synthetic-access-token"):
    return 200, Body(json.dumps({"access_token": token, "expires_in": 3600,
                                "token_type": "Bearer"}).encode()), {}


ENVIRONMENT = {
    "PUSH_BRIDGE_SA_FILE": "/tmp/synthetic-never-opened.json",
    "PUSH_BRIDGE_AMQP_HOST": "fixture.invalid", "PUSH_BRIDGE_AMQP_USER": "fixture",
    "PUSH_BRIDGE_AMQP_PASS": "fixture", "PUSH_BRIDGE_AMQP_VHOST": "/",
    "PUSH_BRIDGE_EXCHANGE": "fixture", "PUSH_BRIDGE_QUEUE": "fixture",
    "PUSH_BRIDGE_BINDING_KEY": "fixture.*",
    "PUSH_BRIDGE_FCM_SCOPE": "https://www.googleapis.com/auth/firebase.messaging",
    "PUSH_BRIDGE_FCM_URL_TEMPLATE": "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
    "PUSH_BRIDGE_WORKERS": "2",
}


class OAuthTransportTests(unittest.TestCase):
    def setUp(self):
        guard = patch.object(socket, "create_connection", side_effect=AssertionError("no sockets"))
        guard.start()
        self.addCleanup(guard.stop)
        self.assertEqual(version("requests"), "2.34.2")
        self.assertEqual(version("google-auth"), "2.57.1")
        self.assertEqual(version("urllib3"), "2.7.0")

    def transport(self, entries):
        owner = bridge.BoundedOAuthSession(requests)
        self.addCleanup(owner.close)
        adapter = Adapter(entries)
        owner._session.mount("https://", adapter)
        owner._session.close = Mock(wraps=owner._session.close)
        return owner, Request(session=owner), adapter

    def runtime(self, entries, fcm_entries=None):
        credential = credentials()
        with patch.object(service_account.Credentials, "from_service_account_file", return_value=credential) as load:
            runtime = bridge.BridgeRuntime(ENVIRONMENT)
        load.assert_called_once_with(ENVIRONMENT["PUSH_BRIDGE_SA_FILE"],
                                     scopes=[ENVIRONMENT["PUSH_BRIDGE_FCM_SCOPE"]])
        self.addCleanup(runtime.close)
        oauth = Adapter(entries)
        runtime._oauth_session._session.mount("https://", oauth)
        runtime._oauth_session._session.close = Mock(wraps=runtime._oauth_session._session.close)
        fcm = Adapter(fcm_entries if fcm_entries is not None else [(200, Body(unreadable=True), {})])
        runtime.http.mount("https://", fcm)
        runtime.http.close = Mock(wraps=runtime.http.close)
        return runtime, oauth, fcm

    def assert_transport_arguments(self, adapter):
        for request, arguments in adapter.calls:
            self.assertEqual(request.url, bridge.OAUTH_TOKEN_URL)
            self.assertEqual(request.method, "POST")
            self.assertEqual(arguments["timeout"], bridge.OAUTH_HTTP_TIMEOUT)
            self.assertTrue(arguments["stream"])
            self.assertTrue(arguments["verify"])
            self.assertEqual(arguments["proxies"], {})

    def test_google_adapter_propagates_clamped_timeout_and_reuses_owned_session(self):
        owner, request, adapter = self.transport([success(), success()])
        for timeout in (None, 999):
            result = request(bridge.OAUTH_TOKEN_URL, method="POST", body=b"assertion=synthetic", timeout=timeout)
            self.assertEqual(result.status, 200)
            self.assertEqual(json.loads(result.data)["access_token"], "synthetic-access-token")
        self.assertEqual(len(adapter.calls), 2)
        self.assert_transport_arguments(adapter)
        self.assertFalse(owner._session.trust_env)
        owner._session.close.assert_not_called()
        for response in adapter.responses:
            self.assertTrue(response._content_consumed)
            self.assertEqual(response.raw.released, 1)
        owner.close()
        request.__del__()  # Pinned Google destructor closes its supplied owner.
        owner.close()
        owner._session.close.assert_called_once_with()
        with self.assertRaisesRegex(bridge.OAuthTransportFailure, "^oauth_transport_closed$"):
            request(bridge.OAUTH_TOKEN_URL, method="POST")

    def test_pinned_http_adapter_converts_tuple_to_urllib3_connect_and_read_timeouts(self):
        owner = bridge.BoundedOAuthSession(requests)
        self.addCleanup(owner.close)
        adapter = requests.adapters.HTTPAdapter()
        connection = Mock()
        connection.urlopen.return_value = HTTPResponse(
            status=200, body=io.BytesIO(b'{}'), headers={}, preload_content=False)
        adapter.get_connection_with_tls_context = Mock(return_value=connection)
        adapter.cert_verify = Mock()
        owner._session.mount("https://", adapter)
        request = Request(session=owner)
        self.assertEqual(request(bridge.OAUTH_TOKEN_URL, method="POST", body=b"synthetic").data, b"{}")
        arguments = connection.urlopen.call_args.kwargs
        self.assertEqual(arguments["timeout"].connect_timeout, 3.05)
        self.assertEqual(arguments["timeout"].read_timeout, 5)
        self.assertFalse(arguments["redirect"])
        self.assertFalse(arguments["preload_content"])
        connection.urlopen.assert_called_once()

    def test_real_service_account_refresh_caches_token_and_keeps_fcm_pool_separate(self):
        runtime, oauth, fcm = self.runtime([success()], [(200, Body(unreadable=True), {})] * 2)
        original_request = runtime._oauth_request
        for _ in range(2):
            self.assertEqual(runtime.send_fcm("synthetic-device", {}), (True, 200, "provider_response"))
        self.assertTrue(runtime.credentials.valid)
        self.assertIs(runtime._oauth_request, original_request)
        self.assertEqual(len(oauth.calls), 1)
        self.assertIn(b"assertion=", oauth.calls[0][0].body)
        self.assertEqual(len(fcm.calls), 2)
        self.assertEqual(runtime._http_sessions, [runtime.http])
        self.assertIsNot(runtime.http, runtime._oauth_session._session)
        self.assert_transport_arguments(oauth)
        for prepared, _ in fcm.calls:
            self.assertEqual(prepared.headers["Authorization"], "Bearer synthetic-access-token")
        runtime.close()
        runtime.close()
        original_request.__del__()
        runtime.http.close.assert_called_once_with()
        runtime._oauth_session._session.close.assert_called_once_with()

    def test_expired_token_refresh_reuses_google_request_and_oauth_session(self):
        runtime, oauth, _ = self.runtime([success("first"), success("second")])
        self.assertEqual(runtime.get_access_token(), "first")
        runtime.credentials.token = None
        self.assertEqual(runtime.get_access_token(), "second")
        self.assertEqual(len(oauth.calls), 2)
        runtime._oauth_session._session.close.assert_not_called()

    def test_every_redirect_rejected_before_body_read_or_credential_forwarding(self):
        for status in (300, 301, 302, 303, 304, 307, 308, 399):
            with self.subTest(status=status):
                body = Body(unreadable=True)
                runtime, oauth, fcm = self.runtime([(status, body, {
                    "Location": "https://unapproved.invalid/secret",
                    "Content-Length": "999999999"})])
                self.assertEqual(runtime.send_fcm("synthetic-device", {}), (False, -1, "oauth_redirect_rejected"))
                self.assertEqual(len(oauth.calls), 1)
                self.assertEqual(len(fcm.calls), 0)
                self.assertEqual(oauth.calls[0][0].url, bridge.OAUTH_TOKEN_URL)
                self.assertEqual(body.yielded, 0)
                self.assertEqual(body.closed, 1)
                self.assertEqual(body.released, 1)

    def test_large_content_length_rejected_without_consuming_body(self):
        body = Body(unreadable=True)
        owner, request, adapter = self.transport([(200, body, {"Content-Length": "999999999"})])
        with self.assertRaisesRegex(bridge.OAuthTransportFailure, "^oauth_response_too_large$"):
            request(bridge.OAUTH_TOKEN_URL, method="POST")
        self.assertEqual(body.closed, 1)
        self.assertEqual(body.released, 1)
        self.assertEqual(body.yielded, 0)

    def test_streamed_body_cap_for_missing_false_and_malformed_lengths(self):
        for headers in ({}, {"Content-Length": "1"}, {"Content-Length": "invalid"}):
            with self.subTest(headers=headers):
                body = Body(b"x" * (bridge.OAUTH_MAX_RESPONSE_BYTES + 8192))
                _, request, _ = self.transport([(400, body, headers)])
                with self.assertRaisesRegex(bridge.OAuthTransportFailure, "^oauth_response_too_large$"):
                    request(bridge.OAUTH_TOKEN_URL, method="POST")
                self.assertEqual(body.yielded, bridge.OAUTH_MAX_RESPONSE_BYTES + 4096)
                self.assertEqual(body.closed, 1)
                self.assertEqual(body.released, 1)

    def test_exact_cap_is_accepted_and_google_receives_cached_bounded_bytes(self):
        data = b"x" * bridge.OAUTH_MAX_RESPONSE_BYTES
        _, request, _ = self.transport([(200, Body(data), {})])
        self.assertEqual(request(bridge.OAUTH_TOKEN_URL, method="POST").data, data)

    def test_real_urllib3_gzip_decoding_is_counted_against_response_cap(self):
        compressed = gzip.compress(b"x" * (bridge.OAUTH_MAX_RESPONSE_BYTES + 1))
        raw = HTTPResponse(body=io.BytesIO(compressed), preload_content=False,
                           headers={"Content-Encoding": "gzip"})
        _, request, _ = self.transport([(200, raw, {"Content-Encoding": "gzip",
                                                   "Content-Length": str(len(compressed))})])
        with self.assertRaisesRegex(bridge.OAuthTransportFailure, "^oauth_response_too_large$"):
            request(bridge.OAUTH_TOKEN_URL, method="POST")
        self.assertTrue(raw.closed)

    def test_timeout_and_provider_refresh_errors_are_fixed_categories(self):
        for entry, category in [(requests.ReadTimeout("secret-url"), "oauth_transport_error"),
                                (requests.ConnectionError("secret-token"), "oauth_transport_error"),
                                ((400, Body(b'{"error":"invalid_grant","error_description":"secret"}'), {}),
                                 "oauth_refresh_error"),
                                ((200, Body(b"malformed-secret-response"), {}), "oauth_refresh_error")]:
            with self.subTest(category=category):
                runtime, oauth, fcm = self.runtime([entry])
                self.assertEqual(runtime.send_fcm("synthetic-device", {}), (False, -1, category))
                self.assertEqual(len(oauth.calls), 1)
                self.assertEqual(len(fcm.calls), 0)

    def test_stream_read_timeout_closes_response_and_remains_fixed_category(self):
        class TimeoutBody(Body):
            def stream(self, size, decode_content=True):
                raise requests.ConnectionError("secret-read-timeout-url")

        body = TimeoutBody()
        _, request, _ = self.transport([(200, body, {})])
        with self.assertRaisesRegex(bridge.OAuthTransportFailure, "^oauth_transport_error$"):
            request(bridge.OAUTH_TOKEN_URL, method="POST")
        self.assertEqual(body.closed, 1)
        self.assertEqual(body.released, 1)

    def test_endpoint_and_override_rejection_precedes_transport(self):
        _, request, adapter = self.transport([])
        for url, kwargs in [("https://unapproved.invalid/token", {}),
                            (bridge.OAUTH_TOKEN_URL, {"allow_redirects": True}),
                            (bridge.OAUTH_TOKEN_URL, {"verify": False})]:
            with self.assertRaisesRegex(bridge.OAuthTransportFailure, "^oauth_request_rejected$"):
                request(url, method="POST", body=b"synthetic-secret", **kwargs)
        self.assertEqual(adapter.calls, [])

    def test_close_defers_owned_oauth_session_until_active_send_refresh_finishes(self):
        entered = threading.Event()
        release = threading.Event()
        results = queue.Queue()

        def gated():
            entered.set()
            if not release.wait(5):
                raise AssertionError("fixture release missing")
            return success()

        runtime, oauth, _ = self.runtime([gated])
        thread = threading.Thread(target=lambda: results.put(runtime.send_fcm("synthetic-device", {})))
        try:
            thread.start()
            self.assertTrue(entered.wait(5))
            runtime.close()
            runtime.close()
            runtime.http.close.assert_not_called()
            runtime._oauth_session._session.close.assert_not_called()
            self.assertEqual(runtime.send_fcm("queued", {}), (False, 0, "bridge_closing"))
        finally:
            release.set()
            thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(results.get_nowait(), (True, 200, "provider_response"))
        self.assertEqual(len(oauth.calls), 1)
        runtime.http.close.assert_called_once_with()
        runtime._oauth_session._session.close.assert_called_once_with()

    def test_concurrent_token_requests_share_one_refresh_under_token_lock(self):
        entered = threading.Event()
        release = threading.Event()
        start = threading.Barrier(3)
        results = queue.Queue()

        def gated():
            entered.set()
            if not release.wait(5):
                raise AssertionError("fixture release missing")
            return success()

        runtime, oauth, _ = self.runtime([gated])

        def token():
            try:
                start.wait(timeout=5)
                results.put(runtime.get_access_token())
            except BaseException as error:
                results.put(error)

        threads = [threading.Thread(target=token) for _ in range(2)]
        try:
            for thread in threads:
                thread.start()
            start.wait(timeout=5)
            self.assertTrue(entered.wait(5))
        finally:
            release.set()
            for thread in threads:
                thread.join(5)
        self.assertTrue(all(not thread.is_alive() for thread in threads))
        self.assertEqual([results.get_nowait(), results.get_nowait()], ["synthetic-access-token"] * 2)
        self.assertEqual(len(oauth.calls), 1)

    def test_google_adapter_constructor_failure_closes_both_new_session_owners(self):
        real_session = requests.Session
        sessions = []

        def new_session():
            session = real_session()
            session.close = Mock(wraps=session.close)
            sessions.append(session)
            self.addCleanup(session.close)
            return session

        with patch.object(service_account.Credentials, "from_service_account_file", return_value=credentials()), \
                patch.object(requests, "Session", side_effect=new_session), \
                patch("google.auth.transport.requests.Request", side_effect=RuntimeError("synthetic-startup-failure")):
            with self.assertRaisesRegex(RuntimeError, "synthetic-startup-failure"):
                bridge.BridgeRuntime(ENVIRONMENT)
        self.assertEqual(len(sessions), 2)
        for session in sessions:
            session.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
