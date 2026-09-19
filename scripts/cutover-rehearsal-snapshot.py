#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Snapshot and compare the rehearsal lab's datastore around Kazoo 5's first start.

Reads the rehearsal lab CouchDB only (same network allow-list as the copy tool).
A snapshot holds, per database, the document count and every document's revision;
it is written 0600 and never printed. `compare` prints counts per database group and,
for `system_config` only, the ids of changed documents (they are configuration
category names, not customer data).

  snapshot --target http://172.30.249.11:5984 --target-credentials FILE --out FILE
  compare BEFORE AFTER
"""
import argparse
import importlib.util
import json
import os
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('cutover_copy', os.path.join(HERE, 'cutover-rehearsal-copy.py'))
copy_tool = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(copy_tool)
plan = copy_tool.plan


def snapshot(target):
    result = {}
    for name in target.call('GET', '/_all_dbs'):
        if name.startswith('_'):
            continue
        revisions, start = {}, None
        while True:
            query = {'limit': '2001'}
            if start is not None:
                query['startkey'] = json.dumps(start)
            rows = target.call('GET', copy_tool.quoted(name) + '/_all_docs?' + urllib.parse.urlencode(query))['rows']
            for row in rows[:2000]:
                revisions[row['id']] = row['value']['rev']
            if len(rows) <= 2000:
                break
            start = rows[2000]['id']
        result[name] = revisions
    return result


def compare(before, after):
    groups, config_changes = {}, {'changed': [], 'added': [], 'removed': []}
    for name in sorted(set(before) | set(after)):
        kind = plan.classify(name, set()) if name in before else 'created_by_kazoo5'
        kind = {'account_month_other': 'account_month'}.get(kind, kind)
        old, new = before.get(name, {}), after.get(name, {})
        group = groups.setdefault(kind, {'databases': 0, 'databases_touched': 0, 'design_changed': 0, 'design_added': 0,
                                         'design_removed': 0, 'documents_changed': 0, 'documents_added': 0,
                                         'documents_removed': 0})
        group['databases'] += 1
        touched = False
        for doc_id in set(old) | set(new):
            design = 'design_' if doc_id.startswith('_design/') else 'documents_'
            if doc_id not in new:
                state = 'removed'
            elif doc_id not in old:
                state = 'added'
            elif old[doc_id] != new[doc_id]:
                state = 'changed'
            else:
                continue
            touched = True
            group[design + state] += 1
            if name == 'system_config' and design == 'documents_':
                config_changes[state].append(doc_id)
        group['databases_touched'] += 1 if touched else 0
    created = sorted(name for name in after if name not in before and not name.startswith('account/'))
    return {'groups': groups, 'system_config': {k: sorted(v) for k, v in config_changes.items()},
            'global_databases_created': created}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='mode', required=True)
    take = sub.add_parser('snapshot')
    for flag in ('--target', '--target-credentials', '--out'):
        take.add_argument(flag, required=True)
    diff = sub.add_parser('compare')
    diff.add_argument('before')
    diff.add_argument('after')
    args = parser.parse_args()
    try:
        if args.mode == 'snapshot':
            target = copy_tool.Target(args.target, *plan.credentials(args.target_credentials))
            data = snapshot(target)
            with open(os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as handle:
                json.dump(data, handle)
            print(json.dumps({'databases': len(data), 'documents': sum(len(v) for v in data.values())}))
        else:
            with open(args.before) as one, open(args.after) as two:
                print(json.dumps(compare(json.load(one), json.load(two)), indent=2, sort_keys=True))
    except Exception as error:   # never echo names or credentials
        sys.stderr.write('Rehearsal snapshot failed (%s)%s\n' % (
            type(error).__name__, ': ' + str(error) if isinstance(error, (copy_tool.CopyError, plan.PlanError)) else ''))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
