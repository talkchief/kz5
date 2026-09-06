# Current deployment tasks

Project-wide priorities, owners and dashboard/workforce requirements are tracked
in [PROJECT_TASKS.md](../PROJECT_TASKS.md). This file retains detailed deployment
and incident evidence; task completion must agree with the project register.

This checklist records requested work, not production certification. The checked
items below have the specific evidence stated; unchecked items are not finished.

- [ ] DASH-01–07: implement the supplied queue overview/live drilldown and both
  historical dashboard designs; add bounded source-backed snapshot/history APIs,
  account/queue-scoped WebSocket updates and OpenAPI/event documentation at
  `/apis`. Clicking a queue opens its live dashboard. See the
  [design and acceptance brief](dashboard_delivery_plan.md).
- [ ] WFM-01–04: agent workforce report in the same style covering login/logout
  sessions, working hours, breaks and break types; filters, details, exports,
  durable event history, policy/timezone definitions and documented APIs.
  Multi-queue logins must not double-count working hours; unknown intervals and
  missing break reasons must be reported rather than invented.

- [ ] P0 report at 2026-09-06 09:48: extension 2000 caller waiting despite a
  globally ready agent. Read-only API snapshot shows queue roster contains only
  Agent 12 (logged out); ready Agent 19 has no queue memberships. SUP queue
  detail reports `Known Agents: NONE`. Both exact SIP endpoints are registered.
  Await operator choice before changing roster/login state; then verify ringing
  on the corrected queue. Improve UI distinction between global status and
  queue eligibility. No broad agent reset, call hangup or queue restart was used.

- [ ] P0 follow-up — queue-specific agent login. Clicking Login must present
  an explicit queue selector and confirm successful login to the chosen queue,
  not merely global agent readiness. Respect account access and queue membership;
  do not silently add an agent to a roster or log other agents out. Show which
  queues the agent is actually logged into. Acceptance: select queue 2000, verify
  runtime eligibility, place a call and confirm that the selected agent rings;
  a globally ready but unassigned agent must not appear eligible for that queue.

- [ ] Update the agent queue-login API and its OpenAPI documentation at `/apis`
  alongside the queue-selecting Login UI. Inspect and reuse the existing
  queue-login contract where possible; explicitly identify the account, agent
  and selected queue, enforce authorization and membership, and make repeated
  login requests safe. Distinguish accepted/pending commands from confirmed
  runtime queue login; never report global readiness as queue-login success.
  Specify request/response schemas, examples, authentication, validation and
  permission errors, missing/nonmember queues, unavailable runtime and retry
  behavior. Document membership changes as a separate explicit operation.
  Add backend, authorization, idempotency, UI and OpenAPI contract tests; publish
  the matching documentation with the implemented API, not as an already-live
  endpoint before implementation and verification.

- [ ] P0 follow-up — pressing callback key 6 did not register a callback or
  play audible notification in the user's live call. Logs for the 09:46:58 call
  report `callback menu unavailable: invalid_number; resuming live queue`; this
  explains a rejected attempt, not successful callback registration. Diagnose
  return-number selection and keypad failure feedback. Provide a usable,
  validated return-number path and clear audio on failure; play success only
  after durable registration, finish confirmation before hanging up, preserve
  queue position and verify unanswered-attempt retries. Reproduce with the
  user's MicroSIP path as well as the isolated fixture; do not invent a number.

- [ ] P0 follow-up — callback offer was not heard at the configured 30 seconds.
  Verify the saved callback-specific enable/initial-delay/repeat fields, their
  runtime loading and actual received audio timestamps on the affected queue.
  The callback offer must use its own schedule, independently of position,
  estimated-wait and generic announcements. Test first offer at the configured
  delay, subsequent repeats, and interaction with key 6/invalid return numbers;
  retain the user's report as unresolved until that live path passes.

- [ ] Finalize prompt-language override for EN, HE, AR, FR and ES. Generate and
  review Gemini speech once at artifact-build time; retain shared versioned
  audio/transcripts/provenance in Git and install shared system-media assets.
  Existing and future accounts/sub-accounts must select those installed assets
  without Gemini requests during account creation, queue editing or playback.
  Test explicit queue overrides and inherited/default language selection,
  including clear missing-pack handling; do not mark incomplete packs ready.

- [ ] Resolve and revalidate the 23:27 host-memory/AMQP incident. Broker alarms
  cleared without platform restarts. The all-offline test phones were recovered
  at 2026-09-06 00:12–00:14 with exact contacts, 30-online/1-offline directory
  results and unchanged one-agent roster/statuses; only the stalled fixture
  supervisor restarted. Serialized resource controls and the current 62-test
  callback/Gemini suite pass. Post-incident isolated callback retry
  `20260906T004339Z` passed full Gemini confirmation, ignored first attempt,
  successful retry/two-way media, scoped cleanup and zero new errors/cores.
  Broader live call/load acceptance remains; see
  [the incident evidence](host_memory_incident_20260905.md).

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
  All165 assets were freshly byte-verified at21:33 UTC. The first Gemini live
  callback run failed because the media-manager prompt caches lacked the newly
  imported IDs. Targeted activation verified all330 mappings and actual AMQP/HTTP
  audio hashes. The repeated live run `20260905T215059Z` exited zero with the
  complete5.491-second Gemini confirmation before BYE, unanswered first attempt,
  successful second bridge and two-way audio, zero new errors/cores and no
  service restarts. Gemini English fixed defaults are now active. Numeric and
  auxiliary completion across allfive languages is still pending approval.
  The installer now verifies immutable assets before application build/restart,
  with11 mocked ordering/failure scenarios and exact-receipt protections passing.
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
  Route: `GET /v2/accounts/{ACCOUNT_ID}/members/devices` is integrated in source
  and the deployed main OpenAPI catalog. Thirteen backend/auth regression groups
  and nine schema/harness tests pass. Live MASTER-admin acceptance returned all31
  users/devices (30online,1offline) with unchanged catalogs. Anonymous and invalid
  cursors are rejected; restricted-token and cross-account-principal tests remain.
  "Offline" is the assumed correction of "office". Ownership uses owner_id only;
  unassigned/shared/hotdesk relationships are not expanded. Above1000devices,
  inventory is explicitly incomplete rather than falsely empty/complete.
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
- [x] Document those monitoring APIs in OpenAPI. The locally served public-host
  catalog was checked again on 2026-09-06: OpenAPI 3.0.3, 354 paths and 649
  operations, with `eavesdrop`, `whisper`, `barge`, `join` and the member/device
  route present. Runtime monitoring evidence is the single-server test above;
  catalog presence does not certify other operations or multi-node behavior.
- [ ] Package source patches, deploy reviewed artifacts with rollback backups,
  verify browser/API/SIP behavior and fresh logs, and give the user test steps.
- [ ] Commit/push completed changes with a credential scan and verified remote SHA.
  Local checkpoints through `ebb50e1` include recordings/transcripts, source
  repairs and scoped test evidence. Actual connector writes return403; remote master remains
  `57560824`. No successful push of that checkpoint has been claimed.
- [x] Contain the 30 existing test-phone UDP control sockets without restarting
  phones; persist explicit loopback control binding for future starts. Exact
  ownership/post-checks and mock argument tests passed. This is not a complete
  firewall/security certificate; see [network scope](network_hardening_checkpoint.md).
- [ ] Fix and repeat the actual all-module installer verification. The live
  RabbitMQ stdin check caught a command-wrapper argument-count hang missed by
  mocked tests. The corrected helper has a finite timeout and 32 passing
  regression scenarios; actual authentication passes. Read-only verifier guards
  are packaged. The actual unwrapped post-fix run completed in 52.675 seconds,
  with all seven backend/media/SIP components passing and its sole failure the
  Monster UI bundle fingerprint. Separate HTTP/same-origin API and ten-app
  catalog checks pass; rebuild/provenance reconciliation is not bypassed.
  HTTPS still refuses port 443 and all five full-language readiness flags remain
  false. See [the exact checkpoint and private receipt locations](installer_verification_checkpoint.md).

Broader unresolved acceptance gates remain in
[the acceptance status](kazoo5_acceptance_status.md): clean/distributed installer
tests, full 30-call draining, simultaneous-answer hardening, failover, restore,
external routing and HTTPS. This task list does not mark those gates passed.
