"""Bounded, provider-independent normalization for native incoming-call pushes."""

import json
import re
import uuid
from types import MappingProxyType


MAX_BODY_BYTES = 32768
MAX_DATA_BYTES = 3072
MAX_APNS_BYTES = 4096
MAX_APNS_TOKEN_HEX = 512
APNS_TYPES = frozenset(("apple", "apns", "ios"))
APNS_DEV_TYPES = frozenset(("apple_dev", "apple_sandbox"))
FCM_TYPES = frozenset(("", "firebase", "android", "fcm"))
FIELDS = {
    "caller-id-number": ("caller_id_number", 128),
    "caller-id-name": ("caller_id_name", 256),
    "registration-token": ("registration_token", 1024),
    "proxy": ("proxy", 1024),
}


class InvalidPush(ValueError):
    """A fixed category only; never retain raw data, identifiers or tokens."""

    def __init__(self):
        super().__init__("invalid_push_payload")


class NormalizedPush:
    __slots__ = ("provider", "sandbox", "token_id", "data", "call_uuid")

    def __init__(self, provider, sandbox, token_id, data, call_uuid):
        self.provider = provider
        self.sandbox = sandbox
        self.token_id = token_id
        self.data = MappingProxyType(data)
        self.call_uuid = call_uuid

    def __repr__(self):
        return "<NormalizedPush redacted>"


def _text(value, maximum, required=False):
    if value is None and not required:
        return None
    if (not isinstance(value, str) or len(value) > maximum
            or (required and not value)
            or any(ord(char) < 32 or 127 <= ord(char) <= 159
                   or 0xD800 <= ord(char) <= 0xDFFF for char in value)):
        raise InvalidPush()
    if len(value.encode("utf-8")) > maximum:
        raise InvalidPush()
    return value


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidPush()
        result[key] = value
    return result


def _invalid_constant(_value):
    raise InvalidPush()


def _object(raw):
    if not isinstance(raw, (str, bytes)) or len(raw) > MAX_BODY_BYTES:
        raise InvalidPush()
    try:
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="strict")
        if len(raw.encode("utf-8")) > MAX_BODY_BYTES:
            raise InvalidPush()
        result = json.loads(raw, object_pairs_hook=_pairs, parse_constant=_invalid_constant)
        if not isinstance(result, dict):
            raise InvalidPush()
        return result
    except (ValueError, UnicodeError, RecursionError, OverflowError):
        raise InvalidPush() from None


def normalize_apns_token(value):
    """Retain the imported optional prefix:HEX form, but bound both parts."""
    value = _text(value, 129 + MAX_APNS_TOKEN_HEX, required=True)
    if ":" in value:
        parts = value.split(":")
        if len(parts) != 2 or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", parts[0]):
            raise InvalidPush()
        value = parts[1]
    # Device tokens are opaque bytes; do not hard-code today's common 32-byte
    # token length as a native compatibility requirement. Bound the resource
    # use while retaining nonempty even-length hex supported by the import.
    if (not re.fullmatch(r"[A-Fa-f0-9]+", value)
            or len(value) % 2 or len(value) > MAX_APNS_TOKEN_HEX):
        raise InvalidPush()
    return value.lower()


def normalize(raw):
    """Parse native notification/push_req, preserving the imported mobile DTO.

    Extra envelope headers remain accepted but are never forwarded to a phone.
    A call ID is mandatory for a stable retry identity; contradictory top-level
    and payload call IDs are rejected. An optional Account-ID scopes the UUID.
    Neither timestamps, caller display text, nor device tokens affect the UUID.
    """
    request = _object(raw)
    for name, expected in (("Event-Category", "notification"), ("Event-Name", "push_req")):
        if name in request and request[name] != expected:
            raise InvalidPush()
    token_type = _text(request.get("Token-Type", ""), 32)
    if token_type is None:
        raise InvalidPush()
    token_type = token_type.lower()
    if token_type in APNS_TYPES | APNS_DEV_TYPES:
        provider = "apns"
        sandbox = token_type in APNS_DEV_TYPES
        token = normalize_apns_token(request.get("Token-ID"))
    elif token_type in FCM_TYPES:
        provider, sandbox = "fcm", False
        token = _text(request.get("Token-ID"), 4096, required=True)
        # Registration tokens are opaque. JSON encoding safely transports
        # punctuation; do not invent a provider-specific base64 alphabet.
        if not re.fullmatch(r"[!-~]+", token):
            raise InvalidPush()
    else:
        raise InvalidPush()
    payload = request.get("Payload")
    if payload is None:
        payload = {}
    elif isinstance(payload, str):
        payload = _object(payload)
    elif not isinstance(payload, dict):
        raise InvalidPush()
    payload_call = _text(payload.get("call-id"), 256)
    envelope_call = _text(request.get("Call-ID"), 256)
    if payload_call and envelope_call and payload_call != envelope_call:
        raise InvalidPush()
    call_id = _text(payload_call or envelope_call, 256, required=True)
    account_id = _text(request.get("Account-ID"), 128)
    data = {"type": "sip_incoming_call", "call_id": call_id}
    for source, (target, maximum) in FIELDS.items():
        data[target] = _text(payload.get(source), maximum)
    encoded = json.dumps({key: value for key, value in data.items() if value is not None},
                         separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    if len(encoded) > MAX_DATA_BYTES:
        raise InvalidPush()
    identity = json.dumps(["kazoo-mobile-call-v1", account_id, call_id],
                          ensure_ascii=False, separators=(",", ":"))
    call_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, identity))
    return NormalizedPush(provider, sandbox, token, data, call_uuid)


def apns_payload(push):
    payload = {key: value for key, value in push.data.items() if value is not None}
    payload["call_uuid"] = push.call_uuid
    if len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")) > MAX_APNS_BYTES:
        raise InvalidPush()
    return payload
