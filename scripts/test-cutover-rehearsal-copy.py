#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Offline proof for the cutover copy tool. Two local stubs; no real host is contacted."""
import http.server
import importlib.util
import io
import ipaddress
import json
import os
import sys
import tempfile
import threading
import urllib.parse
from contextlib import redirect_stderr, redirect_stdout

ROOT = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('copy_tool', os.path.join(ROOT, 'cutover-rehearsal-copy.py'))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

ACCOUNT = 'account/ab/cd/' + 'e' * 28


def docs(prefix, count):
    return {'%s-%03d' % (prefix, i): {'_id': '%s-%03d' % (prefix, i), '_rev': '3-abc%03d' % i, 'value': i}
            for i in range(count)}


SOURCE = {
    'accounts': docs('acct', 3),
    'system_config': dict(docs('cfg', 2), **{'_design/views': {'_id': '_design/views', '_rev': '7-def', 'views': {}}}),
    'token_auth': docs('token', 5),
    '_users': docs('user', 1),
    'numbers/+1415': docs('num', 4),
    ACCOUNT: docs('doc', 120),            # more than two pages
    ACCOUNT + '-202609': docs('cdr', 7),
    ACCOUNT + '-202608': docs('old', 9),
}
SOURCE_SEEN, TARGET_SEEN, TARGET = [], [], {}


def reply(handler, status, body):
    data = json.dumps(body).encode()
    handler.send_response(status)
    handler.send_header('Content-Length', str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


class Source(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_any(self):
        SOURCE_SEEN.append((self.command, self.path, int(self.headers.get('Content-Length') or 0)))
        parsed = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(parsed.path)
        query = urllib.parse.parse_qs(parsed.query)
        if path == '/_all_dbs':
            return reply(self, 200, sorted(SOURCE))
        if path.endswith('/_all_docs'):
            name = path[1:-len('/_all_docs')]
            ids = sorted(SOURCE[name])
            start = json.loads(query['startkey'][0]) if 'startkey' in query else None
            if start is not None:
                ids = [i for i in ids if i >= start]
            ids = ids[:int(query['limit'][0])]
            return reply(self, 200, {'rows': [{'id': i, 'doc': SOURCE[name][i]} for i in ids]})
        if path[1:] in SOURCE:
            return reply(self, 200, {'db_name': path[1:], 'doc_count': len(SOURCE[path[1:]])})
        return reply(self, 404, {})
    do_GET = do_POST = do_PUT = do_DELETE = handle_any


class TargetStub(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_any(self):
        length = int(self.headers.get('Content-Length') or 0)
        body = json.loads(self.rfile.read(length)) if length else None
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        TARGET_SEEN.append((self.command, path))
        if self.command == 'PUT':
            TARGET.setdefault(path[1:], {})
            return reply(self, 201, {'ok': True})
        if self.command == 'POST' and path.endswith('/_bulk_docs'):
            if body.get('new_edits') is not False:
                return reply(self, 400, {})
            for doc in body['docs']:
                TARGET[path[1:-len('/_bulk_docs')]][doc['_id']] = doc
            return reply(self, 201, [])
        if self.command == 'GET' and path[1:] in TARGET:
            return reply(self, 200, {'doc_count': len(TARGET[path[1:]])})
        return reply(self, 404, {})
    do_GET = do_POST = do_PUT = do_DELETE = handle_any


def fail(message):
    print('FAIL: ' + message)
    sys.exit(1)


def run(argv):
    out, err, old = io.StringIO(), io.StringIO(), sys.argv
    sys.argv = ['cutover-rehearsal-copy.py'] + argv
    try:
        with redirect_stdout(out), redirect_stderr(err):
            status = tool.main()
    finally:
        sys.argv = old
    return status, out.getvalue(), err.getvalue()


def main():
    servers = []
    for handler in (Source, TargetStub):
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    source = 'http://localhost:%d' % servers[0].server_address[1]
    target = 'http://127.0.0.1:%d' % servers[1].server_address[1]
    work = tempfile.mkdtemp(prefix='cutover-copy-test.')
    key = os.path.join(work, 'key')
    with open(key, 'w') as handle:
        handle.write('couchdb_user: reader\ncouchdb_pass: s3cret-value\n')
    os.chmod(key, 0o600)
    real_lstat = os.lstat

    class RootOwned:
        def __init__(self, info):
            self.info = info

        def __getattr__(self, name):
            return 0 if name == 'st_uid' else getattr(self.info, name)
    tool.plan.os.lstat = lambda path: RootOwned(real_lstat(path))
    base = ['--source', source, '--credentials', key, '--target-credentials', key, '--months', '202609']

    # The real allow-list: only the fresh lab. Nothing may be contacted when the target is refused.
    if [str(n) for n in tool.TARGET_NETWORKS] != ['172.30.249.0/24']:
        fail('the target allow-list must be exactly the cutover rehearsal lab network')
    for refused in (target, 'http://10.1.0.44:5984', 'http://10.1.0.44:15984', 'http://172.30.253.11:5984', 'http://172.30.250.11:5984',
                    'http://10.1.0.10:5984', 'http://kz5-fresh-couchdb:5984', 'https://172.30.249.11:5984',
                    'http://172.30.249.11:5984/db'):
        status, out, err = run(base + ['--target', refused, '--receipt-dir', os.path.join(work, 'r0')])
        if status == 0 or SOURCE_SEEN or TARGET_SEEN:
            fail('target accepted or a host contacted: ' + refused)
    print('PASS: main, the older labs, production itself, names, https and paths are refused as targets before any request')

    tool.TARGET_NETWORKS = [ipaddress.ip_network('127.0.0.0/8')]   # the stub stands in for the rehearsal lab
    status, out, err = run(base + ['--target', target, '--receipt-dir', os.path.join(work, 'r1')])
    if status != 0:
        fail('copy failed: ' + err)
    receipt = json.loads(out)
    expected = {name for name in SOURCE if name not in ('token_auth', '_users', ACCOUNT + '-202608')}
    if set(TARGET) != expected:
        fail('copied set is wrong: %r' % sorted(TARGET))
    if any(TARGET[name] != SOURCE[name] for name in expected):
        fail('documents or revisions differ')
    if receipt['status'] != 'PASS' or receipt['selected_databases'] != len(expected) or receipt['incomplete_databases'] != 0:
        fail('receipt: %r' % receipt)
    print('PASS: globals (without token_auth), accounts, numbers and the selected month are copied whole, revisions '
          'and design documents included; other months and CouchDB internals are not')

    for method, path, length in SOURCE_SEEN:
        if method != 'GET' or length != 0:
            fail('production saw %s %s' % (method, path))
        if any(word in path for word in ('_replicate', '_bulk', '_local', '_security', '_changes', '_revs_diff')):
            fail('production saw a non-read path: ' + path)
    if receipt['source_get_requests'] != len(SOURCE_SEEN):
        fail('request count is not reported faithfully')
    if {method for method, _ in TARGET_SEEN} - {'GET', 'PUT', 'POST'}:
        fail('unexpected method on the target')
    print('PASS: production saw %d requests, all bodiless GETs of lists, info documents and _all_docs pages' % len(SOURCE_SEEN))

    receipt_path = os.path.join(work, 'r1', 'receipt.json')
    text = out + err + open(receipt_path, encoding='utf-8').read()
    if 'e' * 28 in text or 's3cret-value' in text or (os.stat(receipt_path).st_mode & 0o077):
        fail('an account name or credential leaked, or the receipt is readable by others')
    print('PASS: output and the 0600 receipt hold counts only')

    before = len(SOURCE_SEEN)
    writes_before = len([1 for method, _ in TARGET_SEEN if method != 'GET'])
    status, out, err = run(base + ['--target', target, '--receipt-dir', os.path.join(work, 'r2')])
    if status == 0 or 'must be empty' not in err:
        fail('a target that already holds the data must be refused')
    status, out, err = run(base + ['--target', target, '--receipt-dir', os.path.join(work, 'r2'), '--resume'])
    if status != 0:
        fail('resume failed: ' + err)
    if any('_all_docs' in path for _, path, _length in SOURCE_SEEN[before:]):
        fail('resume re-read databases that were already complete')
    if len([1 for method, _ in TARGET_SEEN if method != 'GET']) != writes_before:
        fail('resume wrote to databases that were already complete')
    print('PASS: a non-empty target is refused; --resume skips complete databases without re-reading or rewriting them')

    source_text = open(os.path.join(ROOT, 'cutover-rehearsal-copy.py'), encoding='utf-8').read()
    code = source_text.split('"""', 2)[2]
    if code.count('urllib.request.Request(') != 1 or 'urllib.request.Request(' in code.split('class Target:')[0]:
        fail('the only request constructor in the tool must be the target writer; production goes through the GET-only reader')
    if "'DELETE'" in code or '_replicate' in code:
        fail('the tool can delete or start a replication')
    status, out, err = run(['--source', target, '--credentials', key, '--target', target,
                            '--target-credentials', key, '--receipt-dir', os.path.join(work, 'r3')])
    if status == 0 or 'same host' not in err:
        fail('source and target on one host must be refused')
    print('PASS: production is reachable only through the GET-only reader; no delete, no replication, never source = target')
    for server in servers:
        server.shutdown()
    print('All 6 cutover copy groups passed')


if __name__ == '__main__':
    main()
