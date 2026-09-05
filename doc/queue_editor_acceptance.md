# Unified queue editor acceptance — 2026-09-05

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
