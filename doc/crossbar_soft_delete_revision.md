# Revision-safe soft deletion — P0-19

Deployed on September7; administrator scope-policy HTTP revision acceptance
passes (stale412, weak412, current-delete200 and absence). Restricted-user,
queue/user side-effect and cluster acceptance remain open. This is a prerequisite for safely cleaning up
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

## HTTP and primary-datastore follow-up

`scripts/test-crossbar-soft-delete-revision.sh --http` now runs ten real
TCP/Cowboy REST cases in a private network namespace with loopback enabled by
the runner. All passed `51f026`/`2b97f1` at
`/tmp/kazoo-soft-delete-revision.9s6mRC`. The `--http-baseline` variant failed six
and passed four (`37edf1`/`a6150b`, `/tmp/kazoo-soft-delete-revision.XyH6Fk`): both
competing-write requests incorrectly returned204 instead of409, and the other
four failures detected revision refresh. Stale/weak/list/malformed rejections
remained unchanged. This is ten HTTP cases, not ten live-platform scenarios.

The runner pins prebuilt Cowboy/Ranch/Cowlib beams/app files and checks loaded
module paths. The explicit REST fixture substitutes document loading, strong
revision ETag generation and error-context response adaptation; it does not
exercise `api_resource` authorization, custom ETag bindings, actual user/queue
routes or CouchDB. It calls real public `crossbar_doc:delete`. Native malformed
header handling returns400 and exits that private request process without its
REST terminate callback. The fixture now observes process death; the expected
local crash report is not a deployed Crossbar service crash.

Run using the same guarded command above with `--http` or `--http-baseline` as
the final argument. The network namespace check rejects host-network listeners.

The separate real CouchDB probe traverses native delete/data-manager/save/driver
code with controlled routing/cache/publication. Both initial runs passed the
soft-delete conflict/body-preservation checks, but discovered a hard-delete
false-success defect in the original Couch driver. See
[P0-20 and its reproduction](couch_single_delete_result.md). Neither follow-up
deployed a production module or opened restricted-dashboard fixture admission.

## Gates still open

- Broader deployed Crossbar route acceptance. The administrator scope-policy
  route now passes3 real HTTP checks (`7c9f07`/`47ce1f`); the private Cowboy
  fixture additionally proves412 versus409 behavior through explicit adapters.
  Neither proves all resource types or restricted-principal authorization.
- Transport fault behavior and secondary replication; the combined P0-19/P0-20
  native primary CAS probe now passes, but isolated primary CAS is not cluster proof.
- Revision-preserving cleanup of exact owned users, policies and queues. Queue
  activation and user cascade deletion have separate earlier side effects;
  no multi-document transaction guarantee is claimed. The fixture uses plain
  user deletion, not cascade deletion.
- Token invalidation before deleting mutable scope policies. Keep the live
  isolation harness unconditionally closed until these gates are proven.

Deployment `489b41`/`b291e2` verified exact installed/loaded modules and unchanged
31-agent state; backup `/tmp/kazoo-revision-deployment.19HpQo`. The subsequent
full-route receipt and retained failed-probe fixture are documented in
`scope_management_dashboard_acceptance.md`. Older no-deployment statements
above describe their individual earlier test slices.

See `queue_live_isolation.md` for the retained-fixture policy and why neither
legacy-token deletion nor user-secret rotation alone proves JWT revocation.
