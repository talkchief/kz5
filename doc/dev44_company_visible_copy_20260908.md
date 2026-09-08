# Talkchief development-visible copy — September 8, 2026

## Where to find it

Open `https://kz5-dev.talkchief.io/`, log into `KazooMaster` as `admin`, and use
the top-bar account selector to select **Talkchief (Development copy)**.
Account ID remains `d8520ce3f29c5b6db692289e782c92af`; its development parent is
`adecbb84fbe9e06902a76731914d1943`. Its separate realm is
`talkchief-dev44.invalid`. This is on the main .44 development stack, not the
isolated lab's API endpoint. Main repository: `/opt/kz5`, kz5 `master`.

**Calling and copied user/device logins are disabled intentionally.** The copy
is initially for administrator UI/API inspection, not permission to use
production SIP credentials, forwarding numbers, mobile push tokens, or external
provisioning. Preparing selected development phones and enabling calling is a
separate step; do not bulk-enable imported production configuration blindly.

Non-deleted records include15 users,82 devices,4 queues and89 callflows, plus
15 number records,680 menus,62 temporal rules,26 temporal-rule sets,11 media
documents,8 groups,8 voicemail boxes,2 conferences,1 directory and1 blacklist.
Media documents do not imply transferred external recordings: the copied
CouchDB documents have no embedded attachments. Production external storage
was not contacted or copied.

## Copy scope and transformations

The prior company-only production export is already retained on .44 in the
isolated compatibility lab. No new production request was needed for this copy.
Preparation reads the lab's existing migrated working account DB only and
checks its update sequence/counts before and after the read. It does not alter
the original production snapshot, lab baseline, or working source documents.

The main copy contains1,757 documents, including retained soft-deleted records.
Excluded56 source documents are53 design documents (main Kazoo5 regenerates its
own views),2 stale parked-call runtime records, and1 old app-catalog configuration
(the copy inherits the new development master's apps instead). It does not copy
other companies, production globals, pending callback jobs, broker state or
registrations. The six monthly company databases remain in the compatibility
lab; they were not imported into main UI storage. Historical dashboard work is
still postponed.

Explicit development transformations:

- Account is named as a development copy, assigned the development master tree
  and reseller, and disabled. API/signature secrets are regenerated; old cloud
  and request-authentication metadata is removed.
- Users and devices are disabled. User password hashes/signature secrets and
  SIP passwords are regenerated; user notification email becomes an invalid
  development address. These are not credentials for production or a promise
  that existing handsets can register.
- Device push/provisioning/sync and custom SIP headers are removed. SIP realm
  becomes the development realm, IP/proxy authorization overrides are removed,
  and authentication method is password. Forward/failover enable flags are off.
- Queue membership/configuration is retained with manual agent login required.
  Voicemail email recipient lists are cleared and email notification flags off.
- Document IDs and internal configuration references are retained; CouchDB
  revisions are new main-instance revisions. Private copy-ownership markers are
  added. Original values remain in the protected lab source, not in Git.

## Source, commands and recovery

Helper: `scripts/prepare-dev-company-copy.py`; offline tests:
`scripts/test-prepare-dev-company-copy.py`. This is an explicit assessment helper,
**not** a normal installer option that imports customer data on every deployment.
It is fixed to this host/account/master, refuses foreign types/identities,
requires protected settings, and allows no deletion or arbitrary endpoint.

Preparation runs as root inside the existing `kazoo-compat-couchdb` network
namespace. Application runs as root in the main host namespace:

```sh
lab_pid=$(systemctl show kazoo-compat-couchdb -p MainPID --value)
test "$lab_pid" -gt 1
nsenter --target "$lab_pid" --net \
  python3 -B /opt/kz5/scripts/prepare-dev-company-copy.py --prepare
python3 -B /opt/kz5/scripts/prepare-dev-company-copy.py --apply
sup kapps_maintenance refresh_account d8520ce3f29c5b6db692289e782c92af
```

These commands have **already run**. Do not run `--prepare` again over the
existing plan. It refuses overwrite. `--apply` can resume an interrupted owned
copy by exact document readback, never by overwriting changed documents. After
normal maintenance or operator edits, conservative replay may refuse differences;
inspect receipts instead of deleting the destination or bypassing guards.
Ambiguous unmarked database creation is never silently adopted. An existing
unowned database or aggregate account is a hard collision.

Private files on .44, root-only, outside Git:

- `/var/lib/kazoo-compat/dev-visible/plan.json`: complete transformed records,
  original source hash/metadata and plan SHA256
  `ed2a5939fa8ef298970c92dc2beffe0acdc6dbede0e72730b4dde91157fe8332`.
- Same directory: `receipt.json` (pre-write intent), `completed.json`
  (verified document copy and account publication).
- Destination DB: `account/d8/52/0ce3f29c5b6db692289e782c92af` on main .44
  CouchDB, with the plan-bound `kz5_dev_copy_receipt` ownership document.
- `/root/kz5-acceptance/company-visible-refresh.log`: native account refresh.
- Original snapshots/baselines remain under `/var/lib/kazoo-compat/snapshots/`
  and the separate lab CouchDB; see the coexistence assessment documents.

No automatic deletion/rollback is implemented. Recover by inspecting the exact
intent/plan/owner/readbacks and preserving operator changes. Never replicate this
transformed copy back to production or use it as the original compatibility
baseline.

## Verification and boundaries

Eleven offline transformation, exact-scope, ownership, interrupted-write,
security-drift and no-overwrite tests passa72ee4. Actual preparation98211/866b95
passes; application20867/d08bff verifies all1,757 writes/readbacks and account
publication in13.1 seconds. Native scoped refresh45388/ca3b54 returnsok. Its six
`undefined` strings describe previously absent service counters initialized to
values, not `undef` exceptions; no error/failed/conflict/timeout markers found.

Post-import source verificationd54b2d proves the entire lab working account
document hash is unchanged:
`7c6258ac1afd10a6f4bb9e24c6f2f69f78417105c3dbdbcf5d9e7915c3f11af1`.
Main account and aggregate readbacks confirm disabled status, development realm,
parent tree and ownership. Actual Chromium81140/36603d selects the visible
account, verifies four queues, and loads SmartPBX/ACDC with no request/page errors
or active top progress indicator. The first probe navigated away while the new
ACDC request was still in flight; the accepted probe waits for that account's
live response before navigating to SmartPBX.

Reusable main-host acceptance is tracked as
`scripts/test-dev44-company-browser.cjs`. It uses installed Playwright/Chromium
(optional `KZ5_PLAYWRIGHT_ROOT` / `KZ5_BROWSER_EXECUTABLE` paths), protected local
installer credentials, and private routing with normal HTTPS certificate
verification. It verifies the actual account selector, collection counts, both
apps and inactive global progress. It neither originates calls nor registers
phones. Remote runners may provide credentials only on stdin using
`--credentials-stdin`, never argv or a committed file. Run under the normal
bounded validation wrapper. Its actual run90232/e44a28 passes, including exact
API counts15/82/4/89 and both apps; no credentials/customer documents are printed.

This visible inspection copy does not establish live calling readiness or
Kazoo4/5 shared writable database compatibility. The latter remains **NO-GO**
on current evidence; see `kazoo4_kazoo5_couchdb_findings.md`.
