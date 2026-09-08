# Unified queue editor acceptance — 2026-09-05

## September8: main-host language persistence acceptance tooling

First native main run81ce691 completed all26 API checks and exact cleanup:
`/var/log/kazoo-acceptance/queue-editor-main44.GUsWUsus/queue-editor-acceptance.json`.
Its enclosing unit58571/fb64fd exited1 because the generic word-based log gate
counted expected negative-response INFO messages (file3/journal5 before final
file flush), not an API/language failure. Source pins and service snapshots
matched. Inspectionfcca7f identifies exactly one anonymous401, changed-body409,
stale-revision409 and two post-deletion404 envelopes from `api_util:error_envelope`.
All eight operation intents are complete and resources removeda94bd1/129dc3;
zero calls remain. The failed enclosing run is retained, not relabeled green.

The harness now records each expected negative response's server request ID,
code and bounded reason. `queue-editor-expected-http.cjs` permits only its exact
INFO envelope line; a different request, severity, code, reason or module,
duplicate observation, missing expected response or unrelated error remains
visible. All17 lifecycle/log-classification cases pass963d33. No production log
level or error handling was changed. A new run is required to exercise this
correlation; do not manufacture request metadata in the earlier receipt.

The armed live runner is now `scripts/test-acdc-queue-editor-live.sh`. It
requires explicit `--fixture-account`, `--extension` (2090–2099), `--run-dir`
and `--allow-fixture-writes`; ambient target/state overrides are cleared. It
validates the canonical protected Acceptance tenant and serializes with call
tests using the non-truncating shared lock. The Node adapter checks the live
account identity and ordinary read-only provisioner inventory, then connects
only to loopback or an IPv4 address assigned to the host for CouchDB reads.
It never selects the imported company or an authenticated master as its fixture.

`run-languages` retains the existing create/replay/idempotency-conflict/edit/
stale-revision sequence, then PATCHes each of EN/HE/AR/FR/ES. Each language has
its own fresh revision snapshot and operation ID, exact replay, and fresh GET
checking language plus distinct generic17/callback30 intervals and45/30 initial
delays. Callback calling is disabled and no roster write is allowed. The
managed route is removed through aggregate hooks; only the exact owned queue
revision is soft-deleted. Operation receipts and released extension claim stay
as audit records. Unknown/partial outcomes are retained without automatic
retries, revision refresh or destructive rollback.

Create an empty root0700 evidence directory under `/var/log/kazoo-acceptance/`
and run through bounded validation/systemd controls, with no active calls:

```sh
bash scripts/test-acdc-queue-editor-live.sh run-languages \
  --fixture-account "$acceptance_account" --extension 2097 \
  --run-dir "$protected_run_directory" --allow-fixture-writes
```

The extension must be unused with no prior aggregate reservation; the runner
refuses otherwise. Do not delete an old claim to force acceptance. Explicit
`cleanup` uses the same account/extension/directory and all original receipt,
call, callback, ownership and revision guards; an ambiguous intent is not
automatically repaired by cleanup.

The previous harness fails three new language casesa231fd. All13 cases pass
1d9f70 and another explicitly selected synthetic account5e8498. Additional
actual-shell/private-flock tests010d6c cover arming, target/extension validation,
ambient isolation, identity refusal and preserved lock inode/content.
Bash/ShellCheck/whitespace checks pass. Native main-host execution is still
open at this source checkpoint; unit tests are not HTTP/database acceptance.

## Historical checkpoints

This is a historical live checkpoint, not acceptance of the latest source.
The source-only 2026-09-06 acknowledgement repair is recorded below.

The English selection repair is deployed and the isolated live API sequence
passed at 22:50–22:51 UTC. This is not complete platform certification.

The UI offered the verified English baseline, but write validation required a
full-pack `ready` flag that deliberately remains false. Validation now accepts
explicit `en-us` only with the valid legacy manifest, a complete system-media
catalog and all required attached English baseline prompts. Missing assets,
incomplete catalogs and unsupported locales still fail closed. No language
readiness flag or customer recording was changed.

The production module was compiled with warnings as errors and no test exports,
then loaded using exact source/BEAM checks, soft purge and rollback backup
`/usr/local/src/kazoo5-installer/queue-language-selection-deploy.cFks6f`.
Source SHA256: `c59b2817f05551c3bbf7e6d65876b41bf39978facdd36683df86fa8c9e85704f`.
BEAM SHA256: `7229343fa250d3d0bf8856150c1336c0dcfbd6a653381715fd833992f920bebb`.
Subsequent source-only installer portability work is a separate checkpoint.

The real API test used the existing isolated tenant and explicitly selected
virgin extension 2096. It passed anonymous rejection, create plus managed route,
exact create replay, changed-body/idempotency conflict, edit plus replay, stale
revision rejection and a fresh GET confirming the explicit English selection.
Managed-route removal and exact-revision queue cleanup passed. Three operation
receipts and the released extension claim remain as normal audit records.
No agents or MASTER queue membership changed, and no SIP calls were made.
The protected receipt is
`/var/log/kazoo-acceptance/queue-editor-english.tg1twF/queue-editor-acceptance.json`.

The harness's ten offline groups pass, including ambiguous-outcome retention,
foreign revision/ownership changes, active-call/callback cleanup guards and
rejection of MASTER as a cleanup target. The separate 22:36 browser acceptance
passed one unified editor GET, zero catalog fanout, the Callflows ACDC action,
authenticated WebSocket subscription and zero console/HTTP errors; see
[the browser record](monster_console_acceptance.md).

Service PIDs and restart counters remained unchanged. Crash logs stayed at
142268 bytes for applications and 386 for eCallMgr. The 22:48–22:59 console-log
window had no error/critical entries and the service journal had no priority
0–3 entries. Two applications large-heap warnings at 22:50 reported 1114136
bytes for one process; this is not a completely warning-free log claim.

Restricted-token, roster-write, cross-node and partial-write recovery live
acceptance remain open. The coordinated multi-document editor is explicitly
non-atomic; clients must reload after success or an ambiguous/partial outcome.

The source-derived `/apis` artifact was regenerated and deployed with backup
`/usr/local/src/kazoo5-installer/apis-editor-proof-deploy.XQFXGZ`. All 354 paths,
649 operations and 1541 internal references validate; deterministic regeneration
and tamper detection pass. The initial HTTP byte-check wrapper hit its default
1-MiB output limit on the 1617584-byte schema; a bounded 8-MiB read then matched
the served schema, coverage and manifest exactly, without another deployment.
The local browser regression loaded all 649 operations with eight requests,
zero external requests/errors, disabled API execution and no token persistence.

## 2026-09-06 — bulk acknowledgement repair, source only

The previous completion classifier ignored extra malformed/foreign result rows
and accepted empty revision strings. Three regression cases failed before the
fix (session `39639`); seven duplicate/missing-result and lost-reply/receipt
controls already passed. The fix now requires exactly one successful result
with a nonempty revision for every planned user before advancing to the route
phase. Ambiguous outcomes retain the existing partial receipt and require a
fresh read; they do not trigger automatic retries or rollback.

Session `68783` passed all 41 editor/manifest tests after the fix, including
all ten new cases. The fixture datastore really applies its in-memory user
changes before simulating lost replies. Tests compare persisted/public
`committed`, `in_flight` and `remaining`, then verify the fresh roster/revisions,
unchanged route and absence of a second bulk write. All three production
modules compiled with `-Werror`; the eight recorded direct inputs were
unchanged during the run. Existing dependency BEAMs were not freshly rebuilt.

Both runs used network isolation, a 180-second guard, 384 MiB memory and 768 MiB
reserve. Retained private evidence:

- Before: `/tmp/kazoo-queue-editor-test.7PWgis/eunit.log`, SHA-256
  `29e392604a8b34d8774f2d86c5bd746a69be44ee22a6f29d2987ac860ac63b92`.
- After: `/tmp/kazoo-queue-editor-test.lLqc7w/eunit.log`, SHA-256
  `6adcaa7b80e5589b7d44efdfa77962f017033ee1efac602ec27a6f0eb9d642f9`.
- Fixed editor source SHA-256:
  `590570cb7c99a286ecdb74c68545dce784a6bcadc5ed2fb2f30e8b19026c6767`.

Run `scripts/test-acdc-queue-editor.sh` for the full suite or `--bulk-only` for
the ten-case matrix, through the resource guard. No service was reloaded or
restarted for this checkpoint. Authorization providers remain doubles in this
suite; real restricted-token coverage, deployment and live failure injection
are separate acceptance gates. OpenAPI retains the dated historical live
record but explicitly marks the latest revision as not live verified.
The refreshed repository API catalog passed generation (`43015`) and the full
offline deterministic-rebuild/tamper/schema suite (`78714`): 354 paths,
649 operations, 477 schemas and 1,548 internal references. This does not deploy
the backend. The subsequent static publication (`83187`) verified all eleven
public `/apis` files against these repository bytes over loopback HTTP. Its
rollback and explicit non-TLS/non-backend scope are recorded in
[the portal publication log](api_developer_portal.md).

## 2026-09-06 — offline production-auth controls

Session `36276` passed nine grouped authorization tests using the real JWT,
restriction, hierarchy and scope code. Fifteen production modules compiled
with `-Werror` and without `-DTEST`; their private loaded paths and compiler
options were checked before and after EUnit. Seventeen source inputs and
37 prebuilt dependency files (including the JSON NIF) retained identical hashes.
This is bounded dependency evidence, not a fresh build of every transitive library.

Controls cover exact queue/editor/roster/callflow grants, null-preservation
requests, partial forbidden catalogs, changed media/number selections,
unrelated-account denial with a descendant-account positive, expired signed
tokens and independently omitted scopes. All writes stop at validation: no
database mutation, AMQP operation, live HTTP request or service reload occurs.
Datastore, account/config/key/identity providers, binding dispatch, error
serialization and queue/callflow schema validators remain explicit substitutes.
Global-media authorization does not certify installed language readiness.

The missing outer queue scope produces a real permission stop before editor
entry or resource reads. The generic middleware leaves its error-code field
unset at that boundary; this fixture does not synthesize an HTTP 403. A separate
public editor call after real preauthentication verifies its own 403 recheck.
The generic middleware's final HTTP error behavior remains separately unverified.

The initial run `46413` retained four passing and five failing groups at
`/tmp/kazoo-queue-editor-auth.PJBVKw`. Corrections used the actual `_` restriction
wildcard, distinguished validation plans from GET response bodies, and captured
the real scope-stop boundary. Its original fixture and failure log are retained.
The passing log is `/tmp/kazoo-queue-editor-auth.pBZfC8/eunit.log`, SHA-256
`1edacc5fc4244ad670047fb161df883a28999881e8d186ce9779d6ba0960be69`.
Run `scripts/test-acdc-queue-editor-real-auth.sh` through the 180-second,
384-MiB/768-MiB-reserve guard with `unshare --net`. No production auth code changed;
live restricted principals, current-revision deployment and live failure
injection remain separate acceptance gates.

## 2026-09-06 — interrupted validation must not report success

Combined guarded session `90416` finished all 12 queue-runtime tests and all
41 editor/manifest tests. It then reached its 180-second runtime limit during
the first production-auth compilation. The guard exited 1; the authorization
suite did not finish and the recovery suite was not reached. This is not an
all-suite pass. The completed editor log is
`/tmp/kazoo-queue-editor-test.xS7GQE/eunit.log`, SHA-256
`549f3886d069c64178c577c1526bba5bc6779b1af3f47d070b26ea53e3568a89`.

That interruption exposed a reporting defect: the auth shell's EXIT cleanup
printed `exit=0` even though compilation had been terminated. Both retained
editor runners now require an explicit completion flag after their final test
pipeline and return nonzero on SIGINT/SIGTERM. Changed source/dependency pins
still fail validation. SIGKILL cannot produce a final receipt; missing or
unfinished evidence remains incomplete, never a pass.

`scripts/test-editor-validation-completion.cjs` extracts the actual finish and
signal handlers and checks 16 completed/incomplete/error/signal/pin-change
cases. It passed under the 384-MiB, network-isolated validation guard at
15:48 UTC. The pin checker is substituted in that fixture: this is bookkeeping
proof, not another Erlang, authorization or live-platform acceptance run.
Run longer suites in separate bounded invocations so one suite's runtime does
not consume the next suite's allowance.

The subsequent standalone authorization run `5127` exited zero with the corrected
completion handling: all nine groups passed, all 15 production module paths and
no-`TEST` checks passed before/after, and source/dependency hashes were unchanged.
Evidence is `/tmp/kazoo-queue-editor-auth.LSTTw9/eunit.log`, SHA-256
`1d067517670b1d2aca608f8f604775e16de927ab1aa9412a588c557ccfcf6fc2`. This retains the
offline provider/substitute boundaries described above; it is not a live-token
or deployment test.
