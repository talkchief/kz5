#!/usr/bin/env python3
"""Reproduce pinned SIPp's call-limit/USR1 race using loopback SIP only."""
import pathlib
import signal
import socket
import subprocess
import tempfile
import time
import unittest
import uuid

SCENARIO = pathlib.Path(__file__).resolve().parent / 'sip-tests/agent-answer.xml'


class FinalPause(unittest.TestCase):
    def check_exit(self, early_signal):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer, \
                socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation, \
                tempfile.TemporaryDirectory(prefix='kz5-sipp-final-pause-') as scratch:
            peer.bind(('127.0.0.1', 0))
            peer.settimeout(0.5)
            reservation.bind(('127.0.0.1', 0))
            target = reservation.getsockname()
            reservation.close()
            call_id = str(uuid.uuid4()) + '@fixture.invalid'
            from_header = '<sip:caller@fixture.invalid>;tag=fixture'
            to_header = '<sip:agent@fixture.invalid>'

            def send(method, cseq):
                lines = [method + ' sip:agent@127.0.0.1 SIP/2.0',
                    'Via: SIP/2.0/UDP 127.0.0.1:%s;branch=z9hG4bK%s%s' % (peer.getsockname()[1], method, cseq),
                    'Max-Forwards: 70', 'From: ' + from_header, 'To: ' + to_header,
                    'Call-ID: ' + call_id, 'CSeq: %s %s' % (cseq, method),
                    'Contact: <sip:caller@127.0.0.1:%s>' % peer.getsockname()[1],
                    'Content-Length: 0', '', '']
                peer.sendto('\r\n'.join(lines).encode(), target)

            def receive_ok():
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    try:
                        data, _ = peer.recvfrom(65535)
                    except socket.timeout:
                        continue
                    text = data.decode()
                    if text.startswith('SIP/2.0 200 '):
                        return dict(line.split(':', 1) for line in text.split('\r\n\r\n')[0].split('\r\n')[1:] if ':' in line)
                self.fail('Loopback peer did not receive 200')

            process = subprocess.Popen(['sipp', '-ci', '127.0.0.1', '-sf', str(SCENARIO),
                '-i', '127.0.0.1', '-p', str(target[1]), '-m', '1', '-l', '1',
                '-nostdin', '-timeout', '6s', '-timeout_error'], cwd=scratch,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                time.sleep(0.2)
                send('INVITE', 1)
                headers = receive_ok()
                to_header = headers['To'].strip()
                send('ACK', 1)
                send('BYE', 2)
                receive_ok()
                if early_signal:
                    process.send_signal(signal.SIGUSR1)
                code = process.wait(timeout=4)
                self.assertNotEqual(code, 0) if early_signal else self.assertEqual(code, 0)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=2)

    def test_immediate_signal_aborts_post_bye_pause(self):
        self.check_exit(True)

    def test_waiting_for_completion_exits_successfully(self):
        self.check_exit(False)


if __name__ == '__main__':
    unittest.main()
