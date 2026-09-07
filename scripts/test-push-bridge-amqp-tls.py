#!/usr/bin/env python3
"""Offline pinned AMQPStorm handoff and real in-memory TLS verification.

Synthetic temporary CA/server certificates are created only when root runs this
suite. No broker, provider, deployed credential or network socket is accessed.
"""
import datetime
from importlib.metadata import version
from pathlib import Path
import socket
import ssl
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import amqpstorm
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services/push-bridge"))
import bridge


class AmqpTlsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="push-bridge-synthetic-tls-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        now = datetime.datetime.now(datetime.timezone.utc)
        ca_key = ec.generate_private_key(ec.SECP256R1())
        ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Synthetic offline CA")])
        ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name)
              .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
              .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=1))
              .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
              .add_extension(x509.KeyUsage(True, False, False, False, False, True, True, False, False), critical=True)
              .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
              .sign(ca_key, hashes.SHA256()))
        server_key = ec.generate_private_key(ec.SECP256R1())
        leaf = (x509.CertificateBuilder()
                .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "broker.fixture.invalid")]))
                .issuer_name(ca_name).public_key(server_key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=1))
                .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                .add_extension(x509.SubjectAlternativeName([x509.DNSName("broker.fixture.invalid")]), critical=False)
                .add_extension(x509.KeyUsage(True, False, False, False, False, False, False, False, False), critical=True)
                .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
                .add_extension(x509.SubjectKeyIdentifier.from_public_key(server_key.public_key()), critical=False)
                .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
                .sign(ca_key, hashes.SHA256()))
        cls.ca_file = directory / "ca.pem"
        cls.ca_file.write_bytes(ca.public_bytes(serialization.Encoding.PEM))
        cert_file, key_file = directory / "server.pem", directory / "server.key"
        cert_file.write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
        key_file.write_bytes(server_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                     serialization.NoEncryption()))
        key_file.chmod(0o600)
        cls.server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.server_context.minimum_version = ssl.TLSVersion.TLSv1_2
        cls.server_context.load_cert_chain(cert_file, key_file)

    def setUp(self):
        self.assertEqual(version("AMQPStorm"), "2.11.1")
        guard = patch.object(socket, "socket", side_effect=AssertionError("network socket forbidden"))
        guard.start()
        self.addCleanup(guard.stop)

    def options(self, custom=True):
        settings = {"AMQP_TLS": "true", "AMQP_HOST": "broker.fixture.invalid"}
        if custom:
            settings["AMQP_CA_FILE"] = str(self.ca_file)
        return bridge.amqp_tls_options(settings)

    def handshake(self, context, hostname):
        client_in, client_out = ssl.MemoryBIO(), ssl.MemoryBIO()
        server_in, server_out = ssl.MemoryBIO(), ssl.MemoryBIO()
        client = context.wrap_bio(client_in, client_out, server_hostname=hostname)
        server = self.server_context.wrap_bio(server_in, server_out, server_side=True)
        complete = [False, False]
        for _ in range(20):
            for index, connection in enumerate((client, server)):
                if not complete[index]:
                    try:
                        connection.do_handshake()
                        complete[index] = True
                    except ssl.SSLWantReadError:
                        pass
            for outgoing, incoming in ((client_out, server_in), (server_out, client_in)):
                data = outgoing.read()
                if data:
                    incoming.write(data)
            if all(complete):
                return client
        self.fail("synthetic TLS handshake did not finish")

    def test_default_plaintext_never_constructs_tls_context(self):
        with patch.object(ssl, "create_default_context", side_effect=AssertionError("unexpected TLS initialization")):
            self.assertEqual(bridge.amqp_tls_options({}), {})
            self.assertEqual(bridge.amqp_tls_options({"AMQP_TLS": "false"}), {})

    def test_system_and_custom_contexts_require_certificate_hostname_and_tls12(self):
        for custom in (False, True):
            options = self.options(custom)
            self.assertTrue(options["ssl"])
            self.assertEqual(options["ssl_options"]["server_hostname"], "broker.fixture.invalid")
            context = options["ssl_options"]["context"]
            self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
            self.assertTrue(context.check_hostname)
            self.assertGreaterEqual(context.minimum_version, ssl.TLSVersion.TLSv1_2)

    def test_real_tls_accepts_only_trusted_matching_broker(self):
        context = self.options()["ssl_options"]["context"]
        client = self.handshake(context, "broker.fixture.invalid")
        self.assertIn(client.version(), ("TLSv1.2", "TLSv1.3"))
        with self.assertRaises(ssl.SSLCertVerificationError):
            self.handshake(context, "wrong.fixture.invalid")
        with self.assertRaises(ssl.SSLCertVerificationError):
            self.handshake(self.options(custom=False)["ssl_options"]["context"], "broker.fixture.invalid")

    def test_bad_ca_load_fails_with_fixed_error_without_plaintext_fallback(self):
        with patch.object(ssl, "create_default_context", side_effect=OSError("sensitive-ca-path")):
            with self.assertRaisesRegex(ValueError, "^invalid_amqp_tls_configuration$"):
                self.options()
        for tls in ("", "yes", "TRUE"):
            with self.assertRaisesRegex(ValueError, "^invalid_amqp_tls_configuration$"):
                bridge.amqp_tls_options({"AMQP_TLS": tls})

    def test_runtime_passes_exact_context_to_pinned_amqpstorm_and_io_uses_it(self):
        runtime = bridge.BridgeRuntime.__new__(bridge.BridgeRuntime)
        runtime._settings = {"AMQP_HOST": "broker.fixture.invalid", "AMQP_USER": "synthetic",
                             "AMQP_PASS": "synthetic-not-a-password", "AMQP_PORT": 15671, "AMQP_VHOST": "/fixture"}
        runtime._amqp_tls_options = self.options()
        runtime.amqpstorm = amqpstorm
        # Real Connection initialization and parameter handoff, but no open,
        # authentication, inbound thread or broker socket.
        with patch.object(amqpstorm.Connection, "open") as opened:
            connection = runtime._connect_amqp()
        opened.assert_called_once_with()
        context = runtime._amqp_tls_options["ssl_options"]["context"]
        self.assertTrue(connection.parameters["ssl"])
        self.assertEqual(connection.parameters["port"], 15671)
        self.assertIs(connection.parameters["ssl_options"]["context"], context)
        self.assertEqual(connection.parameters["timeout"], 10)
        raw, wrapped = object(), object()
        with patch.object(context, "wrap_socket", return_value=wrapped) as wrap, \
                patch.object(ssl, "SSLContext", side_effect=AssertionError("pinned client ignored explicit context")):
            self.assertIs(connection._io._ssl_wrap_socket(raw), wrapped)
        wrap.assert_called_once_with(raw, do_handshake_on_connect=True, server_hostname="broker.fixture.invalid")
        with patch.object(context, "wrap_socket", side_effect=ssl.SSLCertVerificationError("synthetic mismatch")) as wrap:
            with self.assertRaises(ssl.SSLCertVerificationError):
                connection._io._ssl_wrap_socket(raw)
        wrap.assert_called_once()


if __name__ == "__main__":
    unittest.main()
