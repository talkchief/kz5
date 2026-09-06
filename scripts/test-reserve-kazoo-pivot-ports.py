#!/usr/bin/python3
"""Offline reservations and extracted installer unit rendering; no live writes."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("pivot_ports", SCRIPTS / "reserve-kazoo-pivot-ports.py")
ports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ports)


class KernelDouble:
    def __init__(self, value):
        self.value = value
        self.writes = []

    def read(self):
        return self.value

    def write(self, value):
        self.writes.append(value)
        self.value = value


class ReservationTests(unittest.TestCase):
    def test_empty_list_and_boot_reapplication(self):
        for operator_boot_value in ["\n", "1000,2000-2003\n", "34511,34514\n"]:
            kernel = KernelDouble(operator_boot_value)
            self.assertTrue(ports.ensure_reserved(kernel.read, kernel.write))
            self.assertTrue(ports.includes(ports.parse(kernel.value)))
            self.assertFalse(ports.ensure_reserved(kernel.read, kernel.write))
            self.assertEqual(len(kernel.writes), 1)

    def test_preserves_exact_union_without_reserving_gaps(self):
        cases = {"0,1,65535": "0-1,34512-34513,65535\n",
                 "34400-34511,34514-34600,50000-50002": "34400-34600,50000-50002\n",
                 "34512,34513": None,
                 "30000-40000,50000": None,
                 "34513,34513,2000-2010,2005-2020": "2000-2020,34512-34513\n"}
        for original, wanted in cases.items():
            with self.subTest(original=original):
                kernel = KernelDouble(original)
                self.assertEqual(ports.ensure_reserved(kernel.read, kernel.write), wanted is not None)
                self.assertEqual(kernel.writes, [] if wanted is None else [wanted])
        randomizer = random.Random(34512)
        for _ in range(200):
            original = set(randomizer.sample(range(65536), 30))
            kernel = KernelDouble(",".join(map(str, sorted(original))))
            ports.ensure_reserved(kernel.read, kernel.write)
            actual = {port for low, high in ports.parse(kernel.value) for port in range(low, high + 1)}
            self.assertEqual(actual, original | {34512, 34513})

    def test_malformed_ranges_fail_before_any_write(self):
        for value in ["-1", "65536", "3-2", "1,,2", "1,", ",1", "1-2-3", "not-ports", "1 2", "1\n2", "\0"]:
            kernel = KernelDouble(value)
            with self.subTest(value=repr(value)), self.assertRaises(ValueError):
                ports.ensure_reserved(kernel.read, kernel.write)
            self.assertEqual(kernel.writes, [])

    def test_concurrent_operator_change_before_write_is_preserved(self):
        values = iter(["1234", "1234,5678"])
        writes = []
        with self.assertRaisesRegex(RuntimeError, "changed before write"):
            ports.ensure_reserved(lambda: next(values), writes.append)
        self.assertEqual(writes, [])

    def test_write_error_and_changed_readback_fail_without_rollback_or_retry(self):
        kernel = KernelDouble("1234")
        def rejected_write(value):
            raise PermissionError("fixture denied")
        with self.assertRaises(PermissionError):
            ports.ensure_reserved(kernel.read, rejected_write)
        values = iter(["1234", "1234", "5678"])
        writes = []
        with self.assertRaisesRegex(RuntimeError, "readback differs"):
            ports.ensure_reserved(lambda: next(values), writes.append)
        self.assertEqual(writes, ["1234,34512-34513\n"])

    def test_check_mode_is_readonly_and_apply_requires_root(self):
        for value, status in [("34512-34513", 0), ("1234", 1)]:
            with patch.object(ports, "read_kernel", return_value=value), patch.object(ports, "write_kernel") as write:
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(ports.main(["--check"]), status)
                write.assert_not_called()
        with patch.object(ports.os, "geteuid", return_value=1000), patch.object(ports, "read_kernel") as read:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(ports.main(["--apply"]), 1)
            read.assert_not_called()

    def test_protected_lock_refuses_parallel_apply_symlink_and_unsafe_mode(self):
        if os.geteuid() != 0:
            self.skipTest("root ownership contract requires a root test process")
        with tempfile.TemporaryDirectory(prefix="pivot-port-lock.") as directory:
            target = Path(directory) / "pivot.lock"
            with patch.object(ports, "LOCK_FILE", str(target)):
                with ports.application_lock():
                    with self.assertRaises(BlockingIOError):
                        with ports.application_lock():
                            self.fail("parallel lock accepted")
                target.chmod(0o666)
                with self.assertRaises(PermissionError):
                    with ports.application_lock():
                        self.fail("writable lock accepted")
                target.unlink()
                target.symlink_to(Path(directory) / "operator-file")
                with self.assertRaises(OSError):
                    with ports.application_lock():
                        self.fail("symlink lock accepted")
                self.assertFalse((Path(directory) / "operator-file").exists())


class InstallerTests(unittest.TestCase):
    def render(self, unsafe=False):
        source = (SCRIPTS / "install-kazoo5.sh").read_text()
        functions = []
        for name in ["install_kazoo_pivot_port_reservation", "install_kazoo_systemd_units"]:
            found = re.findall(r"^" + name + r"\(\) \{[\s\S]*?^\}", source, re.M)
            self.assertEqual(len(found), 1)
            functions.append(found[0])
        stubs = """set -euo pipefail
run(){ printf '\\036RUN\\037%s\\n' "$*"; }
write_file(){ printf '\\036%s\\037' "$2"; command cat; }
reject_secret_symlink(){ :; }
getent(){ return 0; }
id(){ return 0; }
stat(){ if [[ $UNSAFE == true ]]; then printf '1000 777\\n'; else printf '0 755\\n'; fi; }
die(){ printf '%s\\n' "$*" >&2; exit 42; }
"""
        return subprocess.run(["bash", "--noprofile", "--norc", "-s"], input=stubs + "\n".join(functions)
                              + "\ninstall_kazoo_systemd_units\n", text=True, capture_output=True, timeout=5,
                              env={"PATH": "/usr/bin:/bin", "SCRIPT_DIR": str(SCRIPTS), "DRY_RUN": "false",
                                   "KAZOO_HOSTNAME": "kazoo.fixture.invalid", "KAZOO_ROOT": "/fixture/kazoo",
                                   "KAZOO_RUNTIME_COOKIE_FILE": "/fixture/kazoo/.erlang.cookie", "KAZOO_COOKIE": "fixture-only",
                                   "KAZOO_CONFIG_DIR": "/fixture/config", "KAZOO_APPS_LIST": "pivot",
                                   "KAZOO_NODE_NAME_TYPE": "sname", "KAZOO_ERLANG_DIST_IP": "127.0.0.1",
                                   "UNSAFE": "true" if unsafe else "false"})

    def test_boot_dependencies_and_readonly_restart_guard(self):
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        records = {}
        for record in result.stdout.split("\x1e")[1:]:
            name, body = record.split("\x1f", 1)
            if name != "RUN":
                records[name] = body
        service = records["/etc/systemd/system/kazoo-pivot-port-reservation.service"]
        for line in ["Type=oneshot", "User=root", "Group=root", "Wants=systemd-sysctl.service",
                     "After=systemd-sysctl.service", "Before=kazoo-apps.service kazoo-ecallmgr.service",
                     "RuntimeDirectory=kazoo5-reserved-ports", "RuntimeDirectoryMode=0700",
                     "ExecStart=/usr/local/libexec/kazoo5-reserve-pivot-ports --apply", "RemainAfterExit=yes"]:
            self.assertIn(line + "\n", service)
        for name in ["kazoo-apps", "kazoo-ecallmgr"]:
            unit = records["/etc/systemd/system/" + name + ".service"]
            self.assertIn("Requires=kazoo-pivot-port-reservation.service\n", unit)
            self.assertIn("After=network-online.target kazoo-pivot-port-reservation.service\n", unit)
            check = "ExecStartPre=/usr/local/libexec/kazoo5-reserve-pivot-ports --check"
            self.assertIn(check, unit)
            self.assertLess(unit.index(check), unit.index("ExecStart="))
            self.assertIn("User=kazoo\n", unit)
        self.assertIn("install -D -o root -g root -m 0755", result.stdout)
        self.assertNotIn("sysctl -w", result.stdout)
        self.assertNotIn("/etc/sysctl.d/", result.stdout)
        self.assertNotIn("systemctl start", result.stdout)

    def test_unsafe_helper_directory_refuses_installation(self):
        result = self.render(unsafe=True)
        self.assertEqual(result.returncode, 42)
        self.assertIn("root-owned and not writable", result.stderr)
        self.assertNotIn("install -D", result.stdout)
        self.assertNotIn("/etc/systemd/system/kazoo-apps.service", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
