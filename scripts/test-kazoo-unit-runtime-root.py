#!/usr/bin/python3
"""Real generated unit environment and BEAM guard, using two private trees."""
import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent


class UnitRuntimeRootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="kazoo-unit-runtime-root.")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.checkout = cls.root / "installer-checkout"
        cls.runtime = cls.root / "configured-runtime"
        cls.source = (SCRIPTS / "install-kazoo5.sh").read_text()
        cls.env = {"PATH": "/usr/bin:/bin", "ERL_FLAGS": "+S 1:1 +A 1", "ERL_CRASH_DUMP": "/dev/null"}
        for tree in [cls.checkout, cls.runtime]:
            (tree / "scripts").mkdir(parents=True)
            for relative in ["core/fixture/ebin", "applications", "deps"]:
                (tree / relative).mkdir(parents=True)
        (cls.checkout / "scripts/install-kazoo5.sh").write_text(cls.source)
        cls.module = cls.root / "unit_runtime_root_fixture.erl"
        cls.module.write_text("-module(unit_runtime_root_fixture).\n-export([ok/0]).\nok() -> ok.\n")
        cls.units = cls.render_units()

    @classmethod
    def compile(cls, tree, test=False):
        command = ["erlc"] + (["-DTEST"] if test else []) + ["-o", str(tree / "core/fixture/ebin"), str(cls.module)]
        result = subprocess.run(command, env=cls.env, text=True, capture_output=True, timeout=15)
        if result.returncode:
            raise AssertionError("Fixture BEAM compilation failed: " + result.stderr)

    @classmethod
    def render_units(cls):
        found = re.findall(r"^install_kazoo_systemd_units\(\) \{[\s\S]*?^\}", cls.source, re.M)
        if len(found) != 1:
            raise AssertionError("Expected exactly one actual unit generator")
        stubs = """set -euo pipefail
run(){ :; }
getent(){ return 0; }
id(){ return 0; }
reject_secret_symlink(){ :; }
install_kazoo_pivot_port_reservation(){ :; }
write_file(){ printf '\\036%s\\037' "$2"; command cat; }
"""
        env = {**cls.env, "DRY_RUN": "true", "SCRIPT_DIR": str(cls.checkout / "scripts"),
               "KAZOO_ROOT": str(cls.runtime), "KAZOO_HOSTNAME": "fixture.invalid",
               "KAZOO_RUNTIME_COOKIE_FILE": str(cls.root / "unused-cookie"), "KAZOO_COOKIE": "fixture-only",
               "KAZOO_CONFIG_DIR": str(cls.root / "unused-config"), "KAZOO_APPS_LIST": "pivot",
               "KAZOO_NODE_NAME_TYPE": "-sname", "KAZOO_ERLANG_DIST_IP": "127.0.0.1"}
        result = subprocess.run(["bash", "--noprofile", "--norc", "-s"], env=env, text=True,
                                capture_output=True, timeout=5,
                                input=stubs + found[0] + "\ninstall_kazoo_systemd_units\n")
        if result.returncode:
            raise AssertionError("Actual unit rendering failed: " + result.stderr)
        units = {}
        for record in result.stdout.split("\x1e")[1:]:
            name, body = record.split("\x1f", 1)
            if name.endswith(".service"):
                units[Path(name).name] = body
        return units

    def guard(self, unit):
        env = dict(self.env)
        for line in unit.splitlines():
            if line.startswith("Environment="):
                for assignment in shlex.split(line.partition("=")[2]):
                    key, value = assignment.split("=", 1)
                    env[key] = value
        command = next(line.partition("=")[2] for line in unit.splitlines()
                       if line.startswith("ExecStartPre=") and "verify_kazoo_production_beams" in line)
        # Execute the exact generated guard command/environment, including its
        # disabled deployment-config lookup. Only fixture BEAMs can be scanned.
        return subprocess.run(shlex.split(command), env=env, cwd=self.runtime, text=True,
                              capture_output=True, timeout=15)

    def test_both_units_export_the_configured_runtime_root(self):
        self.assertEqual(set(self.units), {"kazoo-apps.service", "kazoo-ecallmgr.service"})
        self.assertNotEqual(self.runtime, self.checkout)
        for name, unit in self.units.items():
            with self.subTest(unit=name):
                self.assertIn("WorkingDirectory=" + str(self.runtime) + "\n", unit)
                self.assertIn("Environment=KAZOO_ROOT=" + str(self.runtime) + "\n", unit)
                self.assertIn("source " + str(self.checkout / "scripts/install-kazoo5.sh"), unit)

    def test_test_beam_in_runtime_is_rejected_even_when_installer_tree_is_clean(self):
        self.compile(self.checkout)
        self.compile(self.runtime, test=True)
        beam = self.runtime / "core/fixture/ebin/unit_runtime_root_fixture.beam"
        before = hashlib.sha256(beam.read_bytes()).hexdigest()
        for name, unit in self.units.items():
            with self.subTest(unit=name):
                result = self.guard(unit)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("TEST-compiled BEAM", result.stderr)
        self.assertEqual(hashlib.sha256(beam.read_bytes()).hexdigest(), before)

    def test_clean_runtime_passes_even_when_unrelated_installer_tree_has_test_beam(self):
        self.compile(self.checkout, test=True)
        self.compile(self.runtime)
        for name, unit in self.units.items():
            with self.subTest(unit=name):
                result = self.guard(unit)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("compiled without TEST-only code", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
