#!/usr/bin/python3
"""Wait for configured local IP assignment; no remote traffic or network changes."""
import argparse
import ipaddress
import json
import subprocess
import time


def local_addresses():
    result = subprocess.run(
        ['/usr/sbin/ip', '-j', 'address', 'show'], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
    return {ipaddress.ip_address(info['local'])
            for interface in json.loads(result.stdout)
            for info in interface.get('addr_info', [])
            if not info.get('tentative', False) and not info.get('dadfailed', False)}


def wait_addresses(addresses, timeout, read=local_addresses,
                   clock=time.monotonic, sleep=time.sleep):
    wanted = {ipaddress.ip_address(value) for value in addresses}
    wanted = {value for value in wanted if not value.is_unspecified}
    deadline = clock() + timeout
    while wanted:
        try:
            if wanted <= read():
                return True
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            pass  # A transient interface query failure is not readiness.
        remaining = deadline - clock()
        if remaining <= 0:
            return False
        sleep(min(1, remaining))
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('addresses', nargs='+', type=ipaddress.ip_address)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 600:
        parser.error('timeout must be between 1 and 600 seconds')
    if not wait_addresses(args.addresses, args.timeout):
        parser.exit(1, 'Configured Kazoo local address was not assigned before startup deadline\n')


if __name__ == '__main__':
    main()
