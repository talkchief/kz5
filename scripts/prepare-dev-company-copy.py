#!/usr/bin/env python3
"""Explicit company-only, inspection-first copy from the .44 compatibility lab.

--prepare runs INSIDE the lab namespace; --apply runs on .44's main namespace.
No production endpoint, arbitrary account, broad replication or deletion exists.
The original lab is GET-only. The new main account is disabled for calling and
copied login/SIP secrets and push/provisioning settings are replaced/removed.
Raw plans/receipts are root-only, outside Git. This is not an installer default.
"""
import argparse
import base64
import collections
import copy
import hashlib
import importlib.util
import json
import os
import pathlib
import secrets
import socket
import stat
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

ACCOUNT = 'd8520ce3f29c5b6db692289e782c92af'
MASTER = 'adecbb84fbe9e06902a76731914d1943'
DB = 'account/d8/52/0ce3f29c5b6db692289e782c92af'
MASTER_DB = 'account/ad/ec/bb84fbe9e06902a76731914d1943'
REALM = 'talkchief-dev44.invalid'
OWNER = 'kz5-dev44-company-inspection-copy-v1'
MARKER_ID = 'kz5_dev_copy_receipt'
BASE = pathlib.Path('/var/lib/kazoo-compat/dev-visible')
PLAN = BASE / 'plan.json'
RECEIPT = BASE / 'receipt.json'
COMPLETED = BASE / 'completed.json'
KINDS = {'account', 'blacklist', 'callflow', 'conference', 'device', 'directory',
         'group', 'media', 'menu', 'number', 'queue', 'temporal_rule',
         'temporal_rule_set', 'user', 'vmbox'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True) + '\n').encode()


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def safe_parent(path):
    for parent in [*reversed(path.parents), path]:
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022,
                'Unsafe root-owned directory')


def private_read(path):
    safe_parent(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as source:
        info = os.fstat(source.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1
                and info.st_mode & 0o077 == 0 and info.st_size <= 32 * 1024 * 1024,
                'Unsafe or oversized private input')
        return source.read()


def private_create(path, value):
    safe_parent(path.parent)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as target:
        target.write(encoded(value)); target.flush(); os.fsync(target.fileno())
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def strip_revision(doc):
    return {key: value for key, value in doc.items() if key not in ('_rev', '_revisions')}


def transform(original):
    doc = copy.deepcopy(original)
    ident, kind = doc.get('_id'), doc.get('pvt_type')
    require(isinstance(ident, str) and ident and not any(ord(c) < 32 for c in ident), 'Invalid document ID')
    if ident.startswith('_design/') or kind == 'parked_call' or (kind is None and isinstance(doc.get('apps'), dict)):
        return None
    require(kind in KINDS and ident != MARKER_ID, 'Unreviewed document type')
    require(doc.get('pvt_account_id', ACCOUNT) == ACCOUNT, 'Foreign account document')
    require(doc.get('pvt_account_db', quote(DB, safe='')) in (DB, quote(DB, safe='')), 'Foreign account database')
    require(not doc.get('_attachments'), 'Attachment transfer requires explicit verification')
    require(not doc.get('_deleted'), 'Unexpected live tombstone')
    doc = strip_revision(doc)
    for key in list(doc):
        if key.startswith('pvt_auth_') or key in ('pvt_request_id', 'pvt_is_authenticated', 'pvt_cpaas_token'):
            del doc[key]
    doc['pvt_kz5_dev_copy'] = OWNER
    if kind == 'account':
        require(ident == ACCOUNT, 'Foreign account identity')
        doc.update(name='Talkchief (Development copy)', realm=REALM, pvt_enabled=False,
                   pvt_tree=[MASTER], pvt_reseller_id=MASTER, reseller_id=MASTER,
                   is_reseller=False, pvt_reseller=False, descendants_count=0,
                   pvt_api_key=secrets.token_hex(32), pvt_signature_secret=secrets.token_hex(32))
        doc['pvt_alphanum_name'] = 'talkchiefdevelopmentcopy'
    if kind in ('user', 'device'):
        doc['enabled'] = False
        for key in ('push', 'provision', 'sync'):
            doc.pop(key, None)
        for key in ('call_forward', 'call_failover'):
            if isinstance(doc.get(key), dict):
                doc[key]['enabled'] = False
        doc['send_email_on_creation'] = False
        doc['vm_to_email_enabled'] = False
    if kind == 'user':
        password = secrets.token_hex(32)
        login = str(doc.get('username', ident)) + ':' + password
        doc['pvt_md5_auth'] = hashlib.md5(login.encode()).hexdigest()
        doc['pvt_sha1_auth'] = hashlib.sha1(login.encode()).hexdigest()
        doc['pvt_signature_secret'] = secrets.token_hex(32)
        doc.pop('password', None)
        if 'email' in doc:
            doc['email'] = 'dev-' + hashlib.sha256(ident.encode()).hexdigest()[:16] + '@example.invalid'
    if kind == 'device':
        sip = doc.get('sip', {})
        require(isinstance(sip, dict), 'Unsupported SIP settings')
        sip['password'] = secrets.token_hex(32)
        sip['realm'] = REALM
        for key in ('ip', 'proxy', 'outbound_proxy', 'invite_format'):
            sip.pop(key, None)
        sip['method'] = 'password'
        doc['sip'] = sip
        for key in ('custom_sip_headers', 'sip.custom_sip_headers.in', 'sip.custom_sip_headers.out'):
            doc.pop(key, None)
        sip.pop('custom_sip_headers', None)
    if kind == 'queue':
        doc['agents_login_manually'] = True
    if kind == 'vmbox':
        doc['notify_email_addresses'] = []
        doc['vm_to_email_enabled'] = False
    return doc


def validate_plan(plan):
    require(plan.get('version') == 1 and plan.get('owner') == OWNER and plan.get('account') == ACCOUNT
            and plan.get('master') == MASTER and plan.get('database') == DB and plan.get('realm') == REALM,
            'Plan identity mismatch')
    require(plan.get('sha256') == digest({k: v for k, v in plan.items() if k != 'sha256'}), 'Plan hash mismatch')
    docs = plan.get('documents')
    require(isinstance(docs, list) and 1 < len(docs) <= 10000, 'Invalid plan size')
    require(len({d['_id'] for d in docs}) == len(docs), 'Duplicate plan ID')
    accounts = [d for d in docs if d.get('pvt_type') == 'account']
    require(len(accounts) == 1, 'Plan must contain one account')
    account = accounts[0]
    require(account['_id'] == ACCOUNT and account['pvt_enabled'] is False and account['pvt_tree'] == [MASTER]
            and account['realm'] == REALM and account['pvt_reseller_id'] == MASTER, 'Unsafe copied account')
    for doc in docs:
        require(doc.get('pvt_type') in KINDS and doc.get('pvt_kz5_dev_copy') == OWNER
                and doc['_id'] != MARKER_ID and not doc['_id'].startswith('_')
                and not doc.get('_attachments') and '_rev' not in doc
                and doc.get('pvt_account_id', ACCOUNT) == ACCOUNT, 'Unsafe copied document')
        if doc['pvt_type'] in ('user', 'device'):
            require(doc['enabled'] is False and all(k not in doc for k in ('push', 'provision', 'sync')),
                    'Production integration retained')
            for key in ('call_forward', 'call_failover'):
                require(not isinstance(doc.get(key), dict) or doc[key].get('enabled') is False,
                        'Forwarding still enabled')
        if doc['pvt_type'] == 'device':
            require(doc['sip']['realm'] == REALM and len(doc['sip']['password']) == 64, 'Unsafe copied SIP identity')
    return plan


def prepare():
    spec = importlib.util.spec_from_file_location('inspection', pathlib.Path(__file__).with_name('inspect-company-compat.py'))
    inspection = importlib.util.module_from_spec(spec); spec.loader.exec_module(inspection)
    client = inspection.restore.Client()  # Enforces the existing lab namespace.
    before = client.request('GET', '/' + quote(DB, safe=''))
    originals = inspection.documents(client, DB)
    after = client.request('GET', '/' + quote(DB, safe=''))
    require(all(before.get(k) == after.get(k) for k in ('doc_count', 'doc_del_count', 'update_seq', 'purge_seq')),
            'Source changed during read')
    docs = [transformed for _, original in sorted(originals.items()) if (transformed := transform(original)) is not None]
    plan = dict(version=1, owner=OWNER, account=ACCOUNT, master=MASTER, database=DB, realm=REALM,
                source_sha256=digest(originals), source_metadata={k: before.get(k) for k in ('doc_count', 'doc_del_count', 'update_seq', 'purge_seq')},
                excluded_documents=len(originals) - len(docs), documents=docs)
    plan['sha256'] = digest(plan)
    validate_plan(plan)
    safe_parent(BASE.parent)
    BASE.mkdir(mode=0o700, exist_ok=True)
    private_create(PLAN, plan)
    summary = collections.Counter(d['pvt_type'] for d in docs if not d.get('pvt_deleted'))
    print(json.dumps(dict(status='prepared', plan_sha256=plan['sha256'], active_types=dict(summary),
                          documents=len(docs), excluded=plan['excluded_documents'], calling_enabled=False)))


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('Redirect forbidden')


class MainClient:
    def __init__(self):
        require(os.geteuid() == 0 and socket.gethostname() == 'dev-testing', 'Wrong host/user')
        require(os.readlink('/proc/self/ns/net') == os.readlink('/proc/1/ns/net'), 'Main namespace required')
        values = {}
        for line in private_read(pathlib.Path('/etc/kazoo/deployment.env')).decode().splitlines():
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                require(key not in values, 'Duplicate setting')
                values[key] = base64.b64decode(value, validate=True).decode()
        require(values['KAZOO_COUCHDB_HOST'] == '10.1.0.44' and values['KAZOO_COUCHDB_PORT'] == '5984',
                'Main datastore is not fixed development host')
        self.username = values['KAZOO_COUCHDB_USER']
        self.auth = 'Basic ' + base64.b64encode((self.username + ':' + values['KAZOO_COUCHDB_PASSWORD']).encode()).decode()
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    def request(self, method, database, document=None, payload=None):
        require(database in (DB, MASTER_DB, 'accounts'), 'Outside development copy scope')
        if database != DB:
            require((database == MASTER_DB and document == MASTER and method == 'GET')
                    or (database == 'accounts' and document == ACCOUNT and method in ('GET', 'PUT')),
                    'Outside exact account aggregation scope')
        else:
            require(method in ('GET', 'PUT') and (document not in ('_all_dbs', '_replicate', '_purge')),
                    'Forbidden development operation')
        url = 'http://10.1.0.44:5984/' + quote(database, safe='')
        if document is not None:
            url += '/' + quote(document, safe='')
        elif method == 'PUT':
            url += '?q=1&n=1'
        req = Request(url, method=method, data=None if payload is None else encoded(payload),
                      headers={'Authorization': self.auth, 'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with self.opener.open(req, timeout=45) as response:
                return response.status, json.load(response)
        except HTTPError as error:
            if error.code == 404:
                return 404, None
            raise ValueError('Development CouchDB operation failed') from None


def apply_plan(client, plan):
    validate_plan(plan)
    status, master = client.request('GET', MASTER_DB, MASTER)
    require(status == 200 and master.get('_id') == MASTER and master.get('pvt_tree', []) == [], 'Wrong development master')
    status, existing_db = client.request('GET', DB)
    if status == 404:
        require(client.request('GET', 'accounts', ACCOUNT)[0] == 404, 'Account aggregate collision')
        # Write intent before creation. A failed ambiguous creation is never
        # adopted without the exact marker and verified document readbacks.
        if not RECEIPT.exists():
            private_create(RECEIPT, dict(owner=OWNER, plan_sha256=plan['sha256'], state='intent'))
        receipt = json.loads(private_read(RECEIPT))
        require(receipt.get('owner') == OWNER and receipt.get('plan_sha256') == plan['sha256'], 'Receipt mismatch')
        require(client.request('PUT', DB, payload={})[0] in (201, 202), 'Database creation failed')
        security = {key: {'names': [client.username], 'roles': []} for key in ('admins', 'members')}
        require(client.request('PUT', DB, '_security', security)[0] == 200, 'Security setup failed')
        marker = dict(_id=MARKER_ID, owner=OWNER, plan_sha256=plan['sha256'])
        require(client.request('PUT', DB, MARKER_ID, marker)[0] in (201, 202), 'Owner marker failed')
    status, marker = client.request('GET', DB, MARKER_ID)
    require(status == 200 and marker.get('owner') == OWNER and marker.get('plan_sha256') == plan['sha256'],
            'Existing database is not owned by this exact plan')
    expected_security = {key: {'names': [client.username], 'roles': []} for key in ('admins', 'members')}
    require(client.request('GET', DB, '_security') == (200, expected_security), 'Copied database security changed')
    status, rows = client.request('GET', DB, '_all_docs')
    require(status == 200 and isinstance(rows.get('rows'), list), 'Destination inventory failed')
    allowed = {d['_id'] for d in plan['documents']} | {MARKER_ID}
    require(all(r['id'] in allowed or r['id'].startswith('_design/') for r in rows['rows']), 'Unexpected destination records')
    present = {r['id'] for r in rows['rows']}
    for index, doc in enumerate(plan['documents'], 1):
        if doc['_id'] in present:
            status, actual = client.request('GET', DB, doc['_id'])
            require(status == 200 and strip_revision(actual) == doc, 'Existing copied document changed; no overwrite')
        else:
            status, result = client.request('PUT', DB, doc['_id'], doc)
            require(status in (201, 202) and result.get('ok') is True, 'Copy write failed')
            status, actual = client.request('GET', DB, doc['_id'])
            require(status == 200 and strip_revision(actual) == doc, 'Copy readback mismatch')
        if index % 100 == 0:
            print(json.dumps(dict(status='copying', verified_documents=index)), flush=True)
    account = next(d for d in plan['documents'] if d['pvt_type'] == 'account')
    status, aggregate = client.request('GET', 'accounts', ACCOUNT)
    if status == 404:
        require(client.request('PUT', 'accounts', ACCOUNT, account)[0] in (201, 202), 'Aggregate publication failed')
    else:
        require(status == 200 and strip_revision(aggregate) == account, 'Existing aggregate differs; no overwrite')
    status, aggregate = client.request('GET', 'accounts', ACCOUNT)
    require(status == 200 and strip_revision(aggregate) == account, 'Aggregate readback mismatch')
    complete = dict(owner=OWNER, plan_sha256=plan['sha256'], documents=len(plan['documents']), state='copied_and_published')
    if COMPLETED.exists():
        require(json.loads(private_read(COMPLETED)) == complete, 'Completion receipt mismatch')
    else:
        private_create(COMPLETED, complete)
    print(json.dumps(dict(status='copied_and_published', documents=len(plan['documents']),
                          account_id=ACCOUNT, master_account_id=MASTER, calling_enabled=False)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--prepare', action='store_true')
    modes.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    require(os.geteuid() == 0, 'Root required')
    if args.prepare:
        prepare()
    else:
        plan = validate_plan(json.loads(private_read(PLAN)))
        apply_plan(MainClient(), plan)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Development copy stopped (%s); private state preserved, no automatic rollback.' % type(error).__name__, file=sys.stderr)
        sys.exit(1)
