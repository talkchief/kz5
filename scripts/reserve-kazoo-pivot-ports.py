#!/usr/bin/python3
"""Reserve Pivot listeners against ephemeral assignment; no sockets or services.

The kernel replaces the whole reservation list on write. Always union the
current operator reservations, and run after systemd-sysctl on every boot.
https://docs.kernel.org/networking/ip-sysctl.html#ip-variables
"""
import argparse
import fcntl
import os
import re
import stat
import sys
from contextlib import contextmanager

SYSCTL_FILE = "/proc/sys/net/ipv4/ip_local_reserved_ports"
LOCK_FILE = "/run/kazoo5-reserved-ports/pivot.lock"
REQUIRED = ((34512, 34513),)
MAX_BYTES = 1048576


def normalize(ranges):
    merged = []
    for low, high in sorted(ranges):
        if merged and low <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(high, merged[-1][1]))
        else:
            merged.append((low, high))
    return tuple(merged)


def parse(value):
    if not isinstance(value, str) or len(value) > MAX_BYTES:
        raise ValueError("Reserved-port list exceeds the supported bound")
    value = value.strip()
    if not value:
        return ()
    ranges = []
    for token in value.split(","):
        if not re.fullmatch(r"[0-9]{1,5}(?:-[0-9]{1,5})?", token):
            raise ValueError("Malformed reserved-port list; no changes made")
        parts = token.split("-")
        low, high = int(parts[0]), int(parts[-1])
        if not 0 <= low <= high <= 65535:
            raise ValueError("Reserved-port range is invalid; no changes made")
        ranges.append((low, high))
    return normalize(ranges)


def render(ranges):
    return ",".join(str(low) if low == high else str(low) + "-" + str(high)
                    for low, high in ranges)


def includes(ranges, required=REQUIRED):
    return all(any(low <= start and stop <= high for low, high in ranges)
               for start, stop in required)


def ensure_reserved(read_value, write_value):
    """Return whether a write occurred; callbacks isolate offline unit tests."""
    before = parse(read_value())
    if includes(before):
        return False
    wanted = normalize(before + REQUIRED)
    # Coordinate our own invocations with a lock, and refuse an observed
    # concurrent external edit. Linux offers no atomic compare-and-set here.
    if parse(read_value()) != before:
        raise RuntimeError("Reserved ports changed before write; retry after the other sysctl writer finishes")
    write_value(render(wanted) + "\n")
    if parse(read_value()) != wanted:
        raise RuntimeError("Reserved-port readback differs; inspect concurrent sysctl writers; no automatic rollback")
    return True


def read_kernel():
    with open(SYSCTL_FILE, "r", encoding="ascii") as source:
        value = source.read(MAX_BYTES + 1)
    if len(value) > MAX_BYTES:
        raise ValueError("Kernel reserved-port list exceeds the supported bound")
    return value


def write_kernel(value):
    data = value.encode("ascii")
    descriptor = os.open(SYSCTL_FILE, os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    try:
        if os.write(descriptor, data) != len(data):
            raise OSError("Incomplete reserved-port write; inspect kernel state")
    finally:
        os.close(descriptor)


@contextmanager
def application_lock():
    parent = os.lstat(os.path.dirname(LOCK_FILE))
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != 0 or parent.st_mode & 0o077:
        raise PermissionError("Reserved-port runtime directory must be root-owned with mode 0700")
    descriptor = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_nlink != 1 or info.st_mode & 0o077:
            raise PermissionError("Reserved-port lock must be a protected root-owned regular file")
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(descriptor)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="read-only: require Pivot ports to be reserved")
    mode.add_argument("--apply", action="store_true", help="root-only: add Pivot ports to the current kernel list")
    args = parser.parse_args(argv)
    try:
        if args.check:
            if not includes(parse(read_kernel())):
                raise RuntimeError("Pivot TCP ports 34512-34513 are not reserved; start kazoo-pivot-port-reservation.service before Kazoo")
            print("PASS Pivot TCP ports 34512-34513 are reserved against ephemeral assignment")
        else:
            if os.geteuid() != 0:
                raise PermissionError("Applying Pivot port reservations requires root")
            with application_lock():
                changed = ensure_reserved(read_kernel, write_kernel)
            print("PASS Pivot TCP ports 34512-34513 reserved; existing reservations preserved; "
                  + ("kernel updated" if changed else "no write needed"))
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print("FAIL Pivot port reservation: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
