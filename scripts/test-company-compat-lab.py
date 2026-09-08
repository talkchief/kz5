#!/usr/bin/env python3
import importlib.util
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('lab', pathlib.Path(__file__).with_name('prepare-company-compat-lab.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class LabTests(unittest.TestCase):
    def test_unit_network_filesystem_and_identity_isolation(self):
        unit = lab.unit_text()
        for directive in ['PrivateNetwork=yes', 'User=kazoo-compat', 'Group=kazoo-compat',
                          'ProtectSystem=strict', 'ProtectHome=yes', 'CapabilityBoundingSet=',
                          'NoNewPrivileges=yes', 'ReadWritePaths=/var/lib/kazoo-compat-runtime',
                          'MemoryMax=4G', 'MemorySwapMax=0', 'CPUQuota=200%', 'Restart=no']:
            self.assertIn(directive + '\n', unit)
        self.assertNotIn('[Install]', unit)
        self.assertNotIn('JoinsNamespaceOf=', unit)
        self.assertIn('COUCHDB_INI_FILES=/opt/couchdb/etc/default.ini /var/lib/kazoo-compat-runtime/local.ini', unit)

    def test_configuration_has_no_production_or_main_dev_endpoints(self):
        text = lab.local_ini('fixture-secret') + lab.vm_args('fixture-cookie')
        self.assertIn('port = 25984', text)
        self.assertIn('n = 1', text)
        self.assertIn('os_process_limit = 8', text)
        self.assertIn('os_process_soft_limit = 4', text)
        self.assertIn('batch_channels = 1', text)
        self.assertIn('incremental_channels = 0', text)
        self.assertIn('compat_couchdb@127.0.0.1', text)
        self.assertIn('/var/lib/kazoo-compat-runtime/data', text)
        for foreign in ['10.1.0.10', '10.1.0.44', '10.1.0.26', '/etc/kazoo/', '/opt/couchdb/data']:
            self.assertNotIn(foreign, text)

    def test_foreign_host_rejected_before_writes(self):
        with patch.object(lab.os, 'geteuid', return_value=0), patch.object(lab.subprocess, 'check_output', return_value=b'[{"addr_info":[{"local":"10.1.0.10"}]}]'):
            with self.assertRaises(RuntimeError):
                lab.preflight()

    def test_existing_path_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(lab, 'BASE', pathlib.Path(directory)), patch.object(lab.os, 'geteuid', return_value=0), patch.object(lab.subprocess, 'check_output', return_value=b'[{"addr_info":[{"local":"10.1.0.44"}]}]'):
            with self.assertRaises(RuntimeError):
                lab.preflight()

    def test_exclusive_private_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'test'
            lab.write_exclusive(path, 'first', 0o600)
            with self.assertRaises(FileExistsError):
                lab.write_exclusive(path, 'second', 0o600)
            self.assertEqual(path.read_text(), 'first')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_symlink_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory) / 'target'
            target.write_text('keep')
            link = pathlib.Path(directory) / 'link'
            link.symlink_to(target)
            with self.assertRaises(FileExistsError):
                lab.write_exclusive(link, 'changed', 0o600)
            self.assertEqual(target.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
