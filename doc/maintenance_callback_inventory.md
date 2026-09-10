# Durable callback inventory for coordinated maintenance

September 10, 2026. This closes the missing durable-reservation observation
component of INST-06. It does **not** close producer fencing, broker drain,
runtime/media drain, or the coordinated upgrade/rollback executor.

## Operator command

The normal Kazoo applications installer now installs the self-contained helper
and verifies that its bytes match the selected repository source:

```sh
sudo node /usr/local/libexec/kazoo5-maintenance-callbacks --check
```

Source: `scripts/kazoo-maintenance-callbacks.cjs`. It reads only root-owned
0600 `/etc/kazoo/deployment.env`, using this installer's configured private
CouchDB HTTP endpoint and administrator identity. No URL/credential override,
redirect, retry, write, cancellation, redial, custom-view installation or
database creation occurs. Do not expose that private database transport to an
untrusted network. Output contains aggregate counts and hashes, not customer
numbers, account IDs, ticket IDs, credentials or private leases.

Exit0 means the bounded durable inventory was observed and contains only
terminal reservations with no outstanding lease/reconciliation marker. Exit2
means the complete observation contains blocked callbacks. Exit1 means the
observation itself was refused or incomplete; never interpret it as an empty
inventory. The JSON explicitly keeps `producer_fence_proven` and
`complete_cluster_drain_proven` false, even on exit0.

## Scope and consistency

The current `acdc_callback_store:create_doc` writes reservations to account
databases. The collector enumerates the configured CouchDB database set with
server-administrator access and scans every current account database, not only
queues with running workers or a supplied account list. Monthly databases are
not callback stores in this implementation. Duplicate account-database aliases
refuse the scan. Future storage changes require this scope to be reviewed.

All non-deleted documents are read through the built-in `_all_docs` endpoint,
100 per page. This avoids depending on a missing or stale custom callback view
and detects malformed callback IDs or conflicting non-callback winning
revisions. Every page must have the exact expected count/offset, strictly
increasing IDs, matching document/revision identities and no conflicts.
The limits are10,000 database names,1,000,000 documents,16MiB per response,
15seconds per request and120seconds overall; exhaustion refuses, not truncates.

All account update/purge sequences and document counts are captured before
scanning and rechecked after the entire inventory. All-docs tokens must remain
identical across pages. CouchDB is queried through `_changes` from each actual
all-docs token and must report zero changes and zero pending entries. Database
names are rechecked at the end. Tokens remain opaque: do not decode them,
compare numeric prefixes, or require database-info and view encodings to be
byte-identical. The first native implementation refused for precisely that
incorrect cross-endpoint comparison; three read-only observations confirmed
stable but different encodings, and the corrected native scan passed.

Relevant primary references: [CouchDB built-in all-docs API](https://docs.couchdb.org/en/stable/api/database/bulk-api.html),
[database information and opaque sequences](https://docs.couchdb.org/en/stable/api/database/common.html),
and [changes feed](https://docs.couchdb.org/en/stable/api/database/changes.html).

`registering`, `queued`, `dialing`, `confirming`, `connecting`, `retry_wait` and
`cancelling` all block. Even `completed`, `cancelled`, `failed` or `expired`
blocks if a lease or reconciliation marker remains. Unknown states, malformed
ownership and conflicts refuse the observation. Deleted historical documents
are not live reservations; this is not an audit or recovery of deleted data.
Terminal callback metadata alone does not prove its old media legs are gone:
the separate native media/controller drain must still pass.

Changes can arrive after observation unless producers are fenced. No scan can
substitute for that barrier, and this helper does not pretend otherwise. No
historical ambiguous callback is cancelled, deleted or forced complete.

## Verification

Run the focused source/installer tests:

```sh
node --test scripts/test-kazoo-maintenance-callbacks.cjs scripts/test-kazoo-maintenance-fence-wiring.cjs
```

They cover all callback states, stale leases/reconciliation, hidden conflicts,
ownership, empty databases, callbacks beyond200 documents, partial pages,
sequence/purge/database-set changes, insufficient privileges, opaque-token
freshness, GET-only transport, refused HTTP errors and installed-helper drift.

The source helper's native read-only development44 scan passed at
2026-09-10T04:44:49Z: five account databases,2219 documents,23 callbacks
(14 completed,2 failed,7 cancelled), zero blocked. No database was changed.
The scan covers this configured dev database endpoint, not the original server's
separately quarantined historical callback or shared production CouchDB.
Normal helper deployment/installed-byte verification is the next step.
