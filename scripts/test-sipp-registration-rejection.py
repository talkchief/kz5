#!/usr/bin/env python3
"""Real SIPp against a loopback-only synthetic registrar; no Kazoo or accounts."""
import pathlib
import socket
import subprocess
import tempfile
import threading
import unittest

SCENARIO = pathlib.Path(__file__).resolve().parent / 'sip-tests/register-rejected.xml'


class RejectionScenario(unittest.TestCase):
    def run_response(self, final):
        requests = []
        stopped = threading.Event()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer:
            peer.bind(('127.0.0.1', 0))
            peer.settimeout(0.1)

            def serve():
                while not stopped.is_set():
                    try:
                        data, address = peer.recvfrom(65535)
                    except socket.timeout:
                        continue
                    text = data.decode()
                    requests.append(text.split(' ', 1)[0])
                    headers = dict(line.split(':', 1) for line in text.split('\r\n')[1:] if ':' in line)
                    first = headers['CSeq'].strip() == '1 REGISTER'
                    code = 401 if first else final
                    if code is None:
                        continue
                    reason = {401: 'Unauthorized', 407: 'Proxy Authentication Required',
                              403: 'Forbidden', 200: 'OK', 503: 'Service Unavailable'}[code]
                    reply = ['SIP/2.0 %s %s' % (code, reason)]
                    for name in ('Via', 'From', 'To', 'Call-ID', 'CSeq'):
                        reply.append(name + ':' + headers[name] + (';tag=fixture' if name == 'To' else ''))
                    if first:
                        reply.append('WWW-Authenticate: Digest realm="fixture.invalid", nonce="abcdef0123456789", algorithm=MD5, qop="auth"')
                    reply.append('Content-Length: 0\r\n\r\n')
                    peer.sendto('\r\n'.join(reply).encode(), address)

            worker = threading.Thread(target=serve, daemon=True)
            worker.start()
            try:
                with tempfile.TemporaryDirectory(prefix='kz5-register-rejection-') as scratch:
                    inputs = pathlib.Path(scratch) / 'input.csv'
                    inputs.write_text('SEQUENTIAL\nfixture;[authentication username=fixture password=synthetic-wrong-password];fixture.invalid;5099;600\n')
                    result = subprocess.run(['sipp', '-ci', '127.0.0.1',
                        '127.0.0.1:%s' % peer.getsockname()[1], '-sf', str(SCENARIO),
                        '-inf', str(inputs), '-i', '127.0.0.1', '-p', '0', '-m', '1',
                        '-l', '1', '-r', '1', '-nostdin', '-timeout', '2s', '-timeout_error'],
                        cwd=scratch, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8)
            finally:
                stopped.set()
                worker.join(timeout=2)
            return result.returncode, requests

    def test_explicit_rejections_without_dialog_traffic(self):
        for status in (401, 407, 403):
            with self.subTest(status=status):
                code, requests = self.run_response(status)
                self.assertEqual(code, 0)
                self.assertEqual(requests, ['REGISTER', 'REGISTER'])

    def test_acceptance_server_error_and_timeout_fail(self):
        for status in (200, 503, None):
            with self.subTest(status=status):
                code, _ = self.run_response(status)
                self.assertNotEqual(code, 0)


if __name__ == '__main__':
    unittest.main()
