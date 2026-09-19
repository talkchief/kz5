#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Copy a production CouchDB into the fresh lab for the cutover rehearsal.

Production is only ever read, with the same single GET primitive as
cutover-rehearsal-plan.py: the database list, database info documents and
paged `_all_docs?include_docs=true&attachments=true`. No replication is started
on production, so no checkpoint or any other document is written there.

The target is written with PUT (create database) and POST `_bulk_docs`
(`new_edits: false`, so revisions are preserved). It must be inside the cutover
lab network and must not already hold any of the selected databases with
documents, unless --resume is given. Main's and the older lab's CouchDB are
outside that network and are refused.

Copied: global databases except the excluded ones, every account database, the
number databases, and the account month databases named by --months. This is a
logical copy of winning revisions; deleted documents and losing conflict
revisions are not copied. Account database names and credentials are never
printed; the receipt holds counts only.

  sudo python3 scripts/cutover-rehearsal-copy.py --source http://10.1.0.10:5984 \\
       --credentials /opt/kz5/key --target http://172.30.249.11:5984 \\
       --target-credentials /root/kz5-cutover-couchdb.key --months 202609,202608 \\
       --receipt-dir /root/kz5-cutover-copy-YYYYMMDD
"""
import argparse
import base64
import http.client
import importlib.util
import ipaddress
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('cutover_plan', os.path.join(HERE, 'cutover-rehearsal-plan.py'))
plan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(plan)

TARGET_NETWORKS = [ipaddress.ip_network('172.30.249.0/24')]   # the cutover rehearsal lab only
EXCLUDED_GLOBALS = {'token_auth'}                              # live session tokens: never needed, never copied
PAGE = 50
MAX_BATCH_BYTES = 8 * 1024 * 1024
ATTEMPTS = 6                  # a reset or timeout is retried; every request here is idempotent
BACKOFF_SECONDS = 2.0
COPIED_KINDS = ('global', 'account', 'numbers', 'account_month_selected')


class CopyError(Exception):
    pass


def retrying(side, call):
    """Run one idempotent request, again after a transport fault. GETs are safe to repeat;
    so are the writes, because documents carry their revision ids (new_edits: false)."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return call()
        except urllib.error.HTTPError as error:
            if error.code < 500 or attempt == ATTEMPTS:
                raise
        except (ConnectionError, TimeoutError, urllib.error.URLError, http.client.HTTPException,
                json.JSONDecodeError) as error:
            if attempt == ATTEMPTS:
                raise CopyError('%s kept failing after %d attempts (%s)' % (side, ATTEMPTS, type(error).__name__))
        time.sleep(BACKOFF_SECONDS * attempt)


class Target:
    """The only writer in this tool, and it can only address the fresh lab."""

    def __init__(self, url, username, password):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'http' or not parsed.hostname or parsed.path not in ('', '/') or parsed.query or parsed.username:
            raise CopyError('Target must be a bare http://address:port')
        try:
            address = ipaddress.ip_address(parsed.hostname)
        except ValueError:
            raise CopyError('Target must be given as an IP address')
        if not any(address in network for network in TARGET_NETWORKS):
            raise CopyError('Target is outside the cutover rehearsal lab network; refusing to write there')
        self.base = url.rstrip('/')
        token = base64.b64encode(('%s:%s' % (username, password)).encode()).decode()
        self.headers = {'Authorization': 'Basic ' + token, 'Accept': 'application/json',
                        'Content-Type': 'application/json'}
        self.opener = urllib.request.build_opener(plan.NoRedirect, urllib.request.ProxyHandler({}))

    def call(self, method, path, body=None, missing_ok=False):
        if method not in ('GET', 'PUT', 'POST'):
            raise CopyError('Method not allowed on the target')
        data = None if body is None else json.dumps(body).encode()

        def once():
            request = urllib.request.Request(self.base + path, data=data, headers=self.headers, method=method)
            try:
                with self.opener.open(request, timeout=300) as response:
                    return json.loads(response.read(plan.MAX_RESPONSE + 1))
            except urllib.error.HTTPError as error:
                if missing_ok and error.code == 404:
                    return None
                if method == 'PUT' and error.code == 412:   # created by an attempt whose answer was lost
                    return {'ok': True}
                raise
        return retrying('the target', once)


def read(reader, path):
    return retrying('the source', lambda: reader.get(path))


def quoted(name):
    return '/' + urllib.parse.quote(name, safe='')


def select(names, months):
    chosen = []
    for name in names:
        kind = plan.classify(name, months)
        if kind in COPIED_KINDS and not (kind == 'global' and name in EXCLUDED_GLOBALS):
            chosen.append((kind, name))
    return chosen


def pages(reader, name):
    """Yield lists of documents, read with GET only, keyed pagination."""
    start = None
    while True:
        query = {'include_docs': 'true', 'attachments': 'true', 'limit': str(PAGE + 1)}
        if start is not None:
            query['startkey'] = json.dumps(start)
        path = quoted(name) + '/_all_docs?' + urllib.parse.urlencode(query)
        rows = read(reader, path).get('rows', [])
        more = len(rows) > PAGE
        docs = [row['doc'] for row in rows[:PAGE] if row.get('doc')]
        if docs:
            yield docs
        if not more:
            return
        start = rows[PAGE]['id']


def batches(docs):
    batch, size = [], 0
    for doc in docs:
        length = len(json.dumps(doc))
        if batch and size + length > MAX_BATCH_BYTES:
            yield batch
            batch, size = [], 0
        batch.append(doc)
        size += length
    if batch:
        yield batch


def copy_database(reader, target, name):
    expected = int(read(reader, quoted(name)).get('doc_count') or 0)
    if target.call('GET', quoted(name), missing_ok=True) is None:
        target.call('PUT', quoted(name))
    copied, rejected = 0, {}
    for docs in pages(reader, name):
        for batch in batches(docs):
            errors = target.call('POST', quoted(name) + '/_bulk_docs', {'docs': batch, 'new_edits': False})
            # A rejected document is counted by CouchDB's error class (never its id or body)
            # and the copy goes on; the database is then reported as incomplete.
            for error in errors or []:
                kind = str(error.get('error') or 'unknown')[:40]
                rejected[kind] = rejected.get(kind, 0) + 1
            copied += len(batch) - len(errors or [])
    stored = int(target.call('GET', quoted(name)).get('doc_count') or 0)
    return {'source_documents': expected, 'read': copied, 'target_documents': stored, 'rejected': rejected,
            'complete': not rejected and stored >= copied and copied >= expected}


def run(reader, target, months, resume, receipt_dir):
    names = read(reader, '/_all_dbs')
    chosen = select(names, months)
    occupied = 0
    for _, name in chosen:
        info = target.call('GET', quoted(name), missing_ok=True)
        if info and int(info.get('doc_count') or 0) > 0:
            occupied += 1
    if occupied and not resume:
        raise CopyError('%d selected database(s) already hold documents on the target; it must be empty (or use --resume)' % occupied)
    totals, incomplete, started = {}, 0, time.time()
    for index, (kind, name) in enumerate(chosen, 1):
        if resume:
            info = target.call('GET', quoted(name), missing_ok=True)
            source_count = int(read(reader, quoted(name)).get('doc_count') or 0)
            if info and int(info.get('doc_count') or 0) >= source_count:
                result = {'source_documents': source_count, 'read': 0, 'rejected': {},
                          'target_documents': int(info.get('doc_count') or 0), 'complete': True}
            else:
                result = copy_database(reader, target, name)
        else:
            result = copy_database(reader, target, name)
        group = totals.setdefault(kind, {'databases': 0, 'source_documents': 0, 'target_documents': 0,
                                         'incomplete': 0, 'rejected': {}})
        for error_kind, count in result['rejected'].items():
            group['rejected'][error_kind] = group['rejected'].get(error_kind, 0) + count
        group['databases'] += 1
        group['source_documents'] += result['source_documents']
        group['target_documents'] += result['target_documents']
        if not result['complete']:
            group['incomplete'] += 1
            incomplete += 1
        if index % 25 == 0 or index == len(chosen):
            sys.stderr.write('copied %d of %d databases\n' % (index, len(chosen)))
    receipt = {'status': 'PASS' if incomplete == 0 else 'INCOMPLETE', 'selected_databases': len(chosen),
               'excluded_globals': sorted(EXCLUDED_GLOBALS), 'months': sorted(months), 'groups': totals,
               'incomplete_databases': incomplete, 'source_get_requests': reader.requests,
               'seconds': int(time.time() - started),
               'consistency': 'winning revisions only; no deleted documents; not a point-in-time snapshot'}
    os.makedirs(receipt_dir, mode=0o700, exist_ok=True)
    path = os.path.join(receipt_dir, 'receipt.json')
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as handle:
        json.dump(receipt, handle, indent=2, sort_keys=True)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for flag in ('--source', '--credentials', '--target', '--target-credentials', '--receipt-dir'):
        parser.add_argument(flag, required=True)
    parser.add_argument('--months', default='')
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    months = {month for month in args.months.split(',') if month}
    try:
        if any(not re.match(r'^[0-9]{4}(0[1-9]|1[0-2])\Z', month) for month in months):
            raise CopyError('Months are YYYYMM')
        target = Target(args.target, *plan.credentials(args.target_credentials))   # refuse a bad target before any source access
        reader = plan.Reader(args.source, *plan.credentials(args.credentials))
        if urllib.parse.urlsplit(args.source).hostname == urllib.parse.urlsplit(args.target).hostname:
            raise CopyError('Source and target are the same host')
        receipt = run(reader, target, months, args.resume, args.receipt_dir)
        print(json.dumps(receipt, indent=2, sort_keys=True))
        if receipt['status'] != 'PASS':
            return 3   # finished, but not everything arrived: see the receipt's counts
    except Exception as error:   # never echo URLs, names or credentials
        status = getattr(error, 'code', None)
        sys.stderr.write('Cutover copy failed (%s, HTTP %s)%s\n' % (
            type(error).__name__, status if isinstance(status, int) else None,
            ': ' + str(error) if isinstance(error, (CopyError, plan.PlanError)) else ''))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
