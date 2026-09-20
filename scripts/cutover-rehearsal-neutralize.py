#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Make a copied production datastore unable to reach customers, before Kazoo 5 starts on it.

The first rehearsal (September 19, 2026) showed why: on its first start the node
re-sent 59 pending customer notification e-mails and held 968 enabled customer
webhooks. Nothing left the lab only because the mail relay it resolved was
localhost with no mail server there. This step removes the luck.

It writes to the rehearsal lab CouchDB only (the copy tool's network allow-list):
  * every webhook definition in the `webhooks` database is disabled and marked
    `pvt_rehearsal_disabled`;
  * every relay in `system_config/smtp_client` is pointed at 127.0.0.1 port 9 (discard);
  * every document in `pending_notifications` is marked deleted (the copy tool no longer
    copies that database; this covers copies made before).
It prints counts only. Run it after the copy and before the applications are installed.

  sudo python3 scripts/cutover-rehearsal-neutralize.py --target http://172.30.249.11:5984 \\
       --target-credentials /root/kz5-cutover-couchdb.key
"""
import argparse
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('cutover_copy', os.path.join(HERE, 'cutover-rehearsal-copy.py'))
copy_tool = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(copy_tool)
plan = copy_tool.plan
DISCARD = {'relay': '127.0.0.1', 'port': 9, 'username': '', 'password': '', 'auth': 'never'}


def all_docs(target, name):
    found = target.call('GET', copy_tool.quoted(name) + '/_all_docs?include_docs=true', missing_ok=True)
    return [] if found is None else [row['doc'] for row in found.get('rows', []) if not row['id'].startswith('_design/')]


def save(target, name, docs):
    rejected = 0
    for start in range(0, len(docs), 200):
        answer = target.call('POST', copy_tool.quoted(name) + '/_bulk_docs', {'docs': docs[start:start + 200]})
        rejected += sum(1 for row in answer if row.get('error'))
    return rejected


def neutralize(target):
    hooks = [doc for doc in all_docs(target, 'webhooks') if doc.get('pvt_type') == 'webhook' and doc.get('enabled', True)]
    for doc in hooks:
        doc['enabled'] = False
        doc['pvt_rehearsal_disabled'] = True
    pending = [{'_id': doc['_id'], '_rev': doc['_rev'], '_deleted': True} for doc in all_docs(target, 'pending_notifications')]
    relays = 0
    smtp = target.call('GET', '/system_config/smtp_client', missing_ok=True)
    if smtp is not None:
        for key, value in smtp.items():
            if not key.startswith(('_', 'pvt_')) and isinstance(value, dict):
                value.update(DISCARD)
                relays += 1
        smtp.setdefault('default', {}).update(DISCARD)
    rejected = save(target, 'webhooks', hooks) + save(target, 'pending_notifications', pending)
    if smtp is not None:
        rejected += save(target, 'system_config', [smtp])
    left = [doc for doc in all_docs(target, 'webhooks') if doc.get('pvt_type') == 'webhook' and doc.get('enabled', True)]
    return {'webhooks_disabled': len(hooks), 'webhooks_still_enabled': len(left),
            'pending_notifications_removed': len(pending),
            'pending_notifications_left': len(all_docs(target, 'pending_notifications')),
            'smtp_relays_pointed_at_discard': relays + (1 if smtp is not None else 0), 'rejected_writes': rejected}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--target', required=True)
    parser.add_argument('--target-credentials', required=True)
    args = parser.parse_args()
    try:
        result = neutralize(copy_tool.Target(args.target, *plan.credentials(args.target_credentials)))
        print(json.dumps(result, indent=2, sort_keys=True))
        clean = not (result['webhooks_still_enabled'] or result['pending_notifications_left'] or result['rejected_writes'])
        return 0 if clean else 3
    except Exception as error:   # never echo names, URLs or credentials
        sys.stderr.write('Rehearsal neutralize failed (%s)%s\n' % (
            type(error).__name__, ': ' + str(error) if isinstance(error, (copy_tool.CopyError, plan.PlanError)) else ''))
        return 1


if __name__ == '__main__':
    sys.exit(main())
