#!/usr/bin/env python3
"""Receive a private company snapshot; no database connection or restore.

Only a fully validated, digest-matching stream is published as *.ndjson.
Failed/interrupted transfers remain visibly *.partial, mode 0600.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import stat
import sys
import tempfile

spec = importlib.util.spec_from_file_location('company_export', pathlib.Path(__file__).with_name('export-company-couchdb.py'))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
MAX_LINE = 96 * 1024 * 1024


def receive(source, directory, account):
    directory = os.path.abspath(directory)
    info = os.stat(directory)
    if (os.path.realpath(directory) != directory or not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077):
        raise ValueError('Destination must be an owned private directory, without symlinks')
    digest = hashlib.sha256()
    count = 0
    names = None
    opened = []
    closed = []
    active = None
    leaves = 0
    total_leaves = 0
    seen = set()
    complete = None
    fd, partial = tempfile.mkstemp(prefix='company-', suffix='.partial', dir=directory)
    with os.fdopen(fd, 'wb') as target:
        while True:
            line = source.readline(MAX_LINE + 1)
            if not line:
                break
            if complete is not None or len(line) > MAX_LINE or not line.endswith(b'\n'):
                raise ValueError('Invalid stream boundary')
            record = json.loads(line)
            kind = record.get('type')
            if count == 0:
                if kind != 'snapshot_start' or record.get('format') != 1 or record.get('account_id') != account:
                    raise ValueError('Wrong snapshot identity')
                _, names = exporter.scope({'account_id': account, 'databases': record.get('databases')})
            elif kind == 'database_start':
                name = record.get('database')
                if active or name not in names or name in opened or record['metadata'].get('db_name') != name:
                    raise ValueError('Wrong database scope or order')
                active = name
                opened.append(name)
                leaves = 0
                seen = set()
            elif kind == 'document':
                if active is None or record.get('database') != active:
                    raise ValueError('Document outside active database')
                doc = record['doc']
                exporter.validate_doc(doc, doc['_id'], doc['_rev'])
                identity = (doc['_id'], doc['_rev'])
                if identity in seen or doc['_id'].startswith('_local/'):
                    raise ValueError('Duplicate or local document')
                seen.add(identity)
                leaves += 1
                total_leaves += 1
            elif kind == 'database_end':
                if (active is None or record.get('database') != active or
                        record['metadata'].get('db_name') != active or record.get('leaf_revisions') != leaves):
                    raise ValueError('Database count or identity mismatch')
                closed.append(active)
                active = None
            elif kind == 'snapshot_end':
                if (active or sorted(closed) != names or record.get('databases') != len(names)
                        or record.get('records_before_end') != count or record.get('sha256') != digest.hexdigest()):
                    raise ValueError('Incomplete snapshot or digest mismatch')
                complete = record
            else:
                raise ValueError('Unexpected stream record')
            target.write(line)
            digest.update(line)
            count += 1
        if complete is None:
            raise ValueError('No completion marker')
        target.flush()
        os.fsync(target.fileno())
    final = partial[:-len('.partial')] + '.ndjson'
    # Exclusive publish: never replace any existing backup.
    os.link(partial, final)
    os.unlink(partial)
    directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    return {'path': final, 'databases': len(names), 'leaf_revisions': total_leaves,
            'sha256_file': digest.hexdigest(), 'all_databases_unchanged': complete['all_databases_unchanged']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True)
    parser.add_argument('--account', required=True)
    args = parser.parse_args()
    try:
        result = receive(sys.stdin.buffer, args.directory, args.account)
        print(json.dumps(result, sort_keys=True))
    except Exception:
        sys.stderr.write('Snapshot receive failed; any partial file is private and incomplete.\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
