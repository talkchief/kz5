# Kazoo 5 project task register

New or returning contributors: read [the engineering handoff](PROJECT_HANDOFF.md)
first for achieved work, deployment status, source locations and next steps.

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

Updated: 2026-09-06. This is the project-wide priority/status index. Detailed
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
| P0-01 | ACTIVE — API + UI | Queue-specific Login: backend committed `4fc2a2b` with 12 isolated regression groups passing and exact fresh pinned installer-patch replay; explicit-selection UI committed `d263342` with focused/full contract passes. Source-bound OpenAPI overlay/reference committed `22b5f94`, with 9 focused groups / 45 schema cases passing. No silent roster changes or other-agent logout; membership is not readiness. Regenerate/publish `/apis`, deploy and test selected-agent ringing. |
| P0-02 | OPEN — acceptance | Re-test extension 2000 after the operator selects the intended queue agent. Observed roster Agent 12 logged out; globally ready Agent 19 unassigned; runtime knows no eligible agents. Do not reset all agents to conceal the mismatch. |
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

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| DASH-01 | ACTIVE — UI source tested; not deployed | Live queue overview using `Queues Live Dashboard Main.png`: sortable queue cards, SLA, waiting/handled/abandoned counts, wait/handle durations, queue administration actions. Source summary/detail navigation passes22 dashboard groups and20 queue-login groups in11055; see doc/acdc_live_dashboard_ui.md. Still legacy observed-stat subset; bounded snapshot/Blackhole wiring and full design/live acceptance open. |
| DASH-02 | ACTIVE — UI source tested; not deployed | Clicking a queue opens its live detail using `Queues Live Dashboard.png`: KPI cards, queue-scoped agent/call states, search/filter/sort, performance and authorized spy/whisper/barge/join controls. Source summary/detail navigation passes22 dashboard groups and20 queue-login groups in11055; see doc/acdc_live_dashboard_ui.md. Still legacy observed-stat subset; bounded snapshot/Blackhole wiring and full design/live acceptance open. |
| DASH-03 | ACTIVE — projection and local collector tested; API open | Bounded account/queue dashboard snapshots with source timestamps, completeness, pagination and authorization. acdc_dashboard_projection now consumes actual call_stat records with bounded queues/rows, separate occupancy/cohort counts, conflict/scope/timeline rejection and explicit incomplete/identity limits;38 tests passed60072. See doc/acdc_dashboard_projection.md. Local collector now passes35 actual ETS tests in7720, bounds all visited keys and time, retains older active calls, releases fixation and rejects table replacement. Authenticated source/API integration, cluster coverage, queue runtime eligibility, HTTP/OpenAPI and live UI still required; no full historical visit claims. Existing stats ignores Limit and its recent-entry filter can omit older active calls; wrapping that API is not a complete snapshot. |
| DASH-04 | OPEN — events | Reuse native Blackhole for authenticated account/queue-scoped WebSocket updates, not a duplicate transport server. Snapshot/event ordering, duplicate/gap handling, reconnect/resubscribe/resync, server-side token expiry/revocation, stale indicators, bounded buffers and multi-node ownership. Native delivery is best effort and has no durable replay cursor; account-hierarchy checks are not queue permissions. No silent polling-only substitution. |
| DASH-05 | OPEN — API + docs | Define/version dashboard request, response and event schemas. Publish HTTP contracts in OpenAPI at `/apis`, link WebSocket message/subscription/lifecycle documentation; distinguish proposals from deployed endpoints. Test schema conformance and tenant isolation. |
| DASH-06 | POSTPONED — UI + reporting | Queue historical dashboard using `Queue Historical Dashboard.png`: time/queue filters, call outcomes, SLA, wait/handle/talk metrics, details and export. Reconcile counts, timezone boundaries and late events. |
| DASH-07 | POSTPONED — UI + reporting | Agent historical dashboard using `Agent Historical Dashboard.png`: agent/queue/date filters, last activity, outcomes, talk/break/idle durations, details and export. Define attribution for transfers/multiple queues. |
| DASH-08 | OPEN — API + Next.js acceptance | Explicit company/account, queue and agent filtering contracts for snapshots and native Blackhole subscriptions. Company means Kazoo ACCOUNT_ID, not a free-text company name; enforce tenant and queue/agent permissions on the server, including wildcards and reseller/sub-account access. Document selected-queue and selected-agent examples, supported filters, unauthorized/unknown IDs and switching scope without leaking old events. Existing generic call bindings are not queue dashboard bindings. Test isolation, reconnect/resnapshot and filter changes with a real Next.js integration before marking ready. |
| DASH-09 | POSTPONED — API + docs | Add live agent dashboard contracts alongside company queue overview, selected-queue live detail and queue/agent history. Publish versioned HTTP request/response/error schemas at /apis and linked WebSocket bindings/event schemas, with copyable Next.js examples. Clearly label planned versus implemented versus deployment-tested contracts; do not advertise invented dashboard routes as callable. Test actual responses/events against schemas and exercise examples against the matching deployment. |
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
