# Development warm-up — September 7, 2026

Scope: development host `kz5-testing` only. This is not a production readiness
certificate. Production Kamailio `10.1.0.28` and its mobile traffic are unchanged.

## Post-deployment follow-up

Both bridge and Kamailio producer-freshness code were deployed through the main
SH and independently verified; see `push_bridge_freshness.md`.
The first callback rerun `a0db03/session18702/81101c` stopped at the audio gate
because the operator command selected a retained legacy6.124-second reference,
not the currently installed5.491-second Gemini clip. Failed evidence is retained
at `/var/log/kazoo-acceptance/20260907T180751Z`; it is not a passing retry test.
Read-only reanalysis against the pinned Gemini reference passes `75de9d`:
one complete5.491-second confirmation, correlation0.999993, no missing samples,
digit6 at4.986seconds and full audio before server BYE. No runtime fix or gate
relaxation was needed. Current retry preflight now rejects legacy references
before calls/state changes; its negative check passes `a40011/893835`.
Historical legacy evidence remains readable by the separate reference verifier.

Corrected full post-deployment rerun `21d377/session53798/55fb32` completed
exit0; evidence `/var/log/kazoo-acceptance/20260907T181123Z`. The busy-agent,
digit6, complete Gemini confirmation, two-second wait, unanswered first return,
durable retry and reciprocal second native bridge all pass. Final phase-scoped
SIP/RTP, agent-ready, unchanged-service and log/core gates pass. The isolated
fixture is deliberately retained. This does not test the operator's1000 device
or prove complete production acceptance.
Offline follow-up `4a9316/session16968/7b37bc` passes24 reference/preflight
checks and79 full-audio/dialog/DTMF regression gates, plus installer/retry shell
syntax. Synthetic preflight verifies Gemini acceptance and legacy/missing/
malformed proof rejection without API, credentials, provider or SIP access.

## Completed checks

- `ba8498/session96565/ff0b00`: the installer's read-only
  `verify_acdc_language_packs` verified all 210 fixed Gemini documents and their
  exact installed WAV bytes, plus 420 mappings across both running media caches.
  Missing mappings: zero. No database or queue configuration writes.
- `90b88b/session59733/08da3f`: the account-local callback probe accepted the
  reported account/queue and extension1000, and constructed one valid native
  endpoint. It created no callback reservation, published no AMQP request and
  did not ring or replace the operator's MicroSIP registration.
- `31ca33`: CouchDB, RabbitMQ, HAProxy, Kazoo apps, eCallMgr, FreeSWITCH,
  Kamailio, nginx and the mobile bridge were all active. FreeSWITCH had zero
  channels before the live test. Available RAM was 5264 MiB; filesystem usage
  14%, with 126 GiB available. Bridge automatic restarts: zero.

## Live internal callback retry

`6e1abf/session73991/6fd51b` completed exit0. Evidence:
`/var/log/kazoo-acceptance/20260907T173406Z`.

The isolated1001 scenario established one busy agent, queued another caller,
pressed6 after about5 seconds, proved the full Gemini confirmation before BYE,
waited2 seconds, then released the busy call. The first native return was left
unanswered; a durable retry followed, and the second return completed digit1
confirmation and a reciprocal native agent bridge. Phase-scoped packet/media
checks and final service/log/agent-ready gates passed.

The diagnostic intentionally retains its existing test fixture. It is not full
fixture cleanup, real PSTN acceptance, or a test of the operator's MicroSIP1000.

## Boundaries

The 210 fixed/digit clips above are distinct from the incomplete expanded
cardinal pack: 409/584 cardinal recordings pass technical QA. Do not represent
that number inventory as a deployed, listening-approved five-language release.

The current bridge consumer uses isolated development routing. Synthetic broker
tests and valid FCM/APNs key parsing do not prove real Android/iOS ringing.
No production provider notifications were sent by these warm-up checks.
