#!/usr/bin/env python3
"""Opt-in kernel acceptance. Targets ONLY this process's new synthetic children.

No SIP, service, manager, network, privileged config, or existing PID targets.
Each child self-expires after eight seconds; cleanup uses its pinned pidfd and
the Popen handle that created it, never a discovered/arbitrary PID.
"""
import sys
sys.dont_write_bytecode = True

import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time


CHILD = """import signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
signal.alarm(8)
print('ready', flush=True)
if sys.argv[1] == 'exit':
    sys.stdin.buffer.read(1)
    sys.exit(7)
signal.pause()
"""


def need(condition):
    if not condition:
        raise RuntimeError("owned_child_acceptance_failed")


def acceptance(helper):
    digest = hashlib.sha256(helper.read_bytes()).hexdigest()
    started = time.monotonic()
    deadline = started + 15
    children, checks, exits = [], [], []
    result = {"schema_version": 1, "helper_sha256": digest,
              "scope": "new_owned_synthetic_children_only", "live_sip_or_services_touched": False}

    def remaining(maximum):
        left = deadline - time.monotonic()
        need(left > 0)
        return min(maximum, left)

    def invoke(operation, child, ticks=None, parent=None):
        # Target PID always comes from an owned Popen object, not an argument,
        # environment variable, process lookup or existing service.
        args = [operation, str(child["process"].pid), str(child["ticks"] if ticks is None else ticks),
                str(os.getpid() if parent is None else parent)]
        response = subprocess.run([sys.executable, "-B", "-I", str(helper), *args],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, timeout=remaining(3), check=False)
        need(response.returncode == 0 and response.stderr == b"" and
             response.stdout in (b"alive\n", b"dead\n", b"foreign\n", b"unknown\n", b"sent\n"))
        return response.stdout.decode("ascii").strip()

    def spawn(mode):
        process = subprocess.Popen([sys.executable, "-B", "-I", "-c", CHILD, mode],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, close_fds=True)
        child = {"process": process, "fd": None}
        children.append(child)
        child["fd"] = os.pidfd_open(process.pid, 0)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            need(bool(selector.select(remaining(2))))
            need(process.stdout.readline() == b"ready\n")
        stat = Path(f"/proc/{process.pid}/stat").read_text(encoding="ascii")
        need(stat.startswith(f"{process.pid} ("))
        fields = stat.rsplit(") ", 1)[1].split()
        need(len(fields) >= 20 and int(fields[1]) == os.getpid())
        child["ticks"] = int(fields[19])
        need(process.poll() is None and invoke("check", child) == "alive")
        return child

    success = False
    try:
        need(callable(getattr(os, "pidfd_open", None)) and callable(getattr(signal, "pidfd_send_signal", None)))
        first = spawn("pause")
        checks.append("exact_child_alive")
        for mismatch in ("ticks", "parent"):
            for operation in ("check", "INT", "KILL"):
                wrong = {"ticks": first["ticks"] + 1} if mismatch == "ticks" else {"parent": os.getpid() + 1}
                need(invoke(operation, first, **wrong) == "foreign")
                need(first["process"].poll() is None and invoke("check", first) == "alive")
                checks.append("wrong_" + mismatch + "_" + operation.lower() + "_rejected_child_alive")
        need(invoke("INT", first) == "sent")
        exits.append(first["process"].wait(timeout=remaining(2)))
        need(exits[-1] == -signal.SIGINT)
        checks.append("exact_child_int_expected_exit")
        need(invoke("check", first) == "dead")
        checks.append("int_child_reaped_dead")

        second = spawn("pause")
        need(invoke("KILL", second) == "sent")
        exits.append(second["process"].wait(timeout=remaining(2)))
        need(exits[-1] == -signal.SIGKILL)
        checks.append("exact_child_kill_expected_exit")
        need(invoke("check", second) == "dead")
        checks.append("kill_child_reaped_dead")

        third = spawn("exit")
        third["process"].stdin.write(b"x")
        third["process"].stdin.flush()
        exits.append(third["process"].wait(timeout=remaining(2)))
        need(exits[-1] == 7 and invoke("check", third) == "dead")
        checks.append("natural_child_exit_reaped_dead")
        need(hashlib.sha256(helper.read_bytes()).hexdigest() == digest)
        success = True
    finally:
        cleanup_ok = True
        for child in children:
            process, fd = child["process"], child["fd"]
            try:
                if process.poll() is None:
                    if fd is not None:
                        try:
                            signal.pidfd_send_signal(fd, signal.SIGKILL, None, 0)
                        except ProcessLookupError:
                            pass
                    # Before pidfd capture, an unreaped Popen child cannot
                    # have its PID reused; Popen is the sole cleanup authority.
                    else:
                        process.kill()
                process.wait(timeout=2)
            except (OSError, subprocess.TimeoutExpired):
                cleanup_ok = False
            finally:
                if fd is not None:
                    os.close(fd)
                if process.stdin is not None:
                    process.stdin.close()
                if process.stdout is not None:
                    process.stdout.close()
        result.update(result="PASS" if success and cleanup_ok else "FAIL",
                      check_count=len(checks), checks=checks, owned_children_created=len(children),
                      owned_child_pids=[child["process"].pid for child in children],
                      expected_exits=exits, owned_children_reaped=cleanup_ok,
                      elapsed_seconds=round(time.monotonic()-started, 3))
        print(json.dumps(result, sort_keys=True))
        need(cleanup_ok)
    return 0


def main(args):
    if not args:
        print("DRY RUN: no child processes or signals. Use --live-owned-children to test only newly spawned synthetic children.")
        return 0
    if args != ["--live-owned-children"]:
        print("Use: test-phone-process-owned-children.py [--live-owned-children]", file=sys.stderr)
        return 2
    helper = Path(__file__).with_name("phone-process-identity.py")
    need(helper.is_file() and not helper.is_symlink())
    return acceptance(helper)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired):
        print("Owned-child acceptance failed; no existing PID targets were used.", file=sys.stderr)
        sys.exit(1)
