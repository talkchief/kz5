#!/usr/bin/env python3
"""Bounded kernel admission probe; no watches, files, sysctl changes or secrets."""
import ctypes
import os
import sys


def main():
    if sys.argv[1:] != ["--check"]:
        return 64
    libc = ctypes.CDLL(None, use_errno=True)
    init = libc.inotify_init1
    init.argtypes = [ctypes.c_int]
    init.restype = ctypes.c_int
    descriptors = []
    try:
        for _ in range(32):
            descriptor = init(os.O_CLOEXEC | os.O_NONBLOCK)
            if descriptor < 0:
                print("Insufficient inotify-instance headroom for another systemd guest; "
                      "park completed cold labs or resolve host resource pressure first.", file=sys.stderr)
                return 78
            descriptors.append(descriptor)
        print("PASS 32 temporary inotify instances available; all closed, no watches created")
        return 0
    finally:
        for descriptor in descriptors:
            os.close(descriptor)


if __name__ == "__main__":
    sys.exit(main())
