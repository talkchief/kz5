#!/usr/bin/env python3
"""Offline APNs transport fixtures: no credentials, provider libraries or sockets."""

from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import apns_sender as apns


class Event:
    def __init__(self, **fields):
        self.__dict__.update(fields)


class ResponseReceived(Event):
    pass


class DataReceived(Event):
    pass


class StreamEnded(Event):
    pass


class StreamReset(Event):
    pass


class ConnectionTerminated(Event):
    pass


EVENTS = SimpleNamespace(ResponseReceived=ResponseReceived, DataReceived=DataReceived,
                         StreamEnded=StreamEnded, StreamReset=StreamReset,
                         ConnectionTerminated=ConnectionTerminated)


def headers(status=b"200", stream=1):
    return ResponseReceived(stream_id=stream, headers=[(b":status", status)])


def data(body, stream=1):
    return DataReceived(stream_id=stream, data=body, flow_controlled_length=len(body))


def ended(stream=1):
    return StreamEnded(stream_id=stream)


class Clock:
    def __init__(self):
        self.now = 100.0

    def monotonic(self):
        return self.now


class FakeSocket:
    def __init__(self, clock, chunks=()):
        self.clock = clock
        self.chunks = list(chunks)
        self.timeouts = []
        self.recv_timeouts = []
        self.send_timeouts = []
        self.recv_sizes = []
        self.closed = 0
        self.alpn = "h2"
        self.handshake_delay = 0
        self.send_delay = 0
        self.handshakes = 0

    def settimeout(self, value):
        self.timeouts.append(value)

    def sendall(self, _body):
        self.send_timeouts.append(self.timeouts[-1])
        self.clock.now += self.send_delay

    def recv(self, size):
        self.recv_sizes.append(size)
        self.recv_timeouts.append(self.timeouts[-1])
        if not self.chunks:
            return b""
        delay, body = self.chunks.pop(0)
        if delay >= self.timeouts[-1]:
            self.clock.now += self.timeouts[-1]
            raise TimeoutError("fixture_receive_timeout")
        self.clock.now += delay
        if isinstance(body, Exception):
            raise body
        if len(body) > size:
            self.chunks.insert(0, (0, body[size:]))
        return body[:size]

    def do_handshake(self):
        self.handshakes += 1
        self.clock.now += self.handshake_delay

    def selected_alpn_protocol(self):
        return self.alpn

    def close(self):
        self.closed += 1


def fixture(clock, events=(), chunks=None):
    sock = FakeSocket(clock, [(0, b"response")] if chunks is None else chunks)
    conn = Mock()
    conn.data_to_send.return_value = b"fixture-h2-data"
    conn.get_next_available_stream_id.return_value = 1
    if isinstance(events, dict):
        conn.receive_data.side_effect = lambda chunk: events.get(chunk, [])
    else:
        conn.receive_data.return_value = events
    sender = apns.ApnsSender.__new__(apns.ApnsSender)
    sender._host_prod = "api.push.apple.com"
    sender._host_dev = "api.sandbox.push.apple.com"
    sender._topic = "fixture.application.voip"
    sender._provider_token = Mock()
    sender._provider_token.get.return_value = "fixture-jwt"
    sender._h2_connection = SimpleNamespace(H2Connection=Mock(return_value=conn))
    sender._h2_events = EVENTS
    sender._open = Mock(return_value=sock)
    return sender, sock, conn


class ResponseTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.monotonic = patch.object(apns.time, "monotonic", self.clock.monotonic)
        self.monotonic.start()
        self.addCleanup(self.monotonic.stop)
        # The transport must not depend on wall-clock adjustments.
        wall = patch.object(apns.time, "time", side_effect=AssertionError("wall_clock_used"))
        wall.start()
        self.addCleanup(wall.stop)
        network = patch.object(apns.socket, "create_connection", side_effect=AssertionError("real_network"))
        network.start()
        self.addCleanup(network.stop)

    def send(self, events, chunks=None, sandbox=False):
        sender, sock, conn = fixture(self.clock, events, chunks)
        result = sender.send("ab" * 32, {"call_id": "fixture-call"}, sandbox=sandbox)
        self.assertEqual(sock.closed, 1)
        return result, sender, sock, conn

    def test_only_completed_200_is_accepted_and_native_headers_are_preserved(self):
        result, sender, _sock, conn = self.send([headers(), ended()])
        self.assertEqual(result, (True, 200, "provider_response"))
        sender._open.assert_called_once_with("api.push.apple.com", 108.0)
        sender._provider_token.get.assert_called_once_with(deadline=108.0)
        sent = dict(conn.send_headers.call_args.args[1])
        self.assertEqual(sent[":path"], "/3/device/" + "ab" * 32)
        self.assertEqual(sent["authorization"], "bearer fixture-jwt")
        self.assertEqual(sent["apns-topic"], "fixture.application.voip")
        self.assertEqual(sent["apns-push-type"], "voip")
        self.assertEqual(sent["apns-expiration"], "0")
        conn.send_data.assert_called_once_with(1, b'{"call_id":"fixture-call"}', end_stream=True)

    def test_completed_rejection_does_not_expose_body_and_sandbox_is_preserved(self):
        result, sender, _sock, conn = self.send(
            [headers(b"400"), data(b'{"reason":"fixture-private-body"}'), ended()], sandbox=True)
        self.assertEqual(result, (False, 400, "provider_response"))
        sender._open.assert_called_once_with("api.sandbox.push.apple.com", 108.0)
        conn.acknowledge_received_data.assert_called_once()

    def test_headers_only_eof_never_succeeds(self):
        result, *_ = self.send([headers()])
        self.assertEqual(result, (False, 200, "apns_incomplete_response"))

    def test_goaway_or_reset_is_not_end_stream(self):
        for terminal in (ConnectionTerminated(), StreamReset(stream_id=1)):
            with self.subTest(terminal=type(terminal).__name__):
                result, *_ = self.send([headers(), terminal])
                self.assertEqual(result, (False, 200, "apns_incomplete_response"))

    def test_complete_stream_before_later_goaway_remains_accepted(self):
        result, *_ = self.send([headers(), ended(), ConnectionTerminated()])
        self.assertEqual(result, (True, 200, "provider_response"))

    def test_goaway_before_end_is_uncertain_even_with_following_end(self):
        result, *_ = self.send([headers(), ConnectionTerminated(), ended()])
        self.assertEqual(result, (False, 200, "apns_incomplete_response"))

    def test_unrelated_stream_cannot_settle_requested_stream(self):
        for other in (headers(stream=3), data(b"x", stream=3), ended(3), StreamReset(stream_id=3)):
            with self.subTest(event=type(other).__name__):
                result, *_ = self.send([headers(), other, ended()])
                self.assertEqual(result, (False, 200, "apns_protocol_error"))

    def test_end_or_data_without_response_headers_fails(self):
        for event in (ended(), data(b"x")):
            with self.subTest(event=type(event).__name__):
                result, *_ = self.send([event])
                self.assertEqual(result, (False, 0, "apns_protocol_error"))

    def test_malformed_duplicate_or_missing_final_status_fails(self):
        cases = [[(b":status", b"200"), (b":status", b"200")], [],
                 [(b":status", b"abc")], [(b":status", b"100")],
                 [(b":status", b"600")], [(b":status", b"0200")]]
        for fields in cases:
            with self.subTest(fields=fields):
                result, *_ = self.send([ResponseReceived(stream_id=1, headers=fields), ended()])
                self.assertEqual(result, (False, 0, "apns_protocol_error"))
        result, *_ = self.send([headers(), headers(), ended()])
        self.assertEqual(result, (False, 200, "apns_protocol_error"))

    def test_body_limit_is_cumulative_and_never_retains_or_returns_body(self):
        result, *_ = self.send([headers(), data(b"x" * apns.MAX_RESPONSE_BYTES), ended()])
        self.assertEqual(result, (True, 200, "provider_response"))
        result, _sender, _sock, conn = self.send(
            [headers(), data(b"x" * apns.MAX_RESPONSE_BYTES), data(b"x"), ended()])
        self.assertEqual(result, (False, 200, "apns_response_too_large"))
        # Oversized final data is not granted additional receive flow control.
        self.assertEqual(conn.acknowledge_received_data.call_count, 1)

    def test_wire_cap_includes_control_frames_not_only_data_events(self):
        result, _sender, sock, conn = self.send([], [(0, b"x" * (apns.MAX_RESPONSE_WIRE_BYTES + 1))])
        self.assertEqual(result, (False, 0, "apns_response_too_large"))
        self.assertEqual(sock.recv_sizes, [16384, 16384, 16384, 16384, 1])
        self.assertEqual(conn.receive_data.call_count, 4)

    def test_decoded_response_headers_are_bounded(self):
        event = headers()
        event.headers.append((b"fixture", b"x" * apns.MAX_RESPONSE_HEADER_BYTES))
        result, *_ = self.send([event, ended()])
        self.assertEqual(result, (False, 0, "apns_response_too_large"))

    def test_partial_reads_consume_one_monotonic_budget(self):
        result, _sender, sock, _conn = self.send(
            {b"headers": [headers()], b"control": [], b"end": [ended()]},
            [(3, b"headers"), (3, b"control"), (3, b"end")])
        self.assertEqual(result, (False, -1, "apns_transport_error"))
        self.assertEqual(sock.recv_timeouts, [8.0, 5.0, 2.0])
        self.assertEqual(self.clock.now, 108.0)

    def test_token_acquisition_consumes_budget_before_open(self):
        sender, sock, _conn = fixture(self.clock, [headers(), ended()])
        def get_token(**_kwargs):
            self.clock.now += 9
            return "fixture-jwt"
        sender._provider_token.get.side_effect = get_token
        result = sender.send("ab" * 32, {})
        self.assertEqual(result, (False, -1, "apns_transport_error"))
        sender._open.assert_not_called()
        self.assertEqual(sock.closed, 0)

    def test_connection_and_writes_share_budget_with_response(self):
        sender, sock, _conn = fixture(self.clock, [headers(), ended()], [(0, b"response")])
        def open_socket(*_args):
            self.clock.now += 3
            return sock
        sender._open.side_effect = open_socket
        sock.send_delay = 1
        result = sender.send("ab" * 32, {})
        self.assertEqual(result, (True, 200, "provider_response"))
        self.assertEqual(sock.send_timeouts, [5.0, 4.0])
        self.assertEqual(sock.recv_timeouts, [3.0])
        self.assertEqual(sock.closed, 1)

    def test_write_failure_or_expired_write_closes_without_success(self):
        for delay, failure in ((9, None), (0, OSError("fixture-private-error"))):
            with self.subTest(delay=delay):
                sender, sock, _conn = fixture(self.clock, [headers(), ended()])
                sock.send_delay = delay
                if failure is not None:
                    sock.sendall = Mock(side_effect=failure)
                self.assertEqual(sender.send("ab" * 32, {}), (False, -1, "apns_transport_error"))
                self.assertEqual(sock.closed, 1)
                self.assertEqual(sock.recv_sizes, [])


class SocketAndTokenTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        monotonic = patch.object(apns.time, "monotonic", self.clock.monotonic)
        monotonic.start()
        self.addCleanup(monotonic.stop)

    def test_tls_wrapping_failure_closes_raw_socket(self):
        raw = FakeSocket(self.clock)
        context = Mock()
        context.wrap_socket.side_effect = OSError("fixture-private-tls-error")
        sender = apns.ApnsSender.__new__(apns.ApnsSender)
        with patch.object(apns.socket, "create_connection", return_value=raw), \
                patch.object(apns.ssl, "create_default_context", return_value=context):
            with self.assertRaises(OSError):
                sender._open("api.push.apple.com", 108)
        self.assertEqual(raw.closed, 1)
        context.wrap_socket.assert_called_once_with(raw, server_hostname="api.push.apple.com",
                                                   do_handshake_on_connect=False)

    def test_tls_budget_covers_connect_and_handshake_without_reset(self):
        raw, tls = FakeSocket(self.clock), FakeSocket(self.clock)
        context = Mock()
        context.wrap_socket.return_value = tls
        def connect(*_args, **_kwargs):
            self.clock.now += 3
            return raw
        sender = apns.ApnsSender.__new__(apns.ApnsSender)
        with patch.object(apns.socket, "create_connection", side_effect=connect) as tcp, \
                patch.object(apns.ssl, "create_default_context", return_value=context):
            result = sender._open("api.push.apple.com", 108)
        self.assertIs(result, tls)
        tcp.assert_called_once_with(("api.push.apple.com", 443), timeout=8.0)
        self.assertEqual(raw.timeouts, [5.0])
        self.assertEqual(tls.timeouts, [5.0])
        self.assertEqual(tls.handshakes, 1)
        self.assertEqual(tls.closed, 0)

    def test_tls_failure_deadline_or_bad_alpn_closes_wrapped_socket(self):
        for mode in ("deadline", "alpn", "exception"):
            with self.subTest(mode=mode):
                self.clock.now = 100
                raw, tls = FakeSocket(self.clock), FakeSocket(self.clock)
                context = Mock()
                context.wrap_socket.return_value = tls
                if mode == "deadline":
                    tls.handshake_delay = 9
                elif mode == "alpn":
                    tls.alpn = "http/1.1"
                else:
                    tls.do_handshake = Mock(side_effect=OSError("fixture-tls-error"))
                sender = apns.ApnsSender.__new__(apns.ApnsSender)
                with patch.object(apns.socket, "create_connection", return_value=raw), \
                        patch.object(apns.ssl, "create_default_context", return_value=context):
                    with self.assertRaises((OSError, TimeoutError)):
                        sender._open("api.push.apple.com", 108)
                self.assertEqual(tls.closed, 1)
                self.assertEqual(raw.closed, 0)  # Ownership passed to TLS.

    def test_late_resolver_or_connect_return_closes_raw_without_tls(self):
        raw = FakeSocket(self.clock)
        context = Mock()
        def connect(*_args, **_kwargs):
            self.clock.now += 9
            return raw
        sender = apns.ApnsSender.__new__(apns.ApnsSender)
        with patch.object(apns.socket, "create_connection", side_effect=connect), \
                patch.object(apns.ssl, "create_default_context", return_value=context):
            with self.assertRaises(TimeoutError):
                sender._open("api.push.apple.com", 108)
        self.assertEqual(raw.closed, 1)
        context.wrap_socket.assert_not_called()

    def test_provider_lock_timeout_is_bounded_and_not_released_unowned(self):
        token = apns._ProviderToken.__new__(apns._ProviderToken)
        token._lock = Mock()
        token._lock.acquire.return_value = False
        with self.assertRaises(TimeoutError):
            token.get(deadline=103)
        token._lock.acquire.assert_called_once_with(timeout=3.0)
        token._lock.release.assert_not_called()

    def test_provider_cache_uses_monotonic_age_and_releases_lock(self):
        token = apns._ProviderToken.__new__(apns._ProviderToken)
        token._lock = Mock()
        token._lock.acquire.return_value = True
        token._token = "fixture-cached-jwt"
        token._minted = 99.0
        # A huge wall-clock change cannot expire the monotonic cache.
        with patch.object(apns.time, "time", return_value=9000000000):
            self.assertEqual(token.get(deadline=108), "fixture-cached-jwt")
        token._lock.release.assert_called_once_with()

    def test_provider_signing_over_budget_cannot_publish_new_cached_token(self):
        token = apns._ProviderToken.__new__(apns._ProviderToken)
        token._lock = Mock()
        token._lock.acquire.return_value = True
        token._token, token._minted = None, 0
        token._key_id, token._team_id = "FIXTUREKEY", "FIXTURETEAM"
        def sign(*_args, **_kwargs):
            self.clock.now += 9
            return b"fixture-signature"
        token._key = Mock()
        token._key.sign_deterministic.side_effect = sign
        with patch.object(apns.time, "time", return_value=1700000000):
            with self.assertRaises(TimeoutError):
                token.get(deadline=108)
        self.assertIsNone(token._token)
        token._lock.release.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
