#!/usr/bin/env python3
"""Native AMQP loss with an HTTP-accepted but unanswered synthetic delivery.

Extends the existing isolated TLS/consumer proof. No production bridge settings,
provider constructor, tokens or external HTTP delivery endpoint are loaded.
"""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import logging
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time
from urllib.parse import quote, urlsplit
from urllib.request import build_opener, ProxyHandler, Request

HERE = Path(__file__).resolve()
spec = importlib.util.spec_from_file_location('service_proof', HERE.with_name('accept-bridge-remote-service.py'))
service = importlib.util.module_from_spec(spec); spec.loader.exec_module(service)
remote = service.remote
require = service.require


def validate_child(value):
    require(type(value) is dict and set(value) == {'settings', 'body', 'endpoint'}, 'invalid_child_input')
    settings = value['settings']
    require(type(settings) is dict, 'invalid_child_settings')
    for key, expected in {'AMQP_HOST': remote.HOST, 'AMQP_PORT': 35671,
                          'AMQP_USER': remote.IDENTITY, 'AMQP_VHOST': remote.IDENTITY,
                          'AMQP_TLS': 'true', 'TOPOLOGY': 'quorum-v1',
                          'RETRY': 'quorum-counted-v1', 'FRESHNESS': 'unix-ms-v1',
                          'AMQP_MANAGEMENT_URL': 'https://10.1.0.44:35672'}.items():
        require(type(settings.get(key)) is type(expected) and settings[key] == expected, 'foreign_child_scope')
    match = re.fullmatch(r'(remote-[0-9a-f]{32})\.quorum-v1', settings.get('QUEUE', ''))
    require(match and settings.get('EXCHANGE') == match[1]+'.pushes'
            and settings.get('BINDING_KEY') == 'fixture.only', 'foreign_child_queue')
    endpoint = urlsplit(value['endpoint'])
    require(endpoint.scheme == 'http' and endpoint.hostname == '127.0.0.1'
            and endpoint.port is not None and not endpoint.username and not endpoint.password
            and not endpoint.query and not endpoint.fragment
            and endpoint.path == '/fixture/'+match[1], 'nonlocal_synthetic_http_refused')
    require(type(value['body']) is str and len(value['body']) < 8192, 'invalid_child_body')
    return value


def child():
    import amqpstorm
    value = validate_child(json.loads(sys.stdin.buffer.read(32769), object_pairs_hook=remote.unique_object))
    class SyntheticHTTPRuntime(service.BridgeRuntime):
        def deliver(self, body, freshness=None):
            require(body == value['body'] and freshness is not None, 'unexpected_worker_body')
            # Deliberately send only to the validated loopback fixture. The
            # provider receives it, but its response is held across AMQP loss.
            request = Request(value['endpoint'], data=body.encode(), method='POST')
            with build_opener(ProxyHandler({})).open(request, timeout=30) as response:
                return response.status == 200, response.status, 'provider_response'
    runtime = SyntheticHTTPRuntime.__new__(SyntheticHTTPRuntime)
    runtime._settings = dict(value['settings'], WORKERS=1, APNS_WORKERS=1,
                             STALL_TIMEOUT=70, DELIVERY_TIMEOUT=60)
    runtime.amqpstorm = amqpstorm
    runtime._amqp_tls_options = service.amqp_tls_options(runtime._settings)
    runtime._stop, runtime._conn = threading.Event(), None
    runtime._last_progress = time.monotonic()
    runtime.run(fail_stop_exit=True)


class HeldHTTP(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, path, body):
        self.path, self.body = path, body.encode()
        self.accepted, self.release = threading.Event(), threading.Event()
        self.posts, self.invalid, self.lock = 0, 0, threading.Lock()
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                self.connection.settimeout(3)
                length = int(self.headers.get('Content-Length', '-1'))
                if self.path != self.server.path or length != len(self.server.body):
                    with self.server.lock: self.server.invalid += 1
                    self.send_error(400); return
                body = self.rfile.read(length)
                if body != self.server.body:
                    with self.server.lock: self.server.invalid += 1
                    self.send_error(400); return
                with self.server.lock: self.server.posts += 1
                self.server.accepted.set()
                self.server.release.wait(60)
                try:
                    self.send_response(200); self.send_header('Content-Length', '2')
                    self.end_headers(); self.wfile.write(b'{}')
                except OSError: pass  # The fail-stopped client has gone away.
        super().__init__(('127.0.0.1', 0), Handler)


class InflightProof(remote.consumer.ConsumerProof):
    def run(self):
        super().run()  # Keep all original retry/exhaustion acceptance assertions.
        import requests
        body = self.body('inflight-loss')
        path = '/fixture/'+self.settings['QUEUE'].removesuffix('.quorum-v1')
        fixture = HeldHTTP(path, body)
        server = threading.Thread(target=fixture.serve_forever, daemon=True); server.start()
        process = None
        digest = hashlib.sha256(HERE.read_bytes()).hexdigest()
        evidence = self.receipt['inflight_loss'] = {'complete': False, 'phase': 'starting_child', 'provider_constructor_used': False,
            'normal_service_reconfigured': False, 'systemd_restart_policy_tested': False,
            'source_sha256': digest}
        try:
            endpoint = 'http://127.0.0.1:'+str(fixture.server_port)+path
            value = validate_child({'settings': self.settings, 'body': body, 'endpoint': endpoint})
            process = subprocess.Popen([sys.executable, '-B', '-I', str(HERE), '--synthetic-worker-child'],
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True)
            process.stdin.write(json.dumps(value).encode()); process.stdin.close()
            with requests.Session() as session:
                session.trust_env = False
                def api(method, path):
                    with session.request(method, self.settings['AMQP_MANAGEMENT_URL']+'/api/'+path,
                        auth=(self.settings['AMQP_USER'], self.settings['AMQP_PASS']),
                        verify=self.settings['AMQP_MANAGEMENT_CA_FILE'], allow_redirects=False,
                        timeout=(3.05, 5), stream=True) as response:
                        require(response.status_code == (204 if method == 'DELETE' else 200), 'management_failed')
                        if method == 'DELETE': return None
                        raw = bytearray()
                        for part in response.iter_content(8192):
                            raw.extend(part); require(len(raw) <= 131072, 'management_oversized')
                        return json.loads(raw, object_pairs_hook=remote.unique_object)
                until = time.monotonic()+20
                while True:
                    require(process.poll() is None, 'child_exited_before_registration')
                    queue = api('GET', 'queues/'+remote.IDENTITY+'/'+self.settings['QUEUE'])
                    if queue.get('consumers') == 1 and len(queue.get('consumer_details', [])) == 1: break
                    require(time.monotonic() < until, 'consumer_registration_timeout'); time.sleep(1)
                sockets = subprocess.run(['ss', '-Hntp', 'dst', '10.1.0.44:35671'], capture_output=True,
                                          text=True, check=True, timeout=10).stdout
                connection = service.matching_connection(api('GET', 'connections'), process.pid, sockets)
                require(queue['consumer_details'][0]['channel_details']['connection_name'] == connection['name'],
                        'child_consumer_connection_mismatch')
                self.publish(body)
                require(fixture.accepted.wait(10) and process.poll() is None, 'http_not_inflight')
                evidence['phase'] = 'http_accepted_response_held'
                started = time.monotonic()
                # Exactly the UUID queue's verified child connection; never
                # close connections by username or stop any broker here.
                api('DELETE', 'connections/'+quote(connection['name'], safe=''))
                require(process.wait(timeout=10) == 78, 'uncertain_delivery_did_not_fail_stop')
                evidence['child_exit'] = 78
                evidence['exit_after_disconnect_seconds'] = round(time.monotonic()-started, 3)
                require(fixture.posts == 1 and fixture.invalid == 0 and not fixture.release.is_set(),
                        'unexpected_http_dispatches')
                message = self.receive(self.wanted.work_queue, body)
                require(message.redelivered is True, 'uncertain_body_not_redelivered')
                require(remote.consumer.delivery_count(message.properties, message.redelivered) == 1,
                        'uncertain_body_counter_changed')
                evidence.update(synthetic_http_posts=fixture.posts, body_sha256=hashlib.sha256(body.encode()).hexdigest(),
                                broker_redelivered=True, broker_delivery_count=1)
                # Only this synthetic body is consumed after verified readback;
                # no second provider dispatch and no recovery replay is made.
                message.ack()
                self.empty()
                require(hashlib.sha256(HERE.read_bytes()).hexdigest() == digest, 'inflight_source_changed')
                evidence['complete'] = True
                self.receipt['checks'].append('real_http_inflight_amqp_loss_exit78_one_post_and_retained_body')
        except Exception as error:
            code = str(error)
            evidence['failure'] = code if re.fullmatch('[a-z_]{1,80}', code) else 'inflight_case_failed'
            raise
        finally:
            if process is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=10)
            fixture.release.set(); fixture.shutdown(); fixture.server_close(); server.join(timeout=5)


def main():
    require(not os.environ.get('NOTIFY_SOCKET'), 'standalone_proof_required')
    if sys.argv[1:] == ['--synthetic-worker-child']:
        child(); return
    require(sys.argv[1:] == ['--run-development-inflight-loss-proof'], 'explicit_action_required')
    remote.consumer.ConsumerProof = InflightProof
    # Reuse all fixed-host/identity/TLS/resource/receipt/cleanup guards.
    sys.argv[1:] = ['--run-development-remote-tls-proof']
    remote.main()


if __name__ == '__main__':
    logging.disable(logging.CRITICAL)
    try: main()
    except Exception:
        print('In-flight acceptance failed; inspect protected receipt; private inputs withheld.', file=sys.stderr)
        sys.exit(1)
