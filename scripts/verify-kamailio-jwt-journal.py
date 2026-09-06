#!/usr/bin/python3
"""Read-only, bounded journal classifier. Never prints journal bodies or keys."""
import argparse
import json
import re
import sys

ERROR = re.compile(r"(?:^| )ERROR:|empty or invalid JSON|destination pseudo-variable is not writable|\$var\(kz_log_id\)|Header-Value can.t be parsed|no amqp connection available")
PREFIX = r"\s*\d+\((?P<worker>\d+)\) {level}: \|[^|\r\n]*\|{config}/kamailio/jwt-keys\.cfg:{line} "


class EvidenceError(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise EvidenceError(reason)


def patterns(config_dir):
    require(re.fullmatch(r"/[A-Za-z0-9_./-]+", config_dir) is not None
            and all(part not in ["", ".", ".."] for part in config_dir.split("/")[1:]),
            "invalid configured JWT source directory")
    prefix = PREFIX.replace("{config}", re.escape(config_dir))
    failure = re.compile(prefix.format(level="ERROR", line="27") + r"failed to load JWT keys: <null>\s*")
    loaded = re.compile(prefix.format(level="NOTICE", line=r"\d+")
                        + r"loaded (?P<count>\d+) entries into jtw\.keys(?P<kind> issuer| identity)? table\s*")
    return failure, loaded


def readiness(stats, query):
    require(len(stats) <= 65536 and len(query) <= 4096, "oversized RPC evidence")
    blocks = re.findall(r"\{([^{}]*)\}", stats)
    selected = [b for b in blocks if re.search(r"(?m)^\s*name:\s*jwt\.keys\s*$", b)]
    require(len(selected) == 1, "JWT table statistics missing or ambiguous")
    totals = re.findall(r"(?m)^\s*all:\s*(\d+)\s*$", selected[0])
    require(len(totals) == 1 and int(totals[0]) > 0, "current JWT key table is empty or invalid")
    require(re.fullmatch(r"\s*\{\s*name:\s*jwt_keys_query\s+type:\s*int\s+value:\s*0\s*\}\s*", query),
            "JWT retry is pending or query-state evidence is invalid")
    return int(totals[0])


def classify(lines, boot_id, active_usec, stats, query, config_dir="/etc/kazoo"):
    require(re.fullmatch(r"[a-f0-9]{32}", boot_id) is not None, "invalid boot identity")
    require(isinstance(active_usec, int) and active_usec > 0, "invalid service activation clock")
    count = readiness(stats, query)
    failure_pattern, loaded_pattern = patterns(config_dir)
    failures, loads, other_errors = [], [], []
    total = records = 0
    # systemctl's human timestamp supplied to journalctl --since is truncated
    # to wall-clock seconds. Inspect this bounded prefix too: never discard an
    # included record or forgive an ERROR just because it predates activation.
    earliest_usec = max(0, active_usec - 1_000_000)
    last = earliest_usec
    for line in lines:
        total += len(line)
        records += 1
        require(total <= 32 * 1024 * 1024 and records <= 100000 and len(line) <= 1024 * 1024,
                "journal evidence exceeds bounded input limit")
        try:
            record = json.loads(line)
            message = record["MESSAGE"]
            if isinstance(message, list):
                require(all(type(x) is int and 0 <= x <= 255 for x in message), "invalid journal message bytes")
                message = bytes(message).decode("utf-8")
            stamp = record["__MONOTONIC_TIMESTAMP"]
            require(isinstance(stamp, str) and stamp.isdigit(), "invalid journal monotonic timestamp")
            stamp = int(stamp)
            require(record["_BOOT_ID"] == boot_id and stamp >= earliest_usec and stamp >= last,
                    "journal boot, activation or ordering mismatch")
            require(isinstance(message, str), "invalid journal message type")
        except (ValueError, KeyError, TypeError, UnicodeError):
            raise EvidenceError("malformed journal evidence") from None
        last = stamp
        failure = failure_pattern.fullmatch(message)
        loaded = loaded_pattern.fullmatch(message)
        if failure or loaded:
            pid = record.get("_PID")
            require(isinstance(pid, str) and pid.isdigit() and int(pid) > 0, "invalid JWT worker identity")
            require((failure or loaded).group("worker") == pid, "JWT worker prefix disagrees with journal metadata")
            if failure:
                failures.append((stamp, pid))
            else:
                loads.append((stamp, pid, (loaded.group("kind") or "keys").strip(), int(loaded.group("count"))))
        elif ERROR.search(message) or "failed to load JWT keys" in message:
            other_errors.append(stamp)
    require(records > 0, "journal evidence is empty")
    require(not other_errors, "runtime integration errors remain; count=" + str(len(other_errors)))
    if not failures:
        return "PASS Kamailio journal and current JWT cache readiness; cached_entries=" + str(count)
    require(len(failures) == 1, "JWT failure is recurring, not a single recovered startup error")
    failed, pid = failures[0]
    require(not any(x[0] <= failed for x in loads), "JWT failure follows an earlier successful load")
    require(0 <= failed - active_usec <= 35_000_000, "JWT failure is outside the startup grace window")
    later = [x for x in loads if x[0] > failed]
    require(len(later) >= 3, "JWT startup failure has no complete later recovery sequence")
    first = later[:3]
    require([x[2] for x in first] == ["keys", "issuer", "identity"], "JWT recovery stages are missing or out of order")
    require(all(x[1] == pid for x in first), "JWT recovery came from a different worker")
    require(first[0][3] > 0 and first[1][3] > 0, "JWT recovery loaded no keys or issuers")
    require(first[-1][0] - failed <= 25_000_000 and first[-1][0] - active_usec <= 60_000_000,
            "JWT recovery was not a bounded startup retry")
    elapsed = (first[-1][0] - failed) / 1_000_000
    return ("WARNING recovered startup JWT null-reply ERROR retained: one failure, same worker, "
            "complete retry in %.3fs; current cached_entries=%d; jwt_keys_query=0" % (elapsed, count))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot-id", required=True)
    parser.add_argument("--active-usec", required=True, type=int)
    parser.add_argument("--stats", required=True)
    parser.add_argument("--query", required=True)
    parser.add_argument("--config-dir", required=True)
    args = parser.parse_args()
    try:
        lines = iter(lambda: sys.stdin.readline(1024 * 1024 + 1), "")
        print(classify(lines, args.boot_id, args.active_usec, args.stats, args.query, args.config_dir))
        return 0
    except EvidenceError as error:
        print("FAIL Kamailio journal/JWT evidence: " + str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
