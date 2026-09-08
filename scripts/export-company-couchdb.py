#!/usr/bin/env python
"""GET-only, exact-account CouchDB leaf-revision export (Python 2.7/3).

Run on the source node over SSH. Read {username,password,account_id,databases}
from stdin; stream private NDJSON on stdout, never to a terminal. Endpoint is
deliberately fixed to source-node loopback. No replication/checkpoint writes.
This is a non-atomic logical snapshot, not a physical/full revision backup.
"""
from __future__ import print_function
import base64
import hashlib
import json
import re
import sys
import time
try:
    from urllib.request import Request, build_opener, HTTPRedirectHandler, ProxyHandler
    from urllib.parse import quote, urlencode
except ImportError:
    from urllib2 import Request, build_opener, HTTPRedirectHandler, ProxyHandler
    from urllib import quote, urlencode

MAX_RESPONSE = 64 * 1024 * 1024
MAX_PAGES = 10000
PAGE_SIZE = 100
try:
    STRING_TYPES = (basestring,)
except NameError:
    STRING_TYPES = (str,)


class ExportError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ExportError('Redirect refused')


def scope(config):
    account = config.get('account_id', '')
    if not re.match(r'^[0-9a-f]{32}\Z', account):
        raise ExportError('Invalid account')
    base = 'account/' + account[:2] + '/' + account[2:4] + '/' + account[4:]
    names = config.get('databases')
    if not isinstance(names, list) or not names or len(names) > 240:
        raise ExportError('Explicit database allowlist required')
    pattern = re.compile('^' + re.escape(base) + r'(?:-[0-9]{4}(?:0[1-9]|1[0-2]))?\Z')
    if any(not isinstance(name, STRING_TYPES) or not pattern.match(name) for name in names):
        raise ExportError('Database outside exact company scope')
    if len(set(names)) != len(names):
        raise ExportError('Duplicate database')
    return account, sorted(names)


def encoded(value):
    return quote(value.encode('utf-8'), safe='')


class Reader(object):
    def __init__(self, username, password):
        if not username or not password:
            raise ExportError('Credentials required through stdin')
        self.authorization = 'Basic ' + base64.b64encode(
            (username + ':' + password).encode('utf-8')).decode('ascii')
        self.opener = build_opener(ProxyHandler({}), NoRedirect())
        self.requests = 0

    def get(self, path, query=None):
        if not path.startswith('/') or path.startswith('//') or '?' in path or '#' in path:
            raise ExportError('Unsafe relative path')
        url = 'http://127.0.0.1:5984' + path
        if query:
            url += '?' + urlencode(query)
        # One sequential request, <=25 requests/second; no retries/load bursts.
        time.sleep(0.04)
        req = Request(url, headers={'Authorization': self.authorization,
                                   'Accept': 'application/json'})
        response = self.opener.open(req, timeout=30)
        try:
            body = response.read(MAX_RESPONSE + 1)
            if len(body) > MAX_RESPONSE:
                raise ExportError('Response exceeds bounded export size')
            self.requests += 1
            return json.loads(body.decode('utf-8'))
        finally:
            response.close()


class Writer(object):
    def __init__(self, stream):
        self.stream = stream
        self.digest = hashlib.sha256()
        self.records = 0

    def emit(self, record):
        line = json.dumps(record, sort_keys=True, separators=(',', ':'), ensure_ascii=True) + '\n'
        self.digest.update(line.encode('ascii'))
        self.records += 1
        self.stream.write(line)
        self.stream.flush()


def validate_doc(doc, doc_id, rev):
    if doc.get('_id') != doc_id or doc.get('_rev') != rev:
        raise ExportError('Revision identity mismatch')
    revisions = doc.get('_revisions', {})
    ids = revisions.get('ids', [])
    if not ids or str(revisions.get('start')) + '-' + ids[0] != rev:
        raise ExportError('Revision ancestry missing')
    for attachment in doc.get('_attachments', {}).values():
        if 'data' not in attachment or attachment.get('stub') or attachment.get('follows'):
            raise ExportError('Attachment bytes missing')
        # Decode to detect corrupt transport, without logging customer bytes.
        data = attachment['data']
        raw = base64.b64decode(data)
        if base64.b64encode(raw).decode('ascii') != data:
            raise ExportError('Attachment encoding invalid')


def export(config, reader, writer):
    account, names = scope(config)
    version = reader.get('/').get('version')
    writer.emit({'type': 'snapshot_start', 'format': 1, 'account_id': account,
                 'databases': names, 'source_version': version,
                 'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                 'consistency': 'non-atomic leaf revisions; no historical bodies or _local documents'})
    summaries = []
    for name in names:
        path = '/' + encoded(name)
        before = reader.get(path)
        if before.get('db_name') != name:
            raise ExportError('Database identity mismatch')
        security = reader.get(path + '/_security')
        writer.emit({'type': 'database_start', 'database': name,
                     'metadata': before, 'security': security})
        since = '0'
        leaves = 0
        rows = 0
        seen = set()
        for unused in range(MAX_PAGES):
            page = reader.get(path + '/_changes', {'since': since, 'limit': PAGE_SIZE,
                              'style': 'all_docs', 'feed': 'normal'})
            changes = page['results']
            last = page['last_seq']
            if changes and last == since:
                raise ExportError('Changes cursor did not advance')
            for change in changes:
                doc_id = change['id']
                if doc_id.startswith('_local/'):
                    raise ExportError('Unexpected local document')
                if not change['changes']:
                    raise ExportError('No leaf revisions returned')
                rows += 1
                for leaf in change['changes']:
                    rev = leaf['rev']
                    identity = (doc_id, rev)
                    if identity in seen:
                        continue
                    doc = reader.get(path + '/' + encoded(doc_id),
                                     {'rev': rev, 'revs': 'true', 'attachments': 'true'})
                    validate_doc(doc, doc_id, rev)
                    writer.emit({'type': 'document', 'database': name, 'doc': doc})
                    seen.add(identity)
                    leaves += 1
            since = last
            if not changes or page.get('pending') == 0:
                break
        else:
            raise ExportError('Export page bound exceeded')
        after = reader.get(path)
        security_after = reader.get(path + '/_security')
        stable = (before.get('update_seq') == after.get('update_seq') and
                  before.get('purge_seq') == after.get('purge_seq') and
                  security == security_after)
        summary = {'type': 'database_end', 'database': name, 'metadata': after,
                   'changes_last_seq': since, 'change_rows': rows,
                   'leaf_revisions': leaves, 'unchanged_during_export': stable}
        writer.emit(summary)
        summaries.append(summary)
    # Digest covers every preceding byte, not this final record.
    writer.emit({'type': 'snapshot_end', 'sha256': writer.digest.hexdigest(),
                 'records_before_end': writer.records, 'databases': len(names),
                 'all_databases_unchanged': all(s['unchanged_during_export'] for s in summaries)})


def main():
    try:
        if sys.stdout.isatty():
            raise ExportError('Private snapshot cannot go to terminal')
        payload = sys.stdin.read(65537)
        if len(payload) > 65536:
            raise ExportError('Input limit exceeded')
        config = json.loads(payload)
        scope(config)  # Validate the entire allowlist before any network access.
        reader = Reader(config.get('username'), config.get('password'))
        export(config, reader, Writer(sys.stdout))
    except Exception:
        # Deliberately exclude URLs, IDs, response bodies and credentials.
        sys.stderr.write('Company export failed; partial stream is not a completed snapshot.\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
