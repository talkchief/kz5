#!/usr/bin/env python3
"""Compare real view responses on baseline and refreshed lab working data."""
import hashlib
import importlib.util
import json
import os
import pathlib
import sys
from urllib.error import HTTPError
from urllib.parse import quote

spec = importlib.util.spec_from_file_location('inspect_lab', pathlib.Path(__file__).with_name('inspect-company-compat.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)

VIEWS = [('trunkstore', 'lookup_user_flags'), ('vmboxes', 'legacy_msg_by_timestamp'),
         ('users', 'crossbar_listing'), ('devices', 'crossbar_listing'),
         ('callflows', 'crossbar_listing'), ('queues', 'crossbar_listing')]


def field_changes(baseline, working):
    # These crossbar_listing views emit one row per document. Never output IDs,
    # keys or values; expose only changed response-field names for developers.
    old = {row['id']: row['value'] for row in baseline}
    new = {row['id']: row['value'] for row in working}
    if len(old) != len(baseline) or len(new) != len(working):
        return {'field_comparison': 'not_applicable_multiple_rows_per_document'}
    added, removed, changed = set(), set(), set()
    for key in set(old) & set(new):
        a, b = old[key], new[key]
        if not isinstance(a, dict) or not isinstance(b, dict):
            continue
        added.update(set(b) - set(a))
        removed.update(set(a) - set(b))
        changed.update(field for field in set(a) & set(b) if a[field] != b[field])
    return {'added_value_fields': sorted(added), 'removed_value_fields': sorted(removed),
            'changed_common_value_fields': sorted(changed), 'same_row_ids': set(old) == set(new)}


def summarize(details):
    summaries = []
    for item in details:
        baseline, working = item['baseline'], item['working']
        result = {'view': item['view'], 'baseline_status': baseline['http_status'],
                  'working_status': working['http_status'],
                  'baseline_rows': baseline.get('row_count'), 'working_rows': working.get('row_count'),
                  'same_rows': baseline.get('rows_sha256') == working.get('rows_sha256') if baseline['http_status'] == working['http_status'] == 200 else False}
        if item['view'].endswith('/crossbar_listing') and baseline['http_status'] == working['http_status'] == 200:
            result.update(field_changes(baseline['rows'], working['rows']))
        summaries.append(result)
    return summaries


def query(client, database, design, view):
    path = '/' + quote(database, safe='') + '/_design/' + design + '/_view/' + view + '?reduce=false'
    try:
        result = client.request('GET', path)
        rows = result['rows']
        raw = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()
        return {'http_status': 200, 'row_count': len(rows), 'rows_sha256': hashlib.sha256(raw).hexdigest(), 'rows': rows}
    except HTTPError as error:
        return {'http_status': error.code}


def main():
    path = lab.restore.SNAPSHOTS / 'view-query-comparison.json'
    if sys.argv[1:] == ['--summarize-existing']:
        print(json.dumps({'views': summarize(json.loads(path.read_text())), 'private_evidence': str(path)}, sort_keys=True))
        return
    if sys.argv[1:]:
        raise ValueError('Unknown arguments')
    client = lab.restore.Client()
    details = []
    for design, view in VIEWS:
        baseline = query(client, 'baseline-' + lab.DATABASE, design, view)
        working = query(client, lab.DATABASE, design, view)
        item = {'view': design + '/' + view, 'baseline': baseline, 'working': working}
        details.append(item)
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(details, output, sort_keys=True, separators=(',', ':'))
        output.flush()
        os.fsync(output.fileno())
    print(json.dumps({'views': summarize(details), 'private_evidence': str(path)}, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Isolated view query comparison failed (%s); private evidence preserved.' % type(error).__name__, file=sys.stderr)
        sys.exit(1)
