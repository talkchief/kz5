# ACDC UI fixes — September 7

## Current scope

The current patch fixes queue-editor request serialization, bounds UI GET waits
and simplifies dashboard labels. It does not change the login command, callback
number validation, metric calculations or tenant/queue authorization.

## Queue creation / editing HTTP 400

The real server logged three `PUT /queues/editor` rejections at 08:19:48,
08:20:12 and 08:20:45 UTC with `editor_body_requires_exact_fields`.
The form builds the required five fields, but Monster's request serializer
automatically adds `data.ui_metadata`. The editor correctly rejects that sixth
field before receipt lookup or resource writes.

`requestQueueEditor` now passes the existing framework option
`removeMetadataAPI: true` outside the request body. The backend stays strict.
The original body, request ID and explicit retry fingerprint are preserved.
Both create and update use this same wrapper.

Root test `e412fe` passed eight groups in
`monster-ui/acdc/tests/queue-editor-request.test.cjs`. It executes the real
Monster request constructor/serializer with captured AJAX, reproduces the
original extra field, and checks exact PUT/PATCH bodies and explicit retries.
This is not an HTTP create or database-write acceptance test.

Actual deployed-browser form submission later succeeded with HTTP201
(`7f91f3`/`816240`). The browser harness initially asserted HTTP200 and stopped;
the persisted completed operation response proved creation. OpenAPI already
documents both200 and201, so the overly narrow assertion was in the harness.
No second create was sent. Explicit recovery `09a4d6`/`131789` verified the exact
saved test name, disabled callback, empty roster and no callflow reference, then
removed only the owned test queue and confirmed HTTP404. The editor operation
receipt remains as an audit record. Protected ledger:
`/tmp/kazoo-editor-ui-acceptance.BHjc9d/ledger.json`.
An earlier browser attempt `0d6653`/`4674f0` stopped before any write.

Queue GET intentionally omits ETag after enriching its dynamic roster. Cleanup
therefore used exact fixture ownership, unchanged fresh settings and editor
revision checks; it was NOT a conditional-delete/concurrent-writer proof.
The create form succeeded, but validation-error recovery, PATCH and uncertain
receipt-recovery browser cases remain separate acceptance work.

## Loading / login verification

GETs previously had no request deadline. `requestBoundedRead` settles once
after at most ten seconds, aborts the transport on timeout, and ignores late
callbacks. Live view disposal also cancels its pending GET. Failed initial
loads show the existing error/retry state; failed refreshes retain stale data.
Writes retain their existing uncertainty handling and are not automatically
retried or declared failed by the read watchdog.

The operator clarified that login succeeds but its UI verification sometimes
fails. Root direct HTTP and selected-queue live reads both confirmed Agent12
ready with runtime membership. Deployed-browser probe `54433a`/`1326c7`
also rendered "Queue membership confirmed" without sending a login mutation.
An earlier shell-readiness timeout and one unclassified TypeError remain to
investigate; a successful later attempt does not close the intermittent report.

Root `b01286` passed 23 queue-login groups, including the actual Monster
response-envelope path. Root `078c38`/`a26140` passed 52 dashboard groups,
including timeout, cancellation, late replies and plain-label coverage.
Both are offline fixtures, not current deployed-build acceptance.

## Dashboard wording

User-facing values no longer include “observed”. Waiting, Ready, Member and
Active calls use plain labels; the progress metric and duration heading read
“In Progress”. Unknown/stale/partial data warnings remain. Existing translation
keys and wire fields keep their names so API clients are not broken.
Caller name/number projection is a separate pending requirement, `DASH-10`.

## Related queue API log fix

`cb_queues` omitted content-negotiation handlers for queue detail/subresources.
The production callback patch adds identity `/2`, `/3`, `/4` handlers while
retaining JSON/CSV for `/queues/stats`. Direct real-module EUnit tests pass all
six cases (`3e423e`/`4a0585`, build `/tmp/kazoo-queue-content-types.w0HXCk`).
The fixed pre-patch source `d7992ca` fails three cases with the same
`function_clause` and `undef` symptoms (`40a8c9`/`e4d6b2`).
The runner now preserves each module's production Lager application tag using
separate output directories. Repeat current build `7a109c`/`575d77` passed all
six tests at `/tmp/kazoo-queue-content-types.TetOzE`; repeat baseline
`db933c`/`8dfe10` failed the same three cases at
`/tmp/kazoo-queue-content-types.QJDwy3`. Normalized baseline abstract forms
exactly matched the installed old module, including log metadata (`39d866`).
Both modules compile without TEST; only `cb_queues` was deployed.

Real read-only HTTP probe `499e52`/`b61caa` reproduced six content-negotiation
error-log entries from six successful queue/detail/live/roster/editor reads.
Stateless module deployment `0c9f54`/`84b347` succeeded without restarting
services. Installed bytes and loaded module MD5/export arities were verified.
Backup: `/tmp/kazoo-queue-types-deployment.XS9QCz/cb_queues.beam`.
Candidate SHA-256:
`e44c41d4065a714890453c5766dcea57a861b254a92a2e641c9f504338934dcc`.
The identical six HTTP reads after deployment passed with zero appended error
lines (`da07ec`/`86d759`). This proves these paths, not cluster-wide reliability.
Canonical source is in kz5, not nested ACDC Git.

The matching full API catalog passed focused/schema/source-inventory checks
(`1811a9`/`5199cf`, `/tmp/kazoo-api-live-catalog.w9c0lS`). Generated repository
assets were refreshed (`159801`/`40e94d`) and published through the installer
helper (`e1a4e3`/`c4a478`). All eleven served assets matched their manifest
hashes, with 358 paths and 653 operations; HTTP redirect/no-store/missing-file
checks passed. No new API semantics were introduced by the handler fallback.

## Deployment and remaining acceptance

Fresh installer-prepared stage:
`/usr/local/src/kazoo5-installer/monster-owned-build.hXJTv6/source`.
Preparation `177c00`/`777ed3` preserved the existing public configuration and
verified unchanged before/after input fingerprints. Production build
`130be8`/`b8aff7` passed the artifact checks. Both temporarily paused services
(`kazoo-ecallmgr`, `kazoo-live-test-agents`) were restored and verified active.
Owned installer deployment `6d7352`/`d9a24c` changed three files, removed none,
and preserved 1,941. Rollback evidence is retained at
`/usr/local/src/kazoo5-installer/monster-owned-plan.dGtNQj/rollback`.
Served index, main bundle and configuration matched the ownership receipt.

Fresh actual-browser check `cbf2ed`/`80cbbf` passed: dashboard visible,
all dashboard translation values free of “observed”, visible Waiting and
In Progress labels, and duration heading In Progress. It also verified the
deployed bounded-read method and confirmed Agent12 queue membership through
both the real UI GET and dialog without a login mutation.
This closes wording task UI-02, not the broader intermittent-loading report.
The browser still emitted a startup TypeError reading `acdc`; bounded frames
were main.js 84:4859, 84:4695, 83:25753 and 83:5048. Keep that defect open.
Source mapping identifies the failed access as `i18n.active().acdc.dashboard`.
The native app loader can clear the shared translation table during overlapping
loads; an installer-owned single-flight fix is being prepared separately and
is not deployed by this checkpoint.

After rollout, exact before/after comparison `090482` confirmed the queue
roster and all 31 reported agent statuses/memberships unchanged. No restore
was performed.

Current bundle SHA-256: main.js
`72c2055288b72a49680134694b074623680f7a0af0b4d26026eff610d0245bc1`;
templates.js
`fd6d1c690383e1d1dc30c73435bdfa165728434e897db2d76fc391bf7418f0bd`.

Remaining: browser timeout/create acceptance, exact queue-create ownership/readback and
cleanup, intermittent startup diagnosis, native HTTP/log checks after the
content-type fix, storage capability404, and caller identity display.
