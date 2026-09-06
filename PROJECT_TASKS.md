# Kazoo 5 project task register

Updated: 2026-09-06. This is the project-wide priority/status index. Detailed
incident evidence remains in [deployment tasks](doc/deployment_tasks.md) and
[acceptance status](doc/kazoo5_acceptance_status.md); earlier passes are scoped
evidence, not proof that later regressions or production acceptance are closed.

Statuses: **ACTIVE** = implementation/investigation underway; **OPEN** = not
accepted; **BLOCKED** = named external input needed; **VERIFIED** = only the
explicitly stated test scope. An item is complete only when its source,
installer integration, API documentation and relevant tests agree. Changes must
be committed and pushed before the delivery is reproducible from the remote.

## Active team coordination — 2026-09-06

The operator's team handed off commits `1634524` (directly tracked ACDC source)
and `83194e7` (delayed queue-satisfaction/outbound-agent recovery) on branch
`fix/acdc-outbound-agent-availability`. The operator explicitly authorized merging
the combined work and continuing. Both commits are already ancestors of the
current checkout; do not reapply their exported patches or recreate nested Git
metadata. ACDC source in `applications/acdc` is now canonical; historical ACDC
patches are compatibility fixtures, not the installation source of truth.
Our phone-service commit `49ccb98` is also on this branch. Preserve all changes
and reconcile the pending installer/UI work against this combined source.

The handoff reports 48 unit, 26 strategy and five migration checks passing,
with no deployment or restart. Independent combined checks are in progress;
this is not live-call acceptance. Regenerate affected API coverage and run
combined call-delivery/callback regressions before release. The private callback
audio adapter still needs native completion, cancellation and owner-handoff
proof before promotion; the handoff does not waive those safety gates.

## P0 — call delivery and callback correctness

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| P0-01 | ACTIVE — API + UI | Queue-specific Login: backend committed `4fc2a2b` with 12 isolated regression groups passing and exact fresh pinned installer-patch replay; explicit-selection UI committed `d263342` with focused/full contract passes. Source-bound OpenAPI overlay/reference committed `22b5f94`, with 9 focused groups / 45 schema cases passing. No silent roster changes or other-agent logout; membership is not readiness. Regenerate/publish `/apis`, deploy and test selected-agent ringing. |
| P0-02 | OPEN — acceptance | Re-test extension 2000 after the operator selects the intended queue agent. Observed roster Agent 12 logged out; globally ready Agent 19 unassigned; runtime knows no eligible agents. Do not reset all agents to conceal the mismatch. |
| P0-03 | ACTIVE — callback | Key 6: identified queue audio starved behind endless hold. Private immediate-audio candidate passed 58 distinct offline cases, but source review found synchronous native playback behind a five-second RPC timeout and blocked call-control handling. Candidate deployment is held for correction/native boundary proof; offline passes do not close this risk. Handle invalid return caller ID clearly; durable registration before success audio/BYE, position retention and unanswered-first-attempt retry require live acceptance. |
| P0-04 | ACTIVE — callback | Callback offer at configured 30 seconds: separate enable, initial delay and repeat interval from position/wait/generic announcements; verify saved values, runtime schedule and received audio. Invalid return numbers must not cause silent failure. |
| P0-05 | OPEN — ACDC | Agent stability: one answered call must not log unrelated agents out. Test failed ringing, reconnect, queue-specific logout, pause/resume and reboot recovery. |
| P0-06 | OPEN — ACDC | Resolve retained ambiguous callback cleanup/reconciliation ticket without losing evidence or falsely marking a live leg settled. |
| P0-07 | OPEN — ACDC recovery | Missed hangup events can leave an agent incorrectly busy (operator review finding). Add bounded reconciliation against authoritative current call state, with exact call/account/owner identity. Prove recovery after lost, duplicate and late hangup events, including multiple direct calls and node reconnect. Never mark an agent available while another tracked call is active; preserve explicit pause/logout and queue membership. SIP registration alone is not recovery proof. |
| P0-08 | OPEN — ACDC + AMQP | Failed AMQP delivery can prevent recovery from ringing (operator review finding). Identify affected publish/ack/recovery paths and make recovery bounded, observable and safe to retry. Test publish failure, broker interruption, lost acknowledgements and redelivery: no permanently stuck ringing state, duplicate bridge, stolen call or unrelated agent/roster mutation. Broker acceptance alone must not count as completed state recovery. |
| P0-09 | OPEN — ACDC policy + UI/API | Repeated connection failures can automatically log agents out (operator review finding). Distinguish intentional configured protection from unintended logout; define configurable thresholds and recovery behavior, expose the reason/current state through API/UI and document it in OpenAPI. Test threshold boundaries, transient failure, successful-call counter reset, reconnect and explicit operator logout. Do not silently disable unreachable-agent safeguards or automatically override an intentional logout. |

The three recovery findings above were added from the operator's 2026-09-06
review and are release-blocking P0 items, not fixed by `83194e7`. That commit's
delayed-notification regression verifies recovery after direct calls finish and
preserves pause/pending logout. Independent testing also passed those three
cases; the wider unit run stopped later on an older mock-setup timeout and has
not yet passed in full under the current resource cap. Each new P0 requires a
reproducer, code and installer integration, focused fault-injection regression,
and relevant live call/state/log evidence before closure.

## Dashboard and workforce delivery

The supplied folder contains four designs, covering two live screens and two
historical screens. Exact references and API/data requirements are in
[the dashboard implementation brief](doc/dashboard_delivery_plan.md).

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| DASH-01 | OPEN — UI | Live queue overview using `Queues Live Dashboard Main.png`: sortable queue cards, SLA, waiting/handled/abandoned counts, wait/handle durations, queue administration actions. |
| DASH-02 | OPEN — UI | Clicking a queue opens its live detail using `Queues Live Dashboard.png`: KPI cards, queue-scoped agent/call states, search/filter/sort, performance and authorized spy/whisper/barge/join controls. |
| DASH-03 | OPEN — API | Bounded account/queue dashboard snapshots with source timestamps, completeness, metric definitions, pagination and authorization. Reuse source APIs where adequate; consolidate backend reads rather than browser fanout. |
| DASH-04 | OPEN — events | Authenticated account/queue-scoped WebSocket updates for live screens. Snapshot/event ordering, duplicate/gap handling, reconnect/resubscribe/resync, token expiry, stale indicators, bounded buffers and multi-node ownership. No silent polling-only substitution. |
| DASH-05 | OPEN — API + docs | Define/version dashboard request, response and event schemas. Publish HTTP contracts in OpenAPI at `/apis`, link WebSocket message/subscription/lifecycle documentation; distinguish proposals from deployed endpoints. Test schema conformance and tenant isolation. |
| DASH-06 | OPEN — UI + reporting | Queue historical dashboard using `Queue Historical Dashboard.png`: time/queue filters, call outcomes, SLA, wait/handle/talk metrics, details and export. Reconcile counts, timezone boundaries and late events. |
| DASH-07 | OPEN — UI + reporting | Agent historical dashboard using `Agent Historical Dashboard.png`: agent/queue/date filters, last activity, outcomes, talk/break/idle durations, details and export. Define attribution for transfers/multiple queues. |
| WFM-01 | OPEN — product + UI | Workforce report in the same design language: agent/date/queue filters, login/logout times, sessions, working hours, total breaks and breakdown by break type; drilldown and export. |
| WFM-02 | OPEN — API + storage | Durable agent session/state-transition and break-reason records with identifiers, timestamps, provenance and runtime confirmation. Handle missing logout, restart, duplicate/late events, overnight shifts, timezone/DST and multi-queue sessions without double counting. |
| WFM-03 | OPEN — API + docs | Workforce summary, session details, break-type catalog and export APIs; access control, bounded ranges/pagination and OpenAPI schemas/examples/errors. Separate break configuration changes from reporting reads. |
| WFM-04 | OPEN — acceptance | Define paid/unpaid break policies and working/available/talk/wrap-up/idle time explicitly. Report unknown/incomplete intervals; never infer payroll hours from SIP registration. Reconcile totals and test exports, corrections/audit trail, retention and sensitive-data access. |

## Queue features, voices and APIs

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| ACDC-01 | OPEN — API + UI | Unified queue create/edit/read: complete bounded catalogs, revision/conflict handling, authorization, safe replay and explicit partial-write recovery. Prior isolated tests passed; restricted-token/roster-failure coverage remains. |
| ACDC-02 | OPEN — UI | Reliable Callflows ACDC action and internal extension routing; dropdowns instead of technical free-text fields; default prompt selection must not trigger required-field errors. Preserve existing customer recordings. |
| ACDC-03 | OPEN — ACDC | Verify/build supported ring strategies: ring-all, ordered, round-robin and existing alternatives. Resolve simultaneous-answer/DTMF exit ownership candidates; test fairness, single winner and cleanup. |
| VOICE-01 | OPEN — media + UI | Finalize EN/HE/AR/FR/ES prompt-language override, queue/call/account defaults and reseller/sub-account inheritance; report incomplete packs rather than enabling unverified choices. |
| VOICE-02 | VERIFIED — packaged assets only | Existing 165 effective Gemini entries / 330 WAVs and transcripts/provenance are committed and hash-verified. Shared system media is reusable; this is not five-language playback certification. |
| VOICE-03 | OPEN — media | Build voices once into versioned shared artifacts for all present/future accounts and sub-accounts. No Gemini generation during installation, account creation, queue editing or calls. Finish missing numeric/auxiliary audio and native listening checks. |
| VOICE-04 | BLOCKED — operator | Agree supplemental generation scope/budget and native-language acceptance; no extra provider calls have been made under an assumed approval. |
| API-01 | VERIFIED — single-server scope | Supervision eavesdrop/whisper/barge/join and stop have prior isolated audio/auth tests and OpenAPI entries. Cross-node/failover/real-traffic acceptance remains OPEN. |
| API-02 | OPEN — API | Company members with owned devices/types/fresh registration state. Existing implementation has scoped tests; complete restricted-token, cross-account, expiry and large-inventory coverage. Keep SIP online distinct from queue eligibility. |
| API-03 | ACTIVE — documentation | Updated repository catalog validates 354 paths / 649 operations; full deterministic-regeneration/tamper suite and 9 queue-login groups / 45 schema cases pass. Target ancestor/hardlink protection committed `2316f27`. Publish reviewed assets at `/apis` and browser-test; keep proposals/gaps explicit. Portal presence alone is not endpoint acceptance. |

## Installer, deployment and release

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| INST-01 | OPEN — installer | One modular install entry point: CouchDB, RabbitMQ, HAProxy, Kazoo apps, eCallMgr, Kazoo FreeSWITCH, Kazoo Kamailio, Monster UI and ALL; automatic pinned dependencies, configuration validation and enabled/running named services. |
| INST-02 | VERIFIED — current-host scope | Named services and `kazoo-applications` compatibility alias exist; Pivot port reservation, test-phone startup preservation and requested SUP alias repaired. Reboot/custom-root/clean-server regression tests still required. |
| INST-03 | ACTIVE — installer | Kamailio verifier repair committed `aff66d3`: 11 regression groups and live `--verify-only kamailio` pass; recovered startup JWT failure remains an explicit warning, later/unrelated errors fail, service identity unchanged. Finish combined all-module verification after remaining deployment; verify source/export availability and configuration/transport readiness. |
| INST-04 | ACTIVE — browser acceptance | Monster production `preloadApps`/`preloadedApps` mismatch corrected. Fresh guarded build and independent readback passed: 1,931 files, 465 compiled templates, 16 canonical preloads; receipts in `doc/post_reboot_acceptance_20260906.md`. Actual writer/reader contract and offline preservation suites pass. Isolated browser acceptance, fresh adoption/provenance plan and matched backend integration are still required before publishing; clean-server dependencies remain unverified. |
| INST-05 | ACTIVE — build | Post-build artifact verification is wired before activation and included in the fingerprint; modular fixtures with/without ACDC pass. eCallMgr no longer trusts stale `.app` files: current-invocation build reuse, environment reset and failure-before-activation fixtures pass. Full real repeat deployment remains required. |
| INST-06 | OPEN — deployment | Publish reviewed matching source/backend/UI with exact backups, preserve unselected apps/config/customer data and record rollback. Two media/editor backend modules updated; compiled UI publication remains held. |
| INST-07 | OPEN — acceptance | Clean Rocky Linux 9 install, each module alone, all-in-one and separated hosts; hostname/address/configuration variations, reboot, repeat install, upgrades and failure recovery. No clean-server success is claimed yet. |
| SEC-01 | BLOCKED — operator | HTTPS `kz5.talkchief.io`: supplied certificates have no matching private key in `/root/ssl`; provide protected matching key or explicitly authorize replacement issuance. Validate WSS and TLS renewal afterward. |
| SEC-02 | OPEN — operations | Network exposure, least privilege, secrets, SELinux policy, auth/tenant isolation, audit logs, backups, retention, monitoring/alerts and resource/disk limits. Do not equate active services with enterprise certification. |
| LOAD-01 | OPEN — acceptance | Resolve prior memory/AMQP incident; rerun sustained 30 concurrent calls and full drain, then establish measured capacity. Distinguish concurrent calls from calls/second; 80 CPS is not certified. |
| HA-01 | OPEN — acceptance | Backup/restore, failure injection, multi-node ownership, distributed queues/broker/database failover, reconnect and no duplicate callbacks/bridges. |
| REL-01 | OPEN — release | Review and credential-scan all task changes, commit source/tests/assets/docs and record exact build/test evidence. Update this register rather than marking untested features done. |
| REL-02 | BLOCKED — operator | Configure fresh protected GitHub write authentication; push reviewed commits and verify remote SHA. No successful latest push is claimed. Never reuse the exposed chat token. |

## Work order and release rules

1. P0-01/P0-03/P0-04 in parallel source work, with serialized resource-capped tests.
2. P0 live acceptance without interrupting operator calls or changing rosters
   without an explicit selection; queue-login API and UI ship together.
3. Correct production UI build and installer gates; matching deployment/browser
   checks; complete language handling without recurring TTS calls.
4. DASH-03/04/05 establish trustworthy data/events, then DASH-01/02; historical
   and workforce designs follow with validated interval/metric definitions.
5. Clean/distributed installation, security, sustained load, restore/failover and
   authenticated remote release. Document external blockers, not fictitious passes.
