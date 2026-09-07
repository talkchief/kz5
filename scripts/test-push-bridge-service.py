#!/usr/bin/env python3
"""Offline service configuration/readiness tests; no credentials or network."""
import importlib.util
import json
from pathlib import Path
import sys
import stat
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "services/push-bridge"
sys.path.insert(0, str(SOURCE))
import service_launcher as launcher
import service_notify as notifier


def configuration():
    value = json.loads((SOURCE / "config.json.example").read_text())
    value.update(PUSH_BRIDGE_AMQP_HOST="broker.example.invalid",
                 PUSH_BRIDGE_AMQP_USER="synthetic", PUSH_BRIDGE_AMQP_PASS="synthetic",
                 PUSH_BRIDGE_QUEUE="fixture-mobile", PUSH_BRIDGE_BINDING_KEY="#")
    return value


def synthetic_ca():
    # Temporary keyless-input fixture: never reads a deployed key or file.
    # The installed pinned venv supplies cryptography for fixture generation;
    # the production launcher validates PEM with stdlib ssl only.
    import datetime
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Synthetic offline CA")])
    now = datetime.datetime.now(datetime.timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=1))
                   .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
                   .sign(key, hashes.SHA256()))
    return certificate.public_bytes(serialization.Encoding.PEM)


class ServiceTests(unittest.TestCase):
    def checked(self, data, service_account=None):
        if service_account is None:
            service_account = {"type": "service_account", "project_id": "fixture-project",
                               "private_key": "synthetic-not-a-key", "client_email": "fixture@example.invalid",
                               "token_uri": "https://oauth2.googleapis.com/token"}
        with mock.patch.object(launcher, "protected_read", side_effect=[json.dumps(data).encode(),
                                                                      json.dumps(service_account).encode()]), \
                mock.patch.object(launcher.grp, "getgrnam", side_effect=KeyError):
            return launcher.load_configuration()

    def test_valid_data_only_configuration(self):
        self.assertEqual(self.checked(configuration()), configuration())

    def test_duplicate_json_rejected(self):
        with self.assertRaises(ValueError):
            json.loads('{"a":"first","a":"second"}', object_pairs_hook=launcher.unique_object)

    def test_missing_broker_rejected(self):
        value = configuration()
        del value["PUSH_BRIDGE_AMQP_HOST"]
        with self.assertRaises(ValueError):
            self.checked(value)

    def test_unknown_or_unrelated_config_rejected(self):
        for key in ("PATH", "PUSH_BRIDGE_TEST_PAYLOAD_JSON", "PUSH_BRIDGE_NEW_UNKNOWN"):
            value = configuration()
            value[key] = "synthetic"
            with self.assertRaises(ValueError):
                self.checked(value)

    def test_credentials_outside_service_directory_rejected(self):
        value = configuration()
        value["PUSH_BRIDGE_SA_FILE"] = "/root/private.json"
        with self.assertRaises(ValueError):
            self.checked(value)

    def test_no_unreviewed_token_endpoint(self):
        account = {"type": "service_account", "project_id": "fixture-project",
                   "private_key": "synthetic", "client_email": "fixture@example.invalid",
                   "token_uri": "https://unexpected.example.invalid/token"}
        with self.assertRaises(ValueError):
            self.checked(configuration(), account)

    def test_custom_ca_is_protected_service_file_and_never_a_private_key(self):
        value = configuration()
        value.update(PUSH_BRIDGE_AMQP_TLS="true", PUSH_BRIDGE_AMQP_CA_FILE="/etc/kazoo-push-bridge/broker-ca.pem")
        account = json.dumps({"type": "service_account", "project_id": "fixture-project",
                              "private_key": "synthetic", "client_email": "fixture@example.invalid",
                              "token_uri": "https://oauth2.googleapis.com/token"}).encode()
        for raw, valid in ((synthetic_ca(), True),
                           (b"-----BEGIN CERTIFICATE-----\nsynthetic\n-----END CERTIFICATE-----", False),
                           (b"invalid-synthetic-bundle", False),
                           (b"-----BEGIN CERTIFICATE-----\n-----BEGIN PRIVATE KEY-----", False)):
            with mock.patch.object(launcher, "protected_read", side_effect=[json.dumps(value).encode(), account, raw]) as reader, \
                    mock.patch.object(launcher.grp, "getgrnam", side_effect=KeyError):
                if valid:
                    self.assertEqual(launcher.load_configuration(), value)
                else:
                    with self.assertRaisesRegex(ValueError, "^invalid_amqp_ca_bundle$"):
                        launcher.load_configuration()
                self.assertEqual(reader.call_args.args, (value["PUSH_BRIDGE_AMQP_CA_FILE"], 65536, None))
        value["PUSH_BRIDGE_AMQP_CA_FILE"] = "/root/outside-ca.pem"
        with mock.patch.object(launcher, "protected_read", side_effect=[json.dumps(value).encode(), account]), \
                mock.patch.object(launcher.grp, "getgrnam", side_effect=KeyError):
            with self.assertRaisesRegex(ValueError, "^credentials_must_use_service_directory$"):
                launcher.load_configuration()
        self.assertIn("PUSH_BRIDGE_AMQP_CA_FILE", launcher.PROTECTED_FILE_KEYS)

    def test_permission_preparation_includes_only_exact_validated_custom_ca(self):
        value = configuration()
        value.update(PUSH_BRIDGE_AMQP_TLS="true", PUSH_BRIDGE_AMQP_CA_FILE="/etc/kazoo-push-bridge/broker-ca.pem")
        with mock.patch.object(launcher, "load_configuration", return_value=value), \
                mock.patch.object(launcher.os, "geteuid", return_value=0), \
                mock.patch.object(launcher.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=42)), \
                mock.patch.object(launcher.os, "open", side_effect=[90, 91, 92, 93]) as opened, \
                mock.patch.object(launcher.os, "fchown") as ownership, \
                mock.patch.object(launcher.os, "fchmod") as modes, \
                mock.patch.object(launcher.os, "close"):
            self.assertEqual(launcher.main(["--prepare-permissions"]), 0)
        self.assertEqual(opened.call_args.args[0], value["PUSH_BRIDGE_AMQP_CA_FILE"])
        self.assertTrue(opened.call_args.args[1] & launcher.os.O_NOFOLLOW)
        self.assertEqual(ownership.call_args.args, (93, 0, 42))
        self.assertEqual(modes.call_args.args, (93, 0o640))

    def test_non_object_config(self):
        with self.assertRaises(ValueError):
            self.checked([])

    def test_fixed_failure_without_exception_payload(self):
        with mock.patch.object(launcher, "load_configuration", side_effect=ValueError("SENSITIVE")), \
                mock.patch("sys.stderr") as output:
            self.assertEqual(launcher.main(["--check"]), 78)
            self.assertNotIn("SENSITIVE", str(output.mock_calls))

    def test_protected_reader_rejects_writable_parent_before_open(self):
        directory = SimpleNamespace(st_mode=stat.S_IFDIR | 0o777, st_uid=0)
        with mock.patch.object(Path, "lstat", return_value=directory), \
                mock.patch.object(launcher.os, "open", side_effect=AssertionError):
            with self.assertRaises(ValueError):
                launcher.protected_read("/etc/kazoo-push-bridge/config.json", 32768)

    def test_protected_reader_rejects_wrong_owner_mode_type_size_group(self):
        directory = SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
        for mode, owner, group, size in ((stat.S_IFREG | 0o644, 0, 42, 100),
                                        (stat.S_IFREG | 0o600, 1000, 42, 100),
                                        (stat.S_IFIFO | 0o600, 0, 42, 100),
                                        (stat.S_IFREG | 0o600, 0, 42, 999999),
                                        (stat.S_IFREG | 0o640, 0, 999, 100)):
            file = SimpleNamespace(st_mode=mode, st_uid=owner, st_gid=group, st_size=size)
            with mock.patch.object(Path, "lstat", return_value=directory), \
                    mock.patch.object(launcher.os, "open", return_value=99) as opened, \
                    mock.patch.object(launcher.os, "fstat", return_value=file), \
                    mock.patch.object(launcher.os, "close") as closed:
                with self.assertRaises(ValueError):
                    launcher.protected_read("/etc/kazoo-push-bridge/config.json", 32768, 42)
                self.assertTrue(opened.call_args.args[1] & launcher.os.O_NOFOLLOW)
                closed.assert_called_once_with(99)

    def test_dependency_lock_rejects_mismatch_without_credentials(self):
        with mock.patch.object(launcher.metadata, "version", return_value="0.0.0"), \
                mock.patch.object(launcher, "load_configuration", side_effect=AssertionError), \
                mock.patch("sys.stderr"):
            self.assertEqual(launcher.main(["--check-dependencies"]), 78)

    def test_offline_check_never_imports_runtime(self):
        with mock.patch.object(launcher, "load_configuration", return_value=configuration()), \
                mock.patch("builtins.print"), mock.patch.dict(sys.modules, {"bridge": None}):
            self.assertEqual(launcher.main(["--check"]), 0)

    def test_notification_absent_outside_systemd(self):
        with mock.patch.dict(notifier.os.environ, {}, clear=True), \
                mock.patch.object(notifier.socket, "socket", side_effect=AssertionError):
            notifier.notify_consumer_ready()
            notifier.notify_status(False)

    def test_actual_readiness_message_and_disconnect(self):
        with mock.patch.dict(notifier.os.environ, {"NOTIFY_SOCKET": "@fixture"}, clear=True), \
                mock.patch.object(notifier.socket, "socket") as constructor:
            connection = constructor.return_value.__enter__.return_value
            notifier.notify_consumer_ready()
            connection.connect.assert_called_with("\0fixture")
            connection.sendall.assert_called_with(b"READY=1\nSTATUS=AMQP consumer registered; mobile delivery not verified")
            notifier.notify_status(False)
            connection.sendall.assert_called_with(b"STATUS=AMQP consumer disconnected")

    def test_unit_hardening_and_actual_consumer_signal(self):
        unit = (SOURCE / "kazoo-push-bridge.service").read_text()
        for directive in ("Type=notify", "NotifyAccess=main", "User=kazoo-push-bridge",
                          "RestartPreventExitStatus=2 78", "ProtectSystem=strict",
                          "ProtectHome=yes", "NoNewPrivileges=yes", "MemoryMax=384M",
                          "TimeoutStopSec=15", "LimitCORE=0"):
            self.assertIn(directive, unit)
        source = (SOURCE / "bridge.py").read_text()
        self.assertLess(source.index("channel.basic.consume("), source.index("notify_consumer_ready()"))


if __name__ == "__main__":
    unittest.main()
