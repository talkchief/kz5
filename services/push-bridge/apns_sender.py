#!/usr/bin/env python3
"""Sanitized internal APNs HTTP/2 sender import; not activation-ready."""

import json
import logging
import socket
import ssl
import threading
import time

from push_payload import InvalidPush, MAX_APNS_BYTES, apns_payload, normalize, normalize_apns_token
from validate_config import APNS_HOSTS, APPLE_ID, TOPIC, _path

log = logging.getLogger("push_bridge.apns")

PORT = 443
TOKEN_TTL = 2700
CONNECT_TIMEOUT = 8
REQUEST_TIMEOUT = 8
MAX_RESPONSE_BYTES = 16 * 1024
MAX_RESPONSE_WIRE_BYTES = 64 * 1024
MAX_RESPONSE_HEADER_BYTES = 16 * 1024


def _remaining(deadline, cap=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("apns_deadline_exceeded")
    return min(remaining, cap) if cap is not None else remaining


def _sendall(sock, data, deadline):
    sock.settimeout(_remaining(deadline))
    sock.sendall(data)
    _remaining(deadline)


def _b64(raw):
    import base64
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


class _ProviderToken(object):
    def __init__(self, key_file, key_id, team_id):
        import ecdsa
        with open(key_file) as handle:
            self._key = ecdsa.SigningKey.from_pem(handle.read())
        self._key_id = key_id
        self._team_id = team_id
        self._lock = threading.Lock()
        self._token = None
        self._minted = 0

    def get(self, deadline=None):
        if deadline is None:
            deadline = time.monotonic() + REQUEST_TIMEOUT
        if not self._lock.acquire(timeout=_remaining(deadline)):
            raise TimeoutError("apns_deadline_exceeded")
        try:
            _remaining(deadline)
            now = time.time()
            minted = time.monotonic()
            if self._token and (minted - self._minted) < TOKEN_TTL:
                return self._token
            header = _b64(json.dumps({"alg": "ES256", "kid": self._key_id}, separators=(",", ":")).encode())
            claims = _b64(json.dumps({"iss": self._team_id, "iat": int(now)}, separators=(",", ":")).encode())
            signing_input = header + b"." + claims
            import hashlib
            signature = self._key.sign_deterministic(signing_input, hashfunc=hashlib.sha256)
            _remaining(deadline)
            self._token = (signing_input + b"." + _b64(signature)).decode()
            self._minted = minted
            return self._token
        finally:
            self._lock.release()


class ApnsSender(object):
    def __init__(self, key_file=None, key_id=None, team_id=None, topic=None,
                 host_prod=None, host_dev=None):
        # No module-global environment or provider initialization. Validate
        # explicit inputs before loading third-party code or opening a key.
        if (not isinstance(key_file, str) or not _path(key_file)
                or not isinstance(key_id, str) or not APPLE_ID.fullmatch(key_id)
                or not isinstance(team_id, str) or not APPLE_ID.fullmatch(team_id)
                or not isinstance(topic, str) or len(topic) > 249
                or not TOPIC.fullmatch(topic) or topic.endswith(".voip")
                or host_prod != APNS_HOSTS["APNS_HOST_PROD"]
                or host_dev != APNS_HOSTS["APNS_HOST_DEV"]):
            raise ValueError("invalid_apns_configuration")
        import h2.connection
        import h2.events
        self._h2_connection = h2.connection
        self._h2_events = h2.events
        self._key_id = key_id
        self._team_id = team_id
        self._topic = topic + ".voip"
        self._host_prod = host_prod
        self._host_dev = host_dev
        self._provider_token = _ProviderToken(key_file, self._key_id, self._team_id)
        log.info("apns_sender_initialized")

    @staticmethod
    def normalize_token(token):
        try:
            return normalize_apns_token(token)
        except InvalidPush:
            return None

    def _open(self, host, deadline):
        ctx = ssl.create_default_context()
        ctx.set_alpn_protocols(["h2"])
        raw, sock = None, None
        try:
            # create_connection's DNS lookup is not governed by its timeout.
            # Recheck the shared budget immediately after it returns; this is
            # not a hard cancellation deadline for the platform resolver.
            raw = socket.create_connection((host, PORT), timeout=_remaining(deadline, CONNECT_TIMEOUT))
            raw.settimeout(_remaining(deadline))
            sock = ctx.wrap_socket(raw, server_hostname=host, do_handshake_on_connect=False)
            sock.settimeout(_remaining(deadline))
            sock.do_handshake()
            _remaining(deadline)
            if sock.selected_alpn_protocol() != "h2":
                raise IOError("apns_http2_negotiation_failed")
            return sock
        except Exception:
            # TLS wrapping can fail before the caller receives a socket.
            owned = sock if sock is not None else raw
            if owned is not None:
                try:
                    owned.close()
                except Exception:
                    pass
            raise

    def send(self, device_token, payload, sandbox=False):
        token = self.normalize_token(device_token)
        if not token:
            return False, 0, "invalid_device_token"
        host = self._host_dev if sandbox else self._host_prod
        if not host:
            return False, 0, "missing_apns_host"
        try:
            if not isinstance(payload, dict):
                raise InvalidPush()
            body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False,
                              allow_nan=False).encode("utf-8")
            if len(body) > MAX_APNS_BYTES:
                raise InvalidPush()
        except (ValueError, TypeError, UnicodeError, RecursionError, OverflowError):
            return False, 0, "invalid_push_payload"
        sock = None
        try:
            deadline = time.monotonic() + REQUEST_TIMEOUT
            authorization = self._provider_token.get(deadline=deadline)
            _remaining(deadline)
            sock = self._open(host, deadline)
            conn = self._h2_connection.H2Connection()
            conn.initiate_connection()
            _sendall(sock, conn.data_to_send(), deadline)
            headers = [
                (":method", "POST"), (":scheme", "https"), (":authority", host),
                (":path", "/3/device/%s" % token), ("authorization", "bearer %s" % authorization),
                ("apns-topic", self._topic), ("apns-push-type", "voip"), ("apns-priority", "10"),
                ("apns-expiration", "0"), ("content-length", str(len(body))),
            ]
            stream_id = conn.get_next_available_stream_id()
            conn.send_headers(stream_id, headers)
            conn.send_data(stream_id, body, end_stream=True)
            _sendall(sock, conn.data_to_send(), deadline)
            status, response_bytes, wire_bytes = None, 0, 0
            while True:
                sock.settimeout(_remaining(deadline))
                chunk = sock.recv(min(16384, MAX_RESPONSE_WIRE_BYTES - wire_bytes + 1))
                _remaining(deadline)
                if not chunk:
                    return False, (status or 0), "apns_incomplete_response"
                wire_bytes += len(chunk)
                if wire_bytes > MAX_RESPONSE_WIRE_BYTES:
                    return False, (status or 0), "apns_response_too_large"
                for event in conn.receive_data(chunk):
                    _remaining(deadline)
                    if isinstance(event, self._h2_events.ConnectionTerminated):
                        # GOAWAY is not proof that our response stream ended.
                        return False, (status or 0), "apns_incomplete_response"
                    if isinstance(event, (self._h2_events.ResponseReceived, self._h2_events.DataReceived,
                                          self._h2_events.StreamEnded, self._h2_events.StreamReset)):
                        if event.stream_id != stream_id:
                            return False, (status or 0), "apns_protocol_error"
                    if isinstance(event, self._h2_events.ResponseReceived):
                        if status is not None:
                            return False, status, "apns_protocol_error"
                        header_bytes = sum(len(key) + len(value) for key, value in event.headers)
                        if header_bytes > MAX_RESPONSE_HEADER_BYTES:
                            return False, 0, "apns_response_too_large"
                        values = [value for key, value in event.headers if key == b":status"]
                        if (len(values) != 1 or len(values[0]) != 3 or not values[0].isdigit()
                                or not 200 <= int(values[0]) <= 599):
                            return False, 0, "apns_protocol_error"
                        status = int(values[0])
                    elif isinstance(event, self._h2_events.DataReceived):
                        if status is None:
                            return False, 0, "apns_protocol_error"
                        response_bytes += len(event.data)
                        if response_bytes > MAX_RESPONSE_BYTES:
                            return False, status, "apns_response_too_large"
                        conn.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                    elif isinstance(event, self._h2_events.StreamReset):
                        return False, (status or 0), "apns_incomplete_response"
                    elif isinstance(event, self._h2_events.StreamEnded):
                        if status is None:
                            return False, 0, "apns_protocol_error"
                        # Only the requested stream's actual END_STREAM proves
                        # a complete response. Never expose the provider body.
                        return status == 200, status, "provider_response"
                out = conn.data_to_send()
                if out:
                    _sendall(sock, out, deadline)
        except Exception:
            return False, -1, "apns_transport_error"
        finally:
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass


def main(argv=None, environment=None):
    import os
    import sys
    logging.basicConfig(level=logging.INFO, stream=sys.stdout)
    if argv is None:
        argv = sys.argv[1:]
    if environment is None:
        environment = os.environ
    if len(argv) not in (1, 2) or (len(argv) == 2 and argv[1] != "--sandbox"):
        print("usage: apns_sender.py DEVICE_TOKEN [--sandbox]; requires PUSH_BRIDGE_TEST_PAYLOAD_JSON")
        return 2
    try:
        sandbox = len(argv) == 2
        raw = json.dumps({"Token-ID": argv[0], "Token-Type": "apple_dev" if sandbox else "apple",
                          "Payload": environment.get("PUSH_BRIDGE_TEST_PAYLOAD_JSON")})
        push = normalize(raw)
        key_file = environment.get("PUSH_BRIDGE_APNS_KEY_FILE")
        key_id = environment.get("PUSH_BRIDGE_APNS_KEY_ID")
        if sandbox:
            key_file = environment.get("PUSH_BRIDGE_APNS_KEY_FILE_DEV", key_file)
            key_id = environment.get("PUSH_BRIDGE_APNS_KEY_ID_DEV", key_id)
        sender = ApnsSender(key_file=key_file, key_id=key_id,
                            team_id=environment.get("PUSH_BRIDGE_APNS_TEAM_ID"),
                            topic=environment.get("PUSH_BRIDGE_APNS_TOPIC"),
                            host_prod=environment.get("PUSH_BRIDGE_APNS_HOST_PROD"),
                            host_dev=environment.get("PUSH_BRIDGE_APNS_HOST_DEV"))
        ok, status, _text = sender.send(push.token_id, apns_payload(push), sandbox=sandbox)
        print("test_result", ok, status)
        return 0 if ok else 1
    except Exception:
        log.error("apns_test_startup_or_send_failed")
        return 2


if __name__ == "__main__":
    import sys
    sys.exit(main())
