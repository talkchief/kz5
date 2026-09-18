#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Size a production CouchDB for the cutover rehearsal. Metadata only, GET only.

Reads the server banner, the database list and each database's info document
(document count and sizes). It never reads a document, a view, _changes or
_security, never sends a request body, and has no code path that issues any
method other than GET; redirects and proxies are refused. Database names of
accounts are counted, not printed. Credentials come from a root-owned 0600
"key: value" file (couchdb_user / couchdb_pass) and are never printed.

  sudo python3 scripts/cutover-rehearsal-plan.py --source http://10.1.0.10:5984 \\
       --credentials /opt/kz5/key [--months 202609,202608]
"""
import argparse
import base64
import json
import os
import re
import stat
import sys
import urllib.parse
import urllib.request

MAX_RESPONSE = 32 * 1024 * 1024
ACCOUNT = re.compile(r'^account/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{28}\Z')
MODB = re.compile(r'^account/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{28}-([0-9]{6})\Z')


class PlanError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise PlanError('Redirect refused')


def credentials(path):
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
        raise PlanError('Credentials file must be a root-owned regular file with mode 0600')
    fields = {}
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            key, separator, value = line.partition(':')
            if separator:
                fields[key.strip()] = value.strip()
    if not fields.get('couchdb_user') or not fields.get('couchdb_pass'):
        raise PlanError('Credentials file lacks couchdb_user / couchdb_pass')
    return fields['couchdb_user'], fields['couchdb_pass']


class Reader:
    """The only network primitive in this tool: an authenticated GET."""

    def __init__(self, source, username, password):
        parsed = urllib.parse.urlsplit(source)
        if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.path not in ('', '/') \
                or parsed.query or parsed.username:
            raise PlanError('Source must be a bare http(s)://host:port')
        self.base = source.rstrip('/')
        token = base64.b64encode(('%s:%s' % (username, password)).encode()).decode()
        self.headers = {'Authorization': 'Basic ' + token, 'Accept': 'application/json'}
        self.opener = urllib.request.build_opener(NoRedirect, urllib.request.ProxyHandler({}))
        self.requests = 0

    def get(self, path):
        request = urllib.request.Request(self.base + path, headers=self.headers, method='GET')
        with self.opener.open(request, timeout=30) as response:
            body = response.read(MAX_RESPONSE + 1)
        if len(body) > MAX_RESPONSE:
            raise PlanError('Response limit exceeded')
        self.requests += 1
        return json.loads(body)


def classify(name, months):
    modb = MODB.match(name)
    if modb:
        return 'account_month_selected' if modb.group(1) in months else 'account_month_other'
    if ACCOUNT.match(name):
        return 'account'
    if name.startswith('numbers/'):
        return 'numbers'
    if name.startswith('_'):
        return 'couchdb_internal'
    return 'global'


def plan(reader, months):
    version = reader.get('/').get('version')
    names = reader.get('/_all_dbs')
    if not isinstance(names, list):
        raise PlanError('Unexpected database list')
    groups, global_names = {}, []
    for name in names:
        kind = classify(name, months)
        info = reader.get('/' + urllib.parse.quote(name, safe=''))
        sizes = info.get('sizes') or {}
        group = groups.setdefault(kind, {'databases': 0, 'documents': 0, 'deleted': 0, 'file_bytes': 0, 'active_bytes': 0})
        group['databases'] += 1
        group['documents'] += int(info.get('doc_count') or 0)
        group['deleted'] += int(info.get('doc_del_count') or 0)
        group['file_bytes'] += int(sizes.get('file') or info.get('disk_size') or 0)
        group['active_bytes'] += int(sizes.get('active') or info.get('data_size') or 0)
        if kind == 'global':
            global_names.append(name)
    return {'source_version': version, 'databases': len(names), 'selected_months': sorted(months),
            'groups': groups, 'global_databases': sorted(global_names), 'get_requests': reader.requests}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', required=True)
    parser.add_argument('--credentials', required=True)
    parser.add_argument('--months', default='')
    args = parser.parse_args()
    months = {month for month in args.months.split(',') if month}
    try:
        if any(not re.match(r'^[0-9]{4}(0[1-9]|1[0-2])\Z', month) for month in months):
            raise PlanError('Months are YYYYMM')
        username, password = credentials(args.credentials)
        print(json.dumps(plan(Reader(args.source, username, password), months), indent=2, sort_keys=True))
    except Exception as error:   # never echo URLs, names or credentials
        status = getattr(error, 'code', None)
        sys.stderr.write('Cutover sizing failed (%s, HTTP %s)%s\n' % (
            type(error).__name__, status if isinstance(status, int) else None,
            ': ' + str(error) if isinstance(error, PlanError) else ''))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
