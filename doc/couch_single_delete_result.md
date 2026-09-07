# Single-document CouchDB deletion result — P0-20

Deployed on September7; full resource acceptance remains open. Discovered during real-datastore checks for
restricted-user live-dashboard fixture cleanup. No historical reporting work.

## Failure

Native `kz_couch_doc:del_doc/4` calls Couchbeam's single-delete API, which actually
submits a one-document `_bulk_docs` request. CouchDB can return HTTP201 with a
row containing `error: conflict`. Previously the driver returned that array
unchanged; `kzs_doc:del_doc/4` interpreted the singleton as success and admitted
publication/secondary-write/cache work. Crossbar could therefore report success
despite the document remaining present.

Real local baseline probe `687399`/`f72f2d` reproduced **stale delete reported
success instead of conflict**. Its preceding soft-delete concurrent-update
check passed. Sanitized stages and the owned database name are retained at
`/tmp/kazoo-soft-delete-couch.mbEeGg`. The first discovery run `7324e1`/`5a06de`
at `/tmp/kazoo-soft-delete-couch.DF1BDX` stopped at the same hard-delete stage
before the diagnostic was made specific. Both runs left only their synthetic
test databases; no existing accounts, queues, calls, policies or services were
changed. The baseline probe used the pinned original Couch driver, with the
P0-19 Crossbar soft-delete source candidate.

## Installer-owned fix

`scripts/patches/kazoo-couch-single-delete-result.patch` modifies only
`core/kazoo_couch/src/kz_couch_doc.erl` through `ensure_kazoo_sources` in the
installer. Core pin is `5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72`. Commit the
root patch, not the nested core checkout.

Classification occurs after the existing transport retry wrapper. It requires
one structurally valid object with unique binary keys and the exact requested
document `id`. A conflict or not-found row becomes the corresponding error;
other row errors/malformed results fail closed as `failed`. Success requires a
nonempty literal `rev`, no error field and `ok:true` or absent `ok` for legacy
compatibility. Valid success returns the original singleton unchanged.
Transport errors are unchanged. There are no dynamic atoms, reason/body logs,
latest-revision lookups or conflict retries in this classification.

Batch `del_docs`, `save_docs`, generic data-manager code and non-Couch drivers
are unchanged. This does not certify batch error interpretation or make
multi-document side effects transactional.

## Reproduction

Offline classification and patch replay:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- /usr/bin/unshare --net /usr/bin/bash /opt/kz5/scripts/test-kazoo-couch-single-delete-result.sh
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- /usr/bin/unshare --net /usr/bin/bash /opt/kz5/scripts/test-kazoo-couch-single-delete-result.sh --baseline
```

The baseline is expected to fail. Nine candidate groups passed `2f23cf`/`586795`
at `/tmp/kazoo-couch-delete-result.88T8n1`. The tests rebuild three production
modules without TEST/export_all and call public `del_doc/4`; only connection,
retry and Couchbeam response seams are substituted. They cover known/unknown
errors, valid/legacy success, malformed/duplicate/identity fields, cardinality,
transport passthrough and unchanged batch results. The retry seam invokes once;
this is not a transport retry test. The actual installer helper is tested on
fresh pinned source, repeated application, reversal and mismatched source.

Root corrected two fixture issues before this pass: a missing closing list in
the identity cases, and the JSON setter dropping `null` error fields instead of
preserving the malformed protocol input. Neither was a production defect.

Offline baseline `106cb5`/`0d0802` failed six groups, with valid/legacy success,
transport errors and unchanged batch output still passing. Evidence:
`/tmp/kazoo-couch-delete-result.u4oYEl`. These are six regression groups for one
result-classification boundary, not six distinct deployed incidents.

Explicit development-only **real datastore mutation**:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 240 -- /usr/bin/bash /opt/kz5/scripts/test-crossbar-soft-delete-couch.sh --owned-local-couchdb-probe
```

Add `--baseline-driver` only when intentionally reproducing the old hard-delete
failure. This runner reads the protected local Couch configuration internally,
accepts only127.0.0.1:5984/CouchDB3, creates a random `kazoo_revision_probe_*`
database and records its name in a private receipt. It never prints credentials
or exception values. It invokes real Crossbar deletion, `kz_datamgr`, `kzs_doc`,
the Couch driver and Couchbeam; routing/cache/publication are controlled in a
separate nondistributed BEAM. Candidate checks also require that conflict does
not admit success publication/cache insertion.

On success it hard-deletes only its two exact revision-bearing synthetic
documents and confirms their absence. On failure it retains them. The database
and ownership marker are intentionally retained even after success; do not
bulk-delete matching names or infer ownership from a prefix alone. No runtime
modules are deployed by this runner. It is not full Crossbar HTTP authorization,
replication, broker/cache propagation, fault-injection or load acceptance.

## Remaining release gates

Candidate real-datastore probe `b3c7e1`/`2a0330` passed at
`/tmp/kazoo-soft-delete-couch.Sm4MLU`. Fifteen production modules compiled with
warnings as errors and without TEST/export_all. Couchbeam/Hackney/Eini prebuilt
beams/app descriptors are now hashed and their loaded paths verified; remaining
dependencies are prebuilt/unpinned. Native soft/hard stale-delete409, concurrent
body preservation and no success-publication/cache insertion all pass. The two
owned test documents were hard-deleted with their exact saved revisions and
both absences read back. All eight platform services/test phones remained
running (`ba33c6`); no service operations occurred.

Retained databases (no customer data):

- Discovery: `kazoo_revision_probe_63fdbd314943869a945a83aa24a6a2b4`;
  receipt `/tmp/kazoo-soft-delete-couch.DF1BDX`, owner marker and two fixture docs.
- Explicit old-driver reproduction:
  `kazoo_revision_probe_bb55685f6a77bfe8835a4dc36384a806`;
  receipt `/tmp/kazoo-soft-delete-couch.mbEeGg`, owner marker and two fixture docs.
- Passing candidate: `kazoo_revision_probe_b6026d9a3cd076c5f83f6da5613a91b5`;
  receipt `/tmp/kazoo-soft-delete-couch.Sm4MLU`, owner marker and two tombstones.

Hard-deleted test bodies may remain in CouchDB revisions until compaction;
they were synthetic test documents, not user data. The failed-baseline
fixtures are deliberately retained for comparison, not automatically retried.

Deployment `489b41`/`b291e2` is complete with exact runtime module verification
and unchanged31-agent state (`/tmp/kazoo-revision-deployment.19HpQo`). Subsequent
administrator scope-policy HTTP acceptance passes stale412, weak412 and
current-delete200+absence (`7c9f07`/`47ce1f`); it is a soft-delete route check,
not a second live hard-delete or cluster proof. See
`scope_management_dashboard_acceptance.md` for receipts and retained fixtures.
Restricted-user dashboard fixtures remain
hard closed until cleanup and token-lifecycle requirements are met. Preserve
the expiry-plus401 policy; do not use unverified secret rotation as a shortcut.
