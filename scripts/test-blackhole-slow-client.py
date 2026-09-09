#!/usr/bin/env python3
"""Bounded dev44-only real TCP receive-starvation test; never logs tokens."""
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import stat
import struct
import subprocess
import sys
import time

HELPER = Path(__file__).parent / 'test-fixtures/blackhole-stream-rpc.escript'
GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'


def rpc(*args):
    result = subprocess.run(['/usr/bin/escript', str(HELPER), *args],
                            capture_output=True, timeout=35, check=False)
    if result.returncode:
        raise RuntimeError('Protected fixture helper refused')
    return json.loads(result.stdout)


def exact(sock, count):
    result = bytearray()
    while len(result) < count:
        chunk = sock.recv(count - len(result))
        if not chunk:
            raise RuntimeError('Unexpected socket closure')
        result.extend(chunk)
    return bytes(result)


def send_json(sock, body):
    payload = json.dumps(body, separators=(',', ':')).encode()
    assert len(payload) < 65536
    mask = secrets.token_bytes(4)
    header = bytes([0x81, 0x80 | len(payload)]) if len(payload) < 126 else bytes([0x81, 0xfe]) + struct.pack('!H', len(payload))
    sock.sendall(header + mask + bytes(c ^ mask[i % 4] for i, c in enumerate(payload)))


def receive_json(sock):
    first, second = exact(sock, 2)
    assert first == 0x81 and not second & 0x80, 'Expected complete unmasked text frame'
    size = second & 127
    if size == 126:
        size = struct.unpack('!H', exact(sock, 2))[0]
    elif size == 127:
        size = struct.unpack('!Q', exact(sock, 8))[0]
    assert size <= 1048576
    return json.loads(exact(sock, size))


def ping(sock, token, tag):
    started = time.monotonic()
    send_json(sock, {'action': 'ping', 'auth_token': token, 'request_id': tag})
    reply = receive_json(sock)
    assert reply.get('request_id') == tag and reply.get('status') == 'success'
    return round((time.monotonic() - started) * 1000, 1)


def connect(transport, token, tag):
    assert transport in ('direct-ws', 'verified-wss')
    sock = socket.socket()
    # Set before connect to constrain TCP window negotiation. No host sysctl,
    # packet filter, qdisc, application process or unrelated socket is changed.
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    sock.settimeout(5)
    try:
        sock.connect(('127.0.0.1', 5555 if transport == 'direct-ws' else 443))
        if transport == 'verified-wss':
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname='kz5-dev.talkchief.io')
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        sock.sendall(('GET /websocket HTTP/1.1\r\nHost: kz5-dev.talkchief.io\r\n'
                      'Upgrade: websocket\r\nConnection: Upgrade\r\n'
                      'Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ' + key + '\r\n\r\n').encode())
        header = bytearray()
        while not header.endswith(b'\r\n\r\n'):
            assert len(header) < 8192
            header.extend(exact(sock, 1))
        lines = header.decode().split('\r\n')
        assert lines[0].startswith('HTTP/1.1 101 ')
        headers = {key.lower(): value for key, value in (line.split(':', 1) for line in lines[1:] if ':' in line)}
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        assert headers['sec-websocket-accept'].strip() == accept
        ping(sock, token, tag)
        return sock
    except BaseException:
        sock.close()
        raise


def run(transport):
    issued = rpc('issue-load')
    token = issued['token']
    tag = 'streamguard-' + secrets.token_hex(16)
    slow = fast = None
    try:
        slow = connect(transport, token, tag)
        fast = connect(transport, token, 'streamguard-' + secrets.token_hex(16))
        latency = []
        # Deliberately never read slow again until after the server-side proof.
        # Keep an independent connection responsive during paced event traffic.
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(rpc, 'transport-load', tag, 'bounded')
            while not future.done():
                latency.append(ping(fast, token, 'streamguard-' + secrets.token_hex(16)))
                time.sleep(0.2)
            result = future.result()
        assert result['socket_process_gone'], 'Slow socket retained beyond bounded deadline'
        assert 1 <= result['sent'] <= 128 and result['elapsed_ms'] < 25000
        assert len(latency) >= 3 and max(latency) < 3000
        assert result['peak_process_bytes'] < 33554432
        assert time.time() < issued['expires'], 'Expiry cannot substitute for pressure cleanup'
        # A fresh connection must still authenticate after pressure cleanup.
        recovered = connect(transport, token, 'streamguard-' + secrets.token_hex(16))
        recovered.close()
        return {'transport': transport, **result, 'control_pings': len(latency),
                'max_control_ping_ms': max(latency), 'reconnect': True}
    finally:
        for sock in (slow, fast):
            if sock is not None:
                sock.close()


def main():
    import fcntl
    assert os.geteuid() == 0 and sys.argv[1:] == ['--live']
    lock = Path('/etc/kazoo/monitor-acceptance.lock')
    st = lock.lstat()
    assert stat.S_ISREG(st.st_mode) and st.st_uid == 0 and st.st_nlink == 1 and stat.S_IMODE(st.st_mode) == 0o600
    with lock.open('r+') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        results = []
        for transport in ('direct-ws', 'verified-wss'):
            results.append(run(transport))
            print(json.dumps({'status': 'PASS', **results[-1]}), flush=True)
        print(json.dumps({'status': 'PASS', 'scope': 'two receive-starved owned sockets, maximum64MiB synthetic data; not prolonged soak or broker event throughput', 'checks': len(results)}))


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        # Exception representations can contain socket/auth data. No tracebacks.
        print(json.dumps({'status': 'FAIL', 'error_type': type(error).__name__}), file=sys.stderr)
        sys.exit(1)
