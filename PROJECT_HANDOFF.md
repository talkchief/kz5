# Kazoo 5 — start here / engineering handoff

Last updated: **2026-09-07**. This is the navigation and current-state guide;
`PROJECT_TASKS.md` is the detailed requirement/acceptance register. Neither this
file nor a green unit test means the platform is production-ready.

## Latest working snapshot — read before resuming

**Summary live PASS (September7):** opt-in
`test-acdc-strategies-live.cjs --dashboard-browser-summary-live` passed f965e9fb.
Receipt `/tmp/kazoo-monster-live-deployed.4jYi2Y/receipt.json` (9checks) and
`/var/log/kazoo-strategy-acceptance-Y68nYp/` prove actual selected queue counters
0/0→1/0→0/1→0/0,3 natural hints/later GETs, all visible card/DTO agreement,
exact subscriptions for both page queues and complete native cleanup. Seven
overview GETs, zero detail/supplemental GETs and zero browser/HTTP/scope errors.
One offer/bridge and12 stable samples passed; borrowed fixtures cleaned up,
MASTER roster/31 statuses/memberships unchanged and30 phones restored. Shared
test-source revalidation:18 observer,16 company-scope,12 shared DTO groups and
CLI/SIP ownership fixtures passed. No UI/backend deployment in this slice.
See `doc/monster_browser_call_acceptance.md`; restricted principals and
cross-node/load/soak remain open, history/WFM postponed.

The final shared test source also passed a fresh detail-mode real call:
`/tmp/kazoo-monster-live-deployed.IBFBXo/receipt.json` (11checks),
`/var/log/kazoo-strategy-acceptance-ULzxV9/` (one offer/bridge,12 samples).
Five detail GETs,3 natural hints and zero browser/HTTP/scope errors. Final MASTER
snapshot equals the pre-first-call roster/31 states/memberships, all nine services
active,30 phones restored, zero calls and no strategy ledger. No crash-report,
OOM or service-failure journal markers since04:18 UTC; no wider stability claim.

**P0-16 source checkpoint:** binding exception logger fix is captured by the
installer-owned `kazoo-bindings-exception-diagnostics.patch`, not a nested core
commit. Current599852 passed8 groups; pinned baseline35d013 failed8 with actual
integer-arity logging exceptions and disclosure cases. Production transformed
compilation and exact installer replay passed; runtime sink assertions are
offline and untransformed. No deployment. See
`doc/kazoo_bindings_exception_diagnostics.md` for paths, scope and next gate.

**Latest live PASS (September7):** guarded job a0d26078 passed the combined
actual-browser/call mode on the deployed nUolDS build. Evidence:
`/var/log/kazoo-strategy-acceptance-elItb6/` and
`/tmp/kazoo-monster-live-deployed.CkHl41/receipt.json`. Eleven browser checks
passed, including actual visible waiting→handled→gone after three natural native
hints and later GETs, normal company switching and subscription cleanup. The
call proof has one offer/bridge and12 stable reciprocal-channel samples. Only
the unrelated30 simulated phones were temporarily stopped, then restored by an
EXIT trap; all eight call-path/platform services stayed running with the original
320MiB cap/512MiB reserve. MASTER before/after fixture-pause snapshots compared
exactly (roster and31 statuses/memberships). All nine services active, zero calls,
no ledger afterward. Summary during calls, restricted principals, cross-node and
load/soak remain open; no production-readiness or master-push claim.

**Earlier source/admission checkpoint:** combined actual-browser/call candidate is
`test-acdc-strategies-live.cjs --dashboard-browser-live`, documented in
`doc/monster_browser_call_acceptance.md`. Source/offline checks passed: CLI/failure
f3ea3d, original SIP3ebc21, shared observer12 groups45380, new browser phase12
groups93501 and scope16 groupsd3c369. Live read-only preflight18152 passed; master
snapshot18604 compared exactly with the original via423ce0. Actual attempt53882e
did **not** run: the memory guard refused before payload at about754MiB available
(320MiB cap+512MiB reserve required). All8 services active, zero calls, no strategy
ledger. Prepared launcher: `/tmp/kazoo-live-rollout.OYdOqh/test-browser-natural-call.sh`.
Do not stop required call services or weaken the guard to manufacture acceptance.
This is test-source work only; the live UI remains the verified nUolDS build below.

**Current UI continuation (September 7):** the user reaffirmed live summary and
clicked queue detail only; history is postponed for future ClickHouse work.
Company-switch acceptance exposed P0-17, an early account-picker click racing
Common initialization. The installer-owned readiness patch passed 14 focused
actual-Core fixture groups98957, including the old-code exception, and installer
preservation44606 passed11 groups. Evidence: `/tmp/monster-account-picker-proof.SS17Sv`.
Fresh source25080 is `/usr/local/src/kazoo5-installer/monster-owned-build.nUolDS/source`;
configuration is byte-identical to live. Wiring13624 exposed an omitted existing
lifecycle patch in the test replay; corrected wiring95129 passed12 groups.
Production build74495 and artifact verification passed; deployment85061 changed
only main/templates and the Core English locale, removed0 and preserved1,941
files. Backup is `monster-owned-build.nUolDS/deployment-backup`; owned verification
10382 passed. New main SHA256 is `a125c954578f3d006b6f2c8bad5236b7ecb33917e9af5226857c0930ed860439`;
templates SHA256 is `fd6d1c690383e1d1dc30c73435bdfa165728434e897db2d76fc391bf7418f0bd`.
Actual browser74850 passed7 checks (`/tmp/kazoo-monster-live-deployed.w8N0gc/receipt.json`)
and switched browser69219 passed10 (`/tmp/kazoo-monster-live-deployed.tE4KRo/receipt.json`).
The latter proves exact home ACK/disposal before target, normal company selection,
target summary/detail and return home after acknowledged cleanup. Both had zero
console/page/HTTP/blocked-scope errors and zero supplemental detail requests.
All8 services were active with zero calls afterward. P0-17 is development-verified;
these are not browser natural-call rendering, restricted-principal, cross-node or
soak results. Historical work remains postponed. See
`doc/monster_account_picker_readiness.md` and `doc/monster_deployed_account_switch.md`.

**Latest continuation (September7):** live-only scope remains unchanged;
history/WFM/ClickHouse are postponed. **P0-15 is fixed and the isolated natural
call transition passed79231**: waiting → handled → gone, each with a fresh
native hint and subsequent GET. All15 HTTP snapshots were valid, three native
invalidations arrived, and zero timeouts occurred. One offer/bridge and12 stable
FreeSWITCH samples establish the actual single call; exact subscribe/unsubscribe
ACKs and cleanup passed. All three original agent states were restored, owned
resources/contacts removed, no recovery ledger remained, zero calls remained
and all eight services were active. Private evidence is in
`/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-evidence.json` and
`dashboard-natural-call-evidence.json` in that same directory. Earlier43165
(`/var/log/kazoo-strategy-acceptance-BMBtU4`) remains the valid failing baseline.
Fresh production build2519 compiled74 ACDC/30 Blackhole modules in
`/usr/local/src/kazoo5-installer/live-dashboard-backend.0KplKA`; deployment29023
changed only the matching FSM, backed up at
`/tmp/kazoo-live-rollout.OYdOqh/acdc_queue_fsm.before-native-proof.beam`.
Focused6 tests86399 and existing channel-I/O16 tests26126 passed; all31 strategy
groups passed in16+15 shards before the sixth focused positive-retry test was
added. See `doc/acdc_ordinary_bridge_proof.md`. Browser call-transition rendering,
cross-node/soak and restricted-user proof remain open. Preceding status POST HTTP500 regression
P0-14 is fixed in canonical `cb_agents`, six focused tests passed93704 versus
two baseline failures90610. Production build
`/usr/local/src/kazoo5-installer/live-dashboard-backend.a0U2gU` compiled74/30
modules; only `cb_agents.beam` deployed59362 with backup
`/tmp/kazoo-live-rollout.OYdOqh/cb_agents.before-status-fix.beam`.
Fix committed locally as `a7c82b1`; all14 combined live-authorization groups19162
passed afterward. Status restoration74067 and preflight10698 passed. Snapshot
77653 exactly matches the original master roster and31 reported agent states;
all eight services are active and zero calls remain. Observer diagnostic fixes
passed all12 offline groups12490; the later79231 call pass supersedes the live failure.
See task register P0-14–16 and `doc/acdc_strategy_live_acceptance.md`.

Final readback22000 saved `phone-snapshot-natural-pass.json` in the private
rollout directory; comparison with the original snapshot passed for the exact
master roster and all31 reported agent states/memberships, without restoration.
All eight services were active; apps/ecallmgr reported zero automatic restarts.
Current `/apis` assets were regenerated50258 and passed the complete offline,
deterministic and tamper suite32709. Actual installer publication52790 passed
all11 HTTP asset hashes, no-store,308 redirect and missing404 checks. Recoverable
previous assets: `/usr/local/src/kazoo5-installer/api-docs-rollback.UW8oYV/previous`.
Earlier publication attempts rolled back after a private verifier used Node
fetch, which did not preserve the intended Host header; the successful verifier
uses a bounded native HTTP request with the explicit virtual-host header.

**Authoritative live-only checkpoint — September 7, 2026:** supersedes the
older chronological checkpoints below. Historical queue/agent dashboards,
workforce reporting and ClickHouse integration are postponed. Root deployed a
coherent production build of 74 ACDC and 30 Blackhole modules, then activated
the dynamic local-registration capability flag. Native `bh_queue_live` was
added with the preserving, persistent maintenance API after an old configured
autoload list masked the new default. Real loopback HTTP/WebSocket acceptance
passed (root65638): authenticated overview/detail, anonymous and wildcard
rejection, scoped subscribe ACK, deliberate invalidation delivery, detail
refetch and unsubscribe ACK. This is not actual call-transition or load proof.

The matching UI source (`742ff77`) passed 43 offline and 24 Chromium fixture
groups. A real browser found Monster's automatic `_` parameter violating the
strict API query contract; exactly three resource definitions now suppress it,
while HTTP `no-store` remains intact. A fresh production build from
`/usr/local/src/kazoo5-installer/monster-owned-build.y1bYgn/source` passed12274
and deployed97771. Owned content, configuration, language assets, app inventory
and compatibility marker were verified; its `deployment-backup` is recoverable.
Initial adoption backups and backend backups are under
`/tmp/kazoo-live-rollout.OYdOqh`.

Subsequent browser90297 isolated a real navigation race: local unsubscribe
cleanup received the same 15-second retry delay as a server failure. Fix
`220b37b` permits three bounded one-second retries only for `cleanup_pending`;
network/authentication/server backoff stays unchanged. Root24147 passed46 offline
groups (including actual patched framework lifecycle) and24 Chromium fixtures,
then built and verified a fresh production artifact in
`/usr/local/src/kazoo5-installer/monster-owned-build.Fd3cY7/source`.
Deployment32580 changed only main/templates, removed nothing and preserved1942
files. Its `deployment-backup` is recoverable.

**Actual deployed browser65670 passed all seven checks**, receipt
`/tmp/kazoo-monster-live-deployed.tWj7DM/receipt.json`: normal login, valid
overview/detail, exact served bytes, one initial detail GET followed by a native
ACK-triggered GET before periodic repair, and acknowledged unsubscribe on
navigation. Console/page/HTTP errors, supplemental reads and new overview
requests after detail entry were all zero. Optional external fonts were omitted;
application/API/socket replies were not mocked. That browser receipt did not
test call transitions; the later79231 wire/call pass above does not establish
browser transition rendering, restricted-token isolation or load/soak. Wire30446 separately
passed available/consensus snapshots, scoped native invalidation/refetch and
negative controls. Exact roster and31 agent states/memberships remained unchanged;
all eight services were active. `/apis` is published (8385); full offline catalog,
deterministic rebuild and tamper checks82241 passed. Installer module migration
`b52988c` passed37 isolated cases and actual idempotent readback58155; it handles
the native maintenance-command exit-2 convention without accepting failed reads.
Next: restricted-user/cross-node/load
checks. Root owns serialized jobs and service windows. No master push or
enterprise-readiness claim; all ACDC source remains directly in kz5.

Final post-deployment check90474 again passed available/consensus HTTP snapshots,
native scoped invalidation/refetch and negative controls. Exact roster and31
reported agent states/memberships match the pre-deployment snapshot
(`phone-snapshot-last.json` in the private rollout directory); all eight services
are active. The browser receipt verifies navigation, while the separate wire
receipt verifies deliberate event delivery; neither claims real call transitions.

### Earlier checkpoints (superseded by the checkpoint above)

**Scope update — September 6, 2026:** the user postponed historical dashboards
and workforce reporting because ClickHouse is available for that future work.
The immediate dashboard delivery is ONLY the live queue summary and the clicked
queue's live detail, using the two supplied live designs, scoped HTTP snapshots
and native Blackhole updates. Do not build historical storage, ingestion,
reports or ClickHouse integration now. Agent state within queue detail remains
in scope; a separate agent dashboard is deferred. Neither live screen is yet
accepted/deployed. See the scope override in `PROJECT_TASKS.md`.

**Latest integration checkpoint — September 7:** `b3faf2d` now supplies authorized selected
roster/names and runtime-agent observations in the same live detail response.
Root15218 passed26 public/roster groups,24 actual DTO/OpenAPI checks,2 helpers
and15 schema groups/297 cases. Auth14 passed36984; transport34 passed82855.
Publisher `0411898` passed24 groups62617. Native Blackhole22/11 compiles passed
62617, and its ordered installer migration passed60 cases82855. These are
source/fixture results, not deployment. UI one-response adapter and sequential
subscription admission are the current integration work. Backend private build
and live wire smoke tooling are being prepared. Historical work stays deferred.

Earlier checkpoint: local `a011934` adds the
capability-gated native subscription controller. Root64066 passed32 offline UI
groups; root55555 passed18 Chromium fixture groups and20 unchanged queue-login
groups (`/tmp/kazoo-monster-live-dashboard.u5WbOa`). Local `5e6a3b6` adds bounded
runtime queue-agent observations: root64066 passed17 protocol tests and three
production compiles (`/tmp/kazoo-dashboard-agents.XzPtgX`). See
`doc/acdc_dashboard_runtime_agents.md` and `doc/acdc_live_dashboard_ui.md`.
These are source/protocol checkpoints, not live broker/agent/call acceptance.
All eight services were active after trapped development test windows. Nothing
new was deployed or pushed to master.

Current owners supersede older assignments below: root owns runtime-agent
federated/public DTO integration and validation; native agent owns dedicated
`bh_queue_live` authorization/delivery and canonical patch replay; media agent
owns post-mutation bounded invalidation publishing; browser agent owns the
live UI controller and same-scope search/focus preservation. Server event work
is still untested work in progress. Hints are explicitly lossy, with mandatory
15-second snapshot reconciliation; no broad cross-tenant resync event or new
historical storage is being added. The public WebSocket/runtime-agent capability
flags remain false until matching backend integration is ready.

**Latest tested integration:** UI commit `900efa8` uses the new bounded summary
and selected-call DTOs. It passed 22 offline dashboard groups, 20 queue-login
groups and 12 Chromium interaction groups with synthetic API responses. The
shared authorization helper passed 10 cases (93576); public routes passed
9 groups plus 2 helpers and 17 actual-handler/OpenAPI DTO checks (23014).
The refreshed catalog verified all 11 assets and 251 current source inputs;
repository assets were regenerated in 93576. See `doc/acdc_live_dashboard_ui.md`
and `doc/acdc_live_auth.md`. No new source/UI or `/apis` deployment occurred.
All temporary development service stops were restored by EXIT traps.

Next required work: implement the server `queue_live.changed.QUEUE_ID` binding
with account/queue authorization, sanitized post-mutation invalidation, bounded
delivery and token/subscription rechecks; connect the tested client lifecycle
with coalesced snapshot refresh and periodic gap reconciliation. Add bounded
runtime queue-agent observations, then coherently build/deploy and test actual
call transitions, permissions and reconnects. The shared auth helper requires
active Crossbar bindings locally and retains native token-cache policy; it is
not a standalone remote authorization service or instant revocation guarantee.

Earlier extension: selected-queue active-call rows passed 42 collector tests
(83794), 28 transport tests and 9 production-route plus 2 helper tests (52933).
The private OpenAPI catalog passed 13 groups/214 schema cases (62421). Detail
advertises its call collection; overview has `calls=null`. Agent runtime and
WebSocket capability remain false pending integration. Evidence and explicit
limits are in `doc/acdc_live_snapshot.md`. The outbound sync-status contract
fix also passed3 baseline and11 candidate regression groups (38933), source
only. Current owners: root public API/validation; native agent OpenAPI and
Blackhole authorization design; media agent Monster socket lifecycle patch;
browser-harness agent live DTO UI adapter. Historical work remains postponed.

The opt-in Monster socket lifecycle patch passed 26 offline groups, 12 installer
wiring groups and 11 preservation groups (27665). It supports account-scoped
native bindings and bounded ACK/cancellation/reconnect handling. See
`doc/monster_socket_lifecycle.md`. This client patch is not deployed and does
not itself implement the backend queue event binding or prove broker readiness.

Documentation baseline: local commit **`57b55e1`**, branch
`fix/acdc-outbound-agent-availability`, September 6, 2026. This section records
subsequent work in progress, not a new deployment. No backend/UI/native service
was deployed or restarted and no master push was performed for this snapshot.

Use this file as the front door, `PROJECT_TASKS.md` as the complete requirements
register, and the component documents linked below as the detailed evidence.
In particular, do not confuse these four states: **committed source**, **passing
tests**, **installed artifacts**, and **accepted live behavior**.

Later checkpoints: `470337e` commits the offline cardinal verifier; `cdd9329`
fixes installer atomic-intercept reconciliation; `b86979f` adds the one-time
cardinal generator (12 groups/173 checks, no real provider calls). Root's
dashboard projection now passes38 pure record-model tests in60072; see
[projection scope and next integration](doc/acdc_dashboard_projection.md).
The requested dashboards remain unfinished: no new snapshot endpoint or live
dashboard UI is deployed. Development ecallmgr was briefly paused with trapped
restoration to provide test memory; it was active afterward. This is a service
restart for validation capacity, not deployment of the new source.

Live-only follow-up: `acdc_dashboard_collector.erl` now passes 35 real-ETS
regressions and production compilation in session 7720. It fixes the collection
gap for old active calls, bounds scan/time and distinguishes missing/incomplete
local observations from zero. Evidence is in
`/tmp/kazoo-dashboard-collector.zxfQ8k`; details in the projection document above.
HTTP/AMQP authorization, cluster coverage and Blackhole/UI integration remain
open. No source was deployed; all eight core services were active afterward.

The live summary/detail UI source now passes 22 dashboard and 20 existing
queue-login groups in session 11055, following a corrected syntax failure in
16433. It removes history requests, adds clicked-queue navigation and explicit
unknown/stale/subset states. See [live UI checkpoint](doc/acdc_live_dashboard_ui.md).
It still uses legacy observed stats: the new collector, authenticated snapshot
endpoint and native Blackhole are not wired into the UI. No UI build/deployment
or real-browser acceptance is claimed.

Current live-only work supersedes the older agent assignments in the table
below. Root owns `cb_acdc_live.erl` and live `cb_queues` routes;
`native_audio_path_audit` owns the internal snapshot transport and its tests;
`media_prerequisites` owns the live OpenAPI fragment; the browser-harness agent
owns Blackhole subscription-resource cleanup. No one is generating voices or
working on historical storage in this live-only step. See
[snapshot implementation boundaries](doc/acdc_live_snapshot.md).

Final source checkpoint for this slice: federated snapshot transport passed24
in4405 (`/tmp/kazoo-dashboard-amqp.FvM34k`). Handler run70142 passed8 public-route
tests using the production no-TEST handler and2 separate pure helper tests
(`/tmp/kazoo-live-snapshot.1bZKPw`). Catalog run92359 passed11 groups/135 schema
cases, full build/11 asset verification and250 current source inputs
(`/tmp/kazoo-api-live-catalog.u6yT2M`). Blackhole cleanup passed10 in8279
(`/tmp/kazoo-blackhole-cleanup.K1n4Qf`), and all46 installer source-transition
cases passed73181 (`/tmp/kazoo-source-transition-tests.HCJE0a`); redaction
compatibility passed10 in83107 (`/tmp/kazoo-blackhole-redaction.y0qhRf`). See
`doc/blackhole_binding_cleanup.md` for the required coherent tuple-ABI restart.
Earlier fixture
failures were retained, not counted as passes. Root restored development
ecallmgr after every memory-limited test window. No new application, UI or
Blackhole source was deployed; no final master push occurred.

The source catalog assets in `scripts/assets/api-docs` were regenerated and
verified in10036; their manifest matches the private92359 proof exactly. The
live portal was not republished. Next resume with bounded selected-queue call
rows/runtime agents and account/queue-authorized Blackhole invalidation, then
wire the UI and perform coherent live acceptance. Do not mistake the new
selected-summary route's false detail/WebSocket capabilities for completion.

| Current owner / work | Where to resume | Verified state / next step |
| --- | --- | --- |
| `media_prerequisites`: cardinal audio authoring | `scripts/acdc-cardinal-pack.cjs`, `scripts/test-acdc-cardinal-pack.cjs`; [verifier evidence](doc/acdc_cardinal_pack_verification.md) | Verifier passed52469:13 groups/2,542 assertions, actual deterministic SoX PCM replay. No new recordings generated. Next: bounded one-time generator with explicit approval/request ledger; no provider calls yet. |
| Root: owned RTP/codec candidate | Private `/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-nowait.HICDXv/`, following `native-rtp-packets.OiCUA5/`; detailed checkpoint in `doc/callback_native_vertical_slice.md` | Session48223 exited0: full APR/RTP compilation and actual APR UDP helper, plain+sanitized fault tests,380 stable inputs. One send attempt avoids APR retry/wait without shared option changes. Actual RTP/SRTP branches, concurrency, linking and live calls remain open; admission closed. |
| `native_audio_path_audit`: SIP signal-processing lifetime | Private `native-signal-fence.ChqP6i` under the same private root, derived from `native-ei-dispatch.S4NXF3` and `native-passive-ready.jpGiQK` | Registry/header, signal parser and Sofia reattach edits implemented; five-TU/fixture proof authored but not run. Reserve before dequeue and retain queued events while playback unwinds. Cross-leg continuation and persistent allocation-failure recovery remain unaccepted. |
| `/root/monster_finalize/browser_harness_audit`: installer reconciliation, then RTP fixtures | `scripts/install-kazoo5.sh`, `scripts/patches/mod-kazoo-kz5-integration.patch`, `scripts/test-mod-kazoo-version-namespace.cjs`; `doc/callback_native_source_packaging.md` | Atomic-intercept reconciliation passed21 module cases68919,42 shared transition cases84663 and installer smoke78269. Initial malformed-hunk failure retained and exact contexts corrected. No install/restart. Next owner task: separate actual RTP/libSRTP boundary fixtures, not source changes to root's frozen candidate. |

Agent names are coordination hints, not services or guaranteed active sessions.
Inspect current agents, Git status and actual process handles before assigning
overlapping work. These files were intentionally **not** included in the
documentation-only commit. Never use `git add -A` to sweep in their unfinished
changes. Private native candidates are outside Git and **will not exist on a
fresh clone**: reviewed source, canonical headers, build integration and tests
must be brought into kz5 before claiming reproducible delivery.

The next release-critical sequence is: finish/review the missing prerecorded
cardinal artifacts and native ownership/output path; reconcile installer
patches; validate a coherent build; deploy matching backend/UI/media; run the
requested key-6 confirmation and unanswered-first-callback retry; then continue
the broader installer, dashboard, supervision, security and load acceptance
register. Do not regenerate the existing210 successful assets or treat this
sequence as permission to skip the other requested features.

## Quick checkpoint for the next agent

Read this file first, then [PROJECT_TASKS.md](PROJECT_TASKS.md), then the
acceptance document for the component you will change. This guide describes the
checkpoint through callback fix **`a75806c`**, French catalog **`2325d9b`** and
Hebrew catalog **`98f62cf`** and Arabic catalog **`9773c35`**,
following the UI/API baseline `61bf505`, plus explicitly identified work in
progress. A later commit containing this documentation is not a new runtime
release. Recheck Git and live state before acting.

| Area | Achieved | Not yet established |
| --- | --- | --- |
| Source ownership | ACDC is tracked directly in kz5; team recovery changes merged | Live failure/recovery acceptance |
| Queue voices | 210 immutable assets /420 WAVs packaged; actual installer verified all210 installed assets | Full natural position speech, native-speaker approval and matching runtime activation |
| Callback backend | P0-12 full87-test suite passed75590; all63 production modules compiled7787 | Coherent deployment and real callback/retry audio |
| Queue language UI/editor | Five choices, obsolete-reference deletion,42-entry callback/57-entry transitional readiness checks tested in `61bf505` | Fresh compiled UI publication and real browser/live queue acceptance |
| Developer reference | Updated static `/apis/` publication verified against all12 HTTP-served files | Documentation is not proof its backend is deployed; proposed dashboards are not callable APIs |
| Installer/services | Modular installer and offline main smoke pass; `kazoo-applications.service` resolves to active `kazoo-apps.service` | Fresh separate-server/ALL installation, reboot, interoperability and sustained load acceptance |
| Cardinal authoring | Pure EN/ES/FR/HE/AR catalog tested through `9773c35`;79,465 checks,584 roles | Reviewed contextual transcripts, missing recordings and runtime integration |
| Native callback transport | Private typed decoder/handler integration compiled;7,962 checks each plain and sanitized | Hard-closed admission; no distributed EI, full module execution or audible media acceptance |
| Release | Recent source changes committed locally through `9773c35`, documentation checkpoint `57b55e1` | Final master integration/push and remote-SHA verification |

For precise test boundaries and failed-before/fixed-after evidence, see
[canonical callback acceptance](doc/acdc_canonical_callback_acceptance.md).
Do not add test counts from different source revisions and call the sum a
single accepted release.

## 1. Repository and non-negotiable requirements

- Project: `/opt/kz5`; current branch: `fix/acdc-outbound-agent-availability`.
- ACDC is **directly tracked in kz5** under `applications/acdc`. Do not restore
  nested Git metadata, create an ACDC submodule, or commit to an ACDC upstream
  repository. Preserve the team's merged recovery changes and unrelated edits.
- The final deliverable is one modular installer, `scripts/install-kazoo5.sh`,
  supporting separate servers or ALL on one server, with actual dependency,
  named-service, repeat-install, reboot and interoperability validation.
- User wants reviewed work committed and ultimately pushed to **master**.
  The latest release has not been pushed. Do not equate a local commit with a
  deployed/published release, or force-push over other work.
- The user confirmed this host is a **development environment** and authorized
  replacement/deployment/restarts as needed. FreeSWITCH reported `0 total`
  calls during this checkpoint. Recheck before restarting; preserve accounts,
  recordings, queue configuration and rollback evidence.

Start with `git status --short`, `git log -5 --oneline`, the task register and
the relevant evidence document below. Reinspect current processes and Git state;
this handoff is a checkpoint, not a substitute for live observation.

## 2. Most important voice requirement

**Generate the required audio now, package it in this release, and never use
Gemini during installation or runtime.** No provider key or online synthesis
is allowed for calls, queue editing, account/sub-account creation or subsequent
installation of this supported release. Missing assets must fail validation,
not trigger TTS. Do not regenerate successful recordings merely to resume work.

The intended UI is one **Queue language** dropdown: **EN, HE, FR, ES, AR**.
Each has one built-in female voice. The choice applies to position/wait,
callback offers, menus, telephone readback, confirmations and error responses.
No per-prompt voice selector/custom-recording editor. Existing media documents
are retained; adopting built-in defaults must clear obsolete queue references
that otherwise silently override the language choice.

Read `doc/acdc_builtin_queue_voices.md` for the full contract.

### Audio inventory achieved

| Location under `scripts/assets/` | Effective contents |
| --- | --- |
| `acdc-gemini-fixed-20260905` | Fixed messages; failed historical entries are recovered by the completion pack |
| `acdc-gemini-completion-20260905` | Fixed recoveries plus Hebrew/Arabic telephone digits |
| The two packs above combined | 165 effective assets: 145 fixed +20 telephone digits |
| `acdc-gemini-supplemental-20260906` | **45 newly generated assets**: three auxiliary messages ×5 locales +30 EN/FR/ES telephone digits |
| Combined release | **210 effective assets /420 WAVs**, 42 assets per locale |

Voice/model: Gemini `gemini-2.5-pro-preview-tts`, **Sulafat**, requested warm
natural adult female delivery. Masters: PCM16 mono 24 kHz. Telephony: PCM16 mono
8 kHz, resampling only. Every effective recording has transcript/provenance,
hashes, duration, clipping and volume checks in its manifest.

The new 45 clips completed in **47 requests**. French zero and two each had one
incomplete response, then one successful explicit retry. Their previous attempt
records remain in the manifest; retry filenames contain `.attempt-2`. The other
valid files were not regenerated. There is no unfinished provider batch at this
checkpoint: session 7635 returned exit 0 with all 45 QA-passed.

These are **format/content-integrity checks, not listening approval**. Native
pronunciation/translation review and actual call playback remain required.
Telephone digits do **not** complete natural queue-position number composition.
The existing position contract spans 0–999,999,999. Do not silently narrow it,
spell positions digit-by-digit, or use robotic native SAY as a completed fix.

### Source/tool map

| Purpose | File |
| --- | --- |
| Exact new localized text | `scripts/acdc-gemini-supplemental-catalog.cjs` |
| Authoring only; not an installer/runtime dependency | `scripts/generate-acdc-gemini-supplemental-pack.cjs` |
| Verify actual supplemental WAVs | Same generator, `--verify-only --output /opt/kz5/scripts/assets/acdc-gemini-supplemental-20260906` |
| Create-only CouchDB import, byte readback | `scripts/import-acdc-gemini-voices.cjs` (`--supplemental-pack` adds the new pack) |
| Exact import receipt validation | `scripts/validate-acdc-gemini-receipt.cjs` |
| Deterministic 210-asset Erlang table | `scripts/generate-acdc-gemini-map.cjs`; `applications/acdc/src/acdc_gemini_map.hrl` |
| Targeted media-map activation/check | `scripts/refresh-acdc-gemini-mappings.cjs` and `.erl.template` |
| Strict built-in lookup/readback contract | `applications/acdc/src/acdc_gemini_prompts.erl` |
| Menu/key handling and durable registration feedback | `applications/acdc/src/cf_acdc_member.erl` |
| Independent announcement scheduling | `applications/acdc/src/acdc_announcements.erl` |
| Returned callback / caller confirmation | `applications/acdc/src/acdc_callback_caller.erl` |

Commit `0904240` packages the new WAVs and updates the installer to require/import/verify the 210
assets using files only. Its mapping/receipt helpers still accept the explicit
older 165 inventory for legacy verification; the new installer requires 210.

## 3. What is actually deployed versus only prepared

**The real installer media-import step passed on September 6 (session 19674,
exit 0): all 210 immutable assets were verified, with existing audio preserved.**
The receipt records **0 created, 210 preserved, 210 verified**; this run verified
existing installed assets rather than adding new documents. Its nonsecret receipt is
`/usr/local/share/kazoo5-installer/acdc-gemini-media.json`. This was the actual
`install_acdc_language_packs` function using the protected deployment settings,
not a fixture. Node/npm were already installed. The run used the validation
guard (256 MiB cap, 768 MiB reserve, 300-second deadline).

This step did **not** activate runtime media mappings, change queue configuration,
deploy the canonical backend, restart services, or prove live playback. The
receipt deliberately reports runtime/full-position readiness as false.
Canonical callback integration passed81 current-source tests; the subsequently
found fixed-inventory projection bug was reproduced and corrected, with20
focused tests passing afterward. A further42-entry projection correction passed
21 focused tests; UI30215 and editor71128 cover the matching57-entry transitional
readiness contract. All63 production modules compiled again in62912.
See `doc/acdc_canonical_callback_acceptance.md` for exact source identities and
scope. Do not tell the user the new callbacks
are ready to test until matching source/media are deployed and verified.

A fresh earlier live probe found a critical discrepancy: the loaded
`acdc_announcements` BEAM imported Gemini helpers, but tracked canonical source
still used older language/media paths. The English default offer resolved a
Gemini ID for account `302ae5a70c403124f764cbc54229cfcd`; that did not prove all
queue paths used it. A forced rebuild before source reconciliation could regress
the live behavior. **Do not blindly reverse old aggregate patches**: preserve
the newer scheduler, ownership and agent-recovery fixes.

Canonical work now implemented covers strict exact system-media paths for the
three auxiliary responses; bounded 20-second playback/21-second feedback;
correlated completion/terminal events; callback fixed-message and telephone
readback integration for all five languages; returned-call language; and
pre-resolved callback offer selection. The new **current-source** harness has
passed; coherent native/backend/UI deployment and live acceptance remain open.
The historical `test-acdc-gemini-runtime.sh`
reconstructs an older patched baseline and is not proof of this new code.

Actual service names include `kazoo-apps`, `kazoo-ecallmgr`,
`kazoo-freeswitch`, `kazoo-kamailio`, `couchdb`, `rabbitmq-server`, `nginx`, and
`haproxy`. The FreeSWITCH service is **not** named `freeswitch` on this host.
All eight were observed active. Activity alone does not establish readiness.
`systemctl show kazoo-applications.service` was rechecked for this handoff:
`Id=kazoo-apps.service`, both names present, `LoadState=loaded`, `ActiveState=active`.
The installer includes `Alias=kazoo-applications.service`; it is an alias, not
a second Erlang node. Crossbar, ACDC and Blackhole run as applications within
the Kazoo apps node, not as three independent systemd services.

## 4. Recent completed fixes and evidence

| Evidence | What it proves / where |
| --- | --- |
| Commit `e4c20e8` | ACDC expired-deadline priority and bounded event drains; 12 scheduler/worker tests. `doc/acdc_announcement_mailbox_fairness.md` |
| Commit `6bddf71` | Installer forced Erlang rebuild, targeted number/MIME regeneration and same-invocation content-drift refusal. `doc/installer_build_identity.md` |
| Commit `08bf317` | Initial central handoff, immutable voice contract and navigation links |
| Commit `0904240` | 45 supplemental recordings, provenance, 210-asset lookup/import/receipt/mapping support and installer regressions; local, not pushed |
| Commit `81b7c15` | Canonical five-language callback integration, bounded auxiliary feedback, initial-deadline preservation, fixed-projection correction and tests; not deployed |
| `/tmp/kazoo-force-recompile.8X2lwo/receipt.json` | 12 private real Make/compiler/readback commands |
| `/tmp/kazoo-generated-rebuild.a46KIZ/receipt.json` | Seven groups /17 real private generator/compiler commands; no downloads |
| Session 46576, exit 0 | Build snapshot + ecallmgr reuse + complete installer dry-run smoke |
| `/tmp/kazoo-gemini-supplemental-test.FoMcpN/receipt.json` | 11 offline authoring/retry groups; no real provider/key access |
| Session 6695, exit 0 | Existing voice import and six mapping tests, including private real Erlang template execution |
| Session 84007, partial pass then exit 1 | Actual 45-WAV verification, deterministic210 map and210-asset import tests passed; installer fixture still supplied old asset arguments and failed |
| Session 60775, exit 0 | Rerun after fixing fixture supplemental arguments: all13 installer scenarios passed, including missing assets, no-effect dry run, create-only import, verify-only and failure-before-deployment. Traces: `/tmp/kazoo-gemini-installer-tests.b2nWlC` |
| Session 19674, exit 0 | Actual installer media import and byte verification of210 assets on this host; receipt path above. No backend/mapping activation |
| Agent session 30693, exit 1 | Current production/TEST compilation passed;64 tests passed and16 success tests failed on a legacy `get_prompt/2` mock mismatch. This run was not externally resource-guarded. Corrected guarded rerun53629 passed; do not count30693 as a pass |
| Session53629, exit0 | Corrected current-source callback suite:81 tests passed; see canonical callback acceptance for input hash and scope |
| Sessions78039/15466 | Expanded fixed-media projection regression failed before count correction, then all20 focused media tests passed afterward |
| Session90582, exit0 | All63 production ACDC modules compiled with-Werror/noTEST and unchanged inputs; pure EN/ES cardinal catalog passed29,344 compositions without provider access |
| Commit `61bf505` | Five-choice UI adoption/deletion and complete callback prerequisite projection; generated and published updated queue-editor OpenAPI. Backend/UI source not deployed |
| Sessions28251/30215/71128, exit0 | Respectively21 focused media tests, UI contracts plus20 queue-login groups, and42 editor tests; exact scope and receipt paths in canonical callback acceptance |
| Session62912, exit0 | API generation/schema/deterministic build validation and fresh63-module production compilation |
| Session28926, exit0 | Actual static `/apis` publication: all12 files matched loopback HTTP bytes and cache policy; redirect/404 checked. Backup: `/usr/local/src/kazoo5-installer/api-docs-rollback.VafWMp/previous` |
| Session71503, exit0 | Main installer smoke after `61bf505`: syntax, pins, aliases, modular paths, security gates, ALL path and error handling. Guarded/offline; no installation or service restart |
| Sessions6821/75590, exit0 | P0-12 cached auxiliary metadata:22 focused then all87 current-source tests, production/TEST compilation and stable matching input digest. No timed metadata calls under poisoned resolver/store assertions; see canonical acceptance |
| Session19058, exit0 | Pure EN/ES/FR cardinal catalog: nine groups /44,040 composition checks;161 French recording roles, full range and8-token bound. No new audio generated or runtime integration |
| Session7787, exit0 | Root combined-source production compile after P0-12: all63 ACDC modules,-Werror/noTEST and stable inputs. No installed BEAM changes |
| Commit `98f62cf`; session50243, exit0 | Pure EN/ES/FR/HE catalog:12 groups /61,747 checks;131 reachable Hebrew roles,11-token bound. No recordings generated or runtime changes. Hebrew number-label context remains subject to intro/transcript review |
| Commit `9773c35`; session20652, exit0 | All five pure cardinal grammars:15 groups /79,465 checks;208 Arabic roles reachable,9-token bound. Arabic transcripts and pausal/intro context remain provisional. No generation or runtime activation |
| Session27998, exit0 | Private normal-writer corrections compiled against real headers with353 stable inputs and ordinary-body comparison. Earlier128MiB attempt21632 was cgroup OOM-killed;224MiB retry kept768MiB reserve. See native continuation guide for exact source/receipt and unclosed behavior/lifetime gates |
| Sessions23159/17639/64711, exit0 | Passive queue/readiness helper:182 plain +182 sanitized cases; integrated full writer TU with355 pinned inputs;64 extracted wrapper/helper cases. Explicit doubles and no real RTP/SRTP/bridge execution; detailed source/receipts in native continuation guide |

Temporary receipt paths are local evidence and may not survive a new server.
The durable test implementations and explanatory documents are in Git/worktree.
Update this section with final outcomes rather than deleting failed evidence.

## 5. Immediate next work

1. Integrate/deploy P0-12 coherently. Its source review, full87-test suite75590
   and all63-module production compile7787 passed: the three auxiliary paths are
   cached before queue entry and timed feedback performs no metadata IO. Keep
   this evidence separate from the older81-test checkpoint. Main installer smoke71503 already passed; rerun
   after further installer integration changes. Never restart a still-running job
   just because an observation timed out.
2. Preserve/review the accepted canonical callback changes and rerun
   `scripts/test-acdc-gemini-canonical-callback.sh`, callback feedback/menu,
   caller/announcement regressions and production compilation after further
   coupled changes. The corrected success fixture, built-in success coverage,
   early deadline/manager-monitor regression and input pins passed in53629;
   subsequent fixed-count correction passed focused verification in15466.
3. Deploy and browser-test the UI adoption/readiness contract implemented in
   `61bf505`. Constructor/selection tests and persisted in-memory merge regressions
   passed; do not redo this as if unimplemented. Adoption deletes obsolete prompt
   references, including when the current English choice is saved without a
   change event. The API's merge/deletion behavior matters: `{}` can recursively
   preserve old values.
   Both the unified editor merge and normal Crossbar queue PATCH remove null
   keys: null on the wire is a deletion marker, not a value to retain. Preserve
   the existing persisted-document regressions when updating this behavior.
   **Do not blindly persist `callback.return_confirmation_prompt: null` or
   `callback.media.returned_confirmation: null`: current helper code treats
   these as explicit invalid configuration and fails closed.** Either ensure
   the fields are absent after the update, or deliberately implement and test
   null-as-deletion semantics at that boundary. Do not delete media documents.
4. Finish the prerecorded position-number catalog/compositor for all five
   languages, generate missing release artifacts once, and verify natural
   playback. `doc/acdc_prerecorded_cardinal_design.md` records the finite catalog
   design and unresolved linguistic gates. `scripts/acdc-cardinal-catalog.cjs`
   is now a tested pure EN/ES/FR/HE/AR full-range building block, not runtime integration
   or recorded assets. Arabic has208 provisional contextual recording roles,
   with pausal delivery/intro compatibility still requiring review. Hebrew is an abstract feminine
   number-label context with masculine scale coefficients, not approval of the
   existing intro's grammatical fit. Do not enable a full-language
   capability based on native SAY.
5. Verify the imported receipt and activate the targeted mappings with validated
   node/hostname settings; deploy the coherent backend/UI
   and native media fixes, and run the actual key-6/30-second-offer/confirmation/
   unanswered-first-attempt retry scenario. Inspect logs and queue/agent state.
6. Continue the remaining task register; voice completion alone does not close
   the original platform goal.

Ownership at this checkpoint: `native_audio_path_audit` handed back the P0-12
helper/member and related canonical/feedback/integration tests, committed in
`a75806c`. Installer
71503 finished and its validation window was released; focused run6821 exited0
with22 media/helper/contract tests passing, production/TEST compilation and
source pins checked. Input digest:
`5bcd7e76678f42988001ad768c391fd272401d2ec8b6d4b48eab975a73759ea8`.
The full lifecycle/timer suite75590 subsequently exited0 with all87 tests and
the same digest. The serialized test window was released for French validation,
then root's production compile. These are source checks, not live acceptance.
`media_prerequisites` completed French, Hebrew and Arabic pure catalog work in
`scripts/acdc-cardinal-catalog.cjs`, its test and
`doc/acdc_prerecorded_cardinal_design.md`; commits `2325d9b`, `98f62cf` and
`9773c35`. Arabic20652 passed all79,465 combined checks:208 context-specific
roles are reachable and the9-token bound is tested. This is **not approved
authoring text or recorded audio**. Existing Arabic intro
`مَوْقِعُكَ الحالي هُوَ.` does not explicitly introduce a number; preserve current
position semantics and review compatibility before choosing new recordings.
No generation or runtime edits have been made for this catalog. The next media
slice implements a provider-free cardinal manifest/WAV verifier and tests,
before one-time authoring and create-only import. Approval is separate from
technical waveform QA. The584-role map must stay separate from the210 callback
rows so callback-completeness checks do not accidentally include cardinal roles.

`native_audio_path_audit` handed back the private typed transport candidate and
its terminal7634 proof; root owns the private normal-codec derivative. Their
exact locations, review defects and next steps are in
[native callback implementation handoff](doc/callback_native_vertical_slice.md).
Work resumed after the documentation freeze: native passive-readiness and
normal-writer behavior fixtures passed in23159/64711; the next native slice
addresses pending SIP signal processing vs full PLAY lifetime, with cross-leg
continuation explicitly still open. The later RTP/codec derivative compiled
both production units in13529; see the latest snapshot above. No root validation
job remained running when that compilation window was released.
These names and job observations are coordination hints, not persistent services:
inspect current messages/processes before resuming. Never blanket-stage another agent's
unfinished source changes with a documentation commit.

### Safe next-agent verification commands

Run from `/opt/kz5`. These validate current files without deploying or calling
Gemini; the receipt check validates inventory identity, not fresh database bytes.

```bash
git status --short
git log -5 --oneline
node scripts/generate-acdc-gemini-map.cjs --check
node scripts/validate-acdc-gemini-receipt.cjs \
  --fixed-pack /opt/kz5/scripts/assets/acdc-gemini-fixed-20260905 \
  --completion-pack /opt/kz5/scripts/assets/acdc-gemini-completion-20260905 \
  --supplemental-pack /opt/kz5/scripts/assets/acdc-gemini-supplemental-20260906 \
  < /usr/local/share/kazoo5-installer/acdc-gemini-media.json
bash scripts/run-kazoo-validation.sh \
  --memory-mib 256 --reserve-mib 768 --runtime-sec 600 -- \
  /usr/bin/unshare --net /usr/bin/bash \
  /opt/kz5/scripts/test-acdc-gemini-canonical-callback.sh
```

Do not run the heavy test alongside another guarded job. A missing temporary
session/receipt is not a passing test; rerun the checked-in harness and record
the source identity, terminal exit status and limitations. To inspect the live
host, use `systemctl is-active` with the service names above,
`journalctl -u kazoo-apps -u kazoo-ecallmgr --since '10 minutes ago'`, and
`/usr/local/freeswitch/bin/fs_cli -x 'show calls count'`. Logs can contain private
call/account data: summarize relevant errors rather than publishing raw dumps.

## 6. Wider goal: where remaining work is tracked

### Component navigation

Paths below are repository-relative unless explicitly absolute. Follow the
linked acceptance documents for exact source versions, test commands and gaps;
the existence of a module is not evidence of successful deployment.

| Workstream | Canonical source / entry point | Guidance / acceptance |
| --- | --- | --- |
| Modular deployment | [scripts/install-kazoo5.sh](scripts/install-kazoo5.sh), `scripts/test-install-kazoo5*.sh` | [Installer checkpoint](doc/installer_regression_acceptance_20260906.md), [build identity](doc/installer_build_identity.md) |
| ACDC agent recovery | `applications/acdc/src/acdc_agent_fsm.erl`, `scripts/test-acdc-agent-recovery.sh` | [Recovery plan](doc/acdc_agent_recovery.md), P0-05/07/08/09 |
| Unified queue editor and login | `applications/acdc/src/cb_acdc_queue_editor.erl`, `applications/acdc/src/cb_agents.erl`, `monster-ui/acdc/app.js` | [Editor acceptance](doc/queue_editor_acceptance.md), [ACDC UI guide](monster-ui/acdc/README.md), P0-01 / ACDC-01 |
| Callback/menu/scheduling | Source table in section2; `scripts/test-acdc-gemini-canonical-callback.sh` | [Canonical tests](doc/acdc_canonical_callback_acceptance.md), [callback acceptance](doc/acdc_callback_acceptance.md), P0-03/04/10/11/12 |
| Native audio and coherent rollout | Installer's Kazoo FreeSWITCH integration; private candidate is NOT the deployed source | [Current implementation handoff](doc/callback_native_vertical_slice.md), [native link readiness](doc/callback_native_link_readiness.md), [coherent upgrade](doc/acdc_coherent_upgrade_readiness.md) |
| Company members/device status | `applications/crossbar/src/modules/cb_members.erl`, `scripts/api-docs-members-devices.cjs` | [Members/device evidence and limits](doc/members_devices_acceptance.md) |
| Listen/whisper/barge/join | `applications/crossbar/src/cb_channel_monitor.erl`, `scripts/test-channel-monitor-live.cjs` | [Monitoring acceptance](doc/channel_monitor_acceptance.md), SUP-01–03 |
| Native WebSocket transport | `applications/blackhole/src/`, `scripts/api-docs-blackhole.cjs` | [Resilience](doc/blackhole_resilience.md), [authorization results](doc/blackhole_binding_results_acceptance.md), BH-01–05 |
| Live/history dashboards, workforce | `monster-ui/acdc/`, supplied `dashboards design/` files; required new contracts remain open | [Dashboard/workforce brief](doc/dashboard_delivery_plan.md), DASH-01–09 / WFM-01–04 |
| OpenAPI and Next.js reference | `scripts/build-api-docs.cjs`, `scripts/api-docs-*.cjs`, generated `scripts/assets/api-docs/` | [Developer portal](doc/api_developer_portal.md); public `/apis/`, `/apis/openapi.json`, `/apis/blackhole.html` |
| Browser console/build | `monster-ui/acdc/`, `scripts/monster-build-inputs.cjs` | [Console acceptance](doc/monster_console_acceptance.md) |

The served static root is `/var/www/html/monster-ui`; do not treat edits there
as durable source fixes. Change tracked source/generators first, rebuild and
validate, then publish with a backup. The latest API-only backup is
`/usr/local/src/kazoo5-installer/api-docs-rollback.VafWMp/previous`.
Current-source production compilation is driven by
`scripts/test-acdc-production-compile.sh`; private compilation is not a hotload.

### Installer usage and scope

The entry point accepts component names, not a separate script for every host:
`couchdb`, `rabbitmq`, `haproxy`, `kazoo-apps`, `ecallmgr`, `freeswitch`,
`kamailio`, `monster-ui`, or `all`. Inspect supported flags without deployment:

```bash
bash scripts/install-kazoo5.sh --help
bash scripts/install-kazoo5.sh --list
```

For distributed deployments, the existing flags include `--couchdb-host`,
`--amqp-host`, `--api-url`, `--api-upstream`, `--public-ip` and
`--erlang-dist-ip`. TLS uses `--hostname`, `--tls-cert`, `--tls-key` and optional
`--tls-chain`. Supply credentials through protected configuration, not examples,
shell history or documentation. Use the **Kazoo** FreeSWITCH/Kamailio builds and
pinned integration checks; do not substitute a stock package or latest version
without compatibility validation. Keep `sup` verification in the apps workflow.

`--dry-run` is a planning/fixture check, not proof an installation works.
`--verify-only` does not install modules, but some checks authenticate to
Crossbar and may create authentication tokens; inspect the selected verifier
before describing it as strictly read-only. Normal component/ALL invocation
can install packages and alter configuration/services: it is not a status probe.
Fresh-host deployment remains a release requirement, not something established
by the examples or offline installer smoke.

- `PROJECT_TASKS.md`: P0 call delivery/recovery/callback acceptance; unified queue
  editor; company members/devices/status; supervision audio/security; Blackhole;
  live/historical dashboards; workforce sessions/break types/reports; installer;
  TLS, load/soak, backup/restore/failover and final release.
- `doc/acdc_coherent_upgrade_readiness.md`: multi-module/source/runtime upgrade
  risks. A single-module hotload is not the complete rollout.
- `doc/installer_regression_acceptance_20260906.md`: existing build/browser and
  installer checkpoint evidence and explicit limitations.
- `doc/blackhole_resilience.md` and
  `doc/blackhole_binding_results_acceptance.md`: native WebSocket robustness and
  authorization work. Reuse Blackhole; no duplicate transport service.
- `doc/api_developer_portal.md`: OpenAPI developer portal publication/evidence.
  `/apis` includes implemented contracts and clearly marked proposals. The
  register reports 356 paths /651 operations; verify fresh source/output before
  quoting it as the current release. Dashboard proposals are not live endpoints.
  Latest static publication28926 includes the built-in-language PATCH deletion
  example, separate create schema and57-entry prerequisite bound. Twelve files
  matched HTTP bytes; no backend/UI bundle deployment or TLS claim is implied.
- `/opt/kz5/dashboards design/`: supplied design references. Dashboard/WFM tasks
  remain open; do not mistake this voice work for their completion.

Outstanding release blockers include real native audio/call ownership tests,
five-language listening, clean/separated-server installs, sustained30 concurrent
calls (not80 calls/sec certification), broker/node failures, TLS/WSS and security.
The last TLS audit found certificates without a matching private key under
`/root/ssl`; recheck/provision with appropriate authority, never invent success.

## 7. Secrets, resources and release discipline

- `/root/key.key` is a protected root-owned0600 file containing distinct Gemini
  and GitHub credentials. Select by provider; never print/copy/commit its text.
  The old token pasted in chat must not be reused. GitHub auth/push is unverified.
- `/etc/kazoo/deployment.env` is protected persisted deployment configuration.
  The installer decodes validated key/value data; do not print secret values or
  replace it with an unsafe shell evaluation. Audio manifests contain no keys.
  `/etc/kazoo/installer-secrets.env` is also protected; do not include its contents
  in evidence or a handoff.
- Use `scripts/run-kazoo-validation.sh` for resource-bounded heavy validation.
  Recent runs use256MiB cap,768MiB reserve and a task-appropriate deadline;
  offline tests additionally use `unshare --net`. Do not remove the reserve to
  force a test through. Serialize guarded jobs on this small host.
- Generate real audio only in explicitly authorized authoring work; **never**
  put authoring commands in an install hook, runtime path or account workflow.
- Preserve dirty worktree changes. Review/scan/test scoped changes before commit.
  Final master push requires the complete requested release and remote-SHA
  verification. Do not mark the active goal complete while any required item is
  missing, only mocked, untested, undeployed or merely documented as planned.

## 8. How to leave a reliable handoff

At the end of each workstream, update this guide and the corresponding task row.
Keep detailed evidence in its component acceptance document, rather than making
this navigation file an unbounded execution log. Record:

1. Date, branch, commit and any still-uncommitted files; preserve other owners' work.
2. What changed and the canonical files, including installer/assets/API implications.
3. Exact test command, source hash/receipt, terminal exit status and what was mocked.
   A running, timed-out or missing session is not a successful test.
4. Whether anything was deployed, the installed artifact identity, backup location,
   services restarted, and post-deployment checks. Say explicitly if nothing deployed.
5. Remaining gaps, next executable step and active agent/test ownership.
6. Commit/push status and verified remote SHA if published. Never include credentials.

Prefer evidence tied to the relevant source hash over an older broad "passed"
summary. `/tmp` receipts, tool session IDs and private native candidates may
disappear; retain reproducible harnesses and the scoped result in Git. Never
assume an old live check certifies a newly rebuilt module or a different host.
