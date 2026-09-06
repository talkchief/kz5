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

## P0 — call delivery and callback correctness

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| P0-01 | ACTIVE — API + UI | Queue-specific Login: explicit queue selector, account/agent/queue authorization, membership validation, retry-safe commands and pending versus runtime-confirmed result. Show actual queue logins; no silent roster changes or other-agent logout. Update OpenAPI and test selected-agent ringing. |
| P0-02 | OPEN — acceptance | Re-test extension 2000 after the operator selects the intended queue agent. Observed roster Agent 12 logged out; globally ready Agent 19 unassigned; runtime knows no eligible agents. Do not reset all agents to conceal the mismatch. |
| P0-03 | ACTIVE — callback | Key 6: handle invalid/nonnumeric return caller ID, alternate-number entry and clear failure audio. Register durably before success audio, finish audio before BYE, retain position, return call, ignore first attempt and verify retry. Reproduce the actual MicroSIP path. |
| P0-04 | ACTIVE — callback | Callback offer at configured 30 seconds: separate enable, initial delay and repeat interval from position/wait/generic announcements; verify saved values, runtime schedule and received audio. Invalid return numbers must not cause silent failure. |
| P0-05 | OPEN — ACDC | Agent stability: one answered call must not log unrelated agents out. Test failed ringing, reconnect, queue-specific logout, pause/resume and reboot recovery. |
| P0-06 | OPEN — ACDC | Resolve retained ambiguous callback cleanup/reconciliation ticket without losing evidence or falsely marking a live leg settled. |

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
| API-03 | OPEN — documentation | Keep source-derived `/apis` catalog current for all implemented APIs, explicitly list proposals/gaps, include errors/auth/examples and prevent secret leakage. Portal presence alone is not endpoint acceptance. |

## Installer, deployment and release

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| INST-01 | OPEN — installer | One modular install entry point: CouchDB, RabbitMQ, HAProxy, Kazoo apps, eCallMgr, Kazoo FreeSWITCH, Kazoo Kamailio, Monster UI and ALL; automatic pinned dependencies, configuration validation and enabled/running named services. |
| INST-02 | VERIFIED — current-host scope | Named services and `kazoo-applications` compatibility alias exist; Pivot port reservation, test-phone startup preservation and requested SUP alias repaired. Reboot/custom-root/clean-server regression tests still required. |
| INST-03 | OPEN — installer | Finish actual all-module verification: positively classify recovered Kamailio JWT startup retry without hiding later errors; verify source/export availability and configuration/transport readiness. |
| INST-04 | OPEN — build | Monster production `preloadApps`/`preloadedApps` mismatch found by browser preview. Integrate source writer fix, compatible preservation gates, corrected artifact/provenance and browser tests before publishing. |
| INST-05 | OPEN — build | Wire post-build artifact verification into installer, support selected app sets, prevent stale eCallMgr `.app` files being mistaken for a current-source build, and test repeat deployment. |
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
