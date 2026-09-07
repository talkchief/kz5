# Revision-safe soft deletion — P0-19

Source candidate, not deployed. This is a prerequisite for safely cleaning up
restricted-user live-dashboard acceptance fixtures, not a dashboard feature or
proof that restricted-user acceptance has passed. Historical/ClickHouse work
remains postponed.

## Defect and fix

Pinned Crossbar `2ac862830f9b626d2170d08daf1991b0ca33dba7` loads a document
during validation, then refreshes its revision in `crossbar_doc:delete/2` before
soft-saving the older body. A concurrent update between validation and deletion
can therefore be overwritten. Cowboy's earlier `If-Match` check does not close
this window.

The installer-owned patch
`scripts/patches/crossbar-soft-delete-revision.patch` preserves the revision of
the validated body. A nonempty binary revision is required; missing/invalid
revisions return a conflict before any datastore write. A later concurrent
revision causes the primary save to conflict instead of refreshing and retrying.
The installer applies this required, disjoint patch after the main Crossbar
integration patch. Crossbar remains a pinned nested dependency; commit this
root patch, not the nested checkout.

Hard deletion, successful-delete side-effect admission and existing error
mapping are unchanged. In particular, generic datastore failures currently use
`cb_context:add_system_error/3` and return500, whereas unreachable datastore
errors use its two-argument branch and return503. This fix does not normalize
those responses.

## Reproducible checks

Run serially from the repository through the resource guard:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- /usr/bin/unshare --net /usr/bin/bash /opt/kz5/scripts/test-crossbar-soft-delete-revision.sh
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- /usr/bin/unshare --net /usr/bin/bash /opt/kz5/scripts/test-crossbar-soft-delete-revision.sh --baseline
```

The baseline command is expected to fail. The runner archives the exact pinned
source into a private temporary directory, exercises the actual required-patch
helper forward/repeated/reverse and on mismatched source, and compiles ten
production modules with warnings as errors and without `TEST` or `export_all`.
It verifies loaded paths/options and before/after source hashes. Other runtime
dependencies remain prebuilt/unpinned.

`scripts/erlang-tests/crossbar_soft_delete_revision_tests.erl` exercises real
public `delete/1,2` and document/context transforms with controlled datastore
and asynchronous-hook seams. Nine groups cover saved-body preservation,
concurrent changes with/without a request header, default deletion, five invalid
revision cases, hard deletion and conflicts, datastore failures, existing
not-found semantics, and successful hook admission. Merely attaching a header
in these tests does not exercise Cowboy preconditions.

Current source passed all nine groups in root run `f2f995`/`175bfc`, with evidence
at `/tmp/kazoo-soft-delete-revision.5KQAsH`. An earlier test run exposed an
incorrect fixture expectation of503 for generic failure; source inspection
confirmed the existing500 behavior and only that expectation was corrected.
The earlier multi-case EUnit timeout was corrected to30 seconds per group to
accommodate serial mock compilation under the unchanged50% CPU guard.

Pinned baseline run `43ece5`/`5e488d` at
`/tmp/kazoo-soft-delete-revision.or0rRZ` failed seven groups and passed the two
unchanged hard-delete groups. The concurrent case returned success where a
conflict was required; the other six failures detected revision refresh. These
are seven failing groups, not seven independent production defects. Subsequent
review added the transitive numbers/web include directories to header hashes;
it did not alter production source or regression assertions.

Final runner with those header pins passed all nine groups again in
`c4a234`/`cd17ae`, evidence `/tmp/kazoo-soft-delete-revision.KnmeQz`.
Shell syntax and `git diff --check` pass. Final read-only service check `89e910`
found all eight platform services and the simulated-phone service running.
No service or deployment operation was performed in this work slice.

## Gates still open

- Actual HTTP precondition acceptance: stale/weak `If-Match` must fail412 before
  execute; a race after a matching precondition must fail409 at primary save.
- Real datastore concurrency and transport behavior; the controlled datastore
  seam is not CouchDB acceptance or secondary-replication proof.
- Revision-preserving cleanup of exact owned users, policies and queues. Queue
  activation and user cascade deletion have separate earlier side effects;
  no multi-document transaction guarantee is claimed. The fixture uses plain
  user deletion, not cascade deletion.
- Token invalidation before deleting mutable scope policies. Keep the live
  isolation harness unconditionally closed until these gates are proven.
- Controlled build/deployment and post-deployment validation of this backend
  module. No runtime module was replaced or service restarted for these tests.

See `queue_live_isolation.md` for the retained-fixture policy and why neither
legacy-token deletion nor user-secret rotation alone proves JWT revocation.
