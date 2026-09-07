# Kazoo 5 project task register

New or returning contributors: read [the engineering handoff](PROJECT_HANDOFF.md)
first for achieved work, deployment status, source locations and next steps.

## Handover checkpoint — 2026-09-07

Keep this register current whenever implementation, deployment, testing or a
blocker changes. Each task must retain its stable ID, requested behavior,
source/document locations, evidence, remaining acceptance and next action.
Distinguish source complete, deployed, verified and remotely delivered; do not
close a task on a unit-test pass alone. Older snapshots below are historical;
the latest engineering handoff takes precedence for current deployment state.

- **UI-02 complete:** removed user-facing “observed” wording; progress labels
  and duration heading read “In Progress.” Deployed and browser verified.
- **P0-25 deployed, acceptance incomplete:** bounded reads and app-loader race
  fixes pass initial view, account switching and four reconnect scenarios.
  Controlled real HTTP stall/recovery/disposal now passes nine deployed-browser
  checks05bc67/65a97a and eight offline groups51b9fc/830c4a. Next: delivered-late
  JavaScript callbacks and never-settling loader delivery (transport cancellation
  is not execution of a late callback). See `doc/monster_live_http_stall_acceptance.md`.
- **P0-26 deployed, acceptance incomplete:** actual queue creation returned201;
  saved settings were read back and the exact test queue was removed. Next:
  browser edit/PATCH, validation failures and uncertain-operation recovery.
- **P0-22:** actual queue membership confirmation now passes in the browser;
  error recovery remains to be accepted. Preserve the working login mutation.
- **DASH-10 source candidate under validation, not deployed:** privacy-safe
  caller Name/Number now flows through the selected-queue collector, native
  codec, public API, UI and OpenAPI source. Null/legacy identity displays
  `Caller unavailable`, never a UUID. Upstream10, collector50, native36,
  public-route30 plus2 helper tests passed;51 actual handler DTOs pass schema
  validation. Source Chromium27 groups pass, including caller escaping and
  bounds. See the newest handoff for evidence and coordinated record-migration
  gate; generated/served OpenAPI and installed code are still unchanged.
  Retained-table migration helper11 and staged lifecycle10 tests now pass
  `68e9e6/c09393` and `5e37b0/2a5f12`, including real named ETS transfer and
  deferred native listener activation. Before live deployment: old responder/
  archive-worker drain, direct-reader admission and coordinated replacement.
  Maintenance `find_call/1` admission is now source-tested: before/after ready
  owner checks pin the exact tid and reject missing/legacy/replaced/revoked or
  timed-out sources; unavailable maintenance never publishes abandonment.
  Root startup16 groups pass `156530/e8b860`, with13 fresh production compiles,
  evidence `/tmp/kazoo-stats-startup.fTo5ct`. Not deployed. Remaining dynamic
  callback admission and actual old-worker drain/replacement still gate release;
  source-only drain helper work is not yet accepted or included in this proof.
  Installer readiness is now source-tested too: `acdc_maintenance:stats_ready/0`
  requires the same admitted stats child and true native broker consumption;
  `verify_kazoo_apps` polls the protected RPC and accepts only exact `ready`
  with exit zero. Root startup17 groups `8ecdb9/dff757`, installer5 groups
  `e8f999/b6a8d2` and read-only safety `f77e99` pass. Not deployed; actual broker
  ACK, safe retained-table replacement and fresh/split-host acceptance remain.
- **P0-25 additional source fix, not deployed:** initial pending dashboard
  views now own a disposal observer too. A detached loading view previously
  allowed its watchdog to overwrite the replacement screen. Reproduced in
  `13d01d/bc2755`; fixed in `monster-ui/acdc/app.js`, with27 source-browser
  groups passing `e76537/e3eaaa` and explicit delivered-late callback coverage.
  This is controlled source-browser proof, not deployed transport acceptance.
- **Live idle viewer acceptance passed; soak/failure acceptance pending:** harnesses are at
  `scripts/test-queue-live-load.cjs` and
  `scripts/test-queue-live-load-offline.cjs`. Root14 offline groups pass
  c3b213/5709e0; actual2/10/30 viewers each pass30 seconds full cohort, with
  fresh complete snapshots and exact subscription cleanup. See
  `doc/queue_live_viewer_load_acceptance.md`. Viewer load does not prove call
  capacity. Extended30 viewers also pass180 seconds/391 fresh snapshots/zero
  errors, HTTP p95=97.5ms (2fbd95/90d1e4). All load jobs are terminal; real
  call/event load, cross-node failure and sustained soak remain open.
- **UI-01 storage404 remains open.** Callback/voice issues remain recorded but
  paused under the live-dashboard priority; historical/WFM work is postponed.
- **Checkpoint published:** user requested periodic master pushes;135 committed
  changes were fast-forwarded to remote `master` at `4197917` on September7
  (push6ca149/f6e250, independent remote readback79d4e7). The working branch is
  now `master`, with in-progress changes preserved and excluded from that push.
  Final release acceptance remains pending. Untracked bridge source
  under `services/push-bridge/` is not an accepted installable service (INST-13).
  Fresh standalone/distributed/ALL installer acceptance and release gates remain.
  Subsequent verified remote checkpoints include caller candidate `ccd31c0`
  and staged migration `87ed290`; neither changed the installed runtime.

See [PROJECT_HANDOFF.md](PROJECT_HANDOFF.md) for exact build/deployment evidence,
rollback locations, protected fixture holds and safe resumption instructions.

**Current priority — 2026-09-07:** only the live queue summary and selected-queue
detail dashboard are being finalized. Callback/voice work is paused; the
reported key-6 and30-second announcement failures are unresolved. History,
ClickHouse, WFM and the separate agent dashboard remain postponed. Older ACTIVE
labels below describe unfinished work, not authorization to resume those areas.
Current deployment and acceptance evidence is at the top of PROJECT_HANDOFF.md.

Live isolation checkpoint: all17 actual HTTP/native Blackhole permission cases
pass (`573eb1`/`0d57c2`) with4 genuine nonadmin principals. Corrected harness
passes41 offline groups/180 rejection checks, including real shared-lock
contention. Nine owned fixture resources remain under a permanent automatic-
cleanup hold because the first fourth-login response was uncaptured; explicit
resume did not create more resources or change auth limits. Restricted-user
browser, load/cross-node and reviewed fixture cleanup remain open. See handoff.

Latest continuation checkpoint: callback source `a75806c`, French catalog
`2325d9b`, Hebrew catalog `98f62cf`, Arabic catalog `9773c35`. All five pure
grammars passed79,465 checks in20652; contextual transcript review, missing
recordings and runtime integration remain open. Private native transport and
normal-codec work, exact receipts and unresolved review findings are indexed in
[the native continuation guide](doc/callback_native_vertical_slice.md).
Those private files are not yet reproducible from a fresh kz5 clone and their
admission gates remain hard closed. No new runtime deployment or master push
is established by this documentation checkpoint.

Subsequent work-in-progress snapshot (after local `57b55e1`): the cardinal
manifest/WAV verifier and deterministic resampling check are being authored;
the private RTP/codec derivative compiled two production units in13529 but has
no crypto/UDP/live-call acceptance; SIP signal-processing reservations remain
under implementation; installer atomic-intercept baseline reconciliation is
uncommitted and awaiting tests. Owners, paths and next steps are in
[the latest handoff snapshot](PROJECT_HANDOFF.md#latest-working-snapshot--read-before-resuming).
These are existing voice/P0-03/installer workstreams, not additional completed
features. No backend/UI/native deployment or final master push accompanies this
documentation update.

Updated: 2026-09-07. This is the project-wide priority/status index. Detailed
incident evidence remains in [deployment tasks](doc/deployment_tasks.md) and
[acceptance status](doc/kazoo5_acceptance_status.md); earlier passes are scoped
evidence, not proof that later regressions or production acceptance are closed.

Statuses: **ACTIVE** = implementation/investigation underway; **OPEN** = not
accepted; **BLOCKED** = named external input needed; **VERIFIED** = only the
explicitly stated test scope. An item is complete only when its source,
installer integration, API documentation and relevant tests agree. Changes must
be committed and pushed before the delivery is reproducible from the remote.
Final delivery target requested by the operator: `master`. Integrate reviewed
work without discarding team changes or force-pushing; verify the destination
and remote state before publishing. Fresh per-module, ALL and distributed-server
installer acceptance remains required, not inferred from unit tests.

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
with no deployment or restart. Independent combined testing now passes all 48
unit tests, all 26 strategy tests in two disjoint guarded groups, and six
expanded source-ownership groups. Remaining integration checks are still being
revalidated;
this is not live-call acceptance. Regenerate affected API coverage and run
combined call-delivery/callback regressions before release. The private callback
audio adapter still needs native completion, cancellation and owner-handoff
proof before promotion; the handoff does not waive those safety gates.

## P0 — call delivery and callback correctness

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| P0-21 | DEPLOYED — restricted-user acceptance open | Corrected legacy module spelling with an admin-only management guard. Installer refuses old unguarded backends and preserves unrelated modules. Installer22groups66cc53/cea08b and backend7groupsbcc947/c5cf88 pass; pinned baseline fails5. Deployment209651/1e3fc6 verifies actual bytes/capability/running+effective registration and unchanged31-agent states. Actual admin policy CRUD revision probe7c9f07/47ce1f passes stale412, weak412 and current-delete200+absence. Earlier run2 policy retained after harness POST-replacement mismatch. Ordinary-user HTTP denial and restricted-dashboard matrix remain unverified. See doc/scope_management_dashboard_acceptance.md. |
| P0-22 | ACTIVE — login verification UI | September 7 operator corrected the report: Login DOES work, but UI says login cannot be verified. Root read-only HTTP proof confirms Agent12 ready/runtime_member=true/runtime_observed=true/state=confirmed; selected-queue live independently agrees. Diagnose actual served UI proof requests, handling and stale navigation without changing the working login mutation. No roster write may be reported as login confirmation. Prove actual dialog confirmation and error recovery, other-agent preservation, installer integration and matching OpenAPI. |
| P0-25 | FIXES DEPLOYED — scoped browser PASS; outage acceptance open | September 7 indefinite loading traced to both unbounded GET waits and overlapping native app construction clearing ACDC translations. Bounded GET fix is deployed; installer-owned singleflight patch b02f7fe passes16 actual-loader groups including original failure reproduction. Fresh production MwsDYg bundle deployed ec9a75/9f9af6. Initial dashboard/login-dialog probe passes without page errors3ff064/eefb87; standard default and account-switch production probes pass7/10 checks e5b91d/2241b2 and45576a/e20ac1 with zero page/console/HTTP errors. All four home/switched summary/detail reconnect cases pass7/9/10/12 checks with zero errors; receipts hltOHJ,jDrUgY,hcjYc6,2rApWe. Controlled unavailable-API/late-reply browser recovery and never-settling loader behavior remain open. See doc/monster_app_load_singleflight.md. |
| P0-26 | FIX DEPLOYED — actual create/readback PASS | September 7 repeated PUT /queues/editor400 logged editor_body_requires_exact_fields; actual Monster serializer adds unwanted ui_metadata. Local requestQueueEditor opt-out preserves strict five-field backend body, request identity and explicit retries; eight real-serializer fixture groups pass e412fe. Matching UI deployed6d7352/d9a24c. Actual form PUT created one owned empty-roster/no-extension queue with HTTP201 (7f91f3/816240); harness incorrectly expected200, but completed operation was durably captured. Recovery09a4d6/131789 verified saved settings/empty roster/no callflow, deleted exact owned queue and confirmed404; no create retry. Receipt retained. Validation failures, PATCH and uncertain receipt recovery remain open; normal owned cleanup is not conditional-delete proof. |
| UI-01 | OPEN — storage capability404 | September 7 browser /accounts/{ACCOUNT_ID}/storage GET returns404, reproduced by root. Identify the requesting Monster component and whether storage is absent/unsupported or misconfigured. Gate optional lookup on supported capability or configure the actual feature; do not fake success or assume it causes the independent queue-editor400. Verify affected settings retain correct availability/error behavior and clean initial browser loading. |
| UI-02 | CLOSED — deployed and browser verified | September 7 user requests removing observed wording and renaming Elapsed in progress to In Progress. Plain user-facing dashboard labels now use Waiting, In Progress, Ready, Member and Active calls; technical API field names/metric semantics stay unchanged and unknown/stale/partial warnings remain. Root52 dashboard groups pass078c38/a26140. Matching production build130be8/b8aff7 and owned deployment6d7352/d9a24c passed. Fresh actual browser cbf2ed/80cbbf verified all dashboard values omit observed, visible Waiting/In Progress, and duration heading In Progress. See doc/acdc_ui_stabilization_20260907.md. |
| P0-23 | CLOSED — focused production regression verified | Added missing content_types_provided/2 fallback and /3,/4 handlers, preserving stats JSON/CSV and route authorization. Production-metadata current build7a109c/575d77 passes6; baseline db933c/8dfe10 fails3 and matches installed old normalized forms39d866. Actual six queue/detail/live/roster/editor reads produced6 error-log entries499e52/b61caa. Deployed only cb_queues without service restart0c9f54/84b347, verifying installed bytes/runtime MD5/exports. Identical six reads then returned200 with zero appended error lines da07ec/86d759. Backup /tmp/kazoo-queue-types-deployment.XS9QCz. This closes the missing-handler defect, not general cluster/log reliability. |
| P0-24 | DIAGNOSED — caller configuration; acceptance open | September 7 callback tests at 08:12:33 and 08:15:39 UTC explicitly reject invalid_number before registration. Correlated calls have caller ID number `kz5_test` (SIP username, not a dialable number); the queue has allow_alternate_number=false. The unavailable prompt and staying in queue are correct for that input. Configure a real authorized callback destination or explicitly allow alternate-number collection; do not weaken number/routing validation or claim callback success. Re-test registration, confirmation media, outbound attempt and retry with a valid destination. |
| DASH-10 | ACTIVE — tested source candidate; migration/deployment open | Caller Number/Name instead of visible UUID is implemented in checkpoint ccd31c0 through privacy marker, bounded selected collector, native codec, public DTO, UI and OpenAPI source. Names/numbers are nullable, limited to256/64 UTF-8 bytes; missing legacy provenance is unavailable, not invented identity. Occupancy survives invalid metadata, replica disagreements withhold snapshots, internal call_id remains for identity/actions, and text is escaped. Overview and WebSocket hints carry no caller identity. Upstream10, collector50, native36, public30+2 and source-browser27 tests pass;51 handler DTOs pass schema. Actual deployment and authorized normal/private call display remain unverified. The appended stats field requires a retained-ETS migration and complete reader/writer cohort; see doc/dashboard_caller_identity_upgrade.md for implementation, test evidence and admission/drain gates. |
| P0-18 | DEPLOYED — scoped acceptance PASS | Explicit background Core plugin loads preserve foreground marker/shortcuts; normal foreground/callback/error behavior retained. Installer-owned patch passes12 regressions and reproduces failure before fix. Fresh OxxzgK build/deploy e175b8/e8e212; only2 files changed,1942 preserved,0 removed. All four same-account/switched summary/detail reconnect browser checks pass; active-app and same-controller assertions retained. Native startup readiness and redundant-route handling corrected in harness. New real summary call passes9 checks,2 visible queues/3 hints/one bridge/12 stable samples; exact31-agent state comparison279769 unchanged. See doc/monster_background_app_load.md and doc/monster_live_reconnect_acceptance.md. Restricted/no-default non-admin, cross-node/load and TLS acceptance are not implied. |
| P0-19 | DEPLOYED — source/HTTP/primary-CAS PASS | Installer-owned patch preserves the validated revision and rejects invalid revisions before writes. Nine controlled groups and ten private-Cowboy HTTP cases pass; both HTTP races reproduce204 instead of409 on baseline. Native primary CouchDB checks pass b3c7e1/2a0330. Two-module deployment489b41/b291e2 verifies actual loaded bytes and unchanged31-agent states, with backups at `/tmp/kazoo-revision-deployment.19HpQo`. Full resource acceptance stopped before writes at P0-21; cluster behavior/token lifecycle remain open and restricted-dashboard admission stays closed. No cascade/queue-activation transaction claim. See `doc/crossbar_soft_delete_revision.md`. |
| P0-20 | DEPLOYED — real-primary regression PASS | Native single Couch deletion passed through HTTP201 bulk conflict rows as success; baseline687399/f72f2d reproduces. Required installer patch classifies single-delete rows, preserving valid/legacy shape and transport errors; batch/non-Couch paths unchanged. Nine focused groups pass; baseline fails six. Actual primary soft/hard conflict/body/no-success-hook checks pass b3c7e1/2a0330. Deployed489b41/b291e2 on apps/ecallmgr with exact runtime hashes; only these services restarted and all31 agent states preserved. Three synthetic databases retained, two with baseline documents. Full resource/cluster acceptance remains open. See `doc/couch_single_delete_result.md`. |
| P0-14 | FIX DEPLOYED — focused/runtime regression verified | Dashboard agent-read authorization accidentally raised `function_clause` on ordinary status POST, producing live HTTP500 and blocking isolated-agent restoration. Canonical `cb_agents` now abstains for ordinary actions; global authorization remains required. Baseline90610 reproduced two failures; candidate93704 passed all6 focused groups. Production build4341 compiled74ACDC/30Blackhole modules; only `cb_agents.beam` deployed59362. Real status restoration74067 and fresh preflight10698 passed. Existing restart callback contract is unchanged, not independently proven as an HTTP veto. |
| P0-15 | FIX DEPLOYED — isolated natural-call transition PASS | Baseline43165 physically connected but51valid snapshots stayed waiting. Canonical asynchronous reciprocal-channel proof now requires the selected agent/process and complete answered, mutually linked same-switch observations; no handled inference from acceptance alone. Fresh production build2519 compiled74ACDC/30Blackhole;29023 deployed only the matching FSM with retained backup. Actual call79231 passed waiting→handled→gone with fresh hints/later GETs:15/15valid snapshots,3native invalidations,0timeouts,1offer/bridge,12stable FS samples and exact subscription ACKs. Cleanup restored original3agents, removed owned resources/contacts, left no ledger/FS calls and all8services active. Focused6/root86399, I/O16/root26126 and prior31 strategy groups passed. See doc/acdc_ordinary_bridge_proof.md. Browser call rendering, restricted-user/cross-node/soak proof and conservative unresolved-state liveness remain separate. |
| P0-16 | DEPLOYED — scoped regression verified | Bounded redacted binding diagnostics preserve dispatch exceptions. Canonical installer patch; exact replay passes. Current063784 passes12 tests (8 sink +4 real production-Lager runtime), pinned baseline20b15f fails12; three noTEST production modules compile with -Werror. Deployment be1cb5 verified installed SHA and loaded MD5 on apps/ecallmgr after an initial verifier-permissions failure/rollback. Isolated postdeploy call befb40 passed13 snapshots/3 hints/one bridge/12 stable samples and cleanup; MASTER state unchanged. See doc/kazoo_bindings_exception_diagnostics.md. This is not a whole-log, load or production-readiness claim. |
| P0-17 | FIXED — development browser verified | Early picker clicks reached a partial Common context (`getTemplate` unavailable). Installer-owned readiness patch passed14 actual-Core groups98957 (including old-code reproducer), preservation44606 passed11, corrected wiring95129 passed12 and browser-scope fixture3e50c7 passed16. Fresh production build74495 deployed85061; owned verification10382 passed. Actual default browser74850 passed7 checks and switched browser69219 passed10, including exact home unsubscribe before target, target summary/detail and normal home restoration. Both had zero console/page/HTTP/scope errors; all8 services active, zero calls. No account/queue provisioning. Browser call rendering, restricted principals and soak are separate open gates. See `doc/monster_account_picker_readiness.md`. |
| P0-01 | ACTIVE — API + UI | Queue-specific Login: backend committed `4fc2a2b` with 12 isolated regression groups passing and exact fresh pinned installer-patch replay; explicit-selection UI committed `d263342` with focused/full contract passes. Source-bound OpenAPI overlay/reference committed `22b5f94`, with 9 focused groups / 45 schema cases passing. No silent roster changes or other-agent logout; membership is not readiness. Regenerate/publish `/apis`, deploy and test selected-agent ringing. |
| P0-02 | OPEN — acceptance | Re-test extension 2000 after the operator selects the intended queue agent. Observed roster Agent 12 logged out; globally ready Agent 19 unassigned; runtime knows no eligible agents. Do not reset all agents to conceal the mismatch. |
| P0-13 | SOURCE FIX TESTED — deployment open | Live dashboard review found the outbound FSM emits `outbound` in sync replies, but `kapi_acdc_agent` excluded it from the reply status enum. The legitimate state is now accepted. Root38933 passed3 baseline groups reproducing the actual serializer/publisher failure and11 candidate groups, with broker publication substituted; evidence `/tmp/kazoo-agent-sync-status.xBuTWi`. The listener invokes that publisher synchronously, creating a potential restart path before the fix. Real listener/restart, live-call acceptance and deployment remain separate; no confirmed live crash is claimed. |
| P0-03 | ACTIVE — callback | Key 6: identified queue audio starved behind endless hold. Private immediate-audio candidate passed 58 distinct offline cases, but source review found synchronous native playback behind a five-second RPC timeout and blocked call-control handling. Candidate deployment is held for correction/native boundary proof; offline passes do not close this risk. Handle invalid return caller ID clearly; durable registration before success audio/BYE, position retention and unanswered-first-attempt retry require live acceptance. |
| P0-04 | ACTIVE — callback | Callback offer at configured 30 seconds: separate enable, initial delay and repeat interval from position/wait/generic announcements; verify saved values, runtime schedule and received audio. Invalid return numbers must not cause silent failure. |
| P0-11 | ACTIVE — source fixed; deployment open | Announcement worker mailbox starvation: elapsed deadlines now run before another receive; pre-playback event drains stop the temporary worker after 256 handled events plus one overflow probe. Two regressions failed before the fix; all 12 scheduler/worker tests and production-warning compilation pass afterward. No caller hangup, global media flush or worker restart is added. See doc/acdc_announcement_mailbox_fairness.md. This does not resolve audio behind endless hold, native ownership or live 30-second offer acceptance. |
| P0-12 | ACTIVE — source regression verified; deployment open | Removed synchronous auxiliary metadata lookup from timed unavailable/retry/alternate branches. Built-in preflight retains its three auxiliary paths from42 reads; legacy custom menus preflight three optional assets before queue entry. Missing cache fails quietly without fallback or false registration. Guarded6821 passed22 focused tests; full75590 exited0 with all87 tests and stable input digest5bcd7e76678f42988001ad768c391fd272401d2ec8b6d4b48eab975a73759ea8. Tests poison resolver/datastore access, check30ms budgets and preserve actual21s deadline/ownership/completion cases. Not yet deployed; this does not bound arbitrary synchronous publishing or resolve native audio. |
| P0-05 | OPEN — ACDC | Agent stability: one answered call must not log unrelated agents out. Test failed ringing, reconnect, queue-specific logout, pause/resume and reboot recovery. |
| P0-06 | OPEN — ACDC | Resolve retained ambiguous callback cleanup/reconciliation ticket without losing evidence or falsely marking a live leg settled. |
| P0-10 | ACTIVE — source fix; live acceptance open | Operator report: key 6 played "unable to perform action" and ended the call. Read-only logs show two 14:29 UTC invalid-number fallback crashes in cf_acdc_member: nested Request access raises badarg on ordinary SIP-address metadata. Three matching regressions reproduced in `22426`; typed/lazy lookup fix passes all 17 feedback tests in `9643`, including resuming the same member without cancellation or false success. See doc/callback_feedback_request_crash.md. This does not prove every reported key-6 failure or persisted ticket state. Deployment, spoken feedback, safe fallback, durable successful registration, subsequent callback and unanswered-first-attempt retry remain open. No new live calls were placed. |
| P0-07 | ACTIVE — staging acceptance | Team recovery fix `d69cf04` merged in `8548b98`; combined 174 tests and 63 production-module compile passed. Bounded reconciliation must now be validated with actual lost/late hangups, multiple direct calls and node reconnect. Never mark an agent available while another tracked call is active; preserve pause/logout and membership. SIP registration alone is not recovery proof. |
| P0-08 | ACTIVE — staging acceptance | Team AMQP recovery fix merged and covered by the combined offline checkpoint. Actual broker interruption, lost acknowledgements/redelivery and node failures remain untested: prove no permanently stuck ringing state, duplicate bridge, stolen call or unrelated agent/roster mutation. Broker acceptance alone must not count as completed state recovery. |
| P0-09 | OPEN — ACDC policy + UI/API | Repeated connection failures can automatically log agents out (operator review finding). Distinguish intentional configured protection from unintended logout; define configurable thresholds and recovery behavior, expose the reason/current state through API/UI and document it in OpenAPI. Test threshold boundaries, transient failure, successful-call counter reset, reconnect and explicit operator logout. Do not silently disable unreachable-agent safeguards or automatically override an intentional logout. |

Native callback candidate review remains part of P0-03, not a completed fix:
revocation acknowledgement is not proof that the full native playback stack has
finished. Bridging must reserve both call legs and wait for actual completion
before side effects. A candidate owner-change-away-and-back race also requires a
non-reusable binding generation in both native state and wire requests. The
earlier ten-test/eight-wire-shape codec proof does not cover that new field or
native transport. Core/module lifetime, exact bridge-end release, stale requests,
native build/link and real audio acceptance must pass before promotion.
Private core-source session `19793` passed nine groups plus real-header syntax
checks, including owner-generation reuse, admitted-write quiescence and exact
bridge-ticket release. The core native dispatcher and actual bridge/end caller
hooks are still being implemented; these private proofs do not certify deployed
callback behavior or constitute an installer-ready patch.

Private correction session `47373` passed 14 extracted native cleanup fragments
in four lifecycle modes, a pure C resource classifier/cache-extension check and
56 local Erlang renderer/coordinator tests. Five private production modules
compiled; 20 source and 311 dependency inputs remained unchanged. Receipt:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/owned-resource.ZG05KT/scoped-resource-proof.OeKZXh/receipt.json`,
SHA-256 `91759d38b0c7700e75756130cc47d9965669ce4d3257476f359d8b91f8cd027f`.
This tests scoped cleanup and unsupported-versus-quiescent outcomes, **not**
full native playback, accepted output, transport or callback completion. Native
admission remains closed in that private proposal. Actual atomic media output,
Sofia/RTP failure propagation, bridge callers and live audio remain required;
the next private implementation targets accepted owned G.711 output.

The next private source-fixture run `7180` passed 11 groups in each of plain
and ENABLE_SRTP configurations, including actual core PCMU/PCMA encoding through
the extracted RTP common-write function to an intercepted local socket send.
All 20 source, 16 native and 102 captured dependency inputs remained stable.
Receipt: `/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-write-extractor.DmBWMY/write-proof.1L5N2k/receipt.json`,
SHA-256 `3584e1a176d1f283e55c96efb08530ed9c09cb23d7a4c1982e95ccdd38c885c8`.
The preceding `8530` compile failure was an extractor replacement-string bug,
corrected in a separate retained derivative; it executed no fixtures. Native
dependencies remain explicit substitutes, not full ABI/thread/pool/crypto proof.
Admission is still closed: early codec destruction, RTP mutation/teardown
reservation, every bridge entry/end (including arranged bridge resume), real
native build/link, hold/SAY continuity and live audio acceptance remain open.

Private codec-entry/read-retry session `11226` subsequently passed seven source
fixture groups: all eleven setter exits, recursive/foreign-thread conflicts,
full-playback completion versus revoke/frame acknowledgements, admission fencing,
exact ticket release and all four direct setter call sites. Read-reset retries
retain the pending request and use the existing paced 20-ms CNG path. Receipt:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-codec-fence.E48ZvD/codec-proof.Fi7LWs/receipt.json`,
SHA-256 `cde65bf202404b402fff4dea4a67c7ddb3aba49e72bfb38e2fad55cf62466849`.
The receipt is explicitly complete with stable source/native/dependency inputs.
This uses reduced native dependency fixtures, not real ABI/link/transport or
sanitizer acceptance. Earlier SDP/recovery payload changes and broader RTP/bridge
lifecycle protection remain unresolved; native admission remains closed.

Full-translation-unit real-header compilation `13867` now passes all fifteen
private C units with configured flags and `-Werror`, including mod_kazoo's three
version consumers. A pre-existing generic `VERSION` collision was reproduced and
fixed by a four-identifier module namespace patch, now wired into the installer.
All 464 compiler-selected dependencies and source/path identities were stable.
See [native compilation and installer evidence](doc/mod_kazoo_version_namespace.md).
This is compilation only: no native linking, module loading or live playback,
and it does not close the resource, RTP, bridge or callback acceptance gates.

Actual PIC/link run `90804` subsequently compiled all fifteen units and linked
the private core and Sofia libraries, then failed the Kazoo link because the
test's explicit command omitted normal libtool dependency-library expansion
(first missing direct dependency: libcurl). All 853 input hashes and 913 path
identities were stable. This is a failed overall proof; the test-command
correction must be revalidated without weakening undefined-symbol checks.
See [native link readiness](doc/callback_native_link_readiness.md), including
the concrete unopened SAY, media-lifetime and bridge-caller gates.

The complete corrected private build checkpoint `22624` now passes all fifteen
fresh PIC compilations, three strict links and core/Sofia/Kazoo ELF checks, with
865 input hashes and 925 path identities stable. Native library-dependency
expansion and the test's incorrect public-export expectation for an internal
classifier were corrected; no C/header/visibility or warning checks were changed.
Receipt SHA-256:
`c4c563de93afc3686cafec076b7d48bed69b3047e69fb2ad2698c723dc684912`.
The resource guard first refused 384 MiB; the successful run lowered the cap to
320 MiB while preserving the 768-MiB reserve. This is incremental linking with
pinned cached unchanged objects, not a cold build or runtime acceptance.
Nothing was loaded or deployed; public callback-audio admission remains closed.

Private typed-SAY integration is now in progress in `native-say-scope.MfDQMl`:
bounded numeric WAV leaf/list/path validation passes strict C compilation and
ASan+UBSan fixtures (run `a81ab7`). The three complete root-owned translation
units pass preliminary real-header `-Werror` syntax checks (`fcc723`). Loader
lease/shutdown review, integrated link/runtime tests and packaging remain open;
these changes do not inherit the earlier fifteen-unit link acceptance.
The user authorized missing test tools; distro `libasan` and `libubsan` were
installed without service restarts. See
[typed SAY checkpoint and validation dependencies](doc/callback_typed_say_readiness.md).

The SAY derivative now additionally passes exact completion-block sanitizer
regressions and two negative controls (`6f88de`, `4ab578`), plus four fresh
complete PIC compilations and three strict incremental library links (`5de233`).
These cover source completion behavior and link closure, not loader lifecycle,
full native playback, prompt/voice acceptance or deployment. Public admission
remains closed; the installer/real-call acceptance tasks remain open.

Loader fixture run `610fd9` passes eight groups/39 fault scenarios in plain and
ASan+UBSan modes, including unload/global-drain races and poisoned cleanup.
It uses exact source functions with local dependency/destructor doubles, not
native module/session teardown. This narrows the remaining SAY acceptance gap
but does not close live callback, prompt-language, deployment or installer tasks.

The three recovery findings above were added from the operator's 2026-09-06
review and are release-blocking P0 items, not fixed by `83194e7`. That commit's
delayed-notification regression verifies recovery after direct calls finish and
preserves pause/pending logout. Independent testing also passed those three
cases. The first two resource-capped unit runs stopped in mock setup; a subsequent
run passed all 48 tests using EUnit's supported slow-host timeout scaling and a
narrow configuration mock. The same 384 MiB / 50% CPU cap and 120-second outer
limit remained enforced; production timers and assertions were unchanged.
The external team's recovery commit `d69cf04` is now integrated by kz5 merge
`8548b98`, with its six production-module changes preserved. Root independently
passed all 174 combined Erlang tests: 22 recovery, 48 unit, 26 strategy,
16 recovery I/O and 62 historical media, plus six source-ownership checks.
The first merged historical media run exceeded an incorrectly selected
120-second outer deadline; the documented 900-second allowance passed with
unchanged memory/CPU caps. This does not certify current native playback or
all-language behavior. Root also independently compiled all 63 top-level
production modules with `-Werror`, with input freshness and no TEST build
options or agent test exports; no running BEAM was replaced or loaded.
See `doc/acdc_agent_recovery.md` for exact evidence.
P0-07/08/09 remain release gates for coordinated staging, broker/node failures,
real calls and load/soak testing. Genuine `max_connect_failures` protection is
preserved; policy UI/API documentation is not closed by the FSM fix alone.
Each new P0 requires a
reproducer, code and installer integration, focused fault-injection regression,
and relevant live call/state/log evidence before closure.

## Dashboard and workforce delivery

The supplied folder contains four designs, covering two live screens and two
historical screens. Exact references and API/data requirements are in
[the dashboard implementation brief](doc/dashboard_delivery_plan.md).

**Scope override — September 6, 2026 (user request):** prioritize only the live
queue summary (DASH-01) and clicked queue detail (DASH-02), with their required
snapshot, Blackhole and OpenAPI work (DASH-03/04/05 and queue-related DASH-08).
Historical queue/agent dashboards (DASH-06/07), separate agent dashboard
(DASH-09), and workforce reports/storage (WFM-01–04) are **POSTPONED**, not
completed and not acceptance blockers for this live-dashboard delivery.
ClickHouse is the user-selected future historical platform; no new historical
store, ingestion, migration or ClickHouse integration is authorized by this
scope change. Existing Kazoo archives are left intact. Agent rows/state inside
the selected queue remain in scope. This override takes precedence over the
older OPEN labels and broad requirements retained below for future reference.

**Reconfirmed live-only priority — September 7, 2026:** finish the summary and
clicked-queue detail, their authorized snapshot APIs and native Blackhole
updates. Do not resume history/ClickHouse or separate workforce/agent dashboard
work to close this slice. Actual browser call transitions for both screens have
passed; summary/detail reconnect and company-switch checks also passed against
the deployed system. Remaining live acceptance work is restricted-principal
isolation (including safe fixture cleanup) and cross-node/load checks.
The current guide is `doc/acdc_live_dashboard_ui.md`; earlier chronological
entries below are not a reason to repeat already completed implementation.

**Latest deployed summary/detail checkpoint — September 7:** OxxzgK includes the
P0-18 foreground fix. Same-account and switched-company summary reconnect pass
7/10 checks (1412/1388ms); detail passes9/12 (3123/2708ms). New real-call summary
acceptance `d7a65b`, receipt `/tmp/kazoo-monster-live-deployed.1bmROU/receipt.json`,
passes9 checks with two page queues,7 overview GETs/0 detail or supplemental
reads and3 natural hints. Call evidence `/var/log/kazoo-strategy-acceptance-73777r/`
has one offer/bridge and12 stable samples; owned cleanup passed. Exact final
roster/31 statuses/memberships match the pre-work snapshot (`279769`); all nine
services active, zero calls/no ledger and owned UI verification9144a5 passes.
Test-phone restoration once hit systemd's start limit after repeated manual
pauses; exact-unit reset/start restored it without policy changes. See
`doc/monster_live_reconnect_acceptance.md`. Restricted-user, cross-node/load and
TLS gates remain open. History/ClickHouse remains postponed.

**Earlier deployed selected-detail reconnect — verified September 7:** final
same-account and normal switched-company browser runs passed 9/12 checks
(`4a10d5` / `20c816`), including actual disconnection/stale display, new exact
queue subscription ACK, subsequent no-store GET, independently matched visible
call counts/rows, new-socket unsubscribe and home restoration. Recovery was
2780/3278ms. Offline14 reconnect and17 scope groups passed; final exact
roster/31-state comparison passed `52c1c7`. See
`doc/monster_live_reconnect_acceptance.md`. This closes that bounded detail
reconnect check, not restricted-user isolation, summary-page reconnect,
cross-node failure/load or TLS acceptance. History remains postponed.

Latest live-only checkpoint (September7): production ACDC74/Blackhole30 modules
are deployed, including the dynamic local-registration capability. Native
`bh_queue_live` registration is persisted while preserving existing modules.
Real HTTP/WebSocket smoke65638 passed authorized summary/detail, anonymous and
wildcard rejection, exact subscription, deliberately triggered invalidation,
detail refetch and unsubscribe. Later root79231 passed an actual isolated
normal-call transition after the strict native bridge-proof correction:15 HTTP
requests/15valid snapshots,3native hints,0timeouts, waiting→handled→gone each
with a fresh hint and later GET. One offer/bridge and12 stable FS samples were
observed; exact subscribe/unsubscribe ACKs and scoped cleanup passed. Original
three agents were restored, owned resources/contacts removed, no ledger or FS
calls remained, and all eight services were active. Private evidence is in
`/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-evidence.json` and
`dashboard-natural-call-evidence.json` in that directory. Build2519 compiled
74ACDC/30Blackhole in `live-dashboard-backend.0KplKA`;29023 deployed only the
matching FSM with `acdc_queue_fsm.before-native-proof.beam` backup in the private
rollout directory. Baseline43165 remains a valid earlier failure, not a pass.
UI `220b37b` passed46 offline and24 Chromium fixture groups24147; fresh production
build `monster-owned-build.Fd3cY7` deployed32580. Real browser65670 passed all seven
checks: summary/detail, native ACK/refetch, exact assets and acknowledged
navigation unsubscribe, with zero console/page/HTTP errors, supplemental detail
reads or new overview requests after detail entry. This fixes the strict-query
cache-buster and bounded local cleanup retry bugs discovered by earlier runs.
Installer preserving-module
migration passed37 isolated cases8385 and real idempotent readback58155. Current
OpenAPI is published and verified. Post-restart wire30446 is available/consensus,
and exact roster/31 reported agent states remain unchanged. Remaining live gates:
browser call-transition rendering, restricted-token isolation, cross-node
failure and load/soak acceptance. Historical,
separate agent dashboard, WFM and ClickHouse remain POSTPONED.

Browser natural-call continuation (September7): a separate
`test-acdc-strategies-live.cjs --dashboard-browser-live` candidate now connects
the existing owned call lifecycle to actual deployed-browser observation in the
same process. It is not yet live acceptance. Rootf3ea3d passed CLI admission,
success/failure propagation, shared lock and signal/cleanup controls;3ebc21
passed original SIP/ownership tests;45380 passed12 shared observer groups.
Preflight18152 confirmed isolated users/devices, no calls/contacts and restorable
states without fixture writes. Master snapshot18604 compared exactly with the
original via423ce0: roster and31 statuses/memberships unchanged. Browser phase
fixture93501 passed12 groups and company-scope fixtured3c369 passed16. Peer review
found and the helper fixed a hidden-view false-PASS risk; every phase now checks
visible active controller DOM. Actual run53882e was refused before payload by
memory admission (about754MiB available;320MiB cap+512MiB reserve required).
No fixtures/calls were created in that refused attempt. Subsequent guarded
a0d26078 passed actual browser detail waiting→handled→gone (11 checks,3 natural
hints,6 detail GETs, no console/page/HTTP/scope errors). Call proof: one offer and
bridge,12 stable channel samples. Evidence: `/var/log/kazoo-strategy-acceptance-elItb6/`
and `/tmp/kazoo-monster-live-deployed.CkHl41/receipt.json`. Only unrelated30 test
phones were paused/restored; all eight platform services remained running with
the unchanged320MiB cap/512MiB reserve. Exact MASTER roster/31 states/memberships
matched afterward; all nine services active, zero calls, no ledger. Live detail
rendering is now verified for this one isolated call; summary during calls,
restricted principals, cross-node and load/soak remain open. See
`doc/monster_browser_call_acceptance.md`.

Final development check90474 repeated the available/consensus HTTP and scoped
native event/refetch smoke successfully. The exact saved roster and31 agent
statuses/memberships were unchanged from the pre-deployment snapshot, and all
eight services were active. No new calls were placed by these tests.

Earlier source integration: `b3faf2d` puts authorized roster/names and bounded
runtime-agent observations in the same selected queue GET. Public/roster26,
actual DTO24, helper2 and focused schema15 groups/297 cases passed15218.
Transport34 passed82855 and auth14 passed36984. Publisher `0411898` passed24
groups62617; native Blackhole22 and installer migration60 cases also passed.
The matching one-response UI adapter, sequential subscriptions, coherent build
and live HTTP/WebSocket acceptance remain underway. No new deployment or
master push is claimed. Historical/ClickHouse/WFM stays postponed.

Earlier live integration: UI `900efa8` now consumes the new bounded DTOs with
explicit summary paging and clicked detail. Offline dashboard 22 groups and
queue-login 20 groups passed (37074); Chromium 12 interaction groups passed
(5608, synthetic API only). Shared auth passed 10 cases (93576). Public handler
passed 9 route groups, 2 helpers and 17 actual-response/OpenAPI checks (23014).
Repository catalog regenerated and verified 93576; live `/apis` not published.
See `doc/acdc_live_dashboard_ui.md`, `doc/acdc_live_auth.md` and
`doc/monster_socket_lifecycle.md`. Native queue event publication/delivery,
runtime queue-agent state and coherent deployment/live acceptance remain OPEN.

September7 continuation: `a011934` adds the native lifecycle UI controller;
32 offline groups passed64066,18 Chromium fixture groups and20 queue-login
groups passed55555. `5e6a3b6` adds the local bounded runtime-agent collector;
17 protocol tests and three production compiles passed64066. The latter still
needs authorized federated/public DTO integration, while dedicated Blackhole
server delivery/publishing and installer replay are work in progress. Neither
source checkpoint is deployed/live accepted. Same-scope search/focus retention
is a follow-up UI task so automatic updates do not disrupt operators. No new
historical/ClickHouse work was started; all eight services are active afterward.

Earlier selected-call extension: collector42 tests, transport28 tests,
production HTTP9 groups plus2 helpers, and private OpenAPI13 groups/214 schema
cases passed. Detail now returns at most200 observed active calls, with explicit
unavailable/complete/truncated semantics and full observed count; source and
replica limits remain explicit. See `doc/acdc_live_snapshot.md` for evidence.
The repository catalog was regenerated7042 and verified67333 (11 assets,
byte-identical to private62421); `/apis` was not republished. Native Blackhole,
queue-agent runtime and matching UI/deployment acceptance remain open.

Earlier live integration checkpoint: bounded HTTP summary/selected-summary source is
being connected to the collector through a strict internal broker contract;
see `doc/acdc_live_snapshot.md`. The selected route is not yet full queue detail:
active-call rows, runtime queue agents, Blackhole updates and UI wiring remain
required. The corrected federated transport passed24 cases in4405. The HTTP
handler passed8 public-route production-build tests and2 pure helper tests in
70142; real HTTP/token/broker acceptance remains open. The complete private
OpenAPI catalog passed11 groups/135 schema cases and all11 asset verifications
in92359, with250 unique current source inputs checked. Runtime publication is
pending.
Blackhole callback ownership/listener cleanup passed10 tests and its installer
transition passed46 cases. None of these passes closes DASH-01–05 or establishes
a new deployed dashboard. Historical/WFM work remains postponed.

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| DASH-01 | ACTIVE — actual summary browser call transitions PASS | Live overview uses the bounded authorized page GET and sequential native subscriptions. Guarded f965e9fb passed9 actual-browser checks: selected waiting/handled counters0/0→1/0→0/1→0/0 after3 natural hints/later GETs; both visible cards match DTOs and exact page subscription/cleanup ACKs. Seven overview GETs, zero detail/supplemental calls or browser/HTTP/scope errors. One offer/bridge and12 stable channel samples verified independently. MASTER roster/31 states preserved and30 test phones restored. Summary contains no call identities, account-wide or historical totals. All17 restricted-principal HTTP/native WebSocket cases pass573eb1/0d57c2; restricted-user browser/cross-node/load acceptance remains open. |
| DASH-02 | ACTIVE — deployed detail; actual browser call transitions PASS | One bounded response includes authorized roster/names, observed runtime states/membership and up to200 active calls. Root79231 passed natural HTTP/native transitions. Guarded a0d26078 then passed actual visible waiting→handled→gone:11 browser checks,3 natural hints,6 detail GETs, no supplemental/global reads or console/page/HTTP/scope errors, acknowledged cleanup and normal company restoration. One-agent reciprocal bridge and12 stable samples verified. MASTER roster/31 states preserved and30 test phones restored. Unknown/incomplete limits remain explicit; all17 restricted HTTP/native WebSocket cases pass573eb1/0d57c2. Restricted-browser/cross-node/soak remain open; supervision is outside current live-only scope. See doc/monster_browser_call_acceptance.md. |
| DASH-03 | ACTIVE — deployed; real HTTP/wire/call passed | Fresh production build2519 compiled74ACDC/30Blackhole;29023 deployed only the corrected FSM. Public27/actual DTO28/helper2, transport34 and schema297 cases passed. HTTP32168 reported available/consensus;79231 adds15/15valid natural-call snapshots and0timeouts through waiting/handled/gone. Missing/conflicting sources remain unavailable, not zero. All17 restricted HTTP/native WebSocket cases pass573eb1/0d57c2. Multi-node failure/load and restricted-browser acceptance remain open. |
| DASH-04 | ACTIVE — native scoped natural-call delivery verified | Exact subscribe/unsubscribe and anonymous/wildcard rejection passed wire32168. Root79231 adds3native invalidations during one actual call, each phase followed by a fresh GET, plus exact ACKs and successful cleanup. Hints have no causal call nonce and do not guarantee delivery. UI15s reconciliation/sequential admission fixtures and persisted registration/readback58155 passed. Browser call rendering/reconnect and all17 restricted-token matrix cases now pass (latest573eb1/0d57c2); cross-node/load remain open. |
| DASH-05 | ACTIVE — current specs published | Versioned summary/detail DTOs and native Blackhole message/lifecycle/account/queue contracts are served at `/apis`. Latest source catalog1811a9/5199cf and regeneration159801/40e94d include the deployed cb_queues handler fix. Publicatione1a4e3/c4a478 verifies11 exact HTTP asset hashes, no-store, redirect308 and missing404:358 paths/653 operations/504 schemas/1601 references. Previous assets retained at `/usr/local/src/kazoo5-installer/api-docs-rollback.woSddd/previous`; latest UI rollout preserved them. Earlier offline/deterministic/tamper, call-transition and restricted-token evidence remains scoped as documented. DASH-10 caller fields are not implemented/published yet; planned history is not callable. HTTPS remains SEC-01, not implied by HTTP publication. |
| DASH-11 | ACTIVE — idle viewer load passed; broader load open | Reproducible read-only HTTP/native WebSocket harness passes14 offline fault/bounds groups and actual2/10/30 viewer cohorts for30 seconds with the full cohort ready. Extended30 viewers pass180 seconds with391 fresh/complete snapshots, exact30/30 ACK cleanup, zero errors/incomplete snapshots and97.5ms HTTP p95 (2fbd95/90d1e4). All jobs terminal; nine services active, zero calls and measured application error/crash logs unchanged. See `doc/queue_live_viewer_load_acceptance.md` for scripts, receipts and source hashes. No natural events occurred; this is not30-call capacity, browser rendering, sustained soak, backpressure or cross-node/failure proof. Next: separately coordinated natural call/event load and failure acceptance without weakening scope/freshness checks. |
| DASH-06 | POSTPONED — UI + reporting | Queue historical dashboard using `Queue Historical Dashboard.png`: time/queue filters, call outcomes, SLA, wait/handle/talk metrics, details and export. Reconcile counts, timezone boundaries and late events. |
| DASH-07 | POSTPONED — UI + reporting | Agent historical dashboard using `Agent Historical Dashboard.png`: agent/queue/date filters, last activity, outcomes, talk/break/idle durations, details and export. Define attribution for transfers/multiple queues. |
| DASH-08 | OPEN — API + Next.js acceptance | Explicit company/account, queue and agent filtering contracts for snapshots and native Blackhole subscriptions. Company means Kazoo ACCOUNT_ID, not a free-text company name; enforce tenant and queue/agent permissions on the server, including wildcards and reseller/sub-account access. Document selected-queue and selected-agent examples, supported filters, unauthorized/unknown IDs and switching scope without leaking old events. Existing generic call bindings are not queue dashboard bindings. Test isolation, reconnect/resnapshot and filter changes with a real Next.js integration before marking ready. |
| DASH-09 | POSTPONED — API + docs | Add live agent dashboard contracts alongside company queue overview, selected-queue live detail and queue/agent history. Publish versioned HTTP request/response/error schemas at /apis and linked WebSocket bindings/event schemas, with copyable Next.js examples. Clearly label planned versus implemented versus deployment-tested contracts; do not advertise invented dashboard routes as callable. Test actual responses/events against schemas and exercise examples against the matching deployment. |

Current live acceptance continuation: deployed browser navigation passed;
the isolated one-call `--dashboard-live` run79231 now also passed actual
waiting/handled/terminal absence with a fresh native hint and later GET per
phase. It used the acceptance tenant, not the master queue:15/15valid snapshots,
3native invalidations,0timeouts,1offer/bridge and12stable FS samples. Exact
subscribe/unsubscribe ACKs and cleanup passed, restoring original3agents and
removing owned resources/contacts with no ledger/FS calls and all8services active.
Evidence: `/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-evidence.json` and
`dashboard-natural-call-evidence.json` in that directory. Earlier43165 in
`/var/log/kazoo-strategy-acceptance-BMBtU4` remains the failing baseline, now
superseded by the deployed strict reciprocal proof. Observer diagnostic12
groups12490 and CLI cleanup/forward-signal/lock groups0c58ba are separate offline
evidence. Browser call-transition rendering, restricted-user/cross-node and
load/soak remain open; this single-call pass does not guarantee hint delivery.

DASH-08 / SEC-02 follow-up: source review found scope restrictions are resolved
from mutable user/policy documents, not frozen into JWT permissions. Missing
user/policy reads can fall back to native defaults (`crossbar_util`), while
ordinary token deletion is not proven signed-JWT revocation. Do not delete test
users or their scope policies while their tokens remain authenticated. The
isolation harness must use genuinely restricted non-admin users, exact owned
resources, positive controls and policy-specific denials; retain both user and
policy until actual authentication invalidation is verified. This is a source
risk and cleanup constraint, not yet an established deployed exploit. Native
revocation/cache behavior and any needed fail-closed code fix remain open.
The prepared isolation harness passed19 offline groups and42 rejection checks
(47083), but live provisioning
is not admitted: source review additionally found default Crossbar soft-delete
refreshes the document revision after Cowboy's If-Match check. Its header alone
does not prove race-safe fixture deletion. No isolation users/policies/queues
were created. Keep live admission closed until a scoped atomic cleanup path is
verified; do not toggle global deletion settings to run a dashboard test.
| BH-01 | ACTIVE — deployment acceptance | Token/reason/unsupported-frame redaction is packaged as a pinned installer patch; session `86439` passed eight public-entry tests, six production compiles and exact source replay. No live deployment yet. Malformed JSON and generic application-payload logging, authentication lifetime and full protocol security remain separate gaps; see `doc/blackhole_resilience.md`. |
| BH-02 | ACTIVE — security | Context result classification bug reproduced (five failures/one control), corrected in source (six groups pass, 18786); combined replay and ten public-handler tests including mixed-denial dispatch prevention pass (69993). See doc/blackhole_binding_results_acceptance.md. Enforce and test socket authentication lifetime, token/account changes, expiry/revocation and missing/failed auth modules; existing cached authenticated context is not sufficient. Preserve tenant isolation and add queue/resource permissions for dashboard bindings. |
| BH-03 | ACTIVE — deployment/security acceptance | Finite inbound frame/reassembled-message limits, malformed/non-object rejection and close-reason redaction implemented in installer patch. Session 62506 passes 13 real private-Cowboy wire groups, eight production compiles, exact schema/source replay and cleanup checks. Initial 38610 exit99 rejected because runner changed; clean rerun required and passed. Connection limits/trusted proxy identity, live deployment, load and unrelated-session stress remain open; no total-memory or whole-log-safety guarantee. |
| BH-04 | OPEN — resilience | Slow-client/backpressure policy and observable loss/resync: current emitter can silently drop events and replies over its mailbox threshold. Do not claim replay/exactly-once semantics. Add bounded buffers, load/failure tests and frontend stale/reconnect handling without a duplicate transport service. |
| BH-05 | ACTIVE — deployment acceptance | Native Blackhole reference extended in ab9d78a with company/call versus planned queue/agent filtering, supervision audio matrix and source frame limits. Offline/browser checks pass (24389/95890); /apis publication 51631 verifies all 12 assets, HTTP hashes/no-store/redirect/404 and rollback. Proposed dashboard contracts remain distinct. Native app/listener and reverse proxy, separate-node configuration, reconnect/failover, TLS and real authenticated event delivery still require production acceptance. |
| WFM-01 | POSTPONED — product + UI | Workforce report in the same design language: agent/date/queue filters, login/logout times, sessions, working hours, total breaks and breakdown by break type; drilldown and export. |
| WFM-02 | POSTPONED — API + storage | Durable agent session/state-transition and break-reason records with identifiers, timestamps, provenance and runtime confirmation. Handle missing logout, restart, duplicate/late events, overnight shifts, timezone/DST and multi-queue sessions without double counting. |
| WFM-03 | POSTPONED — API + docs | Workforce summary, session details, break-type catalog and export APIs; access control, bounded ranges/pagination and OpenAPI schemas/examples/errors. Separate break configuration changes from reporting reads. |
| WFM-04 | POSTPONED — acceptance | Define paid/unpaid break policies and working/available/talk/wrap-up/idle time explicitly. Report unknown/incomplete intervals; never infer payroll hours from SIP registration. Reconcile totals and test exports, corrections/audit trail, retention and sensitive-data access. |

## Queue features, voices and APIs

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| ACDC-01 | ACTIVE — auth/deployment acceptance | Unified queue create/edit/read. Queue recovery UI `8c11030` passes 15 source-browser cases; fresh compiled bundle passes all five recovery cases plus queue-specific login (`88551`). Backend malformed/foreign-extra/empty-revision acknowledgement bugs reproduced, fixed, then all 41 editor/manifest tests passed (`68783`, rechecked `90416`), including partial/lost replies, persisted receipts, fresh roster/revisions and no automatic resend. Live restricted-token controls and coordinated backend/UI deployment remain required. |
| ACDC-02 | OPEN — UI | Reliable Callflows ACDC action and internal extension routing; dropdowns instead of technical free-text fields; default prompt selection must not trigger required-field errors. Preserve existing customer recordings. |
| ACDC-03 | OPEN — ACDC | Verify/build supported ring strategies: ring-all, ordered, round-robin and existing alternatives. Resolve simultaneous-answer/DTMF exit ownership candidates; test fairness, single winner and cleanup. |
| VOICE-01 | OPEN — media + UI | Finalize EN/HE/AR/FR/ES prompt-language override, queue/call/account defaults and reseller/sub-account inheritance; report incomplete packs rather than enabling unverified choices. |
| VOICE-05 | ACTIVE — canonical callback integrated; deployment open | Canonical helper/member/announcements/returned-caller now use exact immutable built-in callback media and recorded telephone digits for all five locales. All81 current-source tests passed in53629; stale29-versus32 projection was reproduced/corrected, then complete42-entry callback projection passed21 focused tests in28251. UI30215 and editor71128 cover all57 transitional prerequisites; all63 production modules compiled again in62912. P0-12 is a separate subsequent candidate, not covered by those earlier results. Earlier live runtime/source discrepancy is not closed until coherent deployment and playback checks; full_language_ready and callback_runtime_ready remain false. See doc/acdc_canonical_callback_acceptance.md. |
| VOICE-02 | VERIFIED — generated assets and installer byte check | Existing165 effective Gemini entries /330 WAVs remain unchanged. September6 supplemental generation completed45 missing callback clips /90 WAVs in47 requests (two French digits retried once, previous failures retained). Combined immutable lookup210 assets /420 WAVs, committed0904240. Actual installer media-import19674 verified210, preserved210 and created0; nonsecret receipt at /usr/local/share/kazoo5-installer/acdc-gemini-media.json. This is not runtime mapping activation, five-language playback certification or complete prerecorded queue-position speech. |
| VOICE-03 | OPEN — media | Build voices once into versioned shared artifacts for all present/future accounts and sub-accounts. No Gemini generation during installation, account creation, queue editing or calls. Finish missing numeric/auxiliary audio and native listening checks. |
| VOICE-04 | ACTIVE — generation authorized | User explicitly renewed authorization on September 6 to use Gemini from protected /root/key.key for missing built-in queue WAVs. The file is root-owned mode 0600 and contains distinct Gemini and GitHub credentials; select by provider without logging either. Supplemental generation is no longer blocked on approval. Native listening and five-language call acceptance remain required. |
| VOICE-06 | ACTIVE — source tested; browser/deployment open | Commit61bf505 implements exactly one Queue language dropdown: EN, HE, FR, ES, AR; no sixth inheritance/custom choice or voice picker. Built-in adoption removes obsolete queue prompt references even when saving the current English choice without a change event. UI30215 and all42 editor tests71128 pass; wire null deletion markers persist as absent fields, media documents remain unchanged, and readiness includes42 callback assets plus15 transitional official prerequisites. Matching compiled UI deployment/browser acceptance and all-Gemini position coverage remain open; selection must ultimately govern every queue/callback response path. |
| VOICE-07 | ACTIVE — immutable WAV generation | Generate missing fixed, numeric and auxiliary phrases once using Gemini, reusing valid existing Sulafat recordings. Produce PCM16 mono masters and telephony-rate WAVs; retain transcripts, language/voice/model provenance, hashes and duration/clipping checks. Cover agent-invalid_choice, menu-invalid_entry and cf-enter_number in all five languages, plus complete position/telephone numeric composition. No native robotic SAY or mixed-voice fallback in the finished standard pack. Never regenerate during install, account/sub-account creation, queue editing or calls. User reiterated this as the most important requirement on September 6: generate everything needed for THIS release now; ship it in Git and require no further Gemini usage or credential for the supported release. Missing artifacts must fail installation/readiness explicitly, never trigger online synthesis. Test installer/runtime paths with Gemini access unavailable and no provider key. |
| VOICE-08 | OPEN — backend + build | Integrate the built-in pack in canonical tracked ACDC, not only a private patch or deployed BEAM. One queue-language value drives every prompt path and the persisted callback call context. Package WAVs, maps, import/readback logic, schema/UI changes and tests in kz5; repeated and standalone apps-node installation consumes those artifacts without a provider key. New accounts and sub-accounts use shared installed defaults automatically. |
| VOICE-09 | OPEN — deployment acceptance; development deployment authorized | User confirmed September 6 this is a development environment with no active calls and explicitly authorized replacement/deployment as needed. Verify current call state before restart; preserve account data and rollback artifacts. Prove the selected queue uses the expected Gemini assets for position, independent callback interval, key-6 menu/success, invalid/alternate-number responses and returned-call confirmation in each language. Listen for natural female speech, correct words/numbers/language, no clipping or silence. Deploy matching source/backend/UI/assets through the installer. Imported files or successful TTS generation alone do not close this task. |
| API-01 | VERIFIED — single-server scope | Supervision eavesdrop/whisper/barge/join and stop have prior isolated audio/auth tests and OpenAPI entries. Cross-node/failover/real-traffic acceptance remains OPEN. |
| SUP-01 | OPEN — audio acceptance | Listen / silent monitor / spy uses action eavesdrop: supervisor hears both agent and customer; neither party hears supervisor. Whisper: supervisor hears the conversation and speaks only to the selected agent leg; customer must not hear supervisor. Barge-in: supervisor, agent and customer hear one another; join is the existing full-audio alias. Revalidate each directional audio matrix, target-leg selection and safe stop without ending the original call. Existing single-host evidence in API-01 does not close this release gate. |
| SUP-02 | OPEN — cluster/security acceptance | Test monitoring of authorized calls across queues and FreeSWITCH nodes, answer races, hangup, transfer, stale ownership, unreachable node, retries and supervisor disconnect. Enforce exact-account administrator and owned enabled supervisor-device checks; reject tenant crossing, raw routes/commands and stopping the original call. Correlate accepted requests to actual media connection and audit start/stop without logging credentials. No duplicate supervisor legs or unwanted mode escalation. |
| SUP-03 | OPEN — OpenAPI + installer acceptance | Keep the existing POST /accounts/{ACCOUNT_ID}/channels/{UUID} contract authoritative: eavesdrop, whisper, barge, join and stop_monitoring. Expand /apis with the audio matrix, agent-leg selection, request/response/errors, supervisor-leg correlation, accepted-versus-connected semantics and Next.js examples. Verify actual source-to-FreeSWITCH implementation rather than assuming Pivot, a callflow action or mod_spy is required. Add schema/example regressions, authenticated deployment tests and clean/separated-server installer acceptance before marking these features finalized. |
| API-02 | OPEN — live acceptance | Company members with owned devices/types/fresh registration state. Offline session `99855` passed 25 tests with real production authorization/JWT code against fixture stores: restricted resources, unrelated-account denial, expiry, scopes and exact inventory/page limits. Twelve contract groups pass; page-wide completeness/status constraints are published at `/apis`. Live restricted/foreign/expired principals remain unverified, and registrar limits are post-collection, not transport-memory bounds. Keep SIP online distinct from queue eligibility. |
| API-03 | ACTIVE — documentation | Repository catalog validates356 paths /651 operations. Latest commit61bf505 adds separate queue-create/PATCH schemas, built-in language deletion example and57-entry prerequisite bound; schema/deterministic/tamper checks pass62912. Static publication28926 verified all12 HTTP-served files, redirect/404/no-store and backup, recorded in doc/api_developer_portal.md. Earlier isolated Chromium95890 checks the unchanged viewer, not latest backend/UI deployment. HTTPS, actual endpoint acceptance and proposed dashboard implementation remain separate. |

## Installer, deployment and release

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| INST-13 | ACTIVE — production discovery; import/install pending | Import the mobile push bridge from production Kamailio `10.1.0.28` into canonical kz5 (no nested Git). User authorized read-only SSH discovery and source retrieval on September 7; do not restart, modify or test notifications against production. Identify the actual bridge unit, source/license/provenance, dependencies and Kamailio integration; verify whether Pusher/FCM is used rather than assuming it. Exclude passwords, provider credentials, device tokens, logs and customer data. Add a `bridge` option to the existing modular install SH with pinned dependencies, protected configuration templates, least-privilege named systemd service, enable/start/readiness checks and documented standalone/co-located integration. Preserve existing ALL behavior until required push credentials/configuration semantics are defined. Test repeat install, reboot, invalid config, provider failure/retries and isolated mobile ringing; document actual results and remaining gates. Temporary SSH credentials remain outside Git. |
| INST-01 | OPEN — installer | One modular install entry point: CouchDB, RabbitMQ, HAProxy, Kazoo apps, eCallMgr, Kazoo FreeSWITCH, Kazoo Kamailio, Monster UI and ALL; automatic pinned dependencies, configuration validation and enabled/running named services. |
| INST-02 | VERIFIED — current-host scope | Named services and `kazoo-applications` compatibility alias exist; Pivot port reservation, test-phone startup preservation and requested SUP alias repaired. Reboot/custom-root/clean-server regression tests still required. |
| INST-03 | ACTIVE — installer | Kamailio verifier repair committed `aff66d3`: 11 regression groups and live `--verify-only kamailio` pass; recovered startup JWT failure remains an explicit warning, later/unrelated errors fail, service identity unchanged. Finish combined all-module verification after remaining deployment; verify source/export availability and configuration/transport readiness. |
| INST-04 | ACTIVE — deployment acceptance | Fresh queue-recovery production build `72306` and readback `15995` pass under the unchanged 384-MiB cap: 1,931 files, 465 templates, 16 canonical preloads. Actual artifact browser `88551` passes queue-specific login and five recovery cases with explicitly mocked APIs. Older bundle fails the expected recovery guard. The earlier five-phase checkpoint omitted the main installer smoke, which subsequently passed separately in `45471`. See `doc/installer_regression_acceptance_20260906.md`; adoption, coherent backend, live authentication and clean-server dependencies remain unverified. |
| INST-05 | ACTIVE — build | Post-build artifact verification is wired before activation and included in the fingerprint; modular fixtures with/without ACDC pass. eCallMgr no longer trusts stale `.app` files: current-invocation build reuse, environment reset and failure-before-activation fixtures pass. Full real repeat deployment remains required. |
| INST-06 | OPEN — deployment | Publish reviewed matching source/backend/UI with exact backups; preserve unselected apps/config/customer data and runtime queue memberships/pauses. Read-only probe `29950` confirms old FSM and missing queue-login/recovery interfaces: the candidate now includes at least eleven ACDC/API modules with cf_acdc_member's feedback fix, drained work/admission control and tested migration/restoration, not a six-module hotload. Unsafe legacy FSM conversion fixed in `64f4feb`; 25 recovery tests (`99730`), 48 broader tests (`66281`) and all 63 production modules (`68050`, callback-fix recheck `44008`) pass. Repository real-OTP runner `17426` passes 27 conversion/timer/pause/refusal cases without TEST. Actual isolated old/new code replacement also passes four fresh-VM cases in shared runner `41876`, committed `a3d1110`. Live installed-code replacement, admission control and multi-module rollout remain unverified; compiled UI publication remains held. See `doc/acdc_coherent_upgrade_readiness.md`. |
| INST-07 | OPEN — acceptance | Clean Rocky Linux 9 install, each module alone, all-in-one and separated hosts; hostname/address/configuration variations, reboot, repeat install, upgrades and failure recovery. No clean-server success is claimed yet. |
| INST-08 | ACTIVE — staging acceptance | False-success checks fixed in code: RabbitMQ selected-vhost permissions/exact AMQP bind (65 runtime + 32 password cases pass); external UI API envelope and early API/WebSocket validation (71 cases + main ALL smoke pass). No-route fallback fixed; dry-run no longer claims live validation. Read-only/modular/runtime-config/12 UI wiring groups pass. Actual separated-server connection/install acceptance remains required. |
| INST-09 | VERIFIED — source transition scope | Main installer now handles clean/current/known-previous Blackhole and Crossbar integrations with explicit old-to-new patches, protected private preflight and final full-patch checks. Session 36178 passed all 42 tests against the extracted actual installer helper, then the main installer smoke: partial/unsafe states and staging failures stop without target changes, unrelated edits survive, repeat install is unchanged, inherited Git redirects are isolated. See doc/installer_source_transitions.md. No live checkout upgrade, clean-server deployment or crash-atomic filesystem guarantee; those remain INST-06/07. |
| INST-10 | VERIFIED — mod_kazoo source transition scope | Fixed repeated-install failure from overlapping individual patches by validating the complete integration, preserving unrelated edits and refusing partial/unknown source. Added module-only version namespace fix and rebuild fingerprint. Run 46313 passes 15 actual-helper cases, including independent all-13-patches/aggregate equivalence and linked/missing/out-of-inventory rejection; 33997 reruns all 42 Blackhole/Crossbar cases successfully. See doc/mod_kazoo_version_namespace.md. Real fetch/checkout, native linking and clean/distributed install remain INST-01/06/07, not certified by these fixtures. |
| INST-11 | VERIFIED — local Git fetch/checkout scope | Reproduced fresh-fetch false success under conditional helper callers in 72775; explicit error handling and exact pinned HEAD verification fix it without forced reset or discarding conflicting edits. Run 79712 passes ten actual-Git local repository cases, including failed fetch, retry, branch clone and dirty-source preservation, then main installer smoke. See doc/installer_git_sync_acceptance.md. GitHub authentication/network availability and fresh/distributed deployment remain open. |
| INST-12 | ACTIVE — source fixes regression-tested; deployment open | Installer now forces Erlang recompilation and selected number/MIME regeneration despite restored input mtimes or future-dated artifacts; content snapshots reject changed inputs/artifacts before same-invocation ecallmgr reuse. Actual private Make/erlc fixtures and offline installer regressions passed September 6 (doc/installer_build_identity.md). This does not establish an atomic build/deploy snapshot or current live source parity. Full deployment remains gated on VOICE-05 and coupled native/runtime validation. |
| SEC-01 | BLOCKED — operator | HTTPS `kz5.talkchief.io`: supplied certificates have no matching private key in `/root/ssl`; provide protected matching key or explicitly authorize replacement issuance. Validate WSS and TLS renewal afterward. |
| SEC-02 | OPEN — operations | Network exposure, least privilege, secrets, SELinux policy, auth/tenant isolation, audit logs, backups, retention, monitoring/alerts and resource/disk limits. Do not equate active services with enterprise certification. |
| LOAD-01 | OPEN — acceptance | Resolve prior memory/AMQP incident; rerun sustained 30 concurrent calls and full drain, then establish measured capacity. Distinguish concurrent calls from calls/second; 80 CPS is not certified. |
| HA-01 | OPEN — acceptance | Backup/restore, failure injection, multi-node ownership, distributed queues/broker/database failover, reconnect and no duplicate callbacks/bridges. |
| REL-01 | OPEN — release | Review and credential-scan all task changes, commit source/tests/assets/docs and record exact build/test evidence. Update this register rather than marking untested features done. |
| REL-02 | ACTIVE — credential supplied; release pending | User supplied GitHub PAT in root-owned mode-0600 /root/key.key on September 6; authentication is not yet verified. Select the GitHub token separately from the Gemini key in that file, never print or commit either. When the full requested work is ready, push reviewed commits to master and verify remote SHA. No successful latest push is claimed. Never reuse the exposed chat token. |

## Work order and release rules

1. P0-01/P0-03/P0-04 in parallel source work, with serialized resource-capped tests.
2. P0 live acceptance without interrupting operator calls or changing rosters
   without an explicit selection; queue-login API and UI ship together.
3. Correct production UI build and installer gates; matching deployment/browser
   checks; complete language handling without recurring TTS calls.
4. Immediate dashboard priority: DASH-03/04/05 establish trustworthy live
   data/events alongside DASH-01/02 UI work. Historical dashboards, separate
   agent dashboard and workforce reporting are postponed for future ClickHouse
   work; do not implement them or block live delivery on them.
5. Clean/distributed installation, security, sustained load, restore/failover and
   authenticated remote release. Document external blockers, not fictitious passes.
