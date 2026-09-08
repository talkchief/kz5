#!/usr/bin/env python3
"""Bounded, GET-only seven-database comparison inside the compatibility lab.

Streams 100-document pages; saves only differences and content hashes privately.
No document bodies, IDs or credentials are printed. Not a historical-revision
or attachment-byte comparison: full snapshot restore has a separate verifier.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import sys
from urllib.parse import quote, urlencode

spec = importlib.util.spec_from_file_location('inspection', pathlib.Path(__file__).with_name('inspect-company-compat.py'))
inspection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspection)
restore = inspection.restore
DATABASES = [inspection.DATABASE] + [inspection.DATABASE + '-2026%02d' % month for month in range(4, 10)]


def baseline_name(database):
    if database not in DATABASES:
        raise ValueError('Outside fixed company scope')
    return ('baseline-' if database == inspection.DATABASE else 'baseline-verified-') + database


def encode(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def metadata(client, database):
    info = client.request('GET', '/' + quote(database, safe=''))
    return {key: info[key] for key in ('doc_count', 'doc_del_count', 'update_seq', 'purge_seq')}


def documents(client, database, expected_count):
    last = None
    count = 0
    for _ in range(10000):
        params = {'include_docs': 'true', 'limit': 100}
        if last is not None:
            params.update(startkey=json.dumps(last), skip=1)
        result = client.request('GET', '/' + quote(database, safe='') + '/_all_docs?' + urlencode(params))
        if result['total_rows'] != expected_count:
            raise ValueError('Document count changed while scanning')
        rows = result['rows']
        for row in rows:
            if ('doc' not in row or row['doc'].get('_id') != row['id']
                    or (last is not None and row['id'] <= last)):
                raise ValueError('Invalid or non-progressing document page')
            last = row['id']
            count += 1
            yield row['doc']
        if len(rows) < 100:
            if count != expected_count:
                raise ValueError('Incomplete document scan')
            return
    raise ValueError('Page bound exceeded')


def compare_streams(before, after, journal):
    a, b = iter(before), iter(after)
    old, new = next(a, None), next(b, None)
    old_hash, new_hash = hashlib.sha256(), hashlib.sha256()
    summary = {'baseline_count': 0, 'working_count': 0, 'added': 0, 'removed': 0,
               'content_changed': 0, 'revision_only': 0, 'changed_designs': 0,
               'changed_non_designs': 0}
    while old is not None or new is not None:
        use_old = old is not None and (new is None or old['_id'] <= new['_id'])
        use_new = new is not None and (old is None or new['_id'] <= old['_id'])
        if use_old:
            old_hash.update(encode(inspection.without_revision(old)))
            summary['baseline_count'] += 1
        if use_new:
            new_hash.update(encode(inspection.without_revision(new)))
            summary['working_count'] += 1
        if use_old and use_new:
            if old != new:
                if inspection.without_revision(old) == inspection.without_revision(new):
                    summary['revision_only'] += 1
                else:
                    summary['content_changed'] += 1
                    summary['changed_designs' if old['_id'].startswith('_design/') else 'changed_non_designs'] += 1
                journal({'event': 'difference', 'before': old, 'after': new})
        elif use_old:
            summary['removed'] += 1
            journal({'event': 'difference', 'before': old, 'after': None})
        else:
            summary['added'] += 1
            journal({'event': 'difference', 'before': None, 'after': new})
        if use_old:
            old = next(a, None)
        if use_new:
            new = next(b, None)
    summary.update(baseline_content_sha256=old_hash.hexdigest(), working_content_sha256=new_hash.hexdigest())
    return summary


def compare(phase):
    if not re.fullmatch('[a-z][a-z0-9_-]{0,40}', phase):
        raise ValueError('Invalid phase')
    client = restore.Client()
    path = restore.SNAPSHOTS / ('databases-' + phase + '.ndjson')
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    summaries = []
    digest = hashlib.sha256()
    with os.fdopen(fd, 'wb') as output:
        def journal(record):
            raw = encode(record)
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
            digest.update(raw)
        for database in DATABASES:
            baseline = baseline_name(database)
            old_info, new_info = metadata(client, baseline), metadata(client, database)
            journal({'event': 'database_start', 'database': database,
                     'baseline_metadata': old_info, 'working_metadata': new_info})
            summary = compare_streams(documents(client, baseline, old_info['doc_count']),
                                      documents(client, database, new_info['doc_count']), journal)
            if old_info != metadata(client, baseline) or new_info != metadata(client, database):
                raise ValueError('Database changed while scanning; evidence is not stable')
            summary['database'] = database
            summary['deleted_count_equal'] = old_info['doc_del_count'] == new_info['doc_del_count']
            journal({'event': 'database_end', 'summary': summary})
            summaries.append(summary)
        journal({'event': 'complete', 'databases': len(summaries)})
    print(json.dumps({'summary': summaries, 'private_evidence': str(path), 'sha256': digest.hexdigest()}, sort_keys=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', required=True)
    args = parser.parse_args()
    try:
        compare(args.phase)
    except Exception as error:
        print('Isolated database comparison failed (%s); partial private evidence preserved.' % type(error).__name__, file=sys.stderr)
        sys.exit(1)
