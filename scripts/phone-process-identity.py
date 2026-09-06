#!/usr/bin/env python3
"""Exact child observation/signalling; stdout is one fixed nonsecret result.

No kill(PID) fallback. Open the kernel pidfd before validating /proc identity,
then signal that descriptor, never a numeric PID that could have been reused.
"""
import os
import re
import select
import signal
import sys


def positive(value):
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]{0,19}", value):
        raise ValueError("invalid integer")
    return int(value)


def read_identity(pid):
    with open(f"/proc/{pid}/stat", "r", encoding="ascii") as source:
        line = source.read(8193)
    if len(line) > 8192 or not line.startswith(f"{pid} (") or ") " not in line:
        raise ValueError("invalid stat")
    fields = line.rsplit(") ", 1)[1].split()
    if len(fields) < 20 or not re.fullmatch(r"[A-Za-z]", fields[0]):
        raise ValueError("invalid fields")
    return positive(fields[1]), positive(fields[19]), fields[0]


def descriptor_dead(fd):
    poller = select.poll()
    poller.register(fd, select.POLLIN)
    events = poller.poll(0)
    if any(mask & (select.POLLERR | select.POLLNVAL) for _, mask in events):
        raise OSError("unreadable pidfd")
    return any(mask & (select.POLLIN | select.POLLHUP) for _, mask in events)


def supported():
    return callable(getattr(os, "pidfd_open", None)) and callable(getattr(signal, "pidfd_send_signal", None))


def action(operation, pid, ticks, parent):
    if operation not in ("check", "INT", "KILL") or min(pid, parent) <= 1 or ticks <= 0 or not supported():
        return "unknown"
    try:
        fd = os.pidfd_open(pid, 0)
    except ProcessLookupError:
        return "dead"
    except (OSError, OverflowError):
        return "unknown"
    try:
        try:
            actual_parent, actual_ticks, state = read_identity(pid)
        except (FileNotFoundError, ProcessLookupError):
            return "dead" if descriptor_dead(fd) else "unknown"
        if (actual_parent, actual_ticks) != (parent, ticks):
            return "foreign"
        if state in ("Z", "X", "x") or descriptor_dead(fd):
            return "dead"
        if operation == "check":
            return "alive"
        try:
            signal.pidfd_send_signal(fd, signal.SIGINT if operation == "INT" else signal.SIGKILL, None, 0)
        except ProcessLookupError:
            return "dead"
        return "sent"
    except (OSError, ValueError, UnicodeError, OverflowError):
        return "unknown"
    finally:
        os.close(fd)


def main(arguments):
    if arguments == ["--probe"]:
        if not supported():
            return 1
        try:
            fd = os.pidfd_open(os.getpid(), 0)
            try:
                return 1 if descriptor_dead(fd) else 0
            finally:
                os.close(fd)
        except OSError:
            return 1
    if len(arguments) != 4:
        return 2
    try:
        pid, ticks, parent = (positive(value) for value in arguments[1:])
    except ValueError:
        return 2
    print(action(arguments[0], pid, ticks, parent))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
