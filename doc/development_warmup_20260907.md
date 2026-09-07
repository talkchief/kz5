# Development warm-up — September 7, 2026

Scope: development host `kz5-testing` only. This is not a production readiness
certificate. Production Kamailio `10.1.0.28` and its mobile traffic are unchanged.

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
cardinal pack: 404/584 cardinal recordings pass technical QA. Do not represent
that number inventory as a deployed, listening-approved five-language release.

The current bridge consumer uses isolated development routing. Synthetic broker
tests and valid FCM/APNs key parsing do not prove real Android/iOS ringing.
No production provider notifications were sent by these warm-up checks.
