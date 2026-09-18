#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Offline proof that the cutover sizing tool is metadata-only and GET-only.

A local stub CouchDB records every request. No real host is contacted.
"""
import http.server
import importlib.util
import io
import json
import os
import sys
import tempfile
import threading
import urllib.parse
from contextlib import redirect_stderr, redirect_stdout

ROOT = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('plan', os.path.join(ROOT, 'cutover-rehearsal-plan.py'))
plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan)

ACCOUNT = 'account/ab/cd/' + 'e' * 28
DATABASES = {
    'accounts': {'doc_count': 4, 'sizes': {'file': 1000, 'active': 600}},
    'system_config': {'doc_count': 20, 'sizes': {'file': 500, 'active': 300}},
    '_users': {'doc_count': 1, 'sizes': {'file': 10, 'active': 5}},
    'numbers/+1415': {'doc_count': 7, 'sizes': {'file': 70, 'active': 50}},
    ACCOUNT: {'doc_count': 100, 'doc_del_count': 3, 'sizes': {'file': 9000, 'active': 7000}},
    ACCOUNT + '-202609': {'doc_count': 50, 'sizes': {'file': 4000, 'active': 3000}},
    ACCOUNT + '-202608': {'doc_count': 40, 'disk_size': 3000, 'data_size': 2000},
}
SEEN = []


class Stub(http.server.BaseHTTPRequestHandler):
    redirect = False

    def log_message(self, *args):
        pass

    def answer(self):
        length = int(self.headers.get('Content-Length') or 0)
        SEEN.append((self.command, self.path, length, self.headers.get('Authorization')))
        if Stub.redirect:
            self.send_response(302); self.send_header('Location', '/elsewhere'); self.end_headers(); return
        path = urllib.parse.unquote(self.path)
        if path == '/':
            body = {'couchdb': 'Welcome', 'version': '3.3.2'}
        elif path == '/_all_dbs':
            body = sorted(DATABASES)
        elif path[1:] in DATABASES:
            body = dict(DATABASES[path[1:]], db_name=path[1:])
        else:
            self.send_response(404); self.end_headers(); return
        data = json.dumps(body).encode()
        self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_COPY = answer


def fail(message):
    print('FAIL: ' + message); sys.exit(1)


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    old = sys.argv
    sys.argv = ['cutover-rehearsal-plan.py'] + argv
    try:
        with redirect_stdout(out), redirect_stderr(err):
            status = plan.main()
    finally:
        sys.argv = old
    return status, out.getvalue(), err.getvalue()


def main():
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Stub)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    source = 'http://127.0.0.1:%d' % server.server_address[1]
    work = tempfile.mkdtemp(prefix='cutover-plan-test.')
    key = os.path.join(work, 'key')
    with open(key, 'w') as handle:
        handle.write('ssh_user: nobody\ncouchdb_user: reader\ncouchdb_pass: s3cret-value\n')
    os.chmod(key, 0o600)
    real_lstat = os.lstat

    class RootOwned:   # the test may not run as root; ownership is what is under test elsewhere
        def __init__(self, info): self.info = info
        def __getattr__(self, name): return 0 if name == 'st_uid' else getattr(self.info, name)
    plan.os.lstat = lambda path: RootOwned(real_lstat(path))

    status, out, err = run(['--source', source, '--credentials', key, '--months', '202609'])
    if status != 0:
        fail('healthy run failed: ' + err)
    result = json.loads(out)
    groups = result['groups']
    expected = {'global': 2, 'couchdb_internal': 1, 'numbers': 1, 'account': 1,
                'account_month_selected': 1, 'account_month_other': 1}
    if {kind: group['databases'] for kind, group in groups.items()} != expected:
        fail('classification: %r' % groups)
    if groups['account']['documents'] != 100 or groups['account']['deleted'] != 3 or groups['account']['file_bytes'] != 9000:
        fail('account totals')
    if groups['account_month_other']['file_bytes'] != 3000 or groups['account_month_other']['active_bytes'] != 2000:
        fail('legacy size fields are not read')
    if result['global_databases'] != ['accounts', 'system_config'] or result['source_version'] != '3.3.2':
        fail('global list or version')
    print('PASS: databases are classified and sized from info documents, including legacy size fields')

    allowed = {'/', '/_all_dbs'} | {'/' + urllib.parse.quote(name, safe='') for name in DATABASES}
    if len(SEEN) != 2 + len(DATABASES) or result['get_requests'] != len(SEEN):
        fail('unexpected request count %d' % len(SEEN))
    for method, path, length, auth in SEEN:
        if method != 'GET' or length != 0 or path not in allowed or not auth:
            fail('forbidden request: %s %s body=%d' % (method, path, length))
        if any(part in path for part in ('_changes', '_all_docs', '_security', '_design', '_local', '_replicate', '?')):
            fail('document-level path requested: ' + path)
    print('PASS: %d requests, every one a bodiless authenticated GET of /, /_all_dbs or a database info document' % len(SEEN))

    if 'e' * 28 in out or 's3cret-value' in out + err or 'reader' in out + err:
        fail('an account database name or a credential was printed')
    print('PASS: account database names and credentials are never printed')

    source_text = open(os.path.join(ROOT, 'cutover-rehearsal-plan.py'), encoding='utf-8').read()
    if source_text.count("method='GET'") != 1 or source_text.count('urllib.request.Request(') != 1:
        fail('the tool must have exactly one request constructor, fixed to GET')
    for word in ("'POST'", "'PUT'", "'DELETE'", 'data=', '_replicate', '_bulk_docs'):
        if word in source_text.replace('"""', ''):
            if word == '_replicate' or word == '_bulk_docs' or word == 'data=':
                fail('write-capable construct in the tool: ' + word)
            fail('write method in the tool: ' + word)
    print('PASS: the tool has one request constructor, fixed to GET, and no write-capable construct')

    Stub.redirect = True
    before = len(SEEN)
    status, out, err = run(['--source', source, '--credentials', key])
    Stub.redirect = False
    if status == 0 or len(SEEN) != before + 1 or 'Redirect refused' not in err:
        fail('a redirect must stop the run after one request')
    os.chmod(key, 0o644)
    status, out, err = run(['--source', source, '--credentials', key])
    if status == 0 or 'mode 0600' not in err or len(SEEN) != before + 1:
        fail('a readable credentials file must be refused before any request')
    os.chmod(key, 0o600)
    for bad in (source + '/db', 'ftp://127.0.0.1', 'http://user:pw@127.0.0.1:1', source + '?x=1'):
        status, out, err = run(['--source', bad, '--credentials', key])
        if status == 0 or len(SEEN) != before + 1:
            fail('unsafe source accepted: ' + bad)
    status, out, err = run(['--source', source, '--credentials', key, '--months', '2026-09'])
    if status == 0 or len(SEEN) != before + 1:
        fail('malformed month accepted')
    print('PASS: redirects, a readable credentials file, unsafe sources and malformed months are refused without further requests')
    server.shutdown()
    print('All 5 cutover sizing groups passed')


if __name__ == '__main__':
    main()
