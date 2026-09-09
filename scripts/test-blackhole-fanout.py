#!/usr/bin/env python3
"""Opt-in actual broker -> native Blackhole -> verified WSS fanout acceptance."""
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).parent
spec = importlib.util.spec_from_file_location('transport', ROOT / 'test-blackhole-slow-client.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
ACCOUNT = '8310dc3170a18de37f205d0da172df65'


def helper(*args):
    r = subprocess.run(['escript', str(ROOT / 'test-fixtures/blackhole-fanout-rpc.escript'), *map(str, args)],
                       capture_output=True, timeout=45, check=False)
    if r.returncode:
        raise RuntimeError('Scoped native fanout helper failed')
    return json.loads(r.stdout)


class Client:
    def __init__(self, token, tag, delayed=False, control=False):
        self.socket = transport.connect('verified-wss', token, 'streamguard-' + secrets.token_hex(16))
        self.socket.settimeout(None)
        self.call = 'fanout-' + tag
        self.delayed, self.control = delayed, control
        self.events, self.replies, self.latencies = [], {}, []
        self.error = None
        self.stopping = False
        self.cv = threading.Condition()
        self.reader = threading.Thread(target=self.receive, daemon=True)
        self.reader.start()
        try:
            self.request('subscribe', token)
        except BaseException:
            self.close()
            raise

    def receive(self):
        try:
            while not self.stopping:
                message = transport.receive_json(self.socket)
                with self.cv:
                    if message.get('action') == 'event':
                        assert not self.control, 'Other-call subscription received fixture traffic'
                        data = message['data']
                        ccv = data['Custom-Channel-Vars']
                        assert data['Call-ID'] == self.call and ccv['Account-ID'] == ACCOUNT
                        assert data['Event-Name'] == 'CHANNEL_HOLD'
                        sequence = ccv['KZ5-Fixture-Sequence']
                        assert isinstance(sequence, int) and sequence not in self.events
                        self.events.append(sequence)
                        self.latencies.append(time.time() * 1000 - ccv['KZ5-Fixture-Sent-Ms'])
                    else:
                        self.replies[message['request_id']] = message
                    self.cv.notify_all()
                if self.delayed and message.get('action') == 'event' and len(self.events) % 10 == 0:
                    time.sleep(1.5)  # Genuine periodic receive lag, below sustained offered rate.
        except BaseException:
            with self.cv:
                if not self.stopping:
                    self.error = 'WSS frame, identity, isolation, duplicate or connection failure'
                self.cv.notify_all()

    def wait(self, predicate, timeout=25):
        end = time.monotonic() + timeout
        with self.cv:
            while not predicate():
                if self.error:
                    raise RuntimeError(self.error)
                left = end - time.monotonic()
                if left <= 0:
                    raise RuntimeError('Fanout observation deadline')
                self.cv.wait(min(left, 0.5))
            if self.error:
                raise RuntimeError(self.error)

    def request(self, action, token):
        request = 'fanout-' + secrets.token_hex(16)
        body = {'action': action, 'auth_token': token, 'request_id': request}
        if action != 'ping':
            body['data'] = {'account_id': ACCOUNT, 'binding': 'call.CHANNEL_HOLD.' + self.call}
        started = time.monotonic()
        transport.send_json(self.socket, body)
        self.wait(lambda: request in self.replies)
        reply = self.replies.pop(request)
        assert reply['status'] == 'success', 'Native subscription/authentication refused'
        return (time.monotonic() - started) * 1000

    def close(self):
        self.stopping = True
        try:
            self.socket.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.socket.close()
        self.reader.join(timeout=3)
        assert not self.reader.is_alive()


def run(pilot):
    # 32 actual subscribers plus an isolated other-call control connection.
    count, batches, batch_size = (4, 1, 3) if pilot else (32, 60, 60)
    tag = secrets.token_hex(16)
    clients, control = [], None
    samples, pings = [], []
    started = time.monotonic()
    receipt = Path('/var/log') / ('kazoo-blackhole-fanout-' + tag + '.json')
    result = {'status': 'RUNNING', 'pilot': pilot, 'subscribers': count, 'published': 0,
              'phase': 'native-admission',
              'path': 'kapi_call AMQP -> native call-event subscription -> certificate-verified WSS'}

    def save():
        receipt.write_text(json.dumps(result, indent=2) + '\n')
        os.chmod(receipt, 0o600)

    save()
    try:
        baseline = helper('sample')
        result['phase'] = 'subscribe'
        save()
        token = helper('issue')['token']  # Private 45-minute fixture token; never logged.
        for i in range(count):
            clients.append(Client(token, tag, delayed=i % 4 == 0))
        control = Client(token, secrets.token_hex(16), control=True)
        for batch in range(batches):
            result['phase'] = 'verify-auth'
            save()
            # Keep the same sockets/token: native authentication changes require
            # reconnect. Every command/event still undergoes native validation.
            for client in clients + [control]:
                pings.append(client.request('ping', token))
            first = batch * batch_size + 1
            result['phase'] = 'broker-fanout'
            save()
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(helper, 'publish', tag, first, batch_size)
                while not future.done():
                    pings.append(control.request('ping', token))
                    time.sleep(0.5)
                published = future.result()
            assert published == {'published': batch_size, 'first': first}
            result['phase'] = 'delivery-drain'
            save()
            expected = first + batch_size - 1
            for client in clients:
                client.wait(lambda c=client: len(c.events) == expected)
                assert sorted(client.events) == list(range(1, expected + 1))
            assert not control.events
            samples.append(helper('sample'))
            assert samples[-1]['vm_bytes'] < baseline['vm_bytes'] + 536870912
            assert samples[-1]['processes'] < baseline['processes'] + 1000
            assert max(pings) < 3000, 'Responsive control/auth commands stalled'
            result.update(published=expected, deliveries=sum(len(c.events) for c in clients),
                          elapsed_seconds=round(time.monotonic() - started, 1), completed_batches=batch + 1)
            save()
            print(json.dumps(result), flush=True)
        elapsed = time.monotonic() - started
        if not pilot:
            assert elapsed >= 1800
        assert all(not c.error for c in clients + [control])
        result.update(status='PASS', max_control_ping_ms=round(max(pings), 1),
                      phase='complete',
                      peak_vm_bytes=max(s['vm_bytes'] for s in samples),
                      peak_processes=max(s['processes'] for s in samples),
                      max_delivery_latency_ms=round(max(v for c in clients for v in c.latencies), 1),
                      other_call_leaks=0, baseline=baseline)
    except BaseException as error:
        result['status'] = 'FAIL'
        safe_reasons = {'Scoped native fanout helper failed', 'Fanout observation deadline',
                        'Native subscription/authentication refused',
                        'WSS frame, identity, isolation, duplicate or connection failure',
                        'Responsive control/auth commands stalled'}
        result['failure_reason'] = str(error) if str(error) in safe_reasons else 'Acceptance assertion failed'
        raise
    finally:
        closed = True
        for client in clients + ([control] if control else []):
            try:
                client.close()
            except BaseException:
                closed = False
        result['sockets_closed'] = closed
        if not closed:
            result['status'] = 'FAIL'
        save()
        print(json.dumps({'status': result['status'], 'receipt': str(receipt)}), flush=True)
        assert closed, 'Client cleanup incomplete'


def main():
    import fcntl
    import stat
    assert os.geteuid() == 0 and sys.argv[1:] in (['--pilot'], ['--live'])
    os.umask(0o077)
    lock = Path('/etc/kazoo/monitor-acceptance.lock')
    st = lock.lstat()
    assert stat.S_ISREG(st.st_mode) and st.st_uid == 0 and st.st_nlink == 1 and stat.S_IMODE(st.st_mode) == 0o600
    with lock.open('r+') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run(sys.argv[1] == '--pilot')


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        print('FAIL scoped fanout acceptance; inspect protected receipt, not credentials', file=sys.stderr)
        sys.exit(1)
