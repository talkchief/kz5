#!/usr/bin/env python3
"""Local framing/admission tests; no Kazoo or network service touched."""
import importlib.util
import json
from pathlib import Path
import socket
import struct
import unittest

spec = importlib.util.spec_from_file_location('slow', Path(__file__).with_name('test-blackhole-slow-client.py'))
slow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(slow)


class Framing(unittest.TestCase):
    def pair(self):
        a, b = socket.socketpair()
        self.addCleanup(a.close)
        self.addCleanup(b.close)
        a.settimeout(1)
        b.settimeout(1)
        return a, b

    def test_client_masks_both_length_encodings(self):
        for count in (1, 256):
            a, b = self.pair()
            body = {'value': 'x' * count}
            slow.send_json(a, body)
            first, second = slow.exact(b, 2)
            self.assertEqual(first, 0x81)
            self.assertTrue(second & 0x80)
            size = second & 127
            if size == 126:
                size = struct.unpack('!H', slow.exact(b, 2))[0]
            mask, data = slow.exact(b, 4), slow.exact(b, size)
            self.assertEqual(json.loads(bytes(c ^ mask[i % 4] for i, c in enumerate(data))), body)

    def test_server_length_encodings(self):
        for count in (1, 256, 66000):
            a, b = self.pair()
            body = {'value': 'x' * count}
            data = json.dumps(body).encode()
            header = bytes([0x81, len(data)]) if len(data) < 126 else bytes([0x81, 126]) + struct.pack('!H', len(data)) if len(data) < 65536 else bytes([0x81, 127]) + struct.pack('!Q', len(data))
            a.sendall(header + data)
            self.assertEqual(slow.receive_json(b), body)

    def test_reject_masked_fragmented_close_and_oversize(self):
        for header in (b'\x81\x80', b'\x01\x01', b'\x88\x00', b'\x81\x7f' + struct.pack('!Q', 1048577)):
            a, b = self.pair()
            a.sendall(header)
            with self.assertRaises(AssertionError):
                slow.receive_json(b)

    def test_eof_and_unapproved_transport(self):
        a, b = self.pair()
        a.close()
        with self.assertRaises(RuntimeError):
            slow.exact(b, 1)
        with self.assertRaises(AssertionError):
            slow.connect('production', 'unused', 'unused')


if __name__ == '__main__':
    unittest.main()
