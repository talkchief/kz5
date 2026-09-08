#!/usr/bin/env python3
"""Private evidence capture and sanitized baseline/working comparison in lab."""
import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import sys
from urllib.parse import quote

spec = importlib.util.spec_from_file_location('restore', pathlib.Path(__file__).with_name('restore-company-compat.py'))
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)
ACCOUNT = 'd8520ce3f29c5b6db692289e782c92af'
DATABASE = 'account/d8/52/0ce3f29c5b6db692289e782c92af'


def without_revision(doc):
    return {key: value for key, value in doc.items() if key != '_rev'}


def compare(baseline, working):
    old, new = set(baseline), set(working)
    content, revisions, design_details = [], [], []
    for key in sorted(old & new):
        a, b = baseline[key], working[key]
        if a == b:
            continue
        if without_revision(a) == without_revision(b):
            revisions.append(key)
        else:
            content.append(key)
            if key.startswith('_design/'):
                old_views, new_views = a.get('views', {}), b.get('views', {})
                design_details.append({'design': key,
                    'added_views': sorted(set(new_views) - set(old_views)),
                    'removed_views': sorted(set(old_views) - set(new_views)),
                    'changed_views': sorted(name for name in set(old_views) & set(new_views) if old_views[name] != new_views[name])})
    details = {'added_ids': sorted(new - old), 'removed_ids': sorted(old - new),
               'content_changed_ids': content, 'revision_only_ids': revisions,
               'design_changes': design_details}
    summary = {'added_documents': len(new - old), 'removed_documents': len(old - new),
               'content_changed_documents': len(content), 'revision_only_changes': len(revisions),
               'changed_design_documents': len(design_details),
               'changed_non_design_documents': sum(not key.startswith('_design/') for key in content)}
    return summary, details


def documents(client, database):
    result = client.request('GET', '/' + quote(database, safe='') + '/_all_docs?include_docs=true')
    rows = result['rows']
    if len(rows) != result['total_rows'] or any('doc' not in row for row in rows):
        raise ValueError('Incomplete document read')
    return {row['id']: row['doc'] for row in rows}


def inspect(phase):
    if not re.fullmatch('[a-z][a-z0-9_-]{0,40}', phase):
        raise ValueError('Invalid evidence phase')
    client = restore.Client()
    baseline = documents(client, 'baseline-' + DATABASE)
    working = documents(client, DATABASE)
    summary, details = compare(baseline, working)
    names = client.request('GET', '/_all_dbs')
    metadata = {}
    for name in names:
        info = client.request('GET', '/' + quote(name, safe=''))
        metadata[name] = {key: info.get(key) for key in ['doc_count', 'doc_del_count', 'update_seq', 'purge_seq']}
    version = client.request('GET', '/').get('version')
    evidence = {'phase': phase, 'couchdb_version': version, 'account_id': ACCOUNT,
                'summary': summary, 'details': details, 'databases': metadata,
                'baseline_documents': baseline, 'working_documents': working}
    path = restore.SNAPSHOTS / ('comparison-' + phase + '.json')
    raw = (json.dumps(evidence, sort_keys=True, separators=(',', ':')) + '\n').encode()
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as output:
        output.write(raw)
        output.flush()
        os.fsync(output.fileno())
    print(json.dumps({'phase': phase, 'couchdb_version': version, 'summary': summary,
                      'lab_database_count': len(names), 'private_evidence': str(path),
                      'evidence_sha256': hashlib.sha256(raw).hexdigest()}, sort_keys=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', required=True)
    args = parser.parse_args()
    try:
        inspect(args.phase)
    except Exception as error:
        print('Private comparison failed (%s); existing evidence preserved.' % type(error).__name__, file=sys.stderr)
        sys.exit(1)
