#!/usr/bin/env python3
"""Offline authority/config regression; no accounts, services or listeners."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('setup', Path(__file__).with_name('prepare-bridge-remote-proof.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def test_tls_only_fixed_private_scope(self):
        config = setup.broker_configuration('a' * 64)
        self.assertIn('listeners.tcp = none\n', config)
        self.assertIn('listeners.ssl.1 = 10.1.0.44:35671\n', config)
        self.assertIn('management.ssl.ip = 10.1.0.44\n', config)
        self.assertNotIn('management.tcp.', config)
        self.assertNotIn('/etc/rabbitmq', config)
        self.assertIn('default_user = kz5-bridge-proof\n', config)
        self.assertIn('default_vhost = kz5-bridge-proof\n', config)

    def test_password_injection_refused(self):
        for password in ['short', 'a' * 64 + '\n', 'a' * 63 + '!', 'a' * 63 + 'é']:
            with self.assertRaises(ValueError): setup.broker_configuration(password)

    def test_separate_node_and_data(self):
        unit = setup.service_unit()
        for expected in ['User=kz5-bridge-proof', 'ERL_EPMD_PORT=35369',
                         'ERL_EPMD_ADDRESS=127.0.0.1', 'RABBITMQ_DIST_PORT=35370',
                         'RABBITMQ_NODENAME=rabbit_kz5_bridgeproof@localhost',
                         'RABBITMQ_CONFIG_FILE=/var/lib/kz5-bridge-remote-proof/rabbitmq.conf',
                         'RABBITMQ_MNESIA_BASE=/var/lib/kz5-bridge-remote-proof/mnesia',
                         'RABBITMQ_ADVANCED_CONFIG_FILE=/var/lib/kz5-bridge-remote-proof/advanced.config']:
            self.assertIn(expected, unit)
        self.assertNotIn('/var/lib/rabbitmq', unit)
        self.assertNotIn('setcookie', unit)
        self.assertNotIn('HOME=', unit)

    def test_bounded_not_enabled(self):
        unit = setup.service_unit()
        for expected in ['RuntimeMaxSec=3600', 'MemoryMax=1G', 'MemorySwapMax=0',
                         'CPUQuota=200%', 'TasksMax=256', 'Restart=no', 'NoNewPrivileges=true',
                         'ProtectSystem=strict', 'KillMode=control-group']:
            self.assertIn(expected, unit)
        self.assertNotIn('[Install]', unit)
        self.assertNotIn('rabbitmq-server.service', unit)

    def test_wrong_host_no_command(self):
        with patch.object(setup.os, 'geteuid', return_value=0), \
                patch.object(setup.socket, 'gethostname', return_value='production'), \
                patch.object(setup, 'run') as command:
            with self.assertRaises(ValueError): setup.create()
            command.assert_not_called()

    def test_nonroot_no_command(self):
        with patch.object(setup.os, 'geteuid', return_value=1000), patch.object(setup, 'run') as command:
            with self.assertRaises(ValueError): setup.create()
            command.assert_not_called()

    def test_existing_state_no_command(self):
        with patch.object(setup.os, 'geteuid', return_value=0), \
                patch.object(setup.socket, 'gethostname', return_value='dev-testing'), \
                patch.object(setup.Path, 'exists', return_value=True), \
                patch.object(setup, 'run') as command:
            with self.assertRaises(ValueError): setup.create()
            command.assert_not_called()


if __name__ == '__main__': unittest.main()
