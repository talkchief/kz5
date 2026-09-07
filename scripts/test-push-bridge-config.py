#!/usr/bin/env python3
"""Offline stdlib tests: no sender imports, credentials, broker, or providers."""

import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "services/push-bridge/validate_config.py"
spec = importlib.util.spec_from_file_location("push_bridge_config", SOURCE)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


def environment(apns=False):
    values = {
        "SA_FILE": "/fixture/not-a-real-credential.json",
        "AMQP_HOST": "broker.example.invalid",
        "AMQP_USER": "fixture-user",
        "AMQP_PASS": "fixture-secret-not-a-real-password",
        "AMQP_VHOST": "/fixture",
        "EXCHANGE": "pushes",
        "QUEUE": "fixture-mobile-push",
        "BINDING_KEY": "notification.push.*",
        "FCM_SCOPE": config.FCM_SCOPE,
        "FCM_URL_TEMPLATE": config.FCM_URL,
    }
    if apns:
        values.update({
            "APNS_KEY_FILE": "/fixture/not-a-real-key.p8",
            "APNS_KEY_ID": "ABCDEFGHIJ",
            "APNS_TEAM_ID": "0123456789",
            "APNS_TOPIC": "invalid.example.fixture",
            **config.APNS_HOSTS,
        })
    return {config.PREFIX + name: value for name, value in values.items()}


class ConfigTests(unittest.TestCase):
    def test_retry_requires_explicit_verified_topology_and_strict_freshness(self):
        candidate = environment()
        candidate[config.PREFIX + "RETRY"] = "quorum-counted-v1"
        errors = config.validate(candidate)
        self.assertIn("RETRY:requires_quorum", errors); self.assertIn("RETRY:requires_freshness", errors)
        candidate.update({config.PREFIX + "TOPOLOGY": "quorum-v1", config.PREFIX + "FRESHNESS": "unix-ms-v1",
                          config.PREFIX + "QUEUE": "fixture-mobile.quorum-v1",
                          config.PREFIX + "AMQP_MANAGEMENT_URL": "https://broker.example.invalid:15671"})
        with patch("builtins.open", side_effect=AssertionError("unexpected file access")):
            self.assertEqual(config.validate(candidate), ())
        for value in ("legacy", "", "true", "quorum-counted-v2", "fixture-private-value"):
            candidate[config.PREFIX + "RETRY"] = value
            self.assertIn("RETRY:invalid_mode", config.validate(candidate))

    def test_valid_configs_do_not_read_files_or_import_providers(self):
        with patch("builtins.open", side_effect=AssertionError("unexpected file access")):
            self.assertEqual(config.validate(environment()), ())
            self.assertEqual(config.validate(environment(apns=True)), ())
        for module in ("bridge", "apns_sender", "amqpstorm", "requests", "google.auth", "ecdsa", "h2"):
            self.assertNotIn(module, sys.modules)

    def test_every_required_input_fails_closed(self):
        for name in config.REQUIRED:
            for value in (None, ""):
                with self.subTest(name=name, value=value):
                    candidate = environment()
                    if value is None:
                        del candidate[config.PREFIX + name]
                    else:
                        candidate[config.PREFIX + name] = value
                    self.assertIn(name + ":required", config.validate(candidate))

    def test_numeric_boundaries_and_noncanonical_values(self):
        for name, (_default, low, high) in config.NUMBERS.items():
            for value in (str(low), str(high)):
                candidate = environment()
                candidate[config.PREFIX + name] = value
                self.assertEqual(config.validate(candidate), ())
            for value in ("", "0", str(high + 1), "-1", "+1", " 32", "3.2", "1e2", "9" * 4096):
                candidate = environment()
                candidate[config.PREFIX + name] = value
                self.assertIn(name + ":invalid_range", config.validate(candidate))

    def test_provider_endpoint_and_scope_policy(self):
        for name, bad_values in {
            "FCM_SCOPE": ["arbitrary", config.FCM_SCOPE + " extra"],
            "FCM_URL_TEMPLATE": ["http://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
                                 config.FCM_URL + "?token=fixture", config.FCM_URL.replace("fcm.googleapis.com", "fcm.googleapis.com.evil.invalid"),
                                 config.FCM_URL.replace("{project_id}", "{project_id.__class__}"),
                                 config.FCM_URL.replace("https://", "https://user:pass@")],
            "APNS_HOST_PROD": ["api.push.apple.com.evil.invalid", "https://api.push.apple.com", "api.push.apple.com:443", "api.sandbox.push.apple.com"],
            "APNS_HOST_DEV": ["api.push.apple.com", "api.sandbox.push.apple.com/"],
        }.items():
            for value in bad_values:
                candidate = environment(apns=True)
                candidate[config.PREFIX + name] = value
                self.assertIn(name + ":invalid_format", config.validate(candidate))

    def test_explicit_amqp_tls_and_ca_settings_fail_closed(self):
        for tls in ("true", "false"):
            candidate = environment()
            candidate[config.PREFIX + "AMQP_TLS"] = tls
            with patch("builtins.open", side_effect=AssertionError("no trust-file I/O in shape validation")):
                self.assertEqual(config.validate(candidate), ())
        for tls in ("", "TRUE", "False", "1", "0", "yes", " true"):
            candidate = environment()
            candidate[config.PREFIX + "AMQP_TLS"] = tls
            self.assertIn("AMQP_TLS:invalid_boolean", config.validate(candidate))
        candidate = environment()
        candidate[config.PREFIX + "AMQP_CA_FILE"] = "/etc/kazoo-push-bridge/broker-ca.pem"
        self.assertIn("AMQP_CA_FILE:requires_tls", config.validate(candidate))
        candidate[config.PREFIX + "AMQP_TLS"] = "true"
        self.assertEqual(config.validate(candidate), ())
        for path in ("", "relative.pem", "/etc/../ca.pem", "/tmp/ca secret.pem"):
            candidate[config.PREFIX + "AMQP_CA_FILE"] = path
            self.assertIn("AMQP_CA_FILE:invalid_format", config.validate(candidate))
        for name in ("AMQP_VERIFY", "AMQP_SERVER_HOSTNAME", "AMQP_CERT_NONE"):
            candidate = environment()
            candidate[config.PREFIX + name] = "false"
            self.assertIn("unknown_or_test_setting", config.validate(candidate))

    def test_hosts_paths_topology_and_types(self):
        for host in ("127.0.0.1", "2001:db8::1", "broker", "broker.example.invalid"):
            candidate = environment()
            candidate[config.PREFIX + "AMQP_HOST"] = host
            self.assertEqual(config.validate(candidate), ())
        for name, values in {
            "AMQP_HOST": ["amqp://host", "user@host", "host:5672", "host/path", "host.", "fe80::1%eth0", "bad..host"],
            "SA_FILE": ["relative", "/", "/a/../b", "/a/./b", "/a//b", "/a/b/", "/a/$file", "/a/$(command)", "/a/has space"],
            "EXCHANGE": ["amq.reserved", "name/with/slash", "a" * 256],
            "QUEUE": ["amq.reserved", "name with spaces"],
            "BINDING_KEY": ["name with spaces", "a" * 256],
            "AMQP_USER": [" spaced", "name "],
        }.items():
            for value in values:
                candidate = environment()
                candidate[config.PREFIX + name] = value
                self.assertIn(name + ":invalid_format", config.validate(candidate))
        for value in (None, 32, [], "invalid\nsecret", "secret\x00", "x" * 4097):
            candidate = environment()
            candidate[config.PREFIX + "AMQP_PASS"] = value
            self.assertIn("AMQP_PASS:invalid_value", config.validate(candidate))

    def test_apns_requires_complete_config_and_override_pair(self):
        candidate = environment()
        candidate.update({config.PREFIX + name: "" for name in config.APNS_REQUIRED})
        self.assertEqual(config.validate(candidate), ())
        for name in config.APNS_REQUIRED:
            candidate = environment(apns=True)
            del candidate[config.PREFIX + name]
            self.assertIn(name + ":required_for_apns", config.validate(candidate))
        for name in config.APNS_OVERRIDES:
            candidate = environment(apns=True)
            candidate[config.PREFIX + name] = ""
            self.assertTrue(any("required_override_pair" in error for error in config.validate(candidate)))
        candidate = environment(apns=True)
        candidate.update({config.PREFIX + "APNS_KEY_FILE_DEV": "/fixture/sandbox.p8",
                          config.PREFIX + "APNS_KEY_ID_DEV": "KLMNOPQRST"})
        self.assertEqual(config.validate(candidate), ())
        for name, value in (("APNS_TOPIC", "invalid.example.fixture.voip"), ("APNS_KEY_ID", "short"), ("APNS_TEAM_ID", "lowercases")):
            candidate = environment(apns=True)
            candidate[config.PREFIX + name] = value
            self.assertIn(name + ":invalid_format", config.validate(candidate))

    def test_unknown_test_settings_and_diagnostics_never_echo_values_or_unknown_names(self):
        candidate = environment()
        candidate[config.PREFIX + "unknown-fixture-secret"] = "fixture-secret"
        candidate[config.PREFIX + "TEST_PAYLOAD_JSON"] = '{"token":"fixture-token"}'
        candidate[config.PREFIX + "AMQP_PORT"] = "fixture-secret"
        errors = config.validate(candidate)
        self.assertEqual(errors, ("AMQP_PORT:invalid_range", "unknown_or_test_setting"))
        with patch.dict(os.environ, candidate, clear=True), patch("sys.stderr", new_callable=io.StringIO) as output:
            self.assertEqual(config.main([]), 2)
            self.assertNotIn("fixture", output.getvalue())
        with patch.object(config, "validate", side_effect=RuntimeError("fixture-secret")), patch("sys.stderr", new_callable=io.StringIO) as output:
            self.assertEqual(config.main([]), 2)
            self.assertEqual(output.getvalue(), "push_bridge_config_validation_failed\n")

    def test_cli_isolated_success_is_not_activation_and_arguments_are_not_printed(self):
        result = subprocess.run([sys.executable, "-B", "-I", str(SOURCE)], env=environment(),
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout, "push_bridge_config_shape_valid; activation_not_validated\n")
        result = subprocess.run([sys.executable, "-B", "-I", str(SOURCE), "fixture-secret"], env={},
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("fixture-secret", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
