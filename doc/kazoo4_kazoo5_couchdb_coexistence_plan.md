# Kazoo 4/5 CouchDB coexistence — queued validation

Requested September8,2026. Task `COMPAT-01` in `PROJECT_TASKS.md`.
Run **after the current installer/reboot finalization**, not concurrently with
the in-progress fresh ALL installer. No production connection or copy has yet
been performed for this task.

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
  AMQP/CouchDB routing. Choose the instance/namespace after checking for collisions.

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
