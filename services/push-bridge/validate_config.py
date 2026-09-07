#!/usr/bin/env python3
"""Offline configuration-shape preflight, NOT a bridge activation/readiness gate.

Only examines the supplied environment mapping. Never imports provider modules,
opens credential files, resolves hosts, or sends requests. Diagnostics contain
fixed codes and allowlisted variable names only, never supplied names or values.
"""

import ipaddress
import os
import re
import sys


PREFIX = "PUSH_BRIDGE_"
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
APNS_HOSTS = {
    "APNS_HOST_PROD": "api.push.apple.com",
    "APNS_HOST_DEV": "api.sandbox.push.apple.com",
}
REQUIRED = (
    "SA_FILE", "AMQP_HOST", "AMQP_USER", "AMQP_PASS", "AMQP_VHOST",
    "EXCHANGE", "QUEUE", "BINDING_KEY", "FCM_SCOPE", "FCM_URL_TEMPLATE",
)
NUMBERS = {
    "AMQP_PORT": ("5672", 1, 65535),
    "WORKERS": ("32", 1, 64),
    "APNS_WORKERS": ("8", 1, 32),
    "STALL_TIMEOUT": ("70", 30, 300),
}
APNS_REQUIRED = (
    "APNS_KEY_FILE", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC",
    "APNS_HOST_PROD", "APNS_HOST_DEV",
)
APNS_OVERRIDES = ("APNS_KEY_FILE_DEV", "APNS_KEY_ID_DEV")
AMQP_TLS_SETTINGS = ("AMQP_TLS", "AMQP_CA_FILE")
KNOWN = frozenset(REQUIRED + tuple(NUMBERS) + APNS_REQUIRED + APNS_OVERRIDES + AMQP_TLS_SETTINGS)
SAFE_PATH = re.compile(r"/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\Z")
TOPOLOGY = re.compile(r"[A-Za-z0-9_.:-]{1,255}\Z")
BINDING = re.compile(r"[A-Za-z0-9_.*#:-]{1,255}\Z")
APPLE_ID = re.compile(r"[A-Z0-9]{10}\Z")
TOPIC = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\Z")


def _host(value):
    """IP literal or ASCII DNS name only: no URL, credentials, port, or zone."""
    try:
        ipaddress.ip_address(value)
        return "%" not in value
    except ValueError:
        labels = value.split(".")
        return len(value) <= 253 and all(
            re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in labels
        )


def _path(value):
    # This is lexical validation only, not a check of permissions or existence.
    return bool(SAFE_PATH.fullmatch(value)) and not any(
        part in (".", "..") for part in value.split("/")
    )


def validate(environment):
    """Return sorted, bounded, value-free errors; an empty tuple is NOT ready.

    Optional empty APNs settings from the template count as unconfigured. Once
    any APNs value is set, both environments need explicit host configuration.
    Sandbox key overrides must be a nonempty pair, or entirely absent, matching
    the imported sender's distinction between absent and empty variables.
    """
    errors = set()
    values = {}
    for key, value in environment.items():
        if not isinstance(key, str) or not key.startswith(PREFIX):
            continue
        name = key[len(PREFIX):]
        if name not in KNOWN:
            # Includes provider test payloads: forbidden in service preflight.
            errors.add("unknown_or_test_setting")
            continue
        if (not isinstance(value, str) or len(value) > 4096
                or any(ord(char) < 32 or 127 <= ord(char) <= 159
                       or 0xD800 <= ord(char) <= 0xDFFF for char in value)):
            errors.add(name + ":invalid_value")
            continue
        values[name] = value

    for name in REQUIRED:
        if not values.get(name):
            errors.add(name + ":required")

    for name, (default, low, high) in NUMBERS.items():
        value = values.get(name, default)
        if (not re.fullmatch(r"[0-9]{1,5}", value)
                or not low <= int(value) <= high):
            errors.add(name + ":invalid_range")

    def check(name, predicate):
        value = values.get(name)
        if value and not predicate(value):
            errors.add(name + ":invalid_format")

    check("SA_FILE", _path)
    check("AMQP_HOST", _host)
    tls = values.get("AMQP_TLS", "false")
    if tls not in ("true", "false"):
        errors.add("AMQP_TLS:invalid_boolean")
    if PREFIX + "AMQP_CA_FILE" in environment:
        if not values.get("AMQP_CA_FILE") or not _path(values["AMQP_CA_FILE"]):
            errors.add("AMQP_CA_FILE:invalid_format")
        if tls != "true":
            errors.add("AMQP_CA_FILE:requires_tls")
    for name in ("AMQP_USER", "AMQP_PASS", "AMQP_VHOST"):
        check(name, lambda value: len(value.encode("utf-8")) <= 255
              and value == value.strip())
    for name in ("EXCHANGE", "QUEUE"):
        check(name, lambda value: bool(TOPOLOGY.fullmatch(value))
              and not value.startswith("amq."))
    check("BINDING_KEY", lambda value: bool(BINDING.fullmatch(value)))
    check("FCM_SCOPE", lambda value: value == FCM_SCOPE)
    check("FCM_URL_TEMPLATE", lambda value: value == FCM_URL)

    apns_enabled = any(values.get(name) for name in APNS_REQUIRED + APNS_OVERRIDES)
    if apns_enabled:
        for name in APNS_REQUIRED:
            if not values.get(name):
                errors.add(name + ":required_for_apns")
        override_present = any(PREFIX + name in environment for name in APNS_OVERRIDES)
        if override_present:
            for name in APNS_OVERRIDES:
                if not values.get(name):
                    errors.add(name + ":required_override_pair")
    elif any(PREFIX + name in environment for name in APNS_OVERRIDES):
        errors.add("APNS_KEY_FILE_DEV:unconfigured_override")

    for name in ("APNS_KEY_FILE", "APNS_KEY_FILE_DEV"):
        check(name, _path)
    for name in ("APNS_KEY_ID", "APNS_TEAM_ID", "APNS_KEY_ID_DEV"):
        check(name, lambda value: bool(APPLE_ID.fullmatch(value)))
    check("APNS_TOPIC", lambda value: len(value) <= 249
          and bool(TOPIC.fullmatch(value)) and not value.endswith(".voip"))
    for name, host in APNS_HOSTS.items():
        check(name, lambda value, expected=host: value == expected)
    return tuple(sorted(errors))


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    if argv:
        print("usage: validate_config.py (reads environment only)", file=sys.stderr)
        return 2
    try:
        errors = validate(os.environ)
    except Exception:
        # No exception text or traceback can expose populated configuration.
        print("push_bridge_config_validation_failed", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print("push_bridge_config:" + error, file=sys.stderr)
        return 2
    print("push_bridge_config_shape_valid; activation_not_validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
