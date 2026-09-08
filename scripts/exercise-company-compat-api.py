#!/usr/bin/env python3
"""Fixed-company Crossbar read/cosmetic-edit assessment, isolated lab only.

No caller-supplied endpoint or credentials. Tokens stay in memory. Full document
evidence is private, never suitable for Git. Snapshot/baseline DBs are read-only.
An interrupted run leaves its journal; inspect it before any further edits.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, ProxyHandler, build_opener

import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location('inspection', pathlib.Path(__file__).with_name('inspect-company-compat.py'))
inspection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspection)
restore = inspection.restore
ACCOUNT = inspection.ACCOUNT
DATABASE = inspection.DATABASE
PREFIX = '/accounts/' + ACCOUNT
RESOURCES = [('accounts', 'account', 'name'), ('users', 'user', 'first_name'),
             ('devices', 'device', 'name'), ('queues', 'queue', 'name'),
             ('callflows', 'callflow', 'name')]


def allowed_path(method, path):
    if path.endswith('?paginate=false') and method == 'GET':
        path = path[:-len('?paginate=false')]
        return path in [PREFIX + '/' + resource for resource, _, _ in RESOURCES[1:]]
    if path == '/api_auth':
        return method == 'PUT'
    if path == PREFIX:
        return method in ('GET', 'PATCH')
    if not path.startswith(PREFIX + '/'):
        return False
    suffix = path[len(PREFIX) + 1:].split('/')
    if suffix[0] not in ('users', 'devices', 'queues', 'callflows'):
        return False
    if len(suffix) == 1:
        return method == 'GET'
    return (len(suffix) == 2 and re.fullmatch('[a-f0-9]{32}', suffix[1]) is not None
            and method in ('GET', 'PATCH'))


class Api:
    def __init__(self):
        restore.assert_namespace()
        self.opener = build_opener(ProxyHandler({}), restore.receiver.exporter.NoRedirect())
        self.token = None

    def request(self, method, path, data=None):
        if not allowed_path(method, path):
            raise ValueError('Out-of-scope API request')
        headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}
        if self.token:
            headers['X-Auth-Token'] = self.token
        body = None if data is None else json.dumps({'data': data}).encode()
        req = Request('http://127.0.0.1:8000/v2' + path, data=body, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=45) as response:
                result = json.load(response)
                if path == '/api_auth' and result.get('status') == 'success':
                    self.token = result.get('auth_token')
                # Never return the envelope/token, even to private evidence.
                return {'http': response.status, 'status': result.get('status'),
                        'data': None if path == '/api_auth' else result.get('data')}
        except HTTPError as error:
            # Validation details stay in the private journal, never stdout.
            # Authentication errors may echo keys, so discard those bodies.
            data = None
            if path != '/api_auth':
                try:
                    data = json.load(error).get('data')
                except (ValueError, AttributeError):
                    pass
            return {'http': error.code, 'status': 'error', 'data': data}


def successful(result):
    return 200 <= result['http'] < 300 and result['status'] == 'success'


def choose(documents, resource, doc_type, field):
    if resource == 'accounts':
        candidates = [documents[ACCOUNT]] if ACCOUNT in documents else []
    else:
        candidates = [doc for _, doc in sorted(documents.items()) if doc.get('pvt_type') == doc_type]
    return next((doc for doc in candidates if re.fullmatch('[a-f0-9]{32}', doc.get('_id', ''))
                 and isinstance(doc.get(field), str) and doc[field]
                 and len(doc[field]) < 80 and not doc.get('_deleted') and not doc.get('pvt_deleted')), None)


def edit_and_restore(api, path, field, original, journal):
    marker = original + ' [compat-lab]'
    journal({'event': 'edit_intent', 'path': path, 'field': field, 'original': original})
    result = None
    try:
        result = api.request('PATCH', path, {field: marker})
        journal({'event': 'edit_response', 'path': path, 'result': result})
        readback = api.request('GET', path)
        journal({'event': 'edit_readback', 'path': path, 'result': readback})
        changed = successful(readback) and isinstance(readback['data'], dict) and readback['data'].get(field) == marker
    finally:
        # Even a timeout may have committed the edit. Always attempt rollback
        # through the same native API, never a direct CouchDB overwrite.
        reverted = api.request('PATCH', path, {field: original})
        journal({'event': 'restore_response', 'path': path, 'result': reverted})
        readback = api.request('GET', path)
        journal({'event': 'restore_readback', 'path': path, 'result': readback})
        restored = (successful(readback)
                    and isinstance(readback['data'], dict) and readback['data'].get(field) == original)
        if not restored:
            raise RuntimeError('Original cosmetic field not verified; inspect private journal')
    return {'edit_http': result['http'], 'edit_verified': successful(result) and changed,
            'restore_http': reverted['http'], 'restored': restored}


def exercise(phase, edits=False):
    if not re.fullmatch('[a-z][a-z0-9_-]{0,40}', phase):
        raise ValueError('Invalid phase')
    client = restore.Client()
    api = Api()
    path = restore.SNAPSHOTS / ('api-' + phase + '.ndjson')
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    digest = hashlib.sha256()
    with os.fdopen(fd, 'wb') as output:
        def journal(record):
            raw = (json.dumps(record, sort_keys=True, separators=(',', ':')) + '\n').encode()
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
            digest.update(raw)

        baseline = inspection.documents(client, 'baseline-' + DATABASE)
        before = inspection.documents(client, DATABASE)
        journal({'event': 'before', 'working_documents': before, 'baseline_documents': baseline})
        api_key = before.get(ACCOUNT, {}).get('pvt_api_key')
        if not isinstance(api_key, str) or not api_key:
            raise ValueError('Copied account has no API key')
        auth = api.request('PUT', '/api_auth', {'api_key': api_key})
        journal({'event': 'authentication', 'http': auth['http'], 'status': auth['status']})
        if not successful(auth) or not api.token:
            raise RuntimeError('Isolated native API authentication failed')
        summaries = []
        try:
            for resource, doc_type, field in RESOURCES:
                collection = PREFIX if resource == 'accounts' else PREFIX + '/' + resource
                listing = api.request('GET', collection + ('?paginate=false' if resource != 'accounts' else ''))
                journal({'event': 'collection_read', 'resource': resource, 'result': listing})
                summary = {'resource': resource, 'list_http': listing['http']}
                if isinstance(listing['data'], list):
                    summary['returned_rows'] = len(listing['data'])
                doc = choose(before, resource, doc_type, field)
                if doc is None:
                    summary['detail'] = 'no_safe_fixture'
                else:
                    detail = collection if resource == 'accounts' else collection + '/' + quote(doc['_id'], safe='')
                    read = api.request('GET', detail)
                    journal({'event': 'detail_read', 'resource': resource, 'result': read})
                    summary['detail_http'] = read['http']
                    if edits and successful(read):
                        summary.update(edit_and_restore(api, detail, field, doc[field], journal))
                summaries.append(summary)
        finally:
            after = inspection.documents(client, DATABASE)
            baseline_after = inspection.documents(client, 'baseline-' + DATABASE)
            delta, details = inspection.compare(before, after)
            journal({'event': 'after', 'working_documents': after, 'delta': delta, 'details': details,
                     'baseline_unchanged': baseline == baseline_after})
            if baseline != baseline_after:
                raise RuntimeError('Baseline unexpectedly changed')
        journal({'event': 'complete', 'summary': summaries, 'delta': delta})
    print(json.dumps({'summary': summaries, 'delta': delta, 'baseline_unchanged': True,
                      'private_evidence': str(path), 'sha256': digest.hexdigest()}, sort_keys=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', required=True)
    parser.add_argument('--cosmetic-edits', action='store_true', help='Edit and restore one existing label per resource')
    args = parser.parse_args()
    try:
        exercise(args.phase, args.cosmetic_edits)
    except Exception as error:
        print('Isolated API assessment failed (%s); inspect private journal before retry.' % type(error).__name__, file=sys.stderr)
        sys.exit(1)
