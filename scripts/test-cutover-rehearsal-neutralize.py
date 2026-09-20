#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Offline proof for the rehearsal neutralize step. One local stub CouchDB; no real host."""
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
spec = importlib.util.spec_from_file_location('neutralize', os.path.join(ROOT, 'cutover-rehearsal-neutralize.py'))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

DB = {
    'webhooks': {
        'h1': {'_id': 'h1', '_rev': '1-a', 'pvt_type': 'webhook', 'hook': 'all', 'uri': 'https://customer.invalid/secret-path'},
        'h2': {'_id': 'h2', '_rev': '1-b', 'pvt_type': 'webhook', 'enabled': True, 'uri': 'https://customer.invalid/two'},
        'h3': {'_id': 'h3', '_rev': '1-c', 'pvt_type': 'webhook', 'enabled': False, 'uri': 'https://customer.invalid/off'},
        '_design/webhooks': {'_id': '_design/webhooks', '_rev': '1-d'},
    },
    'pending_notifications': {'p1': {'_id': 'p1', '_rev': '1-e', 'to': 'person@customer.invalid'},
                              'p2': {'_id': 'p2', '_rev': '1-f'}},
    'system_config': {'smtp_client': {'_id': 'smtp_client', '_rev': '4-g', 'pvt_type': 'config',
                                      'default': {'relay': 'smtp.provider.invalid', 'port': 587, 'username': 'u', 'password': 'p'},
                                      'node@prod': {'relay': 'other.invalid'}}},
}
SEEN = []


class Stub(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        length = int(self.headers.get('Content-Length') or 0)
        body = json.loads(self.rfile.read(length)) if length else None
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        SEEN.append((self.command, path))
        parts = path.strip('/').split('/')
        if parts[0] not in DB:
            return self.answer(404, {})
        docs = DB[parts[0]]
        if self.command == 'GET' and parts[1:] == ['_all_docs']:
            return self.answer(200, {'rows': [{'id': i, 'doc': d} for i, d in docs.items()]})
        if self.command == 'GET' and len(parts) == 2 and parts[1] in docs:
            return self.answer(200, docs[parts[1]])
        if self.command == 'POST' and parts[1:] == ['_bulk_docs']:
            for doc in body['docs']:
                if doc.get('_deleted'):
                    docs.pop(doc['_id'], None)
                else:
                    docs[doc['_id']] = doc
            return self.answer(201, [{'ok': True, 'id': d['_id']} for d in body['docs']])
        return self.answer(404, {})
    do_GET = do_POST = do_PUT = do_DELETE = handle_any


def fail(message):
    print('FAIL: ' + message)
    sys.exit(1)


def run(argv):
    out, err, old = io.StringIO(), io.StringIO(), sys.argv
    sys.argv = ['cutover-rehearsal-neutralize.py'] + argv
    try:
        with redirect_stdout(out), redirect_stderr(err):
            status = tool.main()
    finally:
        sys.argv = old
    return status, out.getvalue(), err.getvalue()


def main():
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Stub)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    target = 'http://127.0.0.1:%d' % server.server_address[1]
    work = tempfile.mkdtemp(prefix='cutover-neutralize-test.')
    key = os.path.join(work, 'key')
    with open(key, 'w') as handle:
        handle.write('couchdb_user: admin\ncouchdb_pass: s3cret-value\n')
    os.chmod(key, 0o600)
    real_lstat = os.lstat

    class RootOwned:
        def __init__(self, info):
            self.info = info

        def __getattr__(self, name):
            return 0 if name == 'st_uid' else getattr(self.info, name)
    tool.plan.os.lstat = lambda path: RootOwned(real_lstat(path))

    for refused in (target, 'http://10.1.0.44:5984', 'http://10.1.0.10:5984', 'http://172.30.253.11:5984'):
        status, out, err = run(['--target', refused, '--target-credentials', key])
        if status == 0 or SEEN:
            fail('a target outside the rehearsal lab was accepted or contacted: ' + refused)
    print('PASS: only the rehearsal lab network can be neutralized; main, production and other labs are refused unasked')

    tool.copy_tool.TARGET_NETWORKS = [ipaddress.ip_network('127.0.0.0/8')]
    status, out, err = run(['--target', target, '--target-credentials', key])
    if status != 0:
        fail('neutralize failed: ' + err + out)
    result = json.loads(out)
    hooks = DB['webhooks']
    if any(hooks[i].get('enabled', True) for i in ('h1', 'h2', 'h3')) or not hooks['h1'].get('pvt_rehearsal_disabled'):
        fail('an enabled webhook is left')
    if hooks['h3'].get('pvt_rehearsal_disabled') or hooks['h1']['uri'] != 'https://customer.invalid/secret-path':
        fail('an already disabled hook was marked, or hook content was altered')
    if '_design/webhooks' not in hooks or DB['pending_notifications']:
        fail('the design document was touched or a pending notification is left')
    smtp = DB['system_config']['smtp_client']
    if any(smtp[k].get('relay') != '127.0.0.1' or smtp[k].get('port') != 9 or smtp[k].get('password') for k in ('default', 'node@prod')):
        fail('a mail relay still points outside')
    if result != {'webhooks_disabled': 2, 'webhooks_still_enabled': 0, 'pending_notifications_removed': 2,
                  'pending_notifications_left': 0, 'smtp_relays_pointed_at_discard': 3, 'rejected_writes': 0}:
        fail('counts: %r' % result)
    print('PASS: enabled webhooks are disabled and marked, pending notifications removed, every mail relay points at discard')

    if any(word in out + err for word in ('customer.invalid', 's3cret-value', 'provider.invalid', 'person@')):
        fail('a URL, address, relay or credential was printed')
    if {method for method, _ in SEEN} - {'GET', 'POST'}:
        fail('unexpected method')
    print('PASS: counts only are printed; only GET and POST _bulk_docs are used')

    status, out, err = run(['--target', target, '--target-credentials', key])
    if status != 0 or json.loads(out)['webhooks_disabled'] != 0:
        fail('a second run must be a no-op')
    print('PASS: running it again changes nothing')
    server.shutdown()
    print('All 4 rehearsal neutralize groups passed')


if __name__ == '__main__':
    main()
