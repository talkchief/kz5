# Kazoo 4/5 shared CouchDB assessment — findings in progress

Task: `COMPAT-01`. Date: September8,2026. This is **not a coexistence approval**.
Source node: production `10.1.0.10` (CouchDB3.3.2). Destination: protected,
isolated development storage on `10.1.0.44`; its installed CouchDB is3.5.2.
Only company `d8520ce3f29c5b6db692289e782c92af` is authorized for copying.
No production write, migration, restart or development connection to production
AMQP has been performed. Raw customer documents must remain outside Git.

## Confirmed code-level isolation risks

An isolated Kazoo Erlang/AMQP zone is **not by itself a database isolation
boundary** when both versions use the same writable CouchDB databases:

1. `core/kazoo_apps/src/kapps_maintenance.erl`, `refresh/1` calls
   `kz_datamgr:refresh_views/1` before invoking database/account refresh hooks.
   `core/kazoo_data/src/kz_datamgr.erl`, `do_refresh_views/1` selects registered
   view definitions and calls `db_view_update/2`. The resulting design documents
   are database-wide, not zone-specific. A version5 refresh can therefore alter
   the views queried by version4. Which definitions actually differ in this
   company's snapshot remains to be measured; this path alone is not proof of
   a breaking view change.
2. `kapps_maintenance:refresh_by_classification/2` invokes `ensure_aggregate/1`
   for an account. That calls faxbox/device/account aggregation and services
   reconciliation. `ensure_aggregate_account/1` saves the account document into
   shared `accounts`. Consequently, even an explicitly account-scoped refresh
   is not restricted to writes in only its account database.
3. `kapps_maintenance:migrate/1` invokes system/config migrations and enumerates
   databases. `migrate/2` refreshes selected databases, removes deprecated
   databases from that set, migrates account config and forwarding failover,
   then invokes registered migration hooks. The broad maintenance entry point
   must never be run against production during this assessment.
4. Registered account-refresh hooks include ACDC refresh, number-services view
   updates and service-plan migration (`acdc_app.erl`, `kazoo_numbers_app.erl`,
   `kazoo_services_app.erl`). A test limited to Crossbar GETs or replacing design
   JSON would omit real maintenance effects and cannot establish compatibility.

These findings establish required test scope, not whether current version4
consumers will break. Shared/global production databases have **not** been copied
or modified. Their migration compatibility and actual version4 runtime contract
remain unverified.

## Snapshot and runtime limits

Account export26720/e97565 is verified complete:1,847 leaf revisions, stable
start/end metadata, protected .44 file
`/var/lib/kazoo-compat/snapshots/company-b05rg4rz.ndjson`. SHA256 is recorded in
the assessment plan. Six monthly databases still require copying; no restore
or migration has been performed. All nine main .44 services remain active
(5674fa); imported customer data is not connected to them.

The protected export uses GET-only `_changes` and exact revision/document reads;
it does not invoke source replication/checkpoint writes. It captures current
leaf revisions including conflicts/tombstones, known ancestry, attachments and
design/security metadata. It excludes `_local` checkpoints and historical
revision bodies. A live database can change during the export; per-database
start/end metadata records this limitation. See the
[assessment plan and source tools](kazoo4_kazoo5_couchdb_coexistence_plan.md).

Production CouchDB3.3.2 versus development3.5.2 is a separate version variable.
Do not attribute every runtime/query difference to Kazoo5 without isolating
that engine-version effect. This logical export/restore also does not establish
physical `.couch` file downgrade compatibility.

## Still required

- Complete and verify the six remaining company monthly exports.
- Restore immutable baseline and disposable working copies in an isolated
  runtime/storage boundary; block calls, webhooks and other outbound effects.
- Compare captured view definitions with the registered Kazoo5 definitions.
- Exercise normal Kazoo5 maintenance plus representative API reads/edits and
  capture exact writes, including effects on isolated synthetic global DBs.
- Establish the actual production Kazoo4 source/runtime contract and replay
  compatible queries where possible. Clearly label unavailable runtime tests.
- Produce a final evidence-based GO/NO-GO with rollback/isolation requirements.

Until these checks are complete, **do not attach a Kazoo5 zone to production
writable CouchDB on the basis of this assessment**.
