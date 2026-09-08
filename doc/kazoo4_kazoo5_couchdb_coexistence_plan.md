# Kazoo 4/5 CouchDB coexistence — active validation

Requested September8,2026. Task `COMPAT-01` in `PROJECT_TASKS.md`.
Installer/reboot finalization passed; assessment is now active. Read-only
production metadata inventory passed September8 (475ad5). Production node
`cdb11.talkchief.io` runs CouchDB3.3.2. Seven exact account-owned databases exist:
`account/d8/52/0ce3f29c5b6db692289e782c92af` and its monthly databases
`-202604`, `-202605`, `-202606`, `-202607`, `-202608`, `-202609`.
Account-only export26720/e97565 now passes:1,847 leaf revisions, matching1,805
live documents +42 tombstones in the inventory; database update/purge/security
metadata unchanged during the export. Snapshot is protected on .44 at
`/var/lib/kazoo-compat/snapshots/company-b05rg4rz.ndjson`, SHA256
`4d2267c62c7a6f280892d4b98c3abdce45bad75596a13909d14ec95b52d004c4`.
Monthly-only export55565/c9e79e completed:27,762 leaf revisions across all six
explicitly allowed monthly databases, with unchanged per-database metadata.
Protected .44 snapshot: `/var/lib/kazoo-compat/snapshots/company-6ubui72f.ndjson`,
SHA256 `d265534c587758706a9b4a125147cc3c858c146175ecd5d72a7766c23e0ee9b4`.
Together the two files contain29,609 leaf revisions. They are retained root-only,
read-only mode0400. No unrelated/global production data was copied.

All seven databases now have verified isolated baseline and working restores.
Account restore receipts79427/a9ee43,19538/fab27e; monthly baseline+working
5405/120ead (terminal success1m8.444s). Exact source document/deletion counts
and every imported revision are checked. Monthly baseline prefix is
`baseline-verified-account/`; account baseline uses `baseline-account/`.
Older interrupted monthly baseline prefixes `baseline-account/` and
`baseline-retry1-account/` are preserved but must not be used as accepted
monthly baselines. Working names are canonical `account/` for native Kazoo.

Native account refresh and real view queries already demonstrate contract
changes, including two removed views. See the evidence-backed interim
**NO-GO for shared production writable databases** in
[coexistence findings](kazoo4_kazoo5_couchdb_findings.md). More migration/API tests
and the actual production Kazoo4 version/code contract remain open. Native
authenticated API reads/representative edits and selected company migration
components have now been measured: legacy failover rejects user edits before
migration; edits pass afterward, but24 stored user/device representations change.
Monthly design migrations also remove two service-view endpoints. See the
findings continuation for exact evidence and remaining limits.

## Reusable snapshot tools

- `scripts/export-company-couchdb.py`: Python2.7/3 source-node helper, GET-only
  against fixed loopback5984, redirects/proxies disabled. Credentials arrive
  through stdin, never argv. An explicit allowlist is validated against the
  exact account's canonical account/MODB names before any HTTP request. It does
  not use replication and cannot write source checkpoints. Requests are
  sequential and throttled to at most25/second, response/page sizes bounded.
- `scripts/receive-company-couchdb.py`: destination-only private file receiver;
  validates account/database identity, counts, record ordering and stream SHA256.
  Exclusive mode0600 files in an owned mode0700 directory outside Git. Interrupted
  or invalid copies remain `.partial`; only complete verified copies become
  `.ndjson`. This helper does not connect to CouchDB or restore into running apps.
- Offline tests: `python3 -B scripts/test-export-company-couchdb.py` (13) and
  `python3 -B scripts/test-receive-company-couchdb.py` (6), passedfcdbd3.
  Include foreign/global DB rejection, GET-only transport, conflict/deletion/
  design/attachment preservation, moving source, truncation, tamper, private
  modes and non-overwriting repeats. Source Python2.7.5 live account export
  passes26720/e97565; completed monthly export/isolated restores are recorded above.
- `prepare-company-compat-lab.py`, `prepare-company-compat-apps.py`: explicit
  .44-only helpers create a separate unprivileged user, storage, credentials and
  loopback-only network namespace. They refuse existing installations and do
  not enable units at boot or change main stack units. The actual lab discovered
  hostname-selector, netlink and index-worker resource issues; fixes are in these
  helpers/tests. Do not rerun creation flags against the already-created lab.
- `restore-company-compat.py`: validate the entire stream/digest before writes;
  allow only the lab service's separate network namespace and loopback25984,
  never arbitrary endpoints. Refuse existing DBs. Preserve revisions using
  `new_edits=false`, verify `_revs_diff`, compare stable-source counts, and replay
  design docs serially. Optional baseline tags retain failed copies without
  overwriting them. No deletion or source write path exists.
- `company-compat-rpc.escript`: fixed lab node, fixed authorized account. Status,
  native account refresh, API registration/readback and explicit selected-company
  migration components only. After lab apps are started, use `prepare-api` to
  register the five optional API modules just as the normal installer does.
  `migrate-company` preflights the seven fixed working DBs and invokes exported
  native refresh/account-config/failover/migration-hook components. `migrate/2`
  is private; never use broad `/0` or `/1` as a substitute. No database deletion
  step is exposed. Reads its generated lab cookie from a protected file, never
  argv. Namespace checks precede distribution. Capture native maintenance output
  privately; returned `ok` does not prove every internally handled operation.
  The helper now checks hook error/EXIT returns, exposes a read-only
  `migration-hooks` arity inventory and has six offline `self-test` cases.
  A missing media `/1` hook was found and fixed as a required installer patch;
  regression/production compilation and native lab rerun evidence are in the
  findings. `verify-media-fix` checks the actual lab override and required apps.
- `inspect-company-compat.py` and `query-company-compat-views.py`: private
  before/after evidence and real query comparison with sanitized public summaries.
  Never print raw captured account/API rows. All helpers live in `scripts/`;
  `test-company-compat-*`, `test-restore-company-compat.py`,
  `test-inspect-company-compat.py`, `test-query-company-compat-views.py` cover
  their boundaries alongside exporter/receiver tests.
- `exercise-company-compat-api.py --phase LABEL [--cosmetic-edits]`: native
  account API auth, complete collection reads for the bounded company sample,
  one existing label per resource with verified original-value restoration.
  Excludes soft-deleted fixtures, rejects out-of-scope routes, disables HTTP
  proxies/redirects, journals intent before mutation. Authentication tokens stay
  in memory. A rejected edit is not a test pass; inspect the result summary.
- `compare-company-compat-databases.py --phase LABEL`:100-document streaming
  pages, stable metadata checks, accepted baseline prefixes only, content hashes
  and full private differences for all seven DBs. Snapshot restore separately
  verifies revision leaves/attachments; this comparison is current live docs.
  `query-company-compat-views.py --monthly` tests two service views in each MODB.
  Both these tools and the API tool refuse existing evidence filenames. Use
  unique phase labels; never overwrite evidence to rerun an interrupted test.
  New tests: `test-exercise-company-compat-api.py` and
  `test-compare-company-compat-databases.py`; full Python suite is60 cases.
  `test-kazoo-media-scoped-migration.sh` additionally proves four regressions
  against a clean pinned source, real installer apply/reapply/rejection and
  production compilation. Use the resource guard for all local test scripts.

The first source attempts safely refused CouchDB's canonical-design-route
redirect. Only three1,021-byte metadata `.partial` files were left privately on
.44, no document records. Source now constructs `_design/name` directly without
weakening redirect refusal; the exact route regression passes. These partials
are not completed backups and must not be restored.

Initial code findings and remaining scope:
[coexistence findings](kazoo4_kazoo5_couchdb_findings.md).

The stream preserves current leaf revisions, known revision ancestry and
attachment bytes, plus database/security metadata before/after. It does not
copy `_local` checkpoint documents or historical revision bodies and is not a
physical CouchDB backup. `_changes` with `style=all_docs` identifies leaf
revisions; exact-revision GETs request `revs=true&attachments=true`.
See [CouchDB changes API](https://docs.couchdb.org/en/stable/api/database/changes.html)
and [document API](https://docs.couchdb.org/en/stable/api/document/common.html).
Per-database update/purge sequences and security are compared before/after;
changing databases are explicitly labeled non-stable, not falsely certified
as an atomic multi-database snapshot. Compacted/missing revisions fail the
export rather than silently producing an incomplete successful backup.

## Question and authorized scope

Can an isolated Kazoo5 zone coexist with current production Kazoo4 infrastructure
without changing shared CouchDB state in ways that break Kazoo4?

- Production CouchDB node: `10.1.0.10`, part of the existing cluster.
- Company/account: `d8520ce3f29c5b6db692289e782c92af`.
- SSH: existing protected operator credentials under `/root/key.key`.
- CouchDB: administrator credentials supplied separately by the operator.
  Do not copy their values into repository files, process arguments, reports or
  tool output. Load them through protected input when execution begins.
- Destination: development only, with an isolated restore and no production
  AMQP/CouchDB routing, on the designated main development server `10.1.0.44`.
  Choose the instance/namespace after checking for collisions.

**Explicit operator limit:** copy only this company's data as a use case.
No full-cluster/database-server backup, no other company's records, and no full
shared/global database copy. If relevant records live in a shared database,
export only records whose ownership can be proven to match this exact account;
otherwise stop that portion and report the missing scope. Metadata needed to
interpret the snapshot must not turn into a bulk copy of unrelated data.

## Ordered procedure

1. Confirm endpoint identity and read-only access. Inventory exact account-owned
   database names from CouchDB metadata; do not infer an unsafe broad prefix.
   Include the account database and account-scoped monthly/statistics databases
   actually present. Record versions and relevant design-document revisions.
2. Make a one-way read-only snapshot into protected development storage. Include
   design docs, attachment metadata/bytes needed for testing, security metadata
   and snapshot consistency/update-sequence information. Production may change
   during export; document consistency limits instead of claiming an atomic
   cluster snapshot. No source writes, view refresh, migrations, restarts or
   bidirectional replication. Do not publish customer data or backups in Git.
3. Restore without overwriting existing development databases/accounts. Retain
   an immutable baseline and use a separate working copy. Ensure Kazoo5 workers
   cannot contact production dependencies or send calls/notifications from the
   copied account. Disable external side effects in this isolated test setup.
4. Establish the actual Kazoo4 contract from current versions/source and captured
   design docs, not merely a guessed version label. Record representative
   document fields, IDs/types, revisions, views, indexes and query results.
5. Run normal Kazoo5 account refresh/migrations and representative read/edit
   operations on the working copy. Capture exact writes and resulting document,
   view, index and schema changes. Test normal maintenance paths as well as APIs;
   a read-only login alone cannot reveal migration effects.
6. Compare the mutated copy with the baseline and Kazoo4 expectations. If an
   isolated Kazoo4 runtime is available, replay its reads/queries and selected
   writes against the changed copy without production connectivity. Explicitly
   report any unavailable runtime/version or untested behavior.
7. Separately audit code paths affecting shared global databases, system config,
   design docs and cross-zone messaging/ownership. The company-only copy does
   not authorize copying/changing all production globals and does not establish
   their compatibility. Request additional scope only if evidence requires it.
8. Produce an evidence-backed report: exact incompatible changes, compatible
   cases, unknowns, required database/broker/zone isolation, safe rollout and
   rollback boundaries, and GO/NO-GO for the proposed coexistence arrangement.

## Acceptance boundary

Do not mark coexistence safe solely because services start, account APIs return
200, or unit tests pass. Shared CouchDB means that an isolated Erlang/AMQP zone
may still change documents used by Kazoo4. Any unverified global migration,
design-view replacement, document semantic change or cross-zone ownership
interaction remains a release risk. No production Kazoo5-zone deployment or
production mutation is authorized by this assessment request.

The final report should contain sanitized structural diffs and reproducible
commands without credentials/customer records. Keep raw snapshots and detailed
customer-data traces protected outside Git, with their locations and retention
instructions documented without exposing their contents.
