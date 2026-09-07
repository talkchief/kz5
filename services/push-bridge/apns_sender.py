#!/usr/bin/env python3
"""Sanitized internal APNs HTTP/2 sender import; not activation-ready."""

import binascii
import json
import logging
import os
import socket
import ssl
import threading
import time

import ecdsa
import h2.connection
import h2.events

log = logging.getLogger("push_bridge.apns")

# Read optional values here so missing APNs configuration is reported by the
# imported lazy sender initialization, not by an embedded production default.
KEY_FILE = os.environ.get("PUSH_BRIDGE_APNS_KEY_FILE")
KEY_ID = os.environ.get("PUSH_BRIDGE_APNS_KEY_ID")
TEAM_ID = os.environ.get("PUSH_BRIDGE_APNS_TEAM_ID")
TOPIC = os.environ.get("PUSH_BRIDGE_APNS_TOPIC")
KEY_FILE_DEV = os.environ.get("PUSH_BRIDGE_APNS_KEY_FILE_DEV", KEY_FILE)
KEY_ID_DEV = os.environ.get("PUSH_BRIDGE_APNS_KEY_ID_DEV", KEY_ID)
HOST_PROD = os.environ.get("PUSH_BRIDGE_APNS_HOST_PROD")
HOST_DEV = os.environ.get("PUSH_BRIDGE_APNS_HOST_DEV")
PORT = 443
TOKEN_TTL = 2700
CONNECT_TIMEOUT = 8
REQUEST_TIMEOUT = 8


def _b64(raw):
    import base64
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


class _ProviderToken(object):
    def __init__(self, key_file, key_id, team_id):
        self._key = ecdsa.SigningKey.from_pem(open(key_file).read())
        self._key_id = key_id
        self._team_id = team_id
        self._lock = threading.Lock()
        self._token = None
        self._minted = 0

    def get(self):
        with self._lock:
            now = time.time()
            if self._token and (now - self._minted) < TOKEN_TTL:
                return self._token
            header = _b64(json.dumps({"alg": "ES256", "kid": self._key_id}, separators=(",", ":")).encode())
            claims = _b64(json.dumps({"iss": self._team_id, "iat": int(now)}, separators=(",", ":")).encode())
            signing_input = header + b"." + claims
            import hashlib
            signature = self._key.sign_deterministic(signing_input, hashfunc=hashlib.sha256)
            self._token = (signing_input + b"." + _b64(signature)).decode()
            self._minted = now
            return self._token


class ApnsSender(object):
    def __init__(self, key_file=None, key_id=None, team_id=None, topic=None):
        key_file = key_file or KEY_FILE
        self._key_id = key_id or KEY_ID
        self._team_id = team_id or TEAM_ID
        base_topic = topic or TOPIC
        if not key_file or not self._key_id or not self._team_id or not base_topic:
            raise ValueError("missing APNs key file, key ID, team ID or base topic configuration")
        self._topic = base_topic + ".voip"
        self._provider_token = _ProviderToken(key_file, self._key_id, self._team_id)
        log.info("apns_sender_initialized")

    @staticmethod
    def normalize_token(token):
        if not token:
            return None
        bare = token.split(":")[-1].strip()
        try:
            binascii.unhexlify(bare)
        except (binascii.Error, TypeError, ValueError):
            return None
        return bare

    def _open(self, host):
        ctx = ssl.create_default_context()
        ctx.set_alpn_protocols(["h2"])
        sock = ctx.wrap_socket(socket.create_connection((host, PORT), timeout=CONNECT_TIMEOUT), server_hostname=host)
        if sock.selected_alpn_protocol() != "h2":
            sock.close()
            raise IOError("apns_http2_negotiation_failed")
        sock.settimeout(REQUEST_TIMEOUT)
        return sock

    def send(self, device_token, payload, sandbox=False):
        token = self.normalize_token(device_token)
        if not token:
            return False, 0, "invalid_device_token"
        host = HOST_DEV if sandbox else HOST_PROD
        if not host:
            return False, 0, "missing_apns_host"
        body = json.dumps(payload, separators=(",", ":")).encode()
        sock = None
        try:
            sock = self._open(host)
            conn = h2.connection.H2Connection()
            conn.initiate_connection()
            sock.sendall(conn.data_to_send())
            headers = [
                (":method", "POST"), (":scheme", "https"), (":authority", host),
                (":path", "/3/device/%s" % token), ("authorization", "bearer %s" % self._provider_token.get()),
                ("apns-topic", self._topic), ("apns-push-type", "voip"), ("apns-priority", "10"),
                ("apns-expiration", "0"), ("content-length", str(len(body))),
            ]
            stream_id = conn.get_next_available_stream_id()
            conn.send_headers(stream_id, headers)
            conn.send_data(stream_id, body, end_stream=True)
            sock.sendall(conn.data_to_send())
            status, response = None, b""
            deadline = time.time() + REQUEST_TIMEOUT
            while time.time() < deadline:
                chunk = sock.recv(65535)
                if not chunk:
                    break
                for event in conn.receive_data(chunk):
                    if isinstance(event, h2.events.ResponseReceived):
                        status = int(dict(event.headers)[b":status"])
                    elif isinstance(event, h2.events.DataReceived):
                        response += event.data
                        conn.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                    elif isinstance(event, (h2.events.StreamEnded, h2.events.ConnectionTerminated)):
                        deadline = 0
                        break
                out = conn.data_to_send()
                if out:
                    sock.sendall(out)
            # Preserve success/status tuple, never return raw provider content.
            return status == 200, (status or 0), "provider_response"
        except Exception:
            return False, -1, "apns_transport_error"
        finally:
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, stream=sys.stdout)
    if len(sys.argv) < 2:
        print("usage: apns_sender.py DEVICE_TOKEN [--sandbox]; requires PUSH_BRIDGE_TEST_PAYLOAD_JSON")
        sys.exit(2)
    sender = ApnsSender()
    ok, st, _tx = sender.send(sys.argv[1], json.loads(os.environ["PUSH_BRIDGE_TEST_PAYLOAD_JSON"]), sandbox="--sandbox" in sys.argv)
    print("test_result", ok, st)
    sys.exit(0 if ok else 1)
