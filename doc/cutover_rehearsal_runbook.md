# Cutover rehearsal runbook (readiness plan, gate E)

Status on September 20, 2026: **first rehearsal run; conditional; see "First rehearsal" below**. The owner authorized a read-only
copy from production. The assistant's session could run the metadata-only sizing but
is refused permission to move customer data, so the copy is started by the owner (see
"State on September 19"). Nothing here writes to production, and nothing here may be
pointed at main's CouchDB.

Standing facts this builds on (`doc/kazoo4_kazoo5_couchdb_findings.md`):
production is Kazoo 4.3.124 on CouchDB 3.3.2; a Kazoo 5 refresh rewrites design
documents database-wide, so Kazoo 5 must run on **its own copy**, never on the
shared writable production databases; the earlier copy authorization covered one
company only (`d8520ce3…`) and did not include the global databases, which is why
authentication, services and routing compatibility are still unproven.

## 1. Size production first (owner runs; metadata only)

```sh
sudo python3 scripts/cutover-rehearsal-plan.py --source http://10.1.0.10:5984 \
     --credentials /opt/kz5/key --months 202609,202608
```

One authenticated GET of `/`, of `/_all_dbs`, and of each database's info document.
It reads no document, view, `_changes` or `_security`, sends no body, refuses
redirects, prints counts and bytes per group (global, account, selected months,
other months, numbers) and the names of global databases only — never an account
database name or a credential. `python3 scripts/test-cutover-rehearsal-plan.py`
proves those properties against a recording stub (5 groups).

The output decides the scope: dev44 has about 210 GiB free; voicemail and CDR months
usually dominate, so copy the globals, every account database and only the months
needed for the rehearsal.

## 2. Decisions the owner must state before any copy

1. **Scope**: all companies, or the already authorized company plus the globals.
   A full copy puts every customer's data (including voicemail) on the development
   host; say so explicitly, and say how long it may be retained.
2. **Window**: replication reads hard from production's disks. Pick a quiet period.
3. **Target**: the empty CouchDB guest of the dedicated rehearsal lab (`kz5-cutover-*`,
   172.30.249.0/24). Not main's CouchDB, not a lab CouchDB that already holds Kazoo 5
   bootstrap documents (the globals would merge and conflict).

## State on September 19, 2026

- Sizing was run with the owner's authorization. The figures are production-derived
  and stay in the root-only file `/root/kz5-cutover-sizing-20260919.json` on dev44;
  they are deliberately not recorded in this repository. Production is small enough
  that scope and disk space are not constraints.
- The copy tool exists: `scripts/cutover-rehearsal-copy.py`, proven offline by
  `python3 scripts/test-cutover-rehearsal-copy.py` (6 groups). Lab guests blackhole
  production's network on purpose, so the copy is driven from the host: production is
  read only through the sizing tool's GET-only reader (database list, info documents,
  paged `_all_docs`), and the only writable network is the rehearsal lab
  `172.30.249.0/24`. Main, the other labs, production itself, host names, https and
  paths are refused before any request; a non-empty target is refused; `token_auth`
  (live session tokens) is never copied; the receipt holds counts only.
- The rehearsal lab exists: variant `--cutover-rehearsal` of
  `scripts/prepare-distributed-install-lab.sh` (guests `kz5-cutover-*`, state in
  `/var/lib/kazoo5-cutover-rehearsal`). `kz5-cutover-couchdb` is installed from
  scratch and empty (`couchdb-install-1` PASS); its credentials are in
  `/root/kz5-cutover-couchdb.key` (0600).
- **The copy has not been run.** The assistant's session is refused permission to move
  customer data, so the owner starts it:

```sh
sudo systemd-run --unit kz5-cutover-copy -p RemainAfterExit=yes -p WorkingDirectory=/opt/kz5 \
  /usr/bin/python3 scripts/cutover-rehearsal-copy.py --source http://10.1.0.10:5984 \
  --credentials /opt/kz5/key --target http://172.30.249.11:5984 \
  --target-credentials /root/kz5-cutover-couchdb.key --months 202609,202608 \
  --receipt-dir /root/kz5-cutover-copy-20260919
```

  Progress: `journalctl -u kz5-cutover-copy -f`. Result: `receipt.json` in the receipt
  directory, `status: PASS`. An interrupted copy is continued by adding `--resume`.
- Parked to stay inside the host's inotify limit: `kz5-fresh-couchdb`,
  `kz5-stage-push-bridge`, `kz5-stage-kazoo-apps-peer`.
- Still to build for step 4: the rehearsal variant's applications install must skip the
  lab's empty-datastore admission and the master-account bootstrap (the variant's
  settings already carry `productionCopy`).

## First rehearsal (September 19-20, 2026)

Order that worked, and the order to use next time:

1. `--cutover-rehearsal --prepare`, `--create couchdb`, `--begin-install couchdb` (the variant
   now gives this guest 6 GiB; raise it to 10 GiB with `podman update --memory 10g
   --memory-swap 10g kz5-cutover-couchdb` before the migration).
2. `scripts/cutover-rehearsal-copy.py` (add `--resume` after an interruption).
3. **`scripts/cutover-rehearsal-neutralize.py` before anything starts on the copy.** The first
   run skipped this step because it did not exist yet: the node re-sent pending customer
   notifications on its first start. Nothing left the lab, by luck.
4. `scripts/cutover-rehearsal-snapshot.py snapshot … --out before.json`.
5. `--create rabbitmq`, install; `--create kazoo-apps`, `--sync-source`, `--begin-install`.
6. Snapshot again and `compare`; timed `sup -t 14400 kapps_maintenance migrate`; API checks.
7. Stop and disable `kazoo-apps` in the rehearsal guest when done.

Findings are in `PROJECT_TASKS.md` (two entries of September 19/20). Deletion of the copy:
`kz5-cutover-copy-delete.timer`, or `bash scripts/cutover-rehearsal-delete-copy.sh` by hand.

## What the migration does to Kazoo 4 data (measured September 20, 2026)

One-way. After `kapps_maintenance migrate` every database is touched: design documents are
rewritten or added everywhere; `account` documents gain fields; `user` and `device` documents
lose `call_forward.failover` (moved to a top-level `call_failover` where it was set), which
Kazoo 4 still reads; `system_config` categories change. No customer document is deleted.
Kazoo 5 works on the migrated data; Kazoo 4 must never be pointed at it. Rollback is the
untouched Kazoo 4 stack on its own untouched CouchDB.

## 3. Why the copy is host-driven

The first design was CouchDB's own pull replication started on the target. It was
dropped: lab guests blackhole `10.1.0.0/16` by design, and opening that for one guest
would weaken the isolation every other lab test relies on. The host-driven copy keeps
the guests isolated and gives a stronger property on the source side: production is
reached only through one GET primitive, which the offline proof enforces. Its limits:
winning revisions only, no deleted documents, not a point-in-time snapshot.

## 4. Rehearsal proper

1. Install `rabbitmq` and then `kazoo-apps` from scratch in the rehearsal lab against
   the copied CouchDB (this is the upgrade-install matrix: the installer's
   migrations run on real production-shaped data for the first time).
2. Record what the first start changes: design documents, `system_config`,
   `accounts`, `services` (the September 8 assessment measured 38 changed and 8 new
   design documents for one company).
3. Native checks against the copy: master and sub-account authentication, device
   registration lookups, callflow and queue listings for every account, ACDC queue
   and agent start-up for every account that has queues (this is where the
   100-agent datastore starvation found on September 18 would have shown),
   callback ticket views, number lookups.
4. Timing: how long the first start and `kapps_maintenance:migrate` take on the full
   data set. That number is the real cutover window.
5. Rollback drill: the Kazoo 4 stack is untouched by construction; the drill is
   proving that and measuring how long pointing SIP and API traffic back takes.

## 5. Exit criteria

Written GO/NO-GO with: migration duration, every changed global document reviewed,
zero failed native checks or each failure triaged, a single-writer cutover order,
and the retained-data deletion date for the copy.
