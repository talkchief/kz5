# Kazoo 5 acceptance status

Latest progress review: 2026-09-06 00:50 UTC. **Acceptance is incomplete. Do not treat
active services or this document as production certification.**

## Host memory incident and deployment hold

The 23:27 global OOM event killed a Codex worker, and both Kazoo nodes recorded
new AMQP timeouts. The broker alarm cleared and read-only checks observed
reconnected clients without platform restarts. Serialized, verified cgroup
controls are now in place and the current-source 62-test Gemini/callback suite
passes under them. The thirty test phones are registered again; actual contacts,
30-online/1-offline directory results and unchanged one-agent roster/statuses
passed after the isolated test-supervisor recovery. A subsequent isolated live
callback retry also passed; its scope is recorded below, not load certification.
See [the incident evidence and remaining gates](host_memory_incident_20260905.md).

A real resource-capped private Monster UI `npm ci` failed on the pinned upstream
lock's inconsistency. The initial narrow repair subsequently passed clean CI,
native Sass/RE2 rebuild and native smoke, but Gulp then failed on incorrectly
resolved dependencies. A corrected private lock passed clean CI with 1,130
required dependency nodes, native rebuild and smoke. Full Gulp progressed to
JavaScript minification but failed V8 heap limits at both 192 and 256 MiB. Neither
failure was a cgroup OOM. A separate-process minification build is being tested
within the unchanged hard resource cap. The live UI was not replaced. A usable clean build remains required;
no provenance marker is being changed to hide these failed build gates.

## Post-incident callback retry — 2026-09-06 00:43–00:49 UTC

Run `20260906T004339Z` exited 0 after its scoped cleanup. The initially busy agent
remained bridged while the second caller pressed 6 at 4.985898 seconds after
answer. The complete 5.491-second installed Gemini/Sulafat confirmation arrived
before server BYE, with correlation 0.999993 and zero missing phrase samples.
This is received PCM evidence, not human transcription or native listening approval.

After the explicit two-second post-proof wait, the first conversation was released
6.927460 seconds after confirmation (including capture/proof work). The first
callback attempt was deliberately unanswered for 15.204356 seconds. Durable
`retry_wait` was observed. The second INVITE arrived 17.737096 seconds after
cancellation, 0.763160 seconds after the recorded retry due time. The confirmed
second attempt formed the reciprocal native bridge and delivered 4,912 PCMU
packets in each agent direction.

The harness recorded zero new errors/cores and unchanged checked service
PIDs/restart counts. Native calls were zero after cleanup; both current Kazoo
crash logs remained empty and the persistent test supervisor still reported
30/30 registered phones with its same PID. Historical unresolved fixture state
remains retained. This does not prove MASTER/MicroSIP/PSTN routing, full fixture
cleanup, multi-node behavior, sustained load or production readiness.

The preceding `20260906T003353Z` attempt failed during isolated setup, before
SIP, because the bounded validation environment omitted the account home needed
by Erlang/SUP. That failure and its possible setup writes are retained. The
[guard repair and read-only verification](validation_resource_guard.md) are
committed in `c023d33`; the callback pass is the subsequent run, not a relabeling
of the failed attempt.

## Queue editor and standalone-apps checkpoint

The explicit English dropdown/API validation mismatch is repaired and deployed.
The 22:50–22:51 isolated real create/edit/replay/conflict/cleanup sequence passed
without agent changes. The separate 22:36 full browser check passed with one
unified editor GET, zero catalog fanout and no JS/HTTP errors. See
[the recorded scope and log warnings](queue_editor_acceptance.md).

The apps-owned negative capability manifest and custom configuration-root path
are now integrated in installer source. All 31 editor/path backend tests and
11 memory-only initializer groups pass, as do order/unit-wiring checks.
No live manifest or service was changed by this portability integration.
A fresh-source audit identified 17 generated legacy WAVs incorrectly included
alongside 175 pinned official recordings by the old broad scan. Committed source
now reads the exact official Git-pin blobs and preserves existing recordings.
Editor prerequisites validate the actual 44 English runtime media documents,
including immutable Gemini IDs, rather than fabricated legacy aliases. Source,
31 backend tests and private UI tests pass; this newer media-prerequisite
mapper/editor/UI combination is not deployed yet.

The private simultaneous-answer repair also uncovered a DTMF queue-exit race:
the callflow can continue before the queue confirms media ownership closure.
The candidate remains isolated until its acknowledgement contract and live
acceptance pass. Unit tests alone do not authorize its rollout.

## Live verifier and network checkpoint — 22:32 UTC

The actual all-module verification caught a RabbitMQ CLI hang that the mocked
password tests missed: installed 3.13.7 disables stdin when `-q` adds a third
argument to its password command. The protected two-argument authentication
probe passed. The installer helper now uses exactly two CLI arguments with a
finite timeout; all 32 regression scenarios pass, including hung-client
termination. Verification reads only an existing configured master ID/catalog,
uses already-loaded SUP modules and read-only SQLite, and avoids the RabbitMQ
root plugin wrapper's cookie-permission repair. The failed audit is retained.
The actual unwrapped post-fix `--verify-only all` completed in 52.675 seconds and
exited 1 solely on the Monster UI bundle fingerprint. CouchDB, RabbitMQ, HAProxy,
Kazoo apps, eCallMgr, FreeSWITCH and Kamailio verification passed; nginx is active
and enabled. Separate HTTP/same-origin API and ten-app catalog checks passed,
but do not waive the mismatch: the marker describes an older bundle while live
UI changes were incremental. Reconcile its provenance/build without merely
overwriting the marker or removing operator-installed apps. Public HTTPS still
refuses port 443, and the current five-language capability manifest keeps every
full-pack readiness flag false. See the [exact verifier receipts, repair and
limits](installer_verification_checkpoint.md).

The test phones' 30 wildcard UDP control sockets are now protected by one
narrow non-loopback-input rule, after exact ownership checks. No phone or
application restarted and no SIP/RTP/SSH rule changed. Future phone starts use
explicit loopback control binding, verified by mock-only tests. Broader public
listener policy, TLS and external security acceptance remain open; see the
[network checkpoint](network_hardening_checkpoint.md).

## Gemini rollout checkpoint — 22:02 UTC

All 165 immutable Gemini recordings were freshly downloaded and byte-verified
without database writes. The new installer verifies them before building or
restarting applications, removes synthetic ACDC generation, and preserves
official/customer media. Eleven offline installer scenarios, thirteen invalid
receipt cases, create-only rerun tests and packaged-path safety tests passed.
The reviewed default runtime layer compiles with production warnings and passes
62 tests; its default/language/atomic patch replay remains separate and exact.

The first live Gemini retry test, `20260905T213514Z`, **failed** the received-audio
gate. The callback registered, but the running media managers had no mappings
for the new Gemini IDs and returned no playable URL. Direct CouchDB import does
not populate these ETS caches. Both `media_map` and `kz_media_map` need verified,
targeted activation on the resolver node; clearing unrelated caches is unnecessary.
The three consumer modules were initially restored to the exact working baseline
without restarting services. Preserve that failed result: it is not a successful
Gemini callback or a regression of the earlier legacy-audio proof.

The targeted refresh subsequently verified all 330 mappings across both caches,
with no database writes or unrelated cache flush. Actual AMQP media-manager
lookup and HTTP downloads matched the menu and success WAV hashes. The verified
consumer modules were reactivated without restart (backup
`gemini-defaults-live-deploy.qZQbd6`). **Gemini English fixed defaults are active.**

Live run `20260905T215059Z` exited zero. Digit 6 arrived 4.989034 seconds after
answer; the entire 5.491-second Gemini confirmation arrived before server BYE
(correlation 0.999993, zero missing phrase samples). The first callback remained
unanswered for 15.292843 seconds. A second INVITE arrived 17.837644 seconds after
cancellation, 0.853395 seconds after the durable retry due time; the confirmed
second attempt formed the reciprocal native bridge and delivered 4,919 PCMU
packets in each agent direction. Busy-call release was 5.788443 seconds after
confirmation, including the explicit two-second wait and proof-processing time.
Final error counters were 0/0, new cores zero, and service PIDs/restarts unchanged.
Cleanup returned native calls to zero. Historical unresolved fixture state is
retained; this is not MASTER/PSTN, multi-node, full cleanup or load certification.

The default-source Gemini patch and portable replay suite are packaged. All 62
tests pass from the pinned installer source, with production warnings and
actual-input freshness checks. Portable installer cache activation is packaged;
six helper groups, twelve install-flow scenarios and the actual read-only
165-document/330-mapping verification pass. Remaining numeric and auxiliary recordings prevent a complete
five-language claim. A separate
150/500-request supplemental generation proposal is awaiting approval; no new paid
requests were made. Existing recordings and transcripts are committed locally in
`2cc1022`; remote push remains blocked by missing working GitHub write credentials.

The wider release gates remain open: HTTPS has no port 443 listener, the matching
private key is missing, full 30-call drain and simultaneous-answer repair have
not passed, and clean-host,
separated-host, failover and backup-restore acceptance are not complete. All eight
requested services are active/enabled; that is not enterprise or HA certification.

## Members API and installer checkpoint — 22:12 UTC

`GET /v2/accounts/{ACCOUNT_ID}/members/devices` is deployed and persisted in
Crossbar autoload, with its built-in route preserving existing custom-route
configuration. The live MASTER-admin test passed31 members/31 devices across
two pages:30 online,1 offline at the recorded time. Anonymous and invalid-query/
different-account-cursor checks passed; catalogs were unchanged. Thirteen
offline backend/auth groups and nine schema/harness groups pass. Actual
restricted-token/cross-account-principal tests and cluster-failure cases remain
unverified. See [the API evidence and exact limits](members_devices_acceptance.md).

The deployed `/apis/` main source catalog contains354 paths,649 operations and
471 schemas. Local source/manifest/negative-schema checks pass; the members route
is no longer labeled planned. Public docs contain no credentials or active API
execution controls. HTTPS remains blocked independently of HTTP docs delivery.
The browser repeat passed all649 operations with eight same-origin requests,
zero external requests or console errors, disabled API execution/token storage
and planned-spec isolation. An earlier10-second render wait timed out while
other tests ran on this constrained host; it was retained as a failed run. The
unchanged timeout passed after heavy concurrent testing paused. The harness
requires its existing Node20+ Playwright toolchain, not the system Node18.

All nine existing offline installer shell suites pass, covering modular endpoint
selection, pinned builds, service gates/aliases, protected cookies/bootstrap,
production-BEAM gates, prompt ordering, logging and CouchDB security. Bash syntax
and ShellCheck warning/error checks pass. RabbitMQ stdin password handling passed
29 isolated scenarios. None of these is a clean-host/distributed deployment,
backup restore, failover, traffic-safe upgrade or sustained-capacity certificate.

## Unified editor and browser checkpoint — 20:59–21:02 UTC

The account-scoped editor backend and compiled Monster ACDC component are now
deployed. The real browser test passed with one editor GET, zero separate catalog
requests, zero JavaScript errors, zero HTTP failures, and all API traffic on the
same HTTP origin. The independent callback-announcement enable/delay/interval
controls passed serialization and validation checks; custom recording selectors
are hidden and existing selections are preserved internally.

The isolated live API run `queue-editor-live.pkUEWo` passed create, edit, identical
create/edit replay, changed-body idempotency rejection, stale queue revision
rejection, fresh GET, managed-route removal and exact-CAS queue cleanup. No users
or agent memberships changed. Three completed operation receipts and one released
extension claim remain as normal audit records. The test queue and route are no
longer API-visible. No new error-priority journal entries or crash-log growth was
observed in the checked window. Restricted-token and cross-node authorization
tests, roster writes and ambiguous partial-write recovery still need live coverage.

The repair preserved strict tenant checks: the Couchbeam query needed the atom
`include_docs`, not the silently ignored tuple. The backend now handles the
explicit legacy English media manifest without claiming other languages ready.
Twenty-six offline editor groups and the real client query-parser checks passed.
Protected UI rollback: `monster-acdc-editor-deploy.9OwDJL`; latest helper rollback:
`queue-editor-catalog-fix.QHBPZD`, both under the installer build directory.

Gemini fixed clips are imported but default activation remains in progress.
HTTPS remains unavailable pending the missing matching private key or replacement
certificate authorization. HTTP browser/API success does not establish TLS.

## Latest callback retry result — clean isolated repeat (20:17 UTC)

A subsequent run, `20260905T210254Z`, also exited zero after the accepted-success
loop follow-up: digit 6 at 4.989387 seconds, full confirmation before BYE, first
return unanswered for 15.099118 seconds, then a confirmed/bridged retry after
17.980275 seconds. Both audio directions progressed; log errors were 0/0 and
new cores 0. Service PIDs/restart counters remained unchanged. This still proves
legacy English audio, not the pending Gemini default switch. See
[the follow-up details](callback_controls_deployment.md#accepted-success-follow-up--approximately-2030-utc).

Run `20260905T201353Z` exited **0**, after the dispatcher/authentication repairs
and callback control-lifecycle update. The requested one-agent scenario passed:
digit 6 at 4.996163 seconds, the full 6.124-second installed confirmation before
server hangup (zero missing samples, correlation 0.999991), a deliberately
unanswered first attempt lasting 15.752454 seconds, durable `retry_wait`, and
an answered/confirmed second attempt with a reciprocal native bridge. The next
INVITE arrived 17.750068 seconds after first-attempt cancellation, consistent
with the configured 15-second minimum backoff and measured scheduling overhead.
There were 4,916 progressing PCMU packets in each agent direction. The busy call
was released 5.974260 seconds after confirmation: the explicit two-second wait
plus evidence-processing overhead, not exactly two seconds.

The strict log gate recorded zero journal/file error matches and no new core
dumps. Checked service PIDs/restart counters remained unchanged during the call
run; cleanup exited zero and native FreeSWITCH calls returned to zero. Apps and
ecallmgr crash-log sizes/timestamps were unchanged. Protected evidence is under
`/var/log/kazoo-acceptance/20260905T201353Z`.

This is the isolated local test, not the user's MicroSIP/PSTN route, cross-node
failover, a sustained-load test or full fixture cleanup. An older unresolved
callback document is deliberately retained pending positive reconciliation.
The independent callback-offer scheduler also passed its 19:35 UTC timing/audio
test. The browser/editor checkpoint above supersedes their earlier deployment
gap; complete voice activation, HTTPS key availability and other unchecked tasks
remain open.

## Earlier callback retry result (16:20 UTC)

The requested one-agent busy-call/callback/retry scenario passes its strict
live functional and packet gates in run `20260905T161308Z`: entry digit at
4.9892 seconds, complete received 6.124-second confirmation, first callback
unanswered for 15.103999 seconds with the complete cancellation transaction,
then a retry 17.735992 seconds after cancellation that confirms and bridges
the same agent. The ticket completes on attempt two with its enqueue identity
preserved; 4,916 progressing PCMU packets are verified in each direction.
The initial conversation was released 5.796588 seconds after prompt completion
(two-second explicit wait plus evidence-processing overhead), not exactly two
seconds. Both caller/agent aggregate counters are two successes, zero failures.
Normal cleanup leaves FreeSWITCH idle, the checked service PIDs unchanged and
active, restart counts zero and no new core dumps.

**Overall exit is still 1:** one known Kamailio `consume_credentials` script
error fails the final log gate. Its narrow authentication-preserving fix and
ten regression groups are now in the installer repository, but the running
proxy was not changed for this run. Historical unresolved callback resources
remain retained. The result is an isolated local functional pass, not MASTER
or PSTN callback acceptance, full cleanup or production certification. See
[complete callback evidence and exact timing](acdc_callback_acceptance.md#busy-agent-callback-and-unanswered-first-attempt-diagnostic).

## Requested one-agent callback retry (15:59 UTC)

Run `20260905T155305Z` connected the initial conversation to the single test
agent. The second caller sent digit 6 at 4.990916 seconds after answer and
received the entire installed 6.124-second callback confirmation before
hangup, with zero missing phrase samples and PCM correlation 0.999991.
This is measured packet/audio delivery, not human listening.

The full scenario did not finish. The test phone's echo-pattern check rejected
the correctly received queue audio despite successful SIP signaling. Cleanup
also exposed an ordering issue: releasing the busy agent before cancellation
briefly allowed callback origination. The new test is being corrected to use
a non-pattern queued caller with independent received-prompt verification and to
cancel the exact current callback before releasing the initial conversation.
The ticket is cancelled and FreeSWITCH is idle. The deliberate first missed
call, retry, second bridge and final clean-log gates remain unproven for this
scenario; no MASTER or external-carrier changes were made. See the
[detailed retry diagnostic](acdc_callback_acceptance.md#busy-agent-callback-and-unanswered-first-attempt-diagnostic).

## Previous callback and system review (14:54 UTC)

The latest isolated callback run `20260905T143709Z` reached a durable completed
ticket on attempt one, verified the exact reciprocal caller/agent bridge, and
preserved enqueue identity/order while the later sentinel remained waiting.
All three phones ended naturally with one successful SIP call and zero failed
calls, and FreeSWITCH returned to zero calls. **The overall test failed**:
the agent RTP check saw no packets. SIPp's active-pattern phones had failed to
bind streaming ports because they also reserved those ports for echo. The
fixture is being corrected and must pass a new full run, including packet,
audio, teardown, readiness and log gates.

Cleanup also correctly retained the isolated fixture because a historical
callback remains `cancelling` with reconciliation required. Idle channels are
not sufficient evidence to mark that origination settled. No manual ticket
rewrite, broad hangup, MASTER routing/roster edit or service restart was used.
See [callback completion evidence and safeguards](acdc_callback_acceptance.md).

All nine services are active and enabled, with zero recorded automatic
restarts and no core dumps. **Logs are not clean:** the broader installer
check found Kamailio authentication and unresolved acceptance-realm routing
errors during callback setup, including the latest run. The earlier journal
counter incorrectly missed native `ERROR:` messages; this has been corrected.
The corrected counter finds eleven journal errors between 14:37:09 and
14:40:00 UTC in the latest callback run.
A separate normal `CHANNEL_EXECUTE_ERROR` event subscription caused one
false-positive file-log match. The revised counters pass fourteen file/journal
test pairs plus four routing/AMQP cases, retaining actual failure detection.
Disk use is about 12 GiB, with 24 GiB available.

Installer syntax, component selection, pinned Kazoo media builds and modular
dry-run checks pass. The fresh live `--verify-only all` check **failed** at
complete localized-media verification. Before stopping, it passed CouchDB,
RabbitMQ, HAProxy, production BEAMs, running Kazoo applications, ACDC database,
SUP, administrator authentication, queue/agent/external-number APIs and 192
English-US prompt attachments. Protected receipt:
`/var/log/kazoo-acceptance/installer-status-verify.6M8HHI`.
These checks do **not** prove clean-host or multi-server installs.
Separate live component verification passes eCallMgr and Kazoo FreeSWITCH.
Kamailio verification fails on the runtime integration errors above, and
Monster UI verification fails because its deployed fingerprint differs from
the requested pinned build/bundle. Neither failed result has been bypassed by
resetting logs or replacing the receipt with an unverified fingerprint.
The later read-only SUP verification also exposed an existing logging-format
defect: typed command arguments are passed to a string formatter, producing
`FORMAT ERROR` notices. The SUP commands returned successfully, but this
logging defect remains open; it is not described as a service crash.
Crossbar and browser checks cover the exercised login, queue/callflow,
callback and supervision paths, not every endpoint. Complete 30-call draining,
simultaneous ring-all, restart/failover recovery, backup restoration, external
calling and matching-key HTTPS remain outstanding. The MASTER callback return
identity/route prerequisites below are still missing. The system is not
finalized or certified production-ready.

## Earlier callback follow-up (13:31 UTC)

The isolated run `/var/log/kazoo-acceptance/20260905T132127Z` is **not a pass**.
It registered the callback, answered the returned call, delivered the negotiated
DTMF confirmation, and reached a real agent answer/bridge. FreeSWITCH emitted
`CHANNEL_BRIDGE` on the initiating agent leg; the queue tracked only the returned
caller leg. The durable callback therefore did not reach `completed`, and its
15-second bridge-proof deadline cancelled the connected call. A narrow repair
is being tested; no completion is inferred merely from agent acceptance.

Ordinary cleanup now settled the exact failed ticket, cleared its reconciliation
flag, removed only the owned fixture, and left zero FreeSWITCH calls. MASTER
configuration and the production test-phone service were not changed. The
separate missing return number, outbound caller ID and routing prerequisites
below still apply to the user's account.

The acceptance fixture now generates DTMF using the actual offered dynamic RTP
payload instead of SIPp's fixed payload. Its evidence gate requires matching
SIP offer/answer/ACK, exact native caller/agent dialog correlation, negotiated
media endpoints, and completed digit 1 before the first agent INVITE. Captures
are limited to the isolated loopback endpoints and their exact ports. Private
tests pass 39 packet-evidence cases, all 32 dynamic payloads, and 28 capture
filter cases. Seven actual-shell cleanup test groups also pass: cancellation or
owned-fixture cleanup failure now makes an otherwise successful gate exit
nonzero, while preserving existing failures and retaining unsettled resources.
These fixture tests are not a substitute for the full live callback gate.

## Latest live fixes (12:44 UTC)

Callback follow-up at 13:13 UTC:

- The callback menu now permits direct audible number entry when caller ID is
  invalid **and** alternate entry was explicitly enabled. False/default policy
  remains unchanged. Reducer/wrapper tests pass 21 cases; the baseline-only
  production modules were hotloaded at 12:57 UTC. See
  [menu repair](acdc_callback_menu_repair.md).
- The first returned-call test exposed a test-phone RTP payload mismatch.
  Correcting its negotiated keypad payload delivered digit 1 and exposed a
  real endpoint-construction failure: the returned Call carried resource type
  `offnet-termination`, while native endpoint selection requires `audio`.
  Normalizing only the top-level call type, preserving route/authentication
  channel variables, passes 10 baseline tests; the old code reproduces the
  endpoint failure. The narrow production caller module was hotloaded at
  13:12 UTC.
- Failed-test cancellation also exposed an eCallMgr parser mismatch:
  `freeswitch:api` strips the `+OK` prefix, but reconciliation expected the raw
  wire reply. The corrected parser accepts the exact normalized success shapes
  and retains fail-closed handling for errors/malformed responses. Six tests
  pass; it was hotloaded at 13:12 UTC. The ordinary queue reconciler then moved
  the exact test ticket to `cancelled`, removed its lease/reconciliation flag,
  and confirmed both call legs down, without a manual ticket rewrite.
- MASTER configuration remains incomplete: the incoming SIP username is not a
  return number; alternate entry is disabled; neither the selected callback
  user nor the account supplies an outbound caller-ID number; number and
  carrier-resource inventories are empty. Code fixes alone cannot provide
  these identities/routes. See [callback identity and routing](acdc_api_reference.md#return-destination-is-separate-from-the-callback-user).
- Full live returned-caller/agent/order acceptance is being rerun after these
  repairs. No PSTN traffic, MASTER roster edits, service restarts, staged
  atomic-answer activation or staged language-backend activation occurred.
- The endpoint exception exposed credential-bearing argument dumps in the
  shared stacktrace logger. A narrow `kz_log:log_stacktrace_mfa/4` repair keeps
  module/function/arity/line diagnostics and omits argument values. Three
  regressions pass, including a real `badarg` frame. Its reconstructed old
  production BEAM matched the installed bytecode; the new baseline module was
  hotloaded on apps and eCallMgr at 13:17 UTC, without a restart. It does not
  remove earlier protected logs or redact arbitrary caller-supplied messages.

- The browser console repair passed private-preview and then unoverlaid live
  acceptance. Login, Billing, unsaved ACDC forms, actual unsaved Callflows
  drag/drop, and authenticated WebSocket subscribe/unsubscribe pass with zero
  console warnings/errors or failed requests. Missing optional branding,
  payment, Webphone and Maps integrations no longer cause startup failures.
  `/websocket` has a real Blackhole proxy and the ACDC language artifact states
  its legacy/unready status explicitly. No third-party credentials or fake
  backend capability were created. See [browser evidence](monster_console_acceptance.md).
- Eleven differing browser assets were replaced with recoverable backups;
  1,921 unrelated files remained byte-identical. The current queue roster has
  one selected member according to the live API; browser tests preserve that
  operator state rather than restoring historical 30-member selections.
- The user's callback call at 12:08 UTC failed before registration because
  caller ID was a nonnumeric SIP username and alternate-number entry was
  disabled. Its resume path exposed a separate missing account/queue scope
  that crashed a queue worker. The narrow resume fix passed two targeted
  regressions and was hotloaded as a baseline-only production BEAM at 12:31 UTC,
  with no service restart. This does not manufacture a dialable callback target
  or prove returned-caller completion. Alternate-entry behavior and isolated
  live callback acceptance are being checked separately.
- The isolated 12:47–12:48 callback run registered a durable reservation and
  received the returned local-carrier call, but failed before an agent INVITE;
  the returned call ended early. Cleanup left zero calls and removed the owned
  fixture. The later investigation above separates the test-phone mismatch
  from actual backend failures; this first run is not a passing callback gate.
  Protected evidence: `/var/log/kazoo-acceptance/20260905T124723Z`.
- Apps, eCallMgr, FreeSWITCH, Kamailio and live test phones remained active with
  unchanged PIDs and zero automatic restarts at the 12:44 check. Disk usage is
  about 12 GiB used / 25 GiB available. The remaining production acceptance and
  HTTPS/private-key limitations listed below still apply.

## Latest checkpoint (11:42 UTC)

This checkpoint preserves deployed fixes and separately staged work. It does not
activate pending backend changes or certify the entire installation. Earlier
checkpoints `c496824` and `17e3ad6` were pushed to `origin/master`; the historical
uncommitted/pending statements below describe their original review times.

- All four call-supervision modes passed live synthetic audio acceptance at
  11:29–11:31 UTC: listen-only, whisper, barge and join, before and after keypad
  `3`. Authorization denials, SIP 180 before 200, supervisor-only stop and
  survival of the original bridge passed. Cleanup left zero fixture calls and
  registrations. Fresh apps/eCallMgr/FreeSWITCH logs contained no errors in that
  test window. This is single-server evidence, not distributed failover proof.
  See [monitoring acceptance](channel_monitor_acceptance.md).
- The successful run includes deployed fixes for normalized monitor-stop
  replies, ACDC events missing optional SIP addresses, and FreeSWITCH routing
  XML. Their focused tests pass 24, 13 and 8 cases respectively.
- Three ordinary ring-all calls passed with one winner and available losing
  agents. The true simultaneous-answer test then failed: all three agents were
  disconnected without a stable caller bridge. The atomic-intercept fix is
  compiled and regression-tested but **not deployed**. It needs coordinated
  module/node deployment and a fresh live test; ordered, round-robin and
  most-idle live gates remain incomplete. See
  [atomic answer selection](acdc_atomic_answer_race.md).
- All 6,143 EN/AR/HE/ES/FR draft prompt files have been generated and validated.
  EN/ES/FR media import passed, preserving existing recordings; AR/HE import is
  not yet complete. The new importer uses revision-conditional writes and a
  coherent final database inventory. Backend language mappings and node-local
  cache maintenance remain staged separately; no runtime-ready artifact or
  native-speaker approval is published. See [language packs](acdc_language_packs.md).
- The language-aware ACDC UI passed its live browser gate at 11:42 UTC: all five
  choices are visible, only verified English is enabled, all 30 roster members
  and ordered selection are preserved, callback dropdowns work, and Callflows
  exposes the queue action. There were zero non-authentication API writes or
  JavaScript errors; 1,924 unrelated web files remained unchanged. The installer
  now preserves verified language capability files and returns a real HTTP 404
  when one is absent, rather than serving the HTML application fallback.
- Full callback return/recovery, the complete 30-call drain gate, clean-host
  distributed deployment, backup restoration and production hardening remain
  pending. HTTPS still lacks the matching certificate private key.

## Earlier checkpoint (10:15 UTC)

## Repository checkpoint: implemented, deployed and pending

This is a user-requested source checkpoint, **not a finalized setup**. The
installer, pinned upstream sources, complete component patches, UI source,
synthetic English audio, tests and documentation are being committed together.
Ignored upstream checkouts are represented by complete ACDC/Crossbar/eCallMgr
integration patches; `scripts/refresh-kazoo-integration-patches.cjs --check`
detects unpackaged changes. Credentials, TLS private keys, private state,
customer records, runtime binaries and SIP/RTP captures are excluded.

- The actual Callflows ACDC palette drag/drop, queue selection and unsaved node
  serialization pass browser acceptance. The dropdown-only ACDC UI is live:
  named callback user, inherited/custom caller ID, owned numbers, verified media,
  installed language and keypad selectors. All 30 selected roster members are
  preserved. Deployment left 1,924 unrelated web files unchanged. Reload the
  browser to load the updated standalone app.
- English position audio passes a real 75-second call: the complete “Your
  current position is one” starts 30.261 seconds after queue entry and repeats
  29.879 seconds later, within documented media jitter; playback/worker/channel
  cleanup passes. Initial delay and repeat interval are independent controls.
- Callback user identity inheritance is deployed; 17 policy tests cover fresh
  user/account defaults, legacy preservation, enablement, ownership and denials.
  Inherited identity does not bypass account restrictions or create a usable
  caller-ID number when none is configured.
- The archive lifecycle fix is deployed. All 30 test-agent statuses were
  independently confirmed persisted in CouchDB before restart and naturally
  recovered as ready afterward, without a login-restoration command. Phone
  service PID 2170317 stayed running with zero automatic restarts. Full
  shutdown during a database outage still lacks a durable local outbox.
- Numbered registration replies and complete collection are deployed. Live
  testing exposed a quoted-macro JSON construction error missed by config
  syntax checks; it is fixed, with 16 wire-expansion regression checks added.
  Twenty consecutive API snapshots now correctly report all 31 master devices
  registered, including the preserved MicroSIP device.
- Ring-all, round-robin and most-idle existed in ACDC. New `in_order`, live
  strategy refresh, ring-all loser/timeout cleanup and callback winner
  preservation are source-complete: 18 strategy tests, 45 upstream tests and
  26 callback queue tests pass. Ordered UI browser tests pass. These new
  strategy binaries/UI are **not yet deployed or live-call certified**.
- Cluster call-supervision APIs are deployed, but the live audio gate has NOT
  passed. The first fixture found a separate direct-call bridge compatibility
  bug before an agent leg connected. Its narrow eCallMgr fix passes six tests
  and is packaged, but is **not yet deployed**. The test fixture was fully
  cleaned. No claim of successful whisper/barge/join or multi-node failover.
- EN/AR/HE/ES/FR remain the requested language target. Only EN has completed
  audible acceptance. ES/FR native module/sound installation hooks are included;
  their modules compile privately. Arabic/Hebrew asset generation, capability
  publication, backend numeric playback and full multilingual acceptance are
  still in development and are not presented as ready.
- Full returned callback/human confirmation/preserved-order acceptance, the
  corrected 30-call complete drain gate, distributed clean-host installation,
  backup/restore and production hardening remain pending. HTTPS still needs the
  matching private key for the supplied certificate. No key is committed.

See [installer and reproducibility](install_kazoo5_script.md),
[API contracts](acdc_api_reference.md),
[ring strategy behavior](acdc_ringing_strategies.md), and
[bridge compatibility](ecallmgr_bridge_compatibility.md).

## Earlier progress (09:00 UTC)

The detailed baseline below was recorded at 02:04 UTC. The following later
evidence supersedes its old deployment/pending statements; historical failures
are retained to avoid losing the audit trail.

- Core/ACDC and eCallMgr production builds restarted coherently at 08:24 UTC.
  Native verification passed. Automatic source reloading is now off by default;
  both running nodes have no reloader. Public generated code/schema permissions
  are repaired without changing secret-file permissions.
- The master account has 30 marked live-test users/devices, extension routes
  1002–1031, and queue `Call Center Live Test` at 2000. Existing MicroSIP user and
  device credentials were preserved. Test phones are receive-only SIP/RTP echo
  endpoints; no external calls are generated.
- Our initial phone-service readiness parser incorrectly rejected successful
  registrations and globally logged out the test agents during a user call.
  Its parser is fixed. A separate hard systemd dependency also stopped all test
  phones during a planned FreeSWITCH restart; it is removed. Individual child
  recovery now preserves healthy phones and agent status. Ownership checks no
  longer reject legitimate user edits to mutable queue settings. Service PID
  2170317 is active with zero automatic restarts after its latest start; final
  sustained/live-call verification is still required.
- ACDC's updated standalone UI is deployed. A My Account transition race that
  hid routed application content is fixed and regression-tested. The Callflows
  Advanced palette now shows ACDC Queue and real drag/drop creates an
  `acdc_member` node. Browser testing found a queue-picker dispatcher defect;
  its fix and complete picker/save acceptance are still in progress.
- FreeSWITCH's Kazoo endless hold playback did not dequeue DTMF until hangup.
  The narrow fix is built and deployed (module SHA256
  `149d04c8589f602c5281d4d09f9a8f1bbede18519d77d90701bf8a948f02dacc`).
  Live calls now enter the callback menu, confirm, hang up and leave a durable
  queued reservation. Returned-caller acceptance remains incomplete: tests
  exposed an incorrect fixture gateway invite format and distinct outer/inner
  originate message IDs that broke recovery correlation. Corrections are staged.
- Registration-status collection can receive the final response before a
  partial response, incorrectly displaying registered phones as offline.
  Numbered multipart response handling passes 16 isolated tests; its production
  binaries/configuration are privately staged, not deployed.
- The user's position announcement currently speaks only the number because
  prompt URIs reach FreeSWITCH unresolved. The full phrase, configurable first
  delay (30 seconds by default), and periodic timing are being fixed. Audible
  verification is mandatory; database/schema success is insufficient.
- New requested work: account-authorized cluster-wide listen/whisper/barge/join
  APIs, secure supervisor-only stop, media isolation tests, and a durable API
  reference. See [ACDC and call actions](acdc_api_reference.md). These endpoints
  are not yet claimed deployed or working.

The active todo list includes all of the above, full callback acceptance,
30-call drain/teardown acceptance, production deployment convergence, HTTPS key
provisioning, and the final commit/push. No production-ready or zero-bug claim
has been made.

## Historical baseline (02:04 UTC)

**Resolved build contamination:** a shared-source test build overwrote production
Erlang beams with `TEST`-defined builds. The audit found 290 such modules loaded
on the applications node and 177 on eCallMgr. In particular, test-mode
`kapps_config` returns `not_found` for real configuration categories, explaining
the authenticated SIP call's 403 rejection. A strict production rebuild and
release build completed, and both nodes restarted at 00:00:21 UTC. The disk
audit found zero test-mode beams; runtime audits found zero among 570 loaded
application-node modules and 572 loaded eCallMgr modules. Installer and live
service startup guards now reject test-mode or corrupt beams. Both Kazoo roles'
native verification passed after restart, including persisted configuration and
the FreeSWITCH authorization ACL. Voice/capacity acceptance remains separate.

The deployment under test is Rocky Linux 9.8 on `kz5-testing`, with two vCPUs,
approximately 3.5 GiB RAM, no swap, and a 38-GiB root filesystem. Approximately
26 GiB remains free after the pinned build sources and sound assets. The
requested capacity gate is 30 simultaneous answered calls, not 30 new calls
per second.

## Source and reproducibility

- Project: `/opt/kz5`, branch `master`, based on local commit `bfbaa552`.
  This incorporates the head of upstream PR 218; the upstream PR itself was
  still open when checked. The local implementation changes have not yet been
  committed or pushed.
- The backend source is Kazoo 5; its development build version is `master.0`.
  Monster UI source tag `5.5.13` retains upstream package metadata `4.3.0`.
- The deployment entry point is `scripts/install-kazoo5.sh`. Its pinned source
  revisions, compatibility patches, modular configuration, and tests are
  described in `doc/install_kazoo5_script.md`.
- This host has received live component tests. A completely new, independent
  distributed multi-server installation has not been demonstrated; modular
  option and fresh-checkout ordering tests are not a substitute for that gate.

## Verified evidence

| Area | Evidence |
| --- | --- |
| Native services | All eight requested systemd services are active and enabled. CouchDB authentication, RabbitMQ authentication/plugin/listener, HAProxy endpoints, Kazoo application inventory, Crossbar login, SUP, and eCallMgr connectivity pass. |
| ACDC backend | Community ACDC compiles and starts; its upstream unit tests and temporary account/queue lifecycle checks pass. A dedicated acceptance tenant has a caller, 30 agent users/devices, queue 2000 and an `acdc_member` callflow. |
| Callback persistence foundation | 14 isolated tests pass. A fresh temporary account's live CouchDB probe passed idempotent registration, conflicting-number rejection, one winner among competing claims, cancellation and queue-scoped listing. The probe and account were deleted. No outbound calls were made; full callback integration is still pending. |
| Authentication regressions | 16 isolated token-validation tests pass; malformed live tokens return 401 without the previous internal exceptions. |
| CDR timestamp regression | Missing report timestamps previously crashed monthly database selection. The report now uses an explicit timestamp, else the interaction timestamp, else current time. Five CDR unit tests pass; the production beam is hotloaded and its hash matches. Three live pure-selector checks pass without creating test CDR records. |
| C-node compatibility | Four isolated tests verify legacy reference reply tags, bounded calls, and version-based media-node ping; the server-local fixes are now captured in an installer patch. |
| Diagnostic handling | Independent Erlang log roots are active with private files; log-retention tests pass. Three dataplan/CouchDB connection-log regression tests cover success, reconnect, and failure; rebuilt modules are hotloaded on both Kazoo nodes. FreeSWITCH size-based rotation and service umask are active. Historical logs are preserved with restricted access. |
| Credential transport | CouchDB retains the same cluster cookie in a private file, absent from process argv after its 23:00 planned restart; pre/post-restart cookie authentication, native HTTP and both HAProxy paths pass. The protected remote shell and isolated cookie-loader tests pass. Initial master-account bootstrap now uses protected stdin RPC with UTF-8, argv, environment and failure-redaction tests. |
| Media assets | All 175 English-US system prompts have nonempty audio attachments. A repeat import preserved existing audio. All 369 local English-US speech and default hold-music files are installed. |
| Native FreeSWITCH | Version, modules, Sofia profile, eCallMgr link, quoted originate arguments and pending-originate cancellation probes pass. The latest planned restart was at 23:22:15 UTC, PID 1611739, for the Sofia Kazoo proxy-URI compatibility fix. Both sides use four-byte event framing. The single-call SIP/ACDC/RTP gate now passes. |
| Crash-dump audit | No new process core dumps were observed between the 21:12:37 baseline and the 22:36 review. This does not mean there were no Erlang process crashes; the live-call failure below includes one. |

## Remaining gates and known failures

- **Answered ACDC call and RTP: passed.** Run
  `/var/log/kazoo-acceptance/20260904T223148Z` proved rejection of a wrong SIP
  password, valid registration, callflow routing, and entry into ACDC. It then
  exposed a malformed external Erlang term from FreeSWITCH, a lost/reconnected
  C-node link, and a call-control process crash. The boolean command-protocol
  fix and reply guard are now installed; both sides use four-byte event
  framing. A later rerun proves caller answer/hold while the agent is logged
  out, but agent origination fails with `NORMAL_TEMPORARY_FAILURE` before the
  test endpoint receives an INVITE. The Sofia proxy-URI fix is installed, but
  rerun `20260904T232641Z` was rejected earlier with 403/CALL_REJECTED due to
  test-mode configuration code loaded on eCallMgr (now repaired above).
  Post-restoration run `20260905T000434Z` reached agent INVITE/answer/bridge at
  00:05:11 UTC and normal teardown around 00:05:21; caller and agent each
  recorded one successful SIP call. The harness incorrectly checked current
  calls only after its blocking login returned and the call had ended. Its
  timing check was corrected. Clean run `20260905T001203Z` passed invalid-password
  rejection, logged-out-agent waiting, agent INVITE/answer/bridge, bidirectional
  RTP (caller packets in/out 1511/1488), normal teardown and agent ready/idle.
  Caller and agent each recorded one success and zero failures. Fresh journal
  and file error counts were both zero, with no new cores. Capacity checks
  retain strict simultaneous-call measurement.
  Broker queue
  depth is not a valid stand-in for ACDC's internal waiting-call state.
- **Capacity: partial evidence, full 30-call gate not passed.** Five-, ten- and
  twenty-simultaneous-call stages passed with exact caller/agent successes,
  zero failures, bidirectional RTP, clean fresh logs and no new cores.
  Run `20260905T011949Z` held 30 bridged agent calls plus five waiting callers
  continuously for at least 180 seconds. Its full queued-drain and exact-agent
  completion gate did not pass: test-phone arrival order and lifetimes caused
  premature fixture termination. Cleanup verified zero channels and no test
  processes. The corrected harness has not rerun. A separate burst of 35 new
  calls/second exceeded this host's routing capacity (ecallmgr route-response
  timeouts); it is not supported throughput. Paced setup used five new
  calls/second. Initial harness runs assigned
  overlapping RTP audio/video ports; no platform capacity conclusion was
  drawn from those failed test-client setups.
- **New Call Center frontend: passed.** The final deployed bundle passed real
  browser sign-in, catalog loading, account switching, dashboard refresh,
  30-agent display, login/pause/resume/logout, queue and two-agent roster CRUD,
  extension/managed-route CRUD, and refusal to delete externally owned routes.
  Cleanup confirmed no temporary queues/routes and agent 30 logged out.
  Post-restoration fingerprint:
  `0fa2ebb1e65de405f933fd688ca7cbed3481d8d487cc7f989b55cd7e6770dee0`.
  Do not infer completed voice functionality from the frontend tests.
- **Kamailio final clean-log gate:** historical failed acceptance calls logged
  unresolved test-realm routes at 22:03 and 22:04. Confirm the call/teardown
  route is fixed, then establish and test a fresh service baseline.
- **HTTPS:** `kz5.talkchief.io` resolves to this host. The certificate and chain
  in `/root/ssl` validate, but their matching private key has not been supplied.
  Port 443 is not active. No private-key material should be pasted into chat.
- **External production coverage:** no PSTN trunk, off-host NAT/RTP endpoints,
  failover, backup restore, or independent distributed-node acceptance has
  been proven. SELinux is currently permissive and firewalld inactive; the
  deployment still needs an agreed production network/exposure policy.
- **Kernel maintenance:** security update kernel `5.14.0-687.42.1.el9_8` is
  already installed and selected for the next boot, but the host still runs
  `5.14.0-687.41.1.el9_8`. A coordinated reboot and post-boot acceptance are
  outstanding; no reboot has been performed during active call diagnosis.
- **Expanded Call Center features:** the user additionally requires custom
  announcements, spoken queue position, announcement-language selection,
  virtual callbacks with keypad confirmation and preserved queue position,
  and their complete APIs and UI. Existing ACDC includes position/wait-time
  announcement code and schema, but no complete virtual-callback flow. UI and
  language/runtime work is active. The public `kazoo-classic/kazoo` reference
  at `c57b3ac0a477302aa04098369502d4be715e15c7` contains a callback implementation
  under assessment; it has not been installed or claimed compatible.
  Announcement language/runtime safeguards and frontend controls are now
  implemented with six isolated runtime tests and frontend contracts. The
  new bundle is deployed (`0fa2ebb1e65de405f933fd688ca7cbed3481d8d487cc7f989b55cd7e6770dee0`),
  and the focused browser/API gate passed after production-beam restoration:
  valid announcement create/edit/persistence plus HTTP400 for all six invalid
  writes (PATCH and POST for uppercase language, interval14, numeric media).
  A separate full post-restoration browser run also passed agent 30's
  login/pause/resume/logout lifecycle and removed its temporary queue/routes;
  it finished before the capacity run. The legacy top-level `announce` field now
  has a source implementation with asynchronous playback completion and
  periodic-producer shutdown. The isolated queue suite passes 24 checks;
  audible pre-connect/position/wait acceptance remains unproven. Pre-connect is
  not yet exposed as a working frontend control.
  The staged callback implementation now has 23 passing isolated store tests,
  seven internal protocol tests, 20 queue-coordinator/listener tests, nine
  account-scoped read/cancel API tests, 11 inbound-menu reducer tests and three
  menu/protocol/media integration tests. The full isolated ACDC unit runner
  passes 45 tests. Additional policy/caller/recovery suites pass independently.
  These source-level checks do not prove live callback calling or restart
  recovery. The old live CouchDB probe above covered an earlier storage-only
  API, not this complete call path. The callback API/menu/UI changes are not
  yet exposed as a working deployed feature.
  Sixteen generated English-US callback prompt variants were rendered twice
  with identical SHA hashes (mono 8 kHz, signed 16-bit, bounded duration) and
  imported through the installer. All 191 English-US system prompt documents
  have usable attachments; audible SIP acceptance remains pending.
  Queue coordinator/recovery, calling/DTMF, API and UI integration are not
  yet complete or live-tested. An approved external callback trunk/test number has
  been requested; internal tests do not prove external routing.
- **Final delivery:** rerun final installer convergence and acceptance after
  the remaining fixes, then commit and push the project changes as requested.

Test captures and credentials are protected server files. Never commit SIP
credentials, API tokens, packet captures, private keys, or raw diagnostic logs.
