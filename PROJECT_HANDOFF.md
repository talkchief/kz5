# Kazoo 5 — start here / engineering handoff

Last updated: **2026-09-07**. This is the navigation and current-state guide;
`PROJECT_TASKS.md` is the detailed requirement/acceptance register. Neither this
file nor a green unit test means the platform is production-ready.

## Latest working snapshot — read before resuming

**Direct maintenance read admission — September7, source tested, NOT deployed:**
`acdc_stats:find_call/1` now requires before/after admission from the same ready
stats owner and checks the exact opaque table identity/ownership. Missing,
legacy, timed-out, revoked or replaced sources return explicit unavailable;
`acdc_maintenance:flush_call_stat/1` prints that status without publishing an
abandonment. The ETS select remains outside the collector mailbox. These are
non-atomic read checks, not a lease, old-worker drain or a hard total read
deadline. See `doc/dashboard_caller_identity_upgrade.md` for boundaries.

Root final startup suite passes16 groups `156530/e8b860`, evidence
`/tmp/kazoo-stats-startup.fTo5ct`. It freshly compiled13 production modules
including stats, maintenance and real gen_listener without TEST, under the
192MiB/512MiB-reserve/150-second guard and isolated network namespace. New tests
cover missing/dead/legacy owners, real listener lookups/newest record selection,
both 1000ms admission timeouts, same-owner/tid second refusal, actual table
replacement after select, and maintenance unavailable with poisoned AMQP
publication. Earlier13/14-group runs also passed; final evidence supersedes
them. All root jobs are terminal; no services, live BEAMs or account data changed.

**Next:** a source-only agent is preparing a separate first-replacement drain
helper/fixture; it is not yet accepted, compiled, installed or part of this
checkpoint. No metadata-only scan or successful soft purge may be treated as
worker completion. Root must review and serially test that helper, integrate
remaining dynamic callback gates and rehearse retained-heir worker replacement
before coordinated backend/UI/OpenAPI deployment. Preserve any uncommitted
agent files and the unrelated untracked bridge directory.

**Retained stats startup migration — September7, source tested, NOT deployed:**
`acdc_stats_migration.erl` now performs owner-only preflight, bounded conversion
and hash/count verification; `acdc_stats` defers its native listener and timers
until both tables are owned and migration succeeds. Startup failure retains
tables and rejects mutation/event/timer work; nonready termination does not run
the archiver over mixed records. Internal readiness is phase/reason, not broker
health. OTP formatting omits continuation keys/digests.

Root helper11 tests pass `68e9e6/c09393`, evidence
`/tmp/kazoo-stats-migration.YErKbj`. Lifecycle10 groups pass `5e37b0/2a5f12`,
`/tmp/kazoo-stats-startup.P2O8a8`; the runner recompiles12 production modules
including real `gen_listener` and migration, without TEST. It uses actual
named ETS donations and proves deferred native responder/channel setup after
verified conversion, with external broker/config/monitor dependencies controlled.
It does not establish real broker consumption or installed old/new replacement.
The first lifecycle run failed10 groups (`2fc1db/3ebc8f`,
`/tmp/kazoo-stats-startup.ZeMcAI`): named ETS transfer messages carry the name,
not the opaque tid, and one fixture channel callback was missing. Root fixed
the source to resolve only the two expected names at transfer, then pin opaque
tids throughout migration; the fixture now consumes actual named messages.
Stale opaque tids and ownership changes still fail closed. A named signal alone
does not establish the age of that signal; actual ownership and conversion are
verified independently.

Earlier full-source compile76 modules passed `67b393/bf1080`; the subsequently
corrected stats module was rebuilt in the passing lifecycle runner. Upstream10
regressions passed `4412fa/0ce91f` before the later startup-only hardening.
All jobs are terminal; no live BEAM, service or account mutation occurred.
**Next gate:** implement/test old responder and archive-worker drain plus remaining
dynamic reader admission (maintenance read admission now tested above), then rehearse the controlled stats-child replacement while
keeping ETS managers alive. Native `gen_listener:code_change` does not delegate
client state conversion; the direct client refusal test is not a hot-upgrade
safety proof. See `doc/dashboard_caller_identity_upgrade.md`. Do not use a full
app restart or discard unarchived tables to bypass this gate.

**DASH-10 caller identity candidate and pending-view disposal — September7:**
source-only, NOT deployed. New `acdc_dashboard_caller.erl` constructs an explicit
privacy-filtered marker from the initialized call and original matching payload;
missing/malformed evidence never authorizes fallback to historical raw caller
fields. Only selected-queue call detail collects the bounded marker. Public call
rows now require nullable `caller_id_name`/`caller_id_number`; legacy native rows
normalize to null and conflicting identities withhold inconsistent snapshots.
Overview and Blackhole invalidation payloads remain identity-free. The UI shows
escaped Name/Number or `Caller unavailable`, retaining internal call IDs in row
attributes for actions/acceptance, not as visible caller text. OpenAPI source is
updated; generated/served assets are NOT yet updated.

Root evidence, all terminal: upstream10 tests and12 production compiles
`aa6509/8c8fcd`, `/tmp/kazoo-dashboard-caller.NgOyOw`; collector50 tests
`5982dd/4fdd34`, `/tmp/kazoo-dashboard-collector.Kx4KMX`; native36 tests
`75b1b8/269935`, `/tmp/kazoo-dashboard-amqp.sWiLlC`; public-route30 plus2 pure
helper tests and51 actual production-handler DTO/schema checks
`ce576d/d73bed`, `/tmp/kazoo-live-snapshot.zkDPRp`. Listed production sources
were rebuilt and pinned; remaining workspace/OTP dependencies are not a fresh
full-system build. Source-browser27 groups passed `e76537/e3eaaa`, evidence
`/tmp/kazoo-monster-live-dashboard.FoLgrA`; paused ecallmgr and simulated phones
were restored and verified active (`4cc2e2/eacf49`).

The browser suite exposed an unrelated initial-loading disposal bug after19
passing groups (`13d01d/bc2755`, `/tmp/kazoo-monster-live-dashboard.gbXtIK`):
navigation created a still-loading controller without an observer; its timeout
could replace the next screen. `watchLiveDashboardView` now owns both loading
and mounted views. Added regression delivers the late callback and advances
the watchdog after disposal, asserting no remount/cache/subscription. The27
passing groups cover this in a controlled source browser; not deployed proof.

**DASH-10 deployment gate:** `#call_stat{}` changes from18 to19 tuple elements.
At that caller checkpoint, `upgrade_legacy/1` was only a tested pure conversion;
the newer staged source implementation is documented above, still NOT deployed.
Rebuild all record readers/writers and implement/test ownership-safe retained
ETS migration before deployment; a stats-worker restart retains old tuples via
the ETS manager. Do not hot-load only a subset or delete unarchived records.
Actual normal/private call payloads, replica transitions, coordinated backend/
UI/OpenAPI deployment and live caller-display acceptance remain required.
Source-only migration audit is captured in
`doc/dashboard_caller_identity_upgrade.md`: implement deferred stats admission,
owner-only resumable conversion and old responder/archive-worker drain. Do not
substitute whole-app restart or zero FreeSWITCH calls for data preservation.

Offline follow-up: schema16 groups/337 cases passed `bf9377/942138`;
observer18, HTTP-stall8, queue observer12, idle-load14 and reconnect24 groups
passed `518baa/dfc99e/b090f3`. An outdated static assertion for the pre-stall
browser deadline caused the first observer run to fail; it now checks the
actual natural-call OR HTTP-stall deadline expression. No runtime behavior
was relaxed. All valid public-call fixture rows now carry both nullable caller
fields; synthetic partial reconnect DTOs are intentionally not API envelopes.

**Remote checkpoint:** `master` was independently read back at
`9e846a5fd1122f6889354fb76bfaa06d2b585778` (`fd09b8`). Caller identity and the
new loading-view disposal fix were not part of that published checkpoint.

**Deployed HTTP-stall acceptance — September7:** eight offline groups pass
51b9fc/830c4a and actual deployed browser05bc67/65a97a passes nine checks.
Two real selected-detail responses were held past the watchdog or normal
navigation. Cached snapshot stayed intact, stale/error/usable Refresh and fresh
GET recovery passed; canceled responses did not remount the disposed view.
Zero unexpected browser/HTTP errors and exact native ACK cleanup. Both paused
services restored; all nine services active and zero calls (930f79). Receipt
`/tmp/kazoo-monster-live-deployed.SYDVca/receipt.json`; implementation and
limitations in `doc/monster_live_http_stall_acceptance.md`. This proves canceled
transport recovery, not execution/ignoring of a delivered late JS callback.
P0-25 remains open for that distinction and never-settling module delivery.

**Periodic master publication — September7:** at the operator's explicit
request,135 committed changes were fast-forwarded from remote5756082 to
`419791716e5e9e890e684d253f6dcd3c0193bb04`. Push6ca149/f6e250 succeeded;
independent `ls-remote` readback79d4e7 matched local HEAD and origin/master.
No force push. Working branch is now `master`; switching identical tips
preserved all uncommitted caller-privacy, browser-stall and bridge work. Those
in-progress files were not published. Future reviewed/tested checkpoints should
be committed and pushed periodically as requested; do not wait for final
production acceptance to back up completed work. Publishing a checkpoint does
not close release gates or certify production readiness. Older pending-push
statements below are historical and superseded by this checkpoint.

**Idle viewer load — September 7:** root14 offline groups passed c3b213/5709e0.
Actual2/10/30 viewer cohorts each held30 seconds after all viewers were ready,
passing fresh complete snapshots, exact subscribe/unsubscribe ACKs and zero
errors. The30-viewer run returned91 valid snapshots, HTTP p95=106.23ms and
max=1,002.42ms (`91df3e`/`e967fb`). No service restart, call control, synthetic
event or account/queue write was used; the wrapper performs normal admin auth.
Evidence: `doc/queue_live_viewer_load_acceptance.md`, private receipts under
`/tmp/kazoo-live-viewer-acceptance.HVcF2T`. These are idle native HTTP/WebSocket
viewers, not browser rendering or30-call capacity acceptance. Extended30 viewers
also passed180 seconds with391 fresh snapshots, zero errors/incomplete results
and97.5ms HTTP p95 (`2fbd95`/`90d1e4`). All four jobs are terminal. Post-run check:
all nine scoped services active, zero calls; the same application error/crash
log files did not grow during the measured interval. The controlled HTTP-stall
acceptance was subsequently completed as documented above. Caller identity
(DASH-10) remains a source-only candidate. DASH-10 appends the
call_stat record: all record consumers and retained ETS migration require
coordinated validation/deployment; do not hot-load this partial source work.

**Tracker maintenance — September 7:** the operator requested an up-to-date,
handover-ready task list. The concise current queue of work is now at
`PROJECT_TASKS.md#handover-checkpoint--2026-09-07`; detailed task IDs and
acceptance criteria remain in that register. Update both documents when status
changes, preserving evidence and distinguishing implementation, deployment,
acceptance and push status. Current Git checkpoint is `208695f` on
`fix/acdc-outbound-agent-availability`; the tracker update itself is not a new
runtime deployment or release acceptance result.

**Startup loader deployed — September 7:** installer-owned singleflight patch
passes16 actual-loader regression groups (`fe213e`/`d8fe85`), including old-source
reproduction of missing ACDC translations. Fresh full installer patch preparation
passed `f65634`/`96a194` at monster-owned-build.MwsDYg/source. Production build
`c56a9e`/`a1f197` passed and both paused services were restored/verified active.
Owned deployment `ec9a75`/`9f9af6` changed only main.js, preserving1,943 files;
served index/main/configuration readback passed. Fresh browser initial view and
login-confirmation dialog passed without page errors (`3ff064`/`eefb87`).
Standard production smoke passed7 checks with zero page/console/HTTP errors and
native subscribe/refetch/disposal/unsubscribe (`e5b91d`/`2241b2`). Account-switch
smoke passed10 checks45576a/e20ac1. All four home/switched summary/detail
reconnect cases passed7/9/10/12 checks with zero page/console/HTTP errors.
Controlled HTTP stalls/late replies and never-settling loader delivery remain;
do not call P0-25 closed yet. See
`doc/monster_app_load_singleflight.md`.

Final post-rollout check `fecef6`: all nine scoped services active, zero calls,
and exact roster/all31 reported agent statuses/memberships unchanged. No jobs
from this checkpoint remain running. Local commits: `9f695ed`, `b02f7fe`;
master push remains pending the broader release gates. Untracked bridge source
and viewer-load harness are not included in those tested-source commits.

**Queue creation acceptance — September 7:** real deployed form PUT returned201
and a complete editor operation; the harness incorrectly expected200. Exact
readback/owned-queue cleanup then passed `09a4d6`/`131789` without another create.
The operation receipt remains, the queue is gone, and all31 reported agent states
and memberships match the pre-test snapshot (`86fb9a`). Details and protected
ledger location are in `doc/acdc_ui_stabilization_20260907.md`.

**Queue API log fix deployed — September 7:** P0-23 now has matching real
before/after HTTP evidence: six successful reads emitted six handler errors
before the fix and no error lines afterward (`499e52`/`b61caa`,
`da07ec`/`86d759`). Only cb_queues was hot-loaded; no service restart. Runtime
hash/export verification passed `0c9f54`/`84b347`, rollback artifact retained at
`/tmp/kazoo-queue-types-deployment.XS9QCz`. Current production-metadata compile
passes six tests; matching installed baseline fails three. Source and details:
`doc/acdc_ui_stabilization_20260907.md`. No cluster-wide reliability claim.

**Earlier UI rollout — September 7:** dashboard wording now removes observed
from user-facing values and uses In Progress. Root52 dashboard groups pass
`078c38`/`a26140`; queue-login23 pass `b01286`. Actual queue-create400 was traced
to Monster injecting ui_metadata into the strict editor body. The local
requestQueueEditor wrapper opts out without relaxing backend validation;
eight actual-serializer groups pass `e412fe`. Build stage hXJTv6 passed production
artifact verification (`130be8`/`b8aff7`), then owned deployment changed three
files and preserved live configuration (`6d7352`/`d9a24c`). Both temporarily
paused services were restored and verified active. Fresh browser `cbf2ed`/`80cbbf`
verified the plain labels and In Progress, plus confirmed membership without a
login mutation. UI-02 is closed; broader editor error-recovery and timeout acceptance remain
open. This earlier rollout still emitted a TypeError reading acdc; the later
loader fix and passing browser checks are recorded above. See
`doc/acdc_ui_stabilization_20260907.md` for evidence and remaining acceptance.

**Newest operator issues — September 7:** P0-22 is a login VERIFICATION display
bug, not a failed login (operator correction). Root actual read-only HTTP proof
and selected-queue live agree Agent12 is ready and a runtime queue member.
P0-25 tracks indefinite ACDC loading; read-deadline changes are source tested
and deployed, with controlled outage/late-reply acceptance still open. P0-26 tracks new
queue creation400; the deployed serializer opt-out fixes unwanted ui_metadata,
and real create/readback acceptance subsequently passed. UI-01 tracks separately
reproduced storage404. DASH-10 requests caller name/number display with preserved
internal call identity. P0-24 explains the latest callback refusal: caller ID
was SIP username `kz5_test`, while alternate-number collection is disabled.
Do not weaken callback validation or call these reports resolved without their
actual-browser/call acceptance. No working agent state was changed by diagnosis.

Focused deployed-browser read-only probe `54433a`/`1326c7` displayed the initial
dashboard and actual Agent12 queue-login dialog as "Queue membership confirmed";
the real UI proof GET returned confirmed/ready. It sent no login mutation.
That earlier probe emitted a TypeError and an earlier run timed out at shell
readiness. Subsequent mapping, source tests and deployments are recorded above;
do not mistake this historical probe for current acceptance. Bridge source is
sanitized under services/push-bridge, but
its installer option/activation are not ready; imported reliability/security
gaps are explicitly documented there. Production bridge was not changed.

**New bridge task — September 7:** user requested importing the mobile push
bridge installed on production Kamailio `10.1.0.28` into kz5 and exposing it as
an installable service in the modular SH installer. Tracked as `INST-13`.
Production access is discovery/source retrieval only: no restart, configuration
change or real notification test. Identify the actual implementation before
claiming Pusher/FCM support; exclude all production secrets and customer data
from Git. This explicitly adds bridge packaging work without resuming postponed
history or voice/callback deployment work.

**Current live isolation result — September7:** all17 real HTTP/native Blackhole
permission cases pass (`573eb1`/`0d57c2`) with4 actual nonadmin principals. This
includes exact allowed queue, same-account other queue, foreign account/binding,
denied cursor, missing stats/queue/roster and positive controls after negatives.
The no-roster principal is denied the detailed HTTP data but allowed the
identity-free invalidation hint, as designed. The existing protected SdiLT6
ledger now has `matrix_passed: true`, all17 check names and4 verified logins.
No additional fixture resources were created by the resumed run.

The corrected harness passes41 offline groups/180 rejection checks
(`407a4a`/`eb685f`), including real fd-lock contention, under-lock stale-ledger
refusal, exact rate-limit diagnostics and one-shot final-login resume. Source
SHA `bb1dfa2a2e37007f698939d898adeee0bd54c408a78d9de116fb41982063eb46`.
An earlier resume (`bef681`) correctly stopped before login because its test
expected a strong queue GET revision; native roster-enriched GET explicitly
drops the ETag. Resume now checks all fixture public hashes/ownership, only user
GET revisions, and retains original write revisions for future conditional
deletion. The final run used the corrected shared descriptor lock.

**Retained fixture, not cleanup PASS:** the original fourth login response was
uncaptured. Explicit resume recorded both `cleanup_hold: uncaptured_prior_login`
and `resume_attempt.ambiguous: true` before requesting its new token. Every
cleanup call refuses that hold even after known tokens expire. Do not clear it
or claim unknown old JWTs revoked. Nine synthetic resources remain isolated in
SdiLT6 for reviewed cleanup; their secrets stay outside Git. No calls/services,
original users, agent memberships or routing were changed by these checks.
Remaining live-dashboard gates: restricted-user browser behavior, bounded load,
cross-node behavior and relevant log review. Callback/voice/history work stays
paused. This is not full production acceptance or master-push completion.

**Earlier restricted-principal checkpoint — September7:** prerequisite deployment
and documentation are committed locally as `c115335`; no master push yet. Root
opened explicit fixture admission after deployed cleanup/role-guard review.
Corrected fixture `5dadd0`/`f05ea0` passes33 offline groups/149 rejection checks.
Live run `5a8685`/`7099e9` created9 isolated resources and verified3 genuine
nonadmin logins, then stopped during the fourth login (`api_success_required`).
Native console request `4c8055cb0759f99f06053218ec5bbdde`,07:42:19, records
PUT/user_auth429. The fixture did not yet persist that response's status or
request ID; its last login remains pending, so do not silently relabel/retry it.
Retained protected ledger: `/var/log/kazoo-queue-live-isolation-SdiLT6/ledger.json`.
It contains passwords/tokens: never print or commit it. No original user, agent,
queue membership or routing was changed. The owned denied queue is
`b516dd656fb84bcbbd51661195a61433` in the isolated acceptance tenant.

Using only the3 verified tokens, separate read-only checks passed5 HTTP cases
(`5da95c`/`e071a8`) and5 native Blackhole cases (`a9bf71`/`716240`): positive exact
queue, other queue denial, foreign-company denial, missing-statistics denial,
missing-queue-read denial. The full17-check matrix, fourth user's roster case,
expiry cleanup and cross-node/load remain open. These supplemental checks did
not modify the ledger or pretend its matrix had completed. Earliest cleanup for
the known tokens, including the61-second guard, is2026-09-07T08:43:19Z; ambiguous
last login still separately blocks cleanup. Retain both users and policies.
Next: record definite rate-limit failures in the harness, then reviewed recovery
of this fixture and completion of remaining live-only checks; never relax auth
limits or bulk-delete test resources to force acceptance.

Harness-lock correction also required before the next live run: the original
`flock -n 3 COMMAND` locked a file named `3`, not the inherited descriptor3.
The empty accidental file was moved to the retained fixture directory as
`incorrect-lock-file`; no customer data was removed. Root serialized all jobs
and source-only agents did not run concurrent acceptance, but those earlier
checks do not prove shared-lock exclusion. The source fix must pass a real
competing-flock test on a private inode, then use the existing shared lock.

**Current scope and acceptance checkpoint — September 7:** work is limited to
the live queue summary and selected-queue detail dashboard. Callback fixes and
voices are paused alongside history, ClickHouse, WFM and the separate agent
dashboard; they are not complete. The reported key-6/30-second callback path
remains unresolved. This scope statement supersedes older continuation plans.

The scope-management prerequisite P0-21 is now deployed: `209651`/`1e3fc6`,
receipt `/tmp/kazoo-scope-deployment.rwm5y2/runtime.json`, verifies guarded
module bytes, loaded MD5s, capability1 and running/effective registration. Only
apps restarted; the exact roster and31 agent states stayed unchanged. Actual
full-route policy revision test `7c9f07`/`47ce1f` passes stale412+unchanged,
weak412+unchanged and current DELETE200+absence. Journal:
`/tmp/kazoo-crossbar-revision-http.zRwU7L/run3/journal.json`. One exact owned
unreferenced policy was soft-deleted. Earlier run2 remains retained after a
harness error (native POST replaces public fields; it does not merge them).
See `doc/scope_management_dashboard_acceptance.md` for recovery boundaries.

Restricted dashboard acceptance is still hard closed, not passed. Its offline
fixture passed28 groups/79 explicit rejection checks (`caacb6`/`9ff5b9`). The
next correction is safe adoption of server-generated IDs for its optional
empty denied queue, before any restricted users or tokens are created. Existing
finite-expiry-plus-actual401 cleanup gates remain mandatory. These results do
not imply cross-node, load, installer-wide or production acceptance.

Matching OpenAPI assets were regenerated (`2c63af`/`5bf86b`), passed the complete
offline deterministic/tamper suite (`c040d5`/`87aabe`), and published at `/apis`
(`f93301`/`0a3f65`). All11 served asset hashes, no-store, redirect308 and missing404
passed. Recoverable previous assets:
`/usr/local/src/kazoo5-installer/api-docs-rollback.obvYfs/previous`. The5 native
scope-policy operations now document their role guard and public-field POST
replacement; their remaining upstream schemas are not promoted to fully
reviewed contracts. This static reference publication did not restart services.

**Latest cleanup prerequisite checkpoint — September 7:** P0-19/P0-20 are now
deployed: guarded deployment `489b41`/`b291e2` replaced only `crossbar_doc.beam`
and `kz_couch_doc.beam` from the tested `Sm4MLU` build. Runtime MD5/installed-byte
checks pass on the relevant nodes; rollback artifacts and receipts are at
`/tmp/kazoo-revision-deployment.19HpQo`. Only apps/ecallmgr restarted. All nine
services are active, and the exact queue roster and all31 agent states/memberships
are unchanged. This supersedes the not-deployed labels in older checkpoints.

The new separate `scripts/test-crossbar-revision-live.cjs` passed15 offline
groups (`7a1a9f`). Actual run `592766` stopped **before any fixture write**:
account GET succeeds, but scope-policy collection/selected GET returns404.
Effective Crossbar autoload contains misspelled `cb_scope_retrictions`; source
default in `crossbar.hrl` has the same typo. Do not simply enable policy
management before checking its authorization: the native resource has no local
role guard. Journal `/tmp/kazoo-crossbar-revision-http.zRwU7L/run/journal.json`
records no writes. The protected admin token alongside it is not a fixture JWT
and must never be printed or committed. Restricted-dashboard admission remains
closed pending safe registration, full-route proof and existing token gates.
Live summary/detail remains the only current dashboard scope; history/WFM and
ClickHouse integration are postponed, not removed or migrated.

**Earlier primary cleanup source checkpoint — September 7:** P0-19 private
Cowboy wire suite passes10 cases (`51f026`), with two204→409 race reproducers on
baseline. Actual native primary CouchDB checks exposed P0-20: single hard-delete
bulk conflict rows were reported as success. New required installer patch
`kazoo-couch-single-delete-result.patch` fixes that boundary; nine focused groups
pass, baseline fails six, and real primary probe `b3c7e1`/`2a0330` passes soft/hard
CAS, unchanged concurrent bodies and no success publication/cache insertion on
conflict. Receipt `/tmp/kazoo-soft-delete-couch.Sm4MLU`; two exact owned test docs
removed/absence verified. Three synthetic databases remain as evidence, including
two failed-baseline fixtures; names and limitations are in
`doc/couch_single_delete_result.md`. All eight platform services/test phones
remain running (`ba33c6`); no runtime module was replaced or service restarted.
Next: controlled deployment and actual Crossbar resource/authorization checks,
then restricted-dashboard fixture admission only after cleanup/token gates.
The live dashboard UI artifact remains OxxzgK. History/ClickHouse/WFM postponed.

**Live-only scope / cleanup prerequisite — September 7:** history, ClickHouse
integration, separate agent dashboard and workforce reporting remain postponed.
The live summary/detail browser and reconnect proofs below remain current.
P0-19 now has an installer-owned revision-preserving soft-delete candidate and
nine passing controlled regression groups; the pinned baseline reproduces the
overwrite. This backend change is not deployed. Actual HTTP/CouchDB cleanup and
token invalidation still gate restricted-user acceptance; its harness remains
unconditionally closed and no fixture identities have been created. See
`doc/crossbar_soft_delete_revision.md` and `doc/queue_live_isolation.md` for exact
reproduction, limitations and the source-only user-secret rotation audit. Do
not use rotation as an unverified cleanup shortcut or delete mutable policies
while their issued tokens may still authenticate.

**Current deployed UI — September 7:** OxxzgK production build/artifact checks
`e175b8` and guarded deployment `e8e212` passed. Installer-owned P0-18 background
load patch preserves the active app/shortcuts;12 targeted tests pass and the
baseline reproduces the defect. Only main/templates changed,1942 files were
preserved and none removed. Backup is
`/usr/local/src/kazoo5-installer/monster-owned-build.OxxzgK/deployment-backup`.
All four actual reconnect paths pass (summary/detail × same-account/company
switch), preserving controller/data/subscription cleanup. New real summary call
`d7a65b` passed9 browser checks with2 visible queues/3 natural hints/7 overview
GETs and no detail/supplemental reads. Receipt
`/tmp/kazoo-monster-live-deployed.1bmROU/receipt.json`; one offer/bridge and12 stable
samples at `/var/log/kazoo-strategy-acceptance-73777r/`. Exact final MASTER
roster/31-state comparison279769 passes, all nine services active, zero calls/no
ledger; owned artifact verification9144a5 passes. Build temporarily paused
ecallmgr/test phones; browsers kept all eight platform services running. One
test-phone restoration hit the manual-start rate limit and was restored by
exact-unit reset/start, without changing restart policy. Source/checkpoint and
failure-to-fix guidance: `doc/monster_background_app_load.md` and
`doc/monster_live_reconnect_acceptance.md`. These supersede the older current-UI
labels below. Restricted-user/no-default non-admin, cross-node/load/TLS gates
remain open; history/ClickHouse/WFM remain postponed. No master push claim.

**Live detail reconnect PASS (September 7):** standalone
`KAZOO_TEST_RECONNECT=true` in `scripts/test-monster-live-deployed.cjs` now
tests actual close/disconnected-stale/new-socket-ACK/snapshot/render/cleanup.
Final same-account `4a10d5` passed nine checks (2780ms), receipt
`/tmp/kazoo-monster-live-deployed.9C6AgQ/receipt.json`. Final normal company
switch `20c816` passed 12 checks (3278ms), receipt
`/tmp/kazoo-monster-live-deployed.3J492k/receipt.json`. Visible call counters
and ordered rows are compared independently with the schema-validated DTO.
Both runs had zero browser/HTTP/scope errors and no supplemental detail reads.
Fourteen pure reconnect groups and 17 scoped harness groups passed. Final
snapshot comparison `52c1c7` preserved the exact roster/31 reported states and
memberships; all 30 simulated phones were restored after their temporary pause.
All eight platform services stayed up. No app/backend deployment or call was
performed. See `doc/monster_live_reconnect_acceptance.md` for limits and paths.
Restricted-user isolation, summary reconnect, cross-node/load and TLS remain
open; historical/ClickHouse work is postponed.

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

**P0-16 deployed checkpoint:** the binding logger fix remains an installer-owned
patch, not a nested core commit. Current063784 passed12 tests (8 sink and4 real
production-Lager runtime); baseline20b15f failed12. Three noTEST/-Werror modules
compiled. Deployment be1cb5 verified installed SHA and loaded MD5 on both nodes;
initial verifier-permissions failure99329b rolled back before the corrected retry.
Postdeploy isolated call befb40 passed13 snapshots/3 hints, one bridge and12 stable
samples with exact cleanup and unchanged MASTER state. See
`doc/kazoo_bindings_exception_diagnostics.md` for evidence/backup paths and the
limited post-restart log check; no whole-log or production-readiness claim.

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
