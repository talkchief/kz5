#!/usr/bin/env python3
import importlib.util
import pathlib
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('apps_lab', pathlib.Path(__file__).with_name('prepare-company-compat-apps.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class AppsLabTests(unittest.TestCase):
    def test_shared_lab_namespace_but_separate_host_services(self):
        for role in ['apps', 'broker']:
            unit = lab.unit(role, {'HOME': '/var/lib/kazoo-compat-runtime/' + role + '/home'}, '/fixture', '1G')
            for directive in ['JoinsNamespaceOf=kazoo-compat-couchdb.service', 'PrivateNetwork=yes', 'BindsTo=kazoo-compat-couchdb.service', 'User=kazoo-compat', 'ProtectSystem=strict', 'CapabilityBoundingSet=', 'Restart=no']:
                self.assertIn(directive + '\n', unit)
            self.assertIn('ReadWritePaths=/var/lib/kazoo-compat-runtime/' + role, unit)
            # OTP inet:getifaddrs needs netlink; the private namespace and lack
            # of capabilities still prevent external routing/interface changes.
            self.assertIn('RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK', unit)
            self.assertNotIn('[Install]', unit)

    def test_real_native_boot_with_isolated_raft_and_logs(self):
        start = lab.app_start_script()
        self.assertIn('-args_file /opt/kz5/rel/dev.vm.args', start)
        self.assertIn('kazoo_compat@127.0.0.1', start)
        self.assertIn('/var/lib/kazoo-compat-runtime/apps/ra', start)
        self.assertNotIn('/opt/kazoo/var/lib/ra', start)
        self.assertNotIn('/etc/kazoo', start)
        # Lab-only tested BEAM overrides avoid changing shared main-stack code.
        self.assertIn('-pa /var/lib/kazoo-compat-runtime/apps/overrides', start)
        subprocess.run(['sh', '-n'], input=start, text=True, check=True)

    def test_cookie_section_has_no_incorrect_hostname_selector(self):
        # Kazoo INI host is a section selector, not a listening address.
        source = pathlib.Path(lab.__file__).read_text()
        section = source.split('[kazoo_apps]')[1].split('[log]')[0]
        self.assertIn('cookie = %s', section)
        self.assertNotIn('host =', section)


if __name__ == '__main__':
    unittest.main()
