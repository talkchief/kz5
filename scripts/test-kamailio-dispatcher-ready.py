#!/usr/bin/env python3
"""Offline dispatcher readiness regression; no RPC or service access."""
import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("dispatcher_ready", HERE / "kamailio-dispatcher-ready.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def inventory(groups):
    sets = []
    for group, flags in groups:
        targets = "\n".join("DEST: {\nIDX: %s\nURI: sip:192.0.2.1:11000\nFLAGS: %s\nPRIORITY: 0\n}"
                            % (index, flag) for index, flag in enumerate(flags))
        sets.append("SET: {\nID: %s\nTARGETS: {\n%s\n}\n}" % (group, targets))
    return "{\nNRSETS: %s\nRECORDS: {\n%s\n}\n}" % (len(groups), "\n".join(sets))


class Readiness(unittest.TestCase):
    def test_old_false_positive(self):
        text = inventory([(1, ["IP", "TX", "DP"])])
        self.assertTrue("No Destination Sets" not in text and "DEST" in text)
        self.assertFalse(module.parse(text, 1, 2)["ready"])

    def test_native_flag_combinations(self):
        for status in "AITD":
            for probe in "PX":
                with self.subTest(flags=status + probe):
                    self.assertEqual(module.parse(inventory([(1, [status + probe])]), 1, 2)["ready"], status == "A")

    def test_fallback(self):
        self.assertTrue(module.parse(inventory([(1, ["IP"]), (2, ["AX"])]), 1, 2)["ready"])

    def test_unrelated_active_group(self):
        self.assertFalse(module.parse(inventory([(1, ["IP"]), (10, ["AP"])]), 1, 2)["ready"])

    def test_effective_custom_groups(self):
        result = module.parse(inventory([(1, ["AP"]), (51, ["TX", "AP"])]), 51, 52)
        self.assertEqual(result["active_destinations"], 1)
        self.assertEqual(result["selected_destinations"], 2)

    def test_disabled_secondary(self):
        self.assertFalse(module.parse(inventory([(0, ["AP"]), (1, ["IP"])]), 1, 0)["ready"])

    def test_empty(self):
        self.assertFalse(module.parse(inventory([]), 1, 2)["ready"])

    def test_malformed_refused(self):
        valid = inventory([(1, ["AP"])])
        for text in ["", "error", valid[:-1], valid + "\n}", valid.replace("NRSETS: 1", "NRSETS: 2"),
                     valid.replace("FLAGS: AP", "FLAGS: AP\nFLAGS: AP"), valid.replace("FLAGS: AP", "FLAGS: UNKNOWN"),
                     inventory([(1, ["AP"]), (1, ["IP"])]), valid.replace("URI: sip:", "URI: invalid:"),
                     "x" * (1024 * 1024 + 1)]:
            with self.subTest(length=len(text)):
                with self.assertRaises((ValueError, KeyError)):
                    module.parse(text, 1, 2)

    def test_installer_and_fault_recovery_use_same_gate(self):
        installer = (HERE / "install-kazoo5.sh").read_text()
        self.assertIn('python3 -B -I "$SCRIPT_DIR/kamailio-dispatcher-ready.py"', installer)
        self.assertNotIn("$dispatcher == *'DEST'*", installer)
        self.assertIn('"$SCRIPT_DIR/kamailio-dispatcher-ready.py"', (HERE / "test-acdc-node-loss.sh").read_text())

    def test_actual_installer_wait_success_and_timeout(self):
        source = (HERE / "install-kazoo5.sh").read_text()
        function = re.search(r"^wait_kamailio_dispatcher_ready\(\) \{\n[\s\S]*?^\}", source, re.M)[0]
        for code in (0, 1):
            script = "set -Eeuo pipefail\nSCRIPT_DIR=/fixture\nKAZOO_START_TIMEOUT=10\n"
            script += 'log(){ echo "$*"; }; die(){ echo "$*" >&2; exit 1; }\n'
            script += 'python3(){ [[ $* == "-B -I /fixture/kamailio-dispatcher-ready.py" ]] || exit 99; return %s; }\n' % code
            script += 'sleep(){ SECONDS=1000; }\n' + function + '\nwait_kamailio_dispatcher_ready\n'
            result = subprocess.run(["bash", "-s"], input=script, text=True, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, code)
            if code:
                self.assertNotIn("PASS", result.stdout)
                self.assertIn("no active destination", result.stderr)
            else:
                self.assertIn("PASS active Kamailio", result.stdout)


if __name__ == "__main__":
    unittest.main()
