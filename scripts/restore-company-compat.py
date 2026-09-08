#!/usr/bin/env python3
"""Restore a verified snapshot only inside the dedicated .44 lab namespace.

Enter the network namespace of kazoo-compat-couchdb.service before invoking.
Creates new baseline-prefixed or canonical working DBs; refuses all collisions.
Never accepts an arbitrary CouchDB endpoint or caller-supplied credentials.
"""
import argparse
import base64
import importlib.util
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import tempfile
from urllib.parse import quote
from urllib.request import Request, build_opener, ProxyHandler

ROOT = pathlib.Path('/var/lib/kazoo-compat-runtime')
SNAPSHOTS = pathlib.Path('/var/lib/kazoo-compat/snapshots')


def sibling(name, filename):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


receiver = sibling('snapshot_receiver', 'receive-company-couchdb.py')


def assert_namespace():
    if os.geteuid() != 0 or os.readlink('/proc/self/ns/net') == os.readlink('/proc/1/ns/net'):
        raise ValueError('Must run as root inside the separate lab network namespace')
    pid = int(subprocess.check_output(['systemctl', 'show', 'kazoo-compat-couchdb.service', '-p', 'MainPID', '--value']))
    if pid <= 0 or os.readlink('/proc/self/ns/net') != os.readlink('/proc/%d/ns/net' % pid):
        raise ValueError('Not the dedicated lab namespace')
    interfaces = json.loads(subprocess.check_output(['ip', '-j', 'address', 'show']))
    if len(interfaces) != 1 or interfaces[0].get('ifname') != 'lo':
        raise ValueError('External network interface detected')
    for address in interfaces[0].get('addr_info', []):
        if address.get('local') not in ['127.0.0.1', '::1']:
            raise ValueError('Unexpected namespace address')


def target_database(source, copy, baseline_tag=None):
    if baseline_tag is not None:
        if copy != 'baseline' or not re.fullmatch('[a-z][a-z0-9]{0,15}', baseline_tag):
            raise ValueError('Invalid baseline tag')
        return 'baseline-' + baseline_tag + '-' + source
    if copy == 'working':
        return source
    if copy == 'baseline':
        return 'baseline-' + source
    raise ValueError('Unknown copy type')


class Client:
    def __init__(self):
        assert_namespace()
        credentials = json.loads((ROOT / 'credentials.json').read_text())
        self.authorization = 'Basic ' + base64.b64encode((credentials['username'] + ':' + credentials['password']).encode()).decode()
        self.opener = build_opener(ProxyHandler({}), receiver.exporter.NoRedirect())

    def request(self, method, path, payload=None):
        if method not in ['GET', 'PUT', 'POST'] or not path.startswith('/') or path.startswith('//'):
            raise ValueError('Invalid lab request')
        body = None if payload is None else json.dumps(payload, separators=(',', ':')).encode()
        request = Request('http://127.0.0.1:25984' + path, data=body, method=method,
                          headers={'Authorization': self.authorization, 'Content-Type': 'application/json', 'Accept': 'application/json'})
        with self.opener.open(request, timeout=60) as response:
            return json.load(response)


def send_batch(client, name, docs):
    if not docs:
        return
    path = '/' + quote(name, safe='')
    result = client.request('POST', path + '/_bulk_docs', {'docs': docs, 'new_edits': False})
    if not isinstance(result, list) or any(row.get('error') for row in result):
        raise ValueError('Bulk revision import failed')
    expected = {}
    for doc in docs:
        expected.setdefault(doc['_id'], []).append(doc['_rev'])
    missing = client.request('POST', path + '/_revs_diff', expected)
    if missing != {}:
        raise ValueError('Restored revisions missing')


def restore(verified_path, account, copy, client, baseline_tag=None):
    with open(verified_path, 'rb') as stream:
        first = json.loads(next(stream))
    _, sources = receiver.exporter.scope({'account_id': account, 'databases': first['databases']})
    targets = [target_database(name, copy, baseline_tag) for name in sources]
    existing = set(client.request('GET', '/_all_dbs'))
    if any(name in existing for name in targets):
        raise ValueError('Destination collision; existing databases are never overwritten')
    for name in targets:
        path = '/' + quote(name, safe='')
        client.request('PUT', path + '?q=1&n=1', {})
        # Imported production roles/users are intentionally not made lab users.
        client.request('PUT', path + '/_security', {'admins': {'names': ['compat_admin'], 'roles': []}, 'members': {'names': ['compat_admin'], 'roles': []}})
    summaries = []
    active = None
    docs, designs = [], []
    leaves = 0
    with open(verified_path, 'rb') as stream:
        for line in stream:
            record = json.loads(line)
            if record['type'] == 'database_start':
                active = target_database(record['database'], copy, baseline_tag)
                leaves = 0
            elif record['type'] == 'document':
                doc = record['doc']
                leaves += 1
                if doc['_id'].startswith('_design/'):
                    designs.append(doc)
                else:
                    docs.append(doc)
                if len(docs) >= 100:
                    send_batch(client, active, docs)
                    docs = []
            elif record['type'] == 'database_end':
                send_batch(client, active, docs)
                # Install design validators after replaying already-existing data.
                # Each design can enqueue indexing work and requires JS
                # validation. Avoid fanning a full batch into query workers.
                for design in designs:
                    send_batch(client, active, [design])
                docs, designs = [], []
                metadata = client.request('GET', '/' + quote(active, safe=''))
                if record['unchanged_during_export']:
                    for key in ['doc_count', 'doc_del_count']:
                        if metadata.get(key) != record['metadata'].get(key):
                            raise ValueError('Stable-source document counts differ after restore')
                summaries.append({'database': active, 'leaf_revisions_checked': leaves,
                                  'doc_count': metadata['doc_count'], 'doc_del_count': metadata['doc_del_count']})
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--account', required=True)
    parser.add_argument('--copy', required=True, choices=['baseline', 'working'])
    parser.add_argument('--baseline-tag', help='Create a distinct baseline without modifying any prior interrupted restore')
    args = parser.parse_args()
    path = pathlib.Path(args.snapshot)
    if path.parent != SNAPSHOTS or path.is_symlink() or path.suffix != '.ndjson':
        raise ValueError('Only completed files in the private snapshot directory are accepted')
    info = path.stat()
    if info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError('Snapshot is not root-private')
    assert_namespace()
    # Full integrity/scope validation before the first destination write.
    # A private temporary copy prevents a second-pass source-file race.
    with tempfile.TemporaryDirectory(prefix='restore-verify-', dir=str(SNAPSHOTS)) as verification:
        with path.open('rb') as source:
            receipt = receiver.receive(source, verification, args.account)
        result = restore(receipt['path'], args.account, args.copy, Client(), args.baseline_tag)
    print(json.dumps({'copy': args.copy, 'snapshot_sha256': receipt['sha256_file'], 'restored': result}, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        status = getattr(error, 'code', None)
        print('Isolated restore failed (%s, HTTP %s); no existing DB was overwritten. Inspect lab state before retrying.' % (type(error).__name__, status if isinstance(status, int) else None), file=sys.stderr)
        sys.exit(1)
