#!/usr/bin/python3
"""Offline synthetic journals and actual shell-hook command doubles only."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("jwt_journal", HERE / "verify-kamailio-jwt-journal.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
BOOT = "bdfdd8453cb545784aabd9a9".ljust(32, "0")
ACTIVE = 10_000_000
STATS = "{\n name: other\n all: 0\n}\n{\n name: jwt.keys\n slots: 16\n all: 7\n min: 0\n max: 1\n}\n"
QUERY = "{\n name: jwt_keys_query\n type: int\n value: 0\n}\n"
PREFIX = "13(2060) {}: |fixture-id|/etc/kazoo/kamailio/jwt-keys.cfg:{} "


def event(seconds, body, level="NOTICE", line=56, pid="2060", **overrides):
    return {"_BOOT_ID": BOOT, "_PID": pid, "__MONOTONIC_TIMESTAMP": str(ACTIVE + int(seconds * 1e6)),
            "MESSAGE": PREFIX.format(level, line) + body, **overrides}


def recovered():
    return [event(29, "failed to load JWT keys: <null>", "ERROR", 27),
            event(49.091, "loaded 1 entries into jtw.keys table"),
            event(49.092, "loaded 6 entries into jtw.keys issuer table", line=76),
            event(49.093, "loaded 0 entries into jtw.keys identity table", line=100)]


def check(events=None, stats=STATS, query=QUERY, boot=BOOT, active=ACTIVE):
    return mod.classify([json.dumps(x) + "\n" for x in (recovered() if events is None else events)], boot, active, stats, query)


class JournalTests(unittest.TestCase):
    def rejected(self, events=None, **kw):
        with self.assertRaises(mod.EvidenceError):
            check(events, **kw)

    def test_exact_recovery_retains_warning_and_cache_proof(self):
        report = check()
        self.assertIn("WARNING recovered startup JWT null-reply ERROR retained", report)
        self.assertIn("20.093s", report)
        self.assertIn("cached_entries=7", report)
        self.assertIn("jwt_keys_query=0", report)

    def test_clean_journal_still_requires_current_readiness(self):
        clean = [event(1, "service ready")]
        self.assertTrue(check(clean).startswith("PASS"))
        self.rejected(clean, stats=STATS.replace("all: 7", "all: 0"))
        self.rejected(clean, query=QUERY.replace("value: 0", "value: 1"))

    def test_recurring_or_late_failure_is_never_ignored(self):
        self.rejected(recovered() + [event(80, "failed to load JWT keys: <null>", "ERROR", 27)])
        late = recovered()
        for row in late:
            row["__MONOTONIC_TIMESTAMP"] = str(int(row["__MONOTONIC_TIMESTAMP"]) + 10_000_000)
        self.rejected(late)
        self.rejected([event(1, "loaded 1 entries into jtw.keys table")] + recovered())

    def test_wrong_error_body_line_and_other_errors_fail(self):
        for changed in ["failed to load JWT keys: not-null", "failed to load JWT keys, request returned by broker", "failed to load JWT keys: <null> EXTRA"]:
            rows = recovered()
            rows[0]["MESSAGE"] = PREFIX.format("ERROR", 27) + changed
            self.rejected(rows)
        rows = recovered()
        rows[0]["MESSAGE"] = rows[0]["MESSAGE"].replace("cfg:27", "cfg:28")
        self.rejected(rows)
        rows = recovered()
        rows[0]["MESSAGE"] = rows[0]["MESSAGE"].replace("/etc/kazoo/", "/other/kazoo/")
        self.rejected(rows)
        for message in [" ERROR: different failure", "empty or invalid JSON", "destination pseudo-variable is not writable",
                        "$var(kz_log_id)", "Header-Value can't be parsed", "no amqp connection available"]:
            self.rejected(recovered() + [event(80, message)])

    def test_recovery_requires_all_stages_same_child_and_positive_keys(self):
        for index in [1, 2, 3]:
            rows = recovered()
            del rows[index]
            self.rejected(rows)
            rows = recovered()
            rows[index]["_PID"] = "999"
            self.rejected(rows)
        for index in [1, 2]:
            rows = recovered()
            rows[index]["MESSAGE"] = re.sub(r"loaded \d+", "loaded 0", rows[index]["MESSAGE"])
            self.rejected(rows)
        rows = recovered()
        rows[3]["__MONOTONIC_TIMESTAMP"] = str(ACTIVE + 61_000_000)
        self.rejected(rows)

    def test_bad_rpc_metadata_and_retry_fail_closed(self):
        for stats in ["", "{}", STATS + STATS, STATS.replace("all: 7", "all: bad"), STATS.replace("all: 7", "all: 0")]:
            self.rejected(stats=stats)
        for query in ["", QUERY + QUERY, QUERY.replace("value: 0", "value: 1"), QUERY.replace("type: int", "type: str")]:
            self.rejected(query=query)

    def test_boot_activation_order_empty_and_malformed_evidence(self):
        self.rejected([])
        self.rejected(boot="wrong")
        self.rejected(active=0)
        for change in [{"_BOOT_ID": "a" * 32}, {"_PID": ["2060"]}, {"__MONOTONIC_TIMESTAMP": "0"},
                       {"__MONOTONIC_TIMESTAMP": "bad"}, {"MESSAGE": {"secret": "MUST_NOT_LEAK"}}]:
            rows = recovered()
            rows[0].update(change)
            self.rejected(rows)
        self.rejected(list(reversed(recovered())))
        with self.assertRaises(mod.EvidenceError):
            mod.classify(["not-json"], BOOT, ACTIVE, STATS, QUERY)

    def test_binary_journal_message_arrays_are_supported(self):
        rows = recovered()
        for row in rows:
            row["MESSAGE"] = list(row["MESSAGE"].encode())
        self.assertTrue(check(rows).startswith("WARNING"))
        rows[0]["MESSAGE"] = [999]
        self.rejected(rows)

    def test_wall_second_prefix_is_bounded_and_never_drops_errors(self):
        prefix = event(-1, "manager startup", pid="1", MESSAGE="Starting Kazoo Kamailio", _SYSTEMD_UNIT="init.scope")
        self.assertTrue(check([prefix] + recovered()).startswith("WARNING"))
        self.assertTrue(check([event(-0.461745, "manager startup", pid="1", MESSAGE="Starting Kazoo Kamailio")] + recovered()).startswith("WARNING"))
        too_old = dict(prefix, __MONOTONIC_TIMESTAMP=str(ACTIVE - 1_000_001))
        self.rejected([too_old] + recovered())
        # The boundary includes information, not a grace period for errors.
        self.rejected([dict(prefix, MESSAGE=" ERROR: preactivation failure")] + recovered())
        self.rejected([event(-0.1, "failed to load JWT keys: <null>", "ERROR", 27)] + recovered()[1:])
        self.rejected([event(-0.1, "manager later"), prefix] + recovered())
        self.rejected([dict(prefix, _BOOT_ID="a" * 32)] + recovered())

    def test_cli_is_bounded_and_never_prints_log_bodies(self):
        argv = ["python3", "-B", "-I", str(HERE / "verify-kamailio-jwt-journal.py"), "--boot-id", BOOT,
                "--active-usec", str(ACTIVE), "--stats", STATS, "--query", QUERY, "--config-dir", "/etc/kazoo"]
        for body in ["MUST_NOT_LEAK " * 100000, json.dumps(event(2, " ERROR: MUST_NOT_LEAK")) + "\n"]:
            result = subprocess.run(argv, input=body, text=True, capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("MUST_NOT_LEAK", result.stdout + result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_actual_shell_hook_rejects_failed_journal_rpc_or_helper(self):
        source = (HERE / "install-kazoo5.sh").read_text()
        hook = re.search(r"^verify_kamailio_journal\(\) \{[\s\S]*?^\}", source, re.M).group()
        stub = r'''set -euo pipefail
die(){ printf '%s\n' "$*" >&2; exit 42; }
log(){ printf '%s\n' "$*"; }
systemctl(){ case "$*" in
 'show kazoo-kamailio.service -p ActiveEnterTimestamp --value') printf 'activation-fixture\n' ;;
 'show kazoo-kamailio.service -p ActiveEnterTimestampMonotonic --value') printf '1000000\n' ;;
 *) exit 99 ;; esac; }
timeout(){ shift 2; case "$*" in
 '/usr/sbin/kamcmd htable.stats') printf 'stats-fixture\n'; return "$RPC_STATUS" ;;
 '/usr/sbin/kamcmd pv.shvGet jwt_keys_query') printf 'query-fixture\n'; return "$RPC_STATUS" ;;
 'journalctl -u kazoo-kamailio.service --boot='*) printf 'journal-fixture\n'; return "$JOURNAL_STATUS" ;;
 *) exit 99 ;; esac; }
python3(){ [[ $* == '-B -I /fixture/verify-kamailio-jwt-journal.py --boot-id '* ]] || exit 99;
 /usr/bin/cat >/dev/null; printf 'safe-classifier-report\n'; return "$HELPER_STATUS"; }
'''
        for failing in [None, "RPC_STATUS", "JOURNAL_STATUS", "HELPER_STATUS"]:
            env = {"PATH": "/usr/bin:/bin", "SCRIPT_DIR": "/fixture", "KAZOO_CONFIG_DIR": "/etc/kazoo", "RPC_STATUS": "0",
                   "JOURNAL_STATUS": "0", "HELPER_STATUS": "0"}
            if failing:
                env[failing] = "1"
            result = subprocess.run(["bash", "--noprofile", "--norc", "-s"], input=stub + hook + "\nverify_kamailio_journal\n",
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 42 if failing else 0, result.stderr)
        self.assertIn("ActiveEnterTimestampMonotonic --value) ==", hook)


if __name__ == "__main__":
    unittest.main()
