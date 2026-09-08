#!/usr/bin/env python3
"""Offline remote-proof authority and TLS-failure classification tests."""
import importlib.util
import json
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('remote_proof', Path(__file__).with_name('accept-bridge-remote-tls.py'))
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)


class RemoteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        base = Path(cls.directory.name)
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=Offline fixture', '-keyout', str(base/'key'), '-out', str(base/'ca')],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=15)
        cls.ca = (base/'ca').read_text()

    @classmethod
    def tearDownClass(cls): cls.directory.cleanup()

    def fixture(self):
        return {'owner': 'kz5-bridge-proof', 'host': '10.1.0.44', 'port': 35671,
                'management_port': 35672, 'username': 'kz5-bridge-proof',
                'password': 'a'*64, 'vhost': 'kz5-bridge-proof', 'ca_pem': self.ca}

    def test_exact_fixture(self):
        value = self.fixture()
        self.assertEqual(remote.validate_fixture(value), value)

    def cleanup_settings(self):
        prefix = 'remote-' + 'a'*32
        return {'QUEUE': prefix + '.quorum-v1', 'EXCHANGE': prefix + '.pushes',
                'AMQP_HOST': '10.1.0.44', 'AMQP_PORT': 35671, 'AMQP_VHOST': 'kz5-bridge-proof',
                'AMQP_USER': 'kz5-bridge-proof', 'AMQP_TLS': 'true'}

    def test_cleanup_exact_drained_fixture_and_native_delete_shape(self):
        connection = MagicMock(); channel = connection.channel.return_value
        channel.queue.declare.return_value = {'message_count': 0, 'consumer_count': 0}
        channel.queue.delete.return_value = {'message_count': 0}
        settings = self.cleanup_settings()
        remote.cleanup_owned_resources(connection, settings)
        self.assertEqual(channel.queue.delete.call_count, 2)
        self.assertEqual(channel.queue.delete.call_args_list[0].kwargs, {'queue': settings['QUEUE']})
        self.assertEqual(channel.queue.delete.call_args_list[1].kwargs, {'queue': settings['QUEUE'] + '.dlq'})
        channel.close.assert_called_once()

    def test_cleanup_unsafe_scope_never_connects(self):
        for key, value in [('AMQP_HOST', '10.1.0.28'), ('AMQP_PORT', 5672), ('AMQP_VHOST', '/'),
                           ('AMQP_USER', 'guest'), ('AMQP_TLS', 'false'), ('QUEUE', 'customer'),
                           ('EXCHANGE', 'other')]:
            connection = MagicMock()
            with self.assertRaises(ValueError):
                remote.cleanup_owned_resources(connection, dict(self.cleanup_settings(), **{key: value}))
            connection.channel.assert_not_called()

    def test_cleanup_never_deletes_nonempty_or_active_or_unknown_queue(self):
        for observed in [{'message_count': 1, 'consumer_count': 0}, {'message_count': 0, 'consumer_count': 1},
                         {'message_count': False, 'consumer_count': 0}, {'message_count': 0}]:
            connection = MagicMock(); channel = connection.channel.return_value
            channel.queue.declare.return_value = observed
            with self.assertRaises(ValueError): remote.cleanup_owned_resources(connection, self.cleanup_settings())
            channel.queue.delete.assert_not_called(); channel.exchange.delete.assert_not_called()

    def test_cleanup_refuses_unexpected_deleted_count(self):
        connection = MagicMock(); channel = connection.channel.return_value
        channel.queue.declare.return_value = {'message_count': 0, 'consumer_count': 0}
        channel.queue.delete.return_value = {'message_count': 1}
        with self.assertRaises(ValueError): remote.cleanup_owned_resources(connection, self.cleanup_settings())
        channel.exchange.delete.assert_not_called()

    def test_management_identity_requires_cluster_and_node(self):
        settings = {'AMQP_USER': 'synthetic', 'AMQP_PASS': 'synthetic', 'AMQP_MANAGEMENT_CA_FILE': 'ca.pem'}
        for cluster, node, valid in [('rabbit_kz5_bridgeproof@dev-testing', 'rabbit_kz5_bridgeproof@localhost', True),
                                     ('rabbit@dev-testing', 'rabbit@dev-testing', False),
                                     ('rabbit_kz5_bridgeproof@dev-testing', 'rabbit@localhost', False),
                                     ('rabbit_kz5_bridgeproof@localhost', 'rabbit_kz5_bridgeproof@localhost', False)]:
            with patch('requests.Session') as factory:
                session = factory.return_value.__enter__.return_value
                response = session.get.return_value.__enter__.return_value
                response.status_code = 200
                response.iter_content.return_value = [json.dumps({'cluster_name': cluster, 'node': node}).encode()]
                if valid: remote.check_broker_identity(settings)
                else:
                    with self.assertRaises(ValueError): remote.check_broker_identity(settings)
                self.assertFalse(session.trust_env)
                self.assertEqual(session.get.call_args.args, ('https://10.1.0.44:35672/api/overview',))
                self.assertFalse(session.get.call_args.kwargs['allow_redirects'])
                self.assertEqual(session.get.call_args.kwargs['verify'], 'ca.pem')

    def test_foreign_or_ambiguous_fixture_before_network(self):
        with patch.object(remote.socket, 'create_connection') as network:
            for key, value in [('host', '10.1.0.28'), ('host', '127.0.0.1'), ('port', 5672),
                               ('port', '35671'), ('username', 'guest'), ('vhost', '/'),
                               ('owner', 'other'), ('management_port', 15672), ('password', 'invalid')]:
                with self.subTest(key=key):
                    with self.assertRaises(ValueError): remote.validate_fixture(dict(self.fixture(), **{key: value}))
            with self.assertRaises(ValueError): remote.validate_fixture(dict(self.fixture(), unexpected=True))
            network.assert_not_called()

    def test_ca_parser_refuses_secret_and_invalid_material(self):
        for value in ['', 'invalid PEM', 'PRIVATE KEY', self.ca + 'PRIVATE KEY', 'x'*16385]:
            with self.assertRaises((ValueError, ssl.SSLError)):
                remote.validate_fixture(dict(self.fixture(), ca_pem=value))

    def test_positive_tls_version_and_exact_target(self):
        context = MagicMock()
        context.wrap_socket.return_value.__enter__.return_value.version.return_value = 'TLSv1.3'
        with patch.object(remote.socket, 'create_connection') as connect:
            self.assertEqual(remote.tls_probe(context), 'TLSv1.3')
            connect.assert_called_once_with(('10.1.0.44', 35671), timeout=5)
        context.wrap_socket.assert_called_once()
        self.assertEqual(context.wrap_socket.call_args.kwargs['server_hostname'], '10.1.0.44')

    def test_certificate_negatives_require_correct_verification_reason(self):
        for reason, codes in [('hostname', [62, 64]), ('authority', [18, 19, 20, 21])]:
            for code in codes:
                error = ssl.SSLCertVerificationError(1, 'synthetic')
                error.verify_code = code
                context = MagicMock()
                context.wrap_socket.side_effect = error
                with patch.object(remote.socket, 'create_connection'):
                    self.assertEqual(remote.tls_probe(context, expected_failure=reason), 'certificate_rejected')
                    with self.assertRaises(ValueError): remote.tls_probe(context)
                    other = 'authority' if reason == 'hostname' else 'hostname'
                    with self.assertRaises(ValueError): remote.tls_probe(context, expected_failure=other)

    def test_timeout_and_network_errors_never_count_as_certificate_refusal(self):
        for error in [TimeoutError(), ConnectionRefusedError(), socket.gaierror()]:
            with patch.object(remote.socket, 'create_connection', side_effect=error):
                with self.assertRaises(OSError): remote.tls_probe(MagicMock(), expected_failure='authority')

    def test_old_tls_or_unexpected_success_refused(self):
        for version, reason in [('TLSv1.1', None), ('TLSv1.3', 'hostname')]:
            context = MagicMock()
            context.wrap_socket.return_value.__enter__.return_value.version.return_value = version
            with patch.object(remote.socket, 'create_connection'):
                with self.assertRaises(ValueError): remote.tls_probe(context, expected_failure=reason)

    def test_host_and_flag_boundaries_before_fixture_read(self):
        for argv, host, uid in [([], 'kz5-testing', 0),
                               (['--run-development-remote-tls-proof'], 'production', 0),
                               (['--run-development-remote-tls-proof'], 'kz5-testing', 1000)]:
            with patch.object(remote.sys, 'argv', ['test', *argv]), \
                    patch.object(remote.socket, 'gethostname', return_value=host), \
                    patch.object(remote.os, 'geteuid', return_value=uid), \
                    patch.object(remote, 'protected_read') as read:
                with self.assertRaises(ValueError): remote.main()
                read.assert_not_called()


if __name__ == '__main__': unittest.main()
