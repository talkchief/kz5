# Current deployment tasks

This checklist records requested work, not production certification. The checked
items below have the specific evidence stated; unchecked items are not finished.

- [ ] Unified account-scoped queue editor API: one initial read and consolidated
  create/edit operations, bounded batch reads, authorization, revision checks,
  retry/idempotency and explicit partial-write recovery.
  Backend and UI are deployed. The 20:59 UTC live browser passed one editor GET,
  no separate catalog requests and no JS/HTTP errors. Isolated live create/edit,
  replay/conflict tests and exact-CAS fixture cleanup passed at 21:02 UTC with no
  agent changes (`queue-editor-live.pkUEWo`). Restricted-token, roster-write and
  partial-failure live coverage remain open; the operation is not transactional.
- [ ] Independent callback-offer enable switch, initial delay and repeat interval;
  no immediate entry offer, no overlapping playback, cancellation/lifecycle tests.
  Production scheduler/control modules and the queue schema were updated on
  2026-09-05 without restarting services. The 19:23 UTC isolated call passed SIP,
  full-phrase audio timing, producer cleanup and unchanged service-PID checks;
  its overall gate failed on SUP audit-log formatting errors. That logger was
  repaired, and the 19:35 UTC repeat passed the full timing/audio/SIP/log gates
  and exact-revision fixture cleanup, without changing agents. Broader lifecycle
  and callback-return tests below remain open.
- [ ] Callback keypad failure feedback; verify confirmation, hangup, return call,
  unanswered first attempt and retry. Resolve the live MicroSIP return destination
  instead of silently accepting its nonnumeric `kz5_test` caller ID.
  The isolated one-agent retry run `20260905T201353Z` exited zero: full received
  confirmation before server hangup, first attempt unanswered, second attempt
  confirmed/bridged, no fresh test-window errors/cores and unchanged services.
  This does not complete MicroSIP/PSTN routing or historical-ticket cleanup.
- [ ] Natural Gemini/Sulafat female queue/callback media for EN, HE, AR, FR and ES;
  retain transcripts, WAVs and provenance in Git; validate and install the tested
  pack without overwriting customer recordings. Numeric-language completeness and
  native listening approval remain separate gates.
- [ ] OpenAPI 3 specification and local developer reference at `/apis`, including
  queue/callback APIs, unified editor APIs and call monitoring actions.
  The source-derived portal is deployed and publicly returns HTTP 200 at
  `http://kz5.talkchief.io/apis/`. Its coverage report explicitly separates
  source contracts, runtime verification gaps and planned endpoints.
- [ ] Company/account member-device directory API: return members and their
  owned devices, device type and fresh cluster registration status
  (`online`, `offline`, `unknown`) with observation/expiry timestamps. Treat
  failed status lookup as unknown; distinguish registration from ACDC agent
  availability. Enforce account permissions, omit secrets and provide bounded
  pagination without silently truncating large accounts. Document the planned
  contract in OpenAPI separately from implemented endpoints.
  Proposed route: `GET /v2/accounts/{ACCOUNT_ID}/members/devices`; the separate
  `planned.openapi.json` is available in the portal. "Offline" is the assumed
  correction of "office"; implementation and live tests are still pending.
- [x] Verify actual module services: `kazoo-apps`, `kazoo-ecallmgr`,
  `kazoo-freeswitch`, `kazoo-kamailio`, `couchdb`, `rabbitmq-server`, `haproxy` and
  `nginx` were all loaded, active and enabled on 2026-09-05.
- [x] Add and verify `kazoo-applications.service` compatibility alias; preserve
  `kazoo-apps.service` as the canonical unit and persist alias in the installer.
  Both names resolved to the same unchanged active PID after daemon reload and
  enable; no service restart was performed.
- [x] Repair SUP remote audit logging for Erlang-term arguments, omit raw
  arguments/results, and preserve command output. Six regression tests and live
  probes passed; only the remote module was updated on applications/ecallmgr,
  with unchanged service PIDs and an installer-persisted source patch.
- [x] Existing eavesdrop/whisper/barge/join APIs passed isolated single-server
  synthetic-audio and authorization tests on 2026-09-05 at 11:29–11:31 UTC; see
  [recorded evidence](channel_monitor_acceptance.md). This is not multi-node proof.
- [ ] Document those monitoring APIs in OpenAPI and run proportionate regression
  checks against the deployment being handed over.
- [ ] Package source patches, deploy reviewed artifacts with rollback backups,
  verify browser/API/SIP behavior and fresh logs, and give the user test steps.
- [ ] Commit/push completed changes with a credential scan and verified remote SHA.

Broader unresolved acceptance gates remain in
[the acceptance status](kazoo5_acceptance_status.md): clean/distributed installer
tests, full 30-call draining, simultaneous-answer hardening, failover, restore,
external routing and HTTPS. This task list does not mark those gates passed.
