#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import build_opener, ProxyHandler, Request

spec = importlib.util.spec_from_file_location('inflight', Path(__file__).with_name('accept-bridge-inflight-loss.py'))
proof = importlib.util.module_from_spec(spec); spec.loader.exec_module(proof)


def value():
    prefix = 'remote-'+'a'*32
    return {'settings': {'AMQP_HOST': '10.1.0.44', 'AMQP_PORT': 35671,
        'AMQP_USER': 'kz5-bridge-proof', 'AMQP_VHOST': 'kz5-bridge-proof', 'AMQP_TLS': 'true',
        'TOPOLOGY': 'quorum-v1', 'RETRY': 'quorum-counted-v1', 'FRESHNESS': 'unix-ms-v1',
        'AMQP_MANAGEMENT_URL': 'https://10.1.0.44:35672', 'QUEUE': prefix+'.quorum-v1',
        'EXCHANGE': prefix+'.pushes', 'BINDING_KEY': 'fixture.only'},
        'body': '{}', 'endpoint': 'http://127.0.0.1:12345/fixture/'+prefix}


class Tests(unittest.TestCase):
    def test_fixed_synthetic_scope(self):
        v = value(); self.assertEqual(proof.validate_child(v), v)

    def test_foreign_brokers_plaintext_modes_or_queue_refused(self):
        for key in value()['settings']:
            v = value(); v['settings'][key] = 'foreign'
            with self.subTest(key=key), self.assertRaises(ValueError): proof.validate_child(v)

    def test_remote_http_credentials_redirect_target_and_wrong_path_refused(self):
        for endpoint in ['https://127.0.0.1:12345/fixture/remote-'+'a'*32,
                         'http://example.com:12345/fixture/remote-'+'a'*32,
                         'http://user:secret@127.0.0.1:12345/fixture/remote-'+'a'*32,
                         'http://127.0.0.1:12345/other', value()['endpoint']+'?target=external',
                         value()['endpoint']+'#fragment']:
            v = value(); v['endpoint'] = endpoint
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError): proof.validate_child(v)

    def test_unbounded_or_nontext_body_and_extra_fields_refused(self):
        for body in [None, {}, 'a'*8192]:
            v = value(); v['body'] = body
            with self.assertRaises(ValueError): proof.validate_child(v)
        with self.assertRaises(ValueError): proof.validate_child(dict(value(), extra='field'))

    def test_real_loopback_post_is_accepted_but_response_held(self):
        server = proof.HeldHTTP('/fixture/owned', '{}')
        serving = threading.Thread(target=server.serve_forever, daemon=True); serving.start()
        done = threading.Event(); outcomes = []
        def send():
            try:
                request = Request('http://127.0.0.1:'+str(server.server_port)+'/fixture/owned', data=b'{}')
                with build_opener(ProxyHandler({})).open(request, timeout=5) as response:
                    outcomes.append((response.status, response.read()))
            except Exception: outcomes.append('failure')
            finally: done.set()
        worker = threading.Thread(target=send); worker.start()
        try:
            self.assertTrue(server.accepted.wait(3))
            self.assertFalse(done.wait(0.1))
            self.assertEqual(server.posts, 1); self.assertEqual(server.invalid, 0)
            server.release.set(); self.assertTrue(done.wait(3))
            self.assertEqual(outcomes, [(200, b'{}')])
        finally:
            server.release.set(); worker.join(6)
            server.shutdown(); server.server_close(); serving.join(3)

    def test_wrong_loopback_body_is_not_accepted(self):
        server = proof.HeldHTTP('/fixture/owned', '{}')
        serving = threading.Thread(target=server.serve_forever, daemon=True); serving.start()
        try:
            request = Request('http://127.0.0.1:'+str(server.server_port)+'/fixture/owned', data=b'xx')
            with self.assertRaises(HTTPError): build_opener(ProxyHandler({})).open(request, timeout=3)
            self.assertFalse(server.accepted.is_set()); self.assertEqual(server.posts, 0)
            self.assertEqual(server.invalid, 1)
        finally:
            server.release.set(); server.shutdown(); server.server_close(); serving.join(3)


if __name__ == '__main__': unittest.main()
