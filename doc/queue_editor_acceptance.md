# Unified queue editor acceptance — 2026-09-05

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
the backend or imply that the public portal already serves these new bytes.
