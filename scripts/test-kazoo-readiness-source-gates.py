#!/usr/bin/python3
"""Offline real shell hooks, systemctl/SUP doubles, and tiny BEAM fixtures."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
SOURCE = (SCRIPTS / "install-kazoo5.sh").read_text()


def hook(name):
    found = re.findall(r"^" + name + r"\(\) \{[\s\S]*?^\}", SOURCE, re.M)
    if len(found) != 1:
        raise AssertionError("Missing actual hook " + name)
    return found[0]


def shell(code, env=None):
    return subprocess.run(["bash", "--noprofile", "--norc", "-s"], text=True, capture_output=True, timeout=15,
                          input="set -euo pipefail\ndie(){ printf '%s\\n' \"$*\" >&2; exit 42; }\nlog(){ :; }\n" + code,
                          env={"PATH": "/usr/bin:/bin", "ERL_FLAGS": "+S 1:1 +A 1", "ERL_CRASH_DUMP": "/dev/null", **(env or {})})


class SourceGateTests(unittest.TestCase):
    def test_canonical_safe_paths_accept_and_metacharacters_fail(self):
        code = hook("validate_install_directory") + '\nvalidate_install_directory KAZOO_ROOT "$VALUE"\n'
        for value in ["/opt/kz5", "/var/www/monster-ui", "/srv/.private/Kazoo_5.0-build"]:
            self.assertEqual(shell(code, {"VALUE": value}).returncode, 0, value)
        for value in ["/", "relative", "/opt//kz5", "/opt/kz5/", "/opt/./kz5", "/opt/../kz5", "/opt/.", "/opt/..",
                      "/opt/quote'", '/opt/quote"', "/opt/$name", "/opt/$(command)", "/opt/%n", "/opt/`command`",
                      "/opt/semi;colon", "/opt/a b", "/opt/line\nname", "/opt/line\rname", "/opt/tab\tname", "/opt/a\\b"]:
            with self.subTest(value=repr(value)):
                self.assertEqual(shell(code, {"VALUE": value}).returncode, 42)
        preflight = hook("preflight")
        self.assertLess(preflight.index('validate_install_directory KAZOO_ROOT'), preflight.index('[[ -d $KAZOO_ROOT/.git ]]'))
        for key in ["KAZOO_ROOT", "KAZOO_BUILD_ROOT", "KAZOO_CACHE_DIR", "KAZOO_CONFIG_DIR", "MONSTER_UI_WEB_ROOT"]:
            self.assertIn('validate_install_directory ' + key + ' "$' + key + '"', preflight)

    def pivot(self, **overrides):
        stubs = """python3(){
    [[ $* == '-B -I /fixture/scripts/reserve-kazoo-pivot-ports.py --check' ]] || exit 99
    return "$HELPER_STATUS"
}
systemctl(){
    case "$*" in
        'is-active --quiet kazoo-pivot-port-reservation.service') return "$ACTIVE_STATUS" ;;
        "show $SERVICE --property=Requires --value") printf '%s\\n' "$REQUIRES" ;;
        "show $SERVICE --property=After --value") printf '%s\\n' "$AFTER" ;;
        *) exit 99 ;;
    esac
}
"""
        env = {"DRY_RUN": "false", "SCRIPT_DIR": "/fixture/scripts", "SERVICE": "kazoo-apps.service",
               "HELPER_STATUS": "0", "ACTIVE_STATUS": "0", "REQUIRES": "sysinit.target kazoo-pivot-port-reservation.service",
               "AFTER": "network-online.target kazoo-pivot-port-reservation.service", **overrides}
        return shell(stubs + hook("verify_kazoo_pivot_port_reservation") + '\nverify_kazoo_pivot_port_reservation "$SERVICE"\n', env)

    def test_pivot_gate_requires_current_ports_and_effective_dependencies_for_both_nodes(self):
        for service in ["kazoo-apps.service", "kazoo-ecallmgr.service"]:
            self.assertEqual(self.pivot(SERVICE=service).returncode, 0)
            for bad in [{"HELPER_STATUS": "1"}, {"ACTIVE_STATUS": "3"}, {"REQUIRES": ""}, {"AFTER": ""},
                        {"REQUIRES": "unrelated-kazoo-pivot-port-reservation.service"}, {"AFTER": "kazoo-pivot-port-reservation.service.extra"}]:
                with self.subTest(service=service, bad=bad):
                    self.assertEqual(self.pivot(SERVICE=service, **bad).returncode, 42)
        for name, service in [("verify_kazoo_apps", "kazoo-apps.service"), ("verify_ecallmgr", "kazoo-ecallmgr.service")]:
            code = hook(name)
            self.assertLess(code.index("verify_kazoo_pivot_port_reservation " + service), code.index("verify_kazoo_production_beams"))

    def test_sup_available_unloaded_module_exports_and_path_failures(self):
        with tempfile.TemporaryDirectory(prefix="kazoo-sup-beam-export.") as directory:
            root = Path(directory)
            ebin = root / "core/kazoo_apps/ebin"
            ebin.mkdir(parents=True)
            env = {"PATH": "/usr/bin:/bin", "ERL_FLAGS": "+S 1:1 +A 1", "ERL_CRASH_DUMP": "/dev/null"}
            def compile(module, function):
                source = root / (module + ".erl")
                source.write_text("-module(" + module + ").\n-export([" + function + "/1]).\n" + function + "(_) -> ok.\n")
                result = subprocess.run(["erlc", "-o", str(ebin), str(source)], env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
            def run(module="kazoo_maintenance", function="syslog_level", response=None, status="0"):
                code = """timeout(){ shift 2; "$@"; }
sup(){ [[ $* == "-e code which $MODULE" ]] || exit 99; printf '%s\\n' "$RESPONSE"; return "$STATUS"; }
""" + hook("verify_sup_beam_export") + '\nverify_sup_beam_export "$MODULE" "$FUNCTION" 1\n'
                return shell(code, {"KAZOO_ROOT": str(root), "MODULE": module, "FUNCTION": function,
                                    "RESPONSE": response if response is not None else '"' + str(ebin / (module + ".beam")) + '"', "STATUS": status})
            compile("kazoo_maintenance", "syslog_level")
            compile("kapps_controller", "start_app")
            for module, function in [("kazoo_maintenance", "syslog_level"), ("kapps_controller", "start_app")]:
                result = run(module, function)
                self.assertEqual(result.returncode, 0, result.stderr)
            normalized = '"' + str(ebin / "../ebin/kazoo_maintenance.beam") + '"'
            self.assertEqual(run(response=normalized).returncode, 0)
            for response in ["non_existing", "preloaded", "{error,unavailable}", '"/outside/kazoo_maintenance.beam"', '"/unsafe/%n.beam"']:
                self.assertEqual(run(response=response).returncode, 42, response)
            self.assertEqual(run(status="1").returncode, 42)
            compile("kazoo_maintenance", "unrelated")
            self.assertEqual(run().returncode, 42)
            (ebin / "kazoo_maintenance.beam").write_bytes((ebin / "kapps_controller.beam").read_bytes())
            self.assertEqual(run().returncode, 42)
            (ebin / "kazoo_maintenance.beam").write_bytes(b"invalid beam")
            self.assertEqual(run().returncode, 42)
            self.assertNotIn("ensure_loaded", hook("verify_sup_beam_export"))
            self.assertNotIn("sup -e code is_loaded", hook("verify_sup_cli"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
