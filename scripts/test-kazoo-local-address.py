#!/usr/bin/env python3
import importlib.util
import ipaddress
import pathlib
import subprocess
import unittest
from unittest.mock import patch

PATH = pathlib.Path(__file__).with_name('wait-kazoo-local-address.py')
spec = importlib.util.spec_from_file_location('address_gate', PATH)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class AddressGateTests(unittest.TestCase):
    def run_wait(self, wanted, reads, timeout=3):
        now = [0]
        def sleep(delay):
            now[0] += delay
        def read():
            value = next(reads)
            if isinstance(value, Exception):
                raise value
            return {ipaddress.ip_address(address) for address in value}
        return gate.wait_addresses(wanted, timeout, read, lambda: now[0], sleep), now[0]

    def test_delayed_private_interface(self):
        self.assertEqual(self.run_wait(['10.1.0.44'], iter([[], ['127.0.0.1'], ['10.1.0.44']])), (True, 2))

    def test_all_interfaces_required(self):
        self.assertEqual(self.run_wait(['10.1.0.44', '46.225.31.248'], iter([['10.1.0.44'], ['10.1.0.44', '46.225.31.248']])), (True, 1))

    def test_timeout_fail_closed(self):
        self.assertEqual(self.run_wait(['10.1.0.44'], iter([[]] * 4)), (False, 3))

    def test_query_error_not_readiness(self):
        self.assertEqual(self.run_wait(['10.1.0.44'], iter([OSError(), ['10.1.0.44']])), (True, 1))

    def test_wildcard_needs_no_specific_interface(self):
        self.assertEqual(self.run_wait(['0.0.0.0', '::'], iter([])), (True, 0))

    def test_ipv6_normalization(self):
        self.assertEqual(self.run_wait(['0:0:0:0:0:0:0:1'], iter([['::1']])), (True, 0))

    def test_tentative_addresses_excluded(self):
        result = subprocess.CompletedProcess([], 0, b'[{"addr_info":[{"local":"::1"},{"local":"10.1.0.44","tentative":true}]}]')
        with patch.object(gate.subprocess, 'run', return_value=result):
            self.assertEqual(gate.local_addresses(), {ipaddress.ip_address('::1')})

    def test_native_loopback(self):
        self.assertTrue(gate.wait_addresses(['127.0.0.1'], 1))

    def test_cli_rejects_hostname(self):
        self.assertNotEqual(subprocess.run(['/usr/bin/python3', '-B', str(PATH), 'localhost'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode, 0)


if __name__ == '__main__':
    unittest.main()
