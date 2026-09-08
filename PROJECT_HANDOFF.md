# Kazoo 5 — start here / engineering handoff

**Primary Kazoo5 development host: `10.1.0.44`**, designated by the user on
September8. Keep its installed stack and `/opt/kz5` checkout for future work.
Canonical Git remote remains `https://github.com/talkchief/kz5.git`, branch
`master`; ACDC remains tracked directly in kz5. Normal ALL installation using
source `30daaab` passed; checkout was fast-forwarded to `b393f62` with a clean
tracked worktree before the successful reboot. Subsequent documentation commits
are synced after publishing. Do not confuse this host with the original
`kz5-testing`/`10.1.0.26` development site or production CouchDB `10.1.0.10`.
No DNS/TLS hostname migration to .44 has been requested or performed.

Active after completed installer finalization: `COMPAT-01`, read-only snapshot of
company `d8520ce3f29c5b6db692289e782c92af` from production CouchDB `10.1.0.10`
into isolated development storage, then assess Kazoo5 writes/migrations against
Kazoo4 compatibility. Read-only production metadata inventory475ad5 confirmed
CouchDB3.3.2 and seven exact company databases (account + April–September2026
MODBs). No customer documents copied at this preparation checkpoint. Reusable
GET-only exporter/private receiver and18 offline safety tests passff6226;
live protected export and isolated restore are next. See
[assessment plan](doc/kazoo4_kazoo5_couchdb_coexistence_plan.md); never point the
development apps at production dependencies or put credentials/backups in Git.

Latest continuation: [fresh-host/TLS acceptance](doc/fresh_host_tls_acceptance_20260908.md).
Physical mobile delivery testing was waived by the user. HTTPS is deployed and
browser transport checks pass. Fresh data services and separate UI on 10.1.0.44
pass installation and verification. The user confirms HTTPS login works.
Fresh bridge installation and independent verification also pass. Fresh apps
audio and MIME prerequisites are fixed; full compilation passed, but initial
startup exposed config traversal/private-binding defects. Both are fixed in
`ee7877c`; rerun24127 caught a file-only validator incorrectly used for the
configuration directories. The directory-specific fix and real-helper negative
tests pass70666/a6a153 (`b6d8bae` pushed). Rerun88880 passed datastore/private
binding but failed account bootstrap; a later protected retry created the
master. Exact RPC-result/readiness fix `cdedba2` is pushed. Rerun85919 found
formatter-created private datastore defaults causing .44 restarts; apps stopped
to end the loop. Fix `1e7e40b` preserves JSON modes and repairs public runtime
JSON; normal rerun23557/5db474 **PASS** for apps/eCallMgr, fresh admin/API/SUP,
and 796 shared prerecorded media documents. Services are enabled/active with
zero automatic restarts; `kazoo-applications.service` alias verified.
SIP template fix `c40fd2d` and sound readability fix `237716e` are pushed.
Normal .44 FreeSWITCH/Kamailio install84616 finished13c663 with a pre-start
permission-check failure after successful compilation. Sound manifest transport
and public binary-parent fixes `bc8f969` pass regressions77793/eea832.
Normal SIP rerun62607/2c4b73 **PASS**, including FreeSWITCH/eCallMgr/Sofia,
Kamailio SIP/AMQP/dispatcher/JWT readiness. Current local-stack UI96182/c9749c
**PASS**, with ten absent catalog entries created. Independent fresh ALL66513/f83cde
and actual fresh-browser48355/8df633 **PASS**. First reboot failed acceptance:
private IP appeared after network-online; HAProxy stayed down while four other
units recovered after one restart. Exact-address startup gate is implemented
and tested, pushed `30daaab`. Normal fresh `ALL`48019/6236b8 **PASS**, followed
by actual reboot to `c8994ec2-c85c-4121-b4c4-2685129d3d35`: all nine services
active, all restart counters0, no repeated address-bind errors (a833e2).
Post-reboot independent ALL76710/8722b4 **PASS**; actual browser login/local
API/WebSocket and `/apis`30795/7b71ff **PASS**. No installer/test job remains.
Protected logs: `/root/kz5-acceptance/all-address-install.log` and
`/root/kz5-acceptance/postboot-verify-all.log`. This closes the measured fresh
installation/repeat/reboot checkpoint, not general production/HA/load acceptance.

Last updated: **2026-09-08**. This is the navigation and current-state guide;
`PROJECT_TASKS.md` is the detailed requirement/acceptance register. Neither this
file nor a green unit test means the platform is production-ready.

**Forwarded-call confirmation complete, including the UI follow-up:** EN/HE/AR/ES/FR
account preference/API, four selectors, immutable Gemini media and MonsterUI are
installed. Normal full installation passed64656/94b843; corrected UI deployment
passed92313/fb92d5. The user can hard-refresh and test **Callflows → Account
Settings → Misc → Forwarded-call confirmation**. The section header and field
label are visible, options align left, and Update saves a changed language,
keeps the form open and confirms success. An untouched dropdown preserves a
newer API value. Both save buttons, reset and missing-locale fallback pass.

Seven Erlang groups and asset/API/installer suites pass; 20 live API/call checks,
seven initial browser checks and ten follow-up browser checks97471/06800e pass.
Full fixture account settings are restored, tagged users deleted, channels0.
OpenAPI account GET/PATCH/POST, all five codes, reset and frontend sample are live
at `https://kz5.talkchief.io/apis/`. Branch:
`feat/account-forward-confirmation-languages`, isolated worktree
`/opt/kz5-fwd-review`; latest pushed and remote-verified commit `52c8d85`
includes the UI follow-up and release handoff. Merged into master as requested,
together with the focused fresh-server/TLS fixes; no current-host redeployment.
Authoring credential: protected `/root/key.key`, the same file used for ACDC WAV
generation; use the Gemini-specific reader in `generate-acdc-gemini-samples.cjs`.
Keep only this location in the handoff, never the key value. All five recordings
are committed. Clean Git-export check bb9c13 imported and byte-verified them in
an empty media fixture with networking disabled and no credential reads or
provider calls. Normal installer hooks install and verify the packaged assets.
Physical cellphone/PSTN and native-speaker certification are not claimed.
[Acceptance and developer handoff](doc/call_forward_confirmation_acceptance.md).

## Latest working snapshot — read before resuming

**Standalone UI catalog gap implemented and locally integrated:** the installer
now requires explicit pinned remote catalog authority when local apps/SUP are
absent, instead of silently skipping registration. Local ALL is unchanged.
The fixed receiver is installed on the dev apps node.19 transport tests,
installer routing/smoke/modular/read-only/persistence suites pass; actual local
receiver proof18673/066c23 and pinned loopback SSH16602/47fb93 pass. The latter
exercises real installer remote routing, ten preserved apps and twenty verifies,
plus wrong host-key/master/source-version rejection. No app service restarts,
catalog overwrite, production SSH changes or provider sends. Temporary daemon
and keys are removed. Receiver source/install hash is
`faa59f49c0ec2072537e241eba6a32dd48ffae3a0d71cf555b7d186072d326b3`.
See `doc/monster_ui_remote_catalog.md`; a genuinely separate clean server and
absent-catalog creation remain unaccepted. Test-phone tokens and a clean Rocky9
SSH target were requested asynchronously; no response yet. Do not invent these
or reuse production bridge credentials for this workflow.

**FULL APPS/ECALLMGR INSTALLER PASS:** session48353, terminal `f4275e`,
exit0 at approximately06:52UTC September8 from pushed `981f317`.
Normal `install-kazoo5.sh kazoo-apps ecallmgr` completed compilation, release
assembly, both service restarts, readiness, all796 prerecorded documents in
both maps, measured five-language selection publication, final verification
and root-only `/etc/kazoo/deployment.env` persistence. No build bypass and no
Gemini calls. Unit `kazoo-validation-af990f40-1680-48f8-877a-16e56a20f4cb.service`
used one worker,384MiB cap,512MiB reserve and3600s runtime. This is a same-host
installation pass, not fresh/split-host acceptance. Source freeze is released.

**Independent installed-stack verification PASS:** session56291,
terminal `3f1242`, exit0 at~07:04UTC, normal `--verify-only ALL`,
384MiB/512MiB reserve/900s. All nine component checks passed, including
Kamailio's full journal/JWT cache, Monster UI's ten apps and bridge consumer
readiness. No live installer/test job remains. Do not repeat the build or this
verification merely to refresh evidence. Final service readback `0a2d67`
confirms all nine units enabled/active with restart counters0.
Apps1614512, eCallMgr1637256, bridge1172968 and nginx1108648 are running.
`kazoo-applications.service` resolves to kazoo-apps.
The unrelated untracked `doc/dashboard_caller_sidecar_design.md` remains
excluded from commits.

The first independent run45977 exited1 (`bc78ef`): Kamailio's journal verifier
hit its aggregate32MiB/100000-record limit on this long-running service.
Focused fix streams the full activation history with constant retained state,
keeps the1MiB record cap and30s journal deadline, and requests only required
JSON fields. It does not tail/drop historical errors.13 regression tests and
43 AMQP fixtures pass34186/2eb247. Actual corrected ALL verification passed
above. Service journals for apps/eCallMgr/bridge/nginx contained zero
priority0–3 entries since06:35UTC at readback9be99d; this is not a claim about
every application log or indefinite crash freedom.

**Latest operator request: finalize ASAP; do not keep expanding tooling.**
Tested changes are already committed and pushed in `981f317`; the normal
apps/eCallMgr installer and independent `--verify-only ALL` passed. Publish
this focused checkpoint; retain the explicit external/release gates below. Do
not start another build merely to refresh evidence. Five-language success/retry and
registered-consumer/DLQ recovery evidence is below. Returned-audio supplemental
proof remains incomplete: HE50498/53cce7 failed coverage, and diagnostic79134/
7eacd4 found160 missing RTP samples inside its matched phrase, correlation
0.999992. Do not misreport that as a full waveform pass. The original callback
pass is unchanged. No need to rerun live calls to publish this checkpoint.
The former private standalone catalog proposal is now integrated and tested to
the scope in the newest snapshot above. Its original private handoff is stale.

Current acceptance details/commands: `doc/focused_acceptance_20260908.md`.
Registered-consumer real broker proof83390/9d4620 PASS; exact counters,
source pins and generated-resource cleanup independently checked2d7db8.
Unbound-DLQ test40711/644081 failed its60s recovery window; broker default
no-route retry is180s. A bounded240s recovery/300s case revision passed12
offline cases and now passes actual broker proof52763/f08152. All resources from the failed test were
removed. Callback/guard repository suites53441/32d30a PASS. Hebrew8443/53f15d
and French15515/f1b8d1 live single-key6 retries PASS against installed prerecorded
success audio; directories20260908T010737Z and20260908T011230Z. Spanish
37303/93b8d4 also PASS at20260908T011714Z; Arabic56725/d5de4c PASS at
20260908T012152Z. Corrected unbound-DLQ actual test52763/f08152 PASS:
exact body recovered174934ms after restoration, one publish/dispatch, no
republish, stable sources and both temporary resources removed (ac566a).
The1h opt-in guard itself was verified by actual unit
readback e2026b, retaining the other resource limits.
The additive returned-confirmation waveform checker is integrated and its
five synthetic groups pass38329/92034c. Hebrew reference capture passed, but
offline replay50498 failed strict coverage as detailed above. The current success
audio proof does not establish that separate recording's actual playback.
No real push notifications or production changes have been made.

### Remaining acceptance, not new implementation scope

- Local full apps/eCallMgr installation and independent ALL verification are
  complete. No further local rebuild is needed for this checkpoint.
- Real Android/iPhone delivery requires test-device tokens plus the APNs topic
  and environment; registered-consumer/broker tests are not phone-delivery proof.
- Fresh-server and split-host installation remain unaccepted. The standalone UI
  catalog transport is implemented and loopback-tested, not second-host-tested.
- Complete returned-call waveform coverage/native voice review, HTTPS/WSS and
  production load/failure/recovery acceptance remain open. Do not label this
  release 100% production-ready.
- Historical dashboards are postponed; live dashboards are below the urgent
  callback, prerecorded-voice and deployment priorities.

### Archived execution history — superseded by the live snapshot above

The paragraphs below retain earlier evidence and decisions. Their words such
as “next,” “running,” “pending,” and “no live job” describe their original
checkpoint, not current instructions. Do not repeat completed work from them.

Last installer job is TERMINAL, not successful: apps/eCallMgr rerun from pushed9642413,
session4728, initialf18428, guarded unit
`kazoo-validation-e15ec615-0dda-496a-9e29-05367204c3fb.service` (~00:29UTC).
Zero channels checked; one worker,384MiB cap,1800s deadline. Session b741fb
 exited1; journal f5c7d5 confirms RuntimeMaxSec timeout at00:59:06UTC.
 Compilation/release assembly, apps startup/datastore and796 media documents/
1592 mappings passed first. Apps/eCallMgr/bridge are active. Full installer
 completion remains unproven. No live job or source freeze remains. A longer
 explicitly bounded validation window is under private review; memory/CPU and
 global serialization limits must remain unchanged.

Original private bridge proposal is `/opt/kz5-bridge-consumer-proposal.lb2qJ4`;
agent `installer_review` finished its offline regressions. It exercises the
actual registered-consumer loop with synthetic providers in UUID-local broker
resources. It is now integrated, offline-tested and actual-broker-tested above. No phones,
production broker credentials or production server changes are authorized by
this harness. The full installer freeze ended with its confirmed timeout.

Use `proposal-v2.patch` (SHA256
`c4cf514b04ba376f858c15313d2aeaf90c6956387cf78dc842f55f28b9c4b35b`), not the
original proposal, plus `tests.patch` (SHA256
`5f3c5da7aaed52534e0a5eaae362ef65a406ae8644b394e65063f4528b3bbdfa`). Root
read both private source files; next is network-isolated
`test-accept-push-bridge-consumer.py` using the installed bridge Python3.11 venv,
then the explicitly local broker command documented in private PROPOSAL.md.
Separate unbound-DLQ proposal is ready at
`/opt/kz5-bridge-dlq-retention.Hkh8Ez/proposal.patch` (SHA256
`92d86c7a6eeb4db42e3c080541071e832f087032ef7ab4afef5c8f761f2beb87`).
Root read the new driver/CLI and nine proposed offline cases. Run its private
`test-push-bridge-dlq-retention.py` plus baseline
`test-accept-push-bridge-retry.py` offline before any local-broker proof.
It tests one confirmed publish/reject while the owned dead binding is absent,
then exact readback after restoration with no republish. No full-queue or
restart claim. Both broker proposals have now been executed with separate
pass/failure outcomes above; do not reuse their initial pending status.

Agent `arabic_review` prepared the integrated test-only locale extension to the
EN-only callback-retry harness/reference helper. Preserve EN defaults and allow
only EN/HE/FR/ES/AR; set only the isolated fixture queue language and require a
matching installed confirmation reference. No runtime or generation changes.
After source review/offline tests, use it to run actual full-confirmation and
missed-first-attempt retry in the other four locales after this deployment.

Bridge deadline is now deployed: source205 tests/smoke82499/98c851 and actual
main-SH install plus independent verify74779/c9f0f1 PASS. New release
`0a3a5ba26bdf26caa9fea2343fb565c3ce218079cf976eb5be801ac9143e94da`,
PID1172968 active, restart count0, installed source hashes match. No actual
provider sends. Dispatch/rollback suite and actual Crossbar formatter transition
pass82966/00c47b; preflight `/tmp/kazoo-integration-preflight.LLkrRB` retained.
These fixes are pushed in9642413; the complete installer is running above.

Latest source work: full apps/eCallMgr installation39751/8e209c stopped before
compilation/restarts on three build-formatted Crossbar schemas. Exact known
formatter transition is now implemented;110 transition cases, installer smoke
and12 catalog tests passed26154/15c456. Full installer rerun remains required.
Unknown/mixed schema changes remain refused rather than overwritten.

Bridge deadline behavior and its earlier private205-test proof12055/09efad are
documented in `doc/push_bridge_worker_deadline.md`. Source tests and main-SH
deployment subsequently passed above. Actual registered-consumer retry/DLQ
failure and phone delivery remain open.

Final focused verification `90006/cb79bd` PASS: cache15, readiness26,
current-build checks, finalization32, actual deployed editor-language functions,
and main-SH `--verify-only push-bridge`. Provider delivery remains unverified.
`kazoo-applications.service` correctly resolves to the active kazoo-apps unit;
apps/eCallMgr/bridge/nginx are active with restart counters0.

Normal Monster UI installation now PASS `44420/6ef89a` (exit0), including all
ten preserved catalog registrations, served owned artifacts, Crossbar proxy,
nginx enabled/active and normal config persistence. Empty-icon helper deployed
after12 catalog tests,87 transition cases and installer smoke checks passed.
Old BEAMs retained in `/root/kazoo-catalog-deploy.Q6EBiJ`; new BEAM SHA256
`79528cf9362e9742c74b62bb079f091e5372fa316da59400258c066e2db19a95`.
Future builds reproduce it from the Crossbar aggregate and exact prior-state
transition patches. Next main gate is uninterrupted apps/eCallMgr installation
using the tested readiness/media-replay fixes. No full-stack acceptance yet.

Latest continuation: callback retry `1297/784164` PASS on the new build
(`/var/log/kazoo-acceptance/20260907T232852Z`): key6, complete confirmation,
missed first return, persisted retry and accepted second return/native bridge.
Uses internal1001; fixture retained. eCallMgr cold restart `34255/656bb8` PASS
with actual datastore readiness, PID1036743. Deployed unified editor/API plus
bundled ACDC language functions pass `59484/322097`: all five enabled,210media,
no queue writes/provider requests. Native listening remains unapproved.

UI and `/apis` deployed in `73828/bc2596`, but the overall UI installation
failed at CSV Onboarding catalog registration because its icon is an empty
string. Focused source fix and12 catalog tests/production compilation pass;
source-transition tests and deployment/retry subsequently passed above. First npm attempt OOMed;
bounded192MiB npm heap and download concurrency fixed the retry. No complete
one-shot stack installer acceptance is claimed. See latest task-register entry.

### Prior working snapshots

At23:29UTC all five actual position-one/offer-six calls pass:71221/06d203(EN)
and75174/44d3e7(HE/FR/ES/AR), including exact audio/timing, runtime/log gates
and conditional cleanup. No agent assignments changed. See
`doc/prerecorded_release_finalization_20260907.md` for all five evidence paths.
Key6/full-confirmation/missed-first-attempt retry1297 is now running on this
new build; do not treat its prior-runtime pass as the new result.

At23:17UTC the actual five-language native function proof passed
`95443/8dee1a` (796documents/1592maps,95position/10callback/80waitcases).
Protected receipt `/root/kazoo-prerecorded-release.F8qJut/runtime-receipt.json`
SHA256`f0f59a60be6fb8607ff15f146e35fbdf4c2dbe51aaed2e17eee4453cfe3f7db0`.
Actual publisher`71766/1727f7` sets all five selections ready under
`/etc/kazoo/acdc/language-capabilities.json`, retaining full/native/listeningfalse.
The prior explicit web-root path was inspected as an all-negative legacy artifact
and migrated; oldfile remains. Marker/proof retained, no false build flag used.
Main-SH legacy-path migration still needs the matching regression/code change.
Startup readiness26fixtures and both actual node reads pass; cold start remains.
The small private conversion cache passes15fixtures. Real pack/reference
run12519/e2951a passes and its complete input equals the prior uncached proof
exactly (`de3c3d`). Reference index `/root/kazoo-prerecorded-reference.PvNvXj/index.json`
SHA256`588d9e5ab556ee1cc7968d6d646f0e21d2fa55c5257c307dc69dab95acd2f78a`.
English live71221/06d203 passed complete position-one and30/60second offers,
runtime/log gates and conditional cleanup. Evidence
`/var/log/kazoo-acceptance/20260907T231909Z`. Other four locales also passed75174.
Next: callbackretry, UI deployment, cold start and complete
main-SH run. Dashboards stay postponed.

Runtime has advanced: pushed `dd39d90` fully compiled and release-assembled in
normal run `5f658d/session54282`. AppsPID944670 is running the new build;
the outer30minute guard timed out during mapping checks, so that installer run
did not complete. Independent mapping continuation `9e200f/7263e9` passed all
586cardinal/intro documents and1172maps (fixed210/420passed in the installer).
Actual eleven-BEAM manifest and real probe options are private under
`/root/kazoo-prerecorded-release.F8qJut`; proof/publication now passed as above.
eCallMgrPID960600 is also activated and its full checks including native
kz_intercept pass `77dbc2/c006ca`. Its initial5second-wait configuration call
raced datastore startup; the new readiness gate passes its offline fixtures
and actual warm-node checks. No calls were performed in these activations.

Most recent verified code fixes: `36876c3` is pushed; direct application build
ordering passes. Second run `dc71ad/session30156` was stopped during media
preparation to repair the runtime probe's wrong OTP `beam_lib:md5/1` return
shape before activation. Actual-template BEAM checks now pass against real
compiled code, not only synthetic JavaScript fixtures (`022310/031fb5`).
The five-language2098 position/offer harness is integrated and passes52 audio,
10 reference and33 fixture groups (`7ac1fc/d39a06`); its guide is
`doc/acdc_five_language_live_audio_acceptance.md`. All live five-language proof
and matched deployment remain pending until a subsequent installer succeeds.

Latest continuation: `99eafe5` is pushed to master and contains the tested
prerecorded/runtime/bridge integration checkpoint. Normal installer attempt
`8a1b8e/session36819` was deliberately stopped before service activation after
both voice packs and the first core/webhooks build passed: top-level `apps`
started a redundant second forced core traversal. Do not classify its manual
systemd stop/zero wrapper status as acceptance. Services retained their existing
PIDs. A minimal direct-applications-aggregate ordering fix is being validated
before the next normal main-SH run; details are at the top of PROJECT_TASKS.md.

Focused checkpoint, 2026-09-07 21:41 UTC: native atomic interception is now
deployed: module-only `012ab4/805728`, installed SHA256
`4ac9d4af50deca7a4163bb158befaecbbdcd59f23e137fe49aaf9d213810cfec`,
backup `/var/lib/kazoo-mod-kazoo-upgrade.dU80a1`, native eCallMgr-to-FreeSWITCH
check `d58bb9/e31aba`. Full FreeSWITCH build marker is intentionally unchanged.
The eCallMgr aggregate reconciliation passes81 source-transition cases.
Matching apps/UI deployment, native five-language capability proof and actual
calls still remain. A five-language position1/offer live-test draft is frozen
outside the repository under `/opt/kz5-voice-acceptance-work`; review/test before
integrating, and do not claim wait-time or full callback coverage from it.

Earlier attempt: the normal apps+ecallmgr installer
`a87725/session80615` ended with exit1 (`4c095b`) before compilation/restart:
eCallMgr's checked-in atomic delta is not included in its installer aggregate.
Reconciliation and the missing native `kz_intercept` prerequisite were subsequently
fixed as recorded above. Offline six Erlang cases and
100 three-answer race iterations pass `ad7f8b/35c78b`; live acceptance remains open.
All796 media documents and1592 runtime mappings are installed
and independently verified. The matching backend/UI and native capability proof
are not yet accepted. Pre-restart call/status ETS snapshots are private under
`/var/lib/kazoo/predeploy-check.BRAAd0/snapshot` (22 call rows including9 unarchived,
685 archived status rows); never commit these. Canonical launcher path fixes and
the finalization hook's16 synthetic cases passed before this build.

Saved five-language cardinal assets are
pushed in `d09d697` on master. Complete voice runtime deployment is still pending;
no more Gemini authoring is required. Bridge source is deployed through main SH,
install `feccd8/4664d3`, independent verify `b0c4d8/02b4a6`, release
`b20944143ade6ae0ad3ffb4c4c69094305348d7220f890669ca57606fb3810f8`.
Consumer readiness passed, not actual Android/iOS delivery. No production changes
or opt-in topology/retry activation. See PROJECT_TASKS.md's top section for
current remaining work; older milestones below are historical.

**Current artifacts:**584/584 complete, including AR208. Final59-receipt replay
`d5f2f4/467d44` leaves no missing roles/proposed requests. Index pin is
`b6c4e2a2ef515be72d378a239086b4421992a095447003c1c397c925d98c1e51`.
All four nonEN maps are actual emitted source. MainSH/all-five playback/cache
integration is in progress; do not infer deployment or listening approval.
Actual synthetic broker retry proof passes `feecd1/ac00b2`; see its detailed
receipt/document. Current task register supersedes historical snapshots below.

**Earlier artifacts:**529/584; EN/HE/FR/ES complete, AR153/208 (55 missing).
Three actual HE/FR/ES source maps are saved and independently reviewed, not
activated. Forty-receipt replay and all nine running services pass
`de95f2/fb1089`. See `doc/acdc_cardinal_ar_model_recovery.md`; older inventory
counts below are historical checkpoints, never runtime acceptance claims.

**Focused source fixes:** mixed-model cardinal admission passes importer8,233
checks, current-module compile/17 EUnit and adapter tests (`38195b/4482a3`).
No nonEN map is activated. Opt-in bridge counted retry passes all187 Python
tests; main-SH retry-module staging/verification paths pass `c73261`.
Actual broker fault/counter proofs, header-directed/APNs retries and real phones
remain open. See `doc/acdc_cardinal_model_runtime_admission.md` and
`doc/push_bridge_counted_retry.md`. Latest Arabic authoring checkpoint is in
`doc/acdc_cardinal_ar_model_recovery.md`.

**Latest combined coverage:**481/584 technical artifacts. EN31, HE131, FR161
and ES53 complete; AR105/208. All36 remaining Hebrew recordings are saved,
actual HE131 plan passes `4842e8/8770e2`, mixed five-locale adapter tests pass
`b086d2/31b376`. See `doc/acdc_cardinal_he_model_recovery.md` for exact pins,
receipts and limits. Arabic103 recovery, listening, runtime model admission/maps
and main-shell deployment remain open. Older counts below are historical.

**Original 2.5 voice ledger (not combined coverage):**412/584 technical QA (EN31/HE92/FR160/ES25/AR104),
697 requests,113 retries,172 failed and no pending/indeterminate identity. Five
bounded concise-v2 Hebrew requests recovered three recordings; six WAVs saved.
See `doc/acdc_cardinal_concise_synthesis.md`; older counts below are historical.
No new cardinal runtime activation or listening approval is implied.
Exact-word Spanish reuse now passes 5,962 importer checks and installer adapter
regression; that earlier resolved inventory was 412 generated + 2 reused, 170 missing.
See `doc/acdc_cardinal_reuse_import_integration.md`; staging is not deployment.
The separate 3.1 model experiment and exact private receipts are documented in
`doc/acdc_cardinal_31_model_trial.md`; trial calls do not alter the legacy counts.
Trial-only MIME compatibility and narrow diagnostic passed637 offline checks.
There are now31 separate QA candidates/62 WAVs and32 additional trial requests
in12 saved receipts.
Spanish artifact coverage is53/53 (25 original+26 model-trial+2 exact aliases).
No mixed-model runtime deployment or listening approval is claimed. Candidate
verifier447 checks and planner204 checks pass; see
`doc/acdc_cardinal_model_recovery.md`. Do not regenerate these successes or
relabel them as 2.5/runtime-approved recordings.
FR89 one-shot succeeded. EN/ES/FR technical artifact coverage complete, HE95/131 and AR105/208
still incomplete. See `doc/acdc_cardinal_fr89_one_shot.md`. The fixed private
FR89 reservation is permanently consumed; do not remove or reset it.
Mixed-model staging importer passes23 groups/8,016 checks. See
`doc/acdc_cardinal_model_trial_staging.md` for index/provenance contracts.
It stages candidates only, not runtime or listening approval.
Actual ES53/FR161 read-only plans pass `cd6452/f2a5bf`,0 unresolved and no
provider/database requests; exact candidate hashes are in that staging document.
Safe prompt-feedback diagnostics are implemented and pass19 groups/377 checks
(`a40011/893835`) without real provider calls. No speculative transcript change
or additional identical retry batch was started.

**Bridge freshness:** versioned producer metadata and worker/auth/transport
expiry checks are implemented;166 offline bridge tests,35 producer checks,
actual private Kamailio route execution and real isolated broker quarantine pass.
See `doc/push_bridge_freshness.md`. Strict activation requires reviewed quorum
configuration and patched producers; legacy development routing is unchanged.
Main-SH bridge deployment `d092dc/1e7b45` and independent verification
`b9e8bb/be5ab7` pass; releasec9d8055d8f92, PID448604, NRestarts0.
Main-SH Kamailio producer deployment `0de2e3/95d41c` passes all current
integration/journal checks; PID451713, NRestarts0. Configuration backup retained,
prior malformed-Via logs preserved, their attribution still open.

**Latest post-deployment callback proof:** `21d377/session53798/55fb32` exits0,
including full Gemini confirmation, missed first return, retry/second native
bridge and final SIP/RTP/agent/service/log gates. Evidence:
`/var/log/kazoo-acceptance/20260907T181123Z`. The failed legacy-reference trial
and corrected analysis are documented in `doc/development_warmup_20260907.md`;
new preflight rejects legacy references before any calls.

**Earlier warm-up and callback proof:** all210 deployed Gemini clips and420
running cache mappings verify; extension1000 native request construction passes.
Live isolated1001 retry `6e1abf/session73991/6fd51b` proves confirmation, missed
first return, durable retry and second native agent bridge. See
`doc/development_warmup_20260907.md`; this is not the operator1000 phone test.

Verified-quorum permanent-message quarantine passes145 bridge tests and actual
broker DLQ/continued acceptance/restored-policy proof (`51559a/3e77be`). Main-SH
deployment `e1b349/b94ad2` passes: release51d97e626ef2, PID423856, NRestarts0;
existing legacy dev routing unchanged. See
`doc/push_bridge_permanent_quarantine.md`. Transient retries/freshness/phones open.
Independent main-SH verify-only passes `55f252/session16031/cbbb2c`.

**Latest voice checkpoint:**404/584 technical QA (EN31/HE84/FR160/ES25/AR104),
676 historical requests and92 cumulative retries. All initial identities are
attempted;180 FAILED, none PENDING or REQUESTING. Added65 Arabic recordings
(130 WAVs), retaining every previous success and attempt. No live authoring job
remains. This does not activate the expanded cardinal pack: failed-only recovery,
listening, complete packaging and runtime integration remain open. See
`doc/acdc_cardinal_ar_initial_completion.md`. Older inventory counts below are
historical. Never call Gemini during installation, account creation or calls.

**Latest bridge/installer follow-up:** new explicit quorum topology and fresh
management-policy/queue verification are deployed in release
`734ca0203eff1bc9da4ca4932d2375ce404b187b0c399222f3ae33edb6217880`, PID381466,
NRestarts0. MainSH `eddec8/session40843/cdcd63`, independent verify
`e02540/session45092/9a1a1c`; all132 bridge tests/43 Kamailio cases pass
`37a62e/session13700/fb9511`. Actual isolated broker proof
`852b0d/session65965/f8265c` passes declaration/confirmed synthetic publish/DLQ
readback/unsafe-policy refusal/restoration. Its temporary vhost/user were removed.
See `doc/push_bridge_quorum_topology.md`. Existing dev consumer stays on its
isolated legacy binding; no production connection or real device notification.
Provider retries, event expiry, fault recovery and designated phones stay OPEN.

Final offline installer regression `0fad16/session97479/43a0e0` passes syntax,
pins, aliases, modular/security/ALL/error paths, bridge dispatch and43 Kamailio
cases. Voice ledger/private-origin equality, historical immutability and all
saved WAV/hash/actual-SoX checks pass `4e6f91/session99094/fbe779`.

Kamailio effective-URI verification fix is in main SH, with43 offline cases and
modular tests passing (`d9be50/1578f8`). Actual verification
`23b62b/session86116/c623a0` proves its effective transport/local-vhost queues
and SBC checks but fails the retained journal gate:4 earlier malformed SIP
replies without valid Via (15:16:37/15:20:36UTC). Not JWT/AMQP failures; sender
unproven. No gate weakened or service restarted. Nine checked services active.
See `doc/kamailio_effective_amqp_verification.md`.

**Latest voice/installer checkpoint:**339/584 cardinal recordings pass technical
QA (EN31/HE84/FR160/ES25/AR39);553 requests,92 retries. New optional versioned
`cardinal-concise-v2` authoring instruction keeps exact text/model/Sulafat and
immutable old history. Four HE recordings were saved;2 HE and4 AR experiments
still failed, so this is not a proven provider fix. Diagnostic old-style HE
attempt2 returned OTHER with no audio/text parts. Failed HE47/FR1/ES28/AR46;
AR123 initial-PENDING. FR89 remains capped at6 failures. No live provider job,
listening approval or new cardinal deployment is implied by this checkpoint.
See `doc/acdc_cardinal_concise_synthesis.md`.

Guard `6a52f3/session77127/e5dc60` passes15 pack groups/4926 assertions,
18 generator groups/299 checks and EN/five-locale adapter cases. The new
`--all-locales` adapter requires complete fixed-path sources/maps before writes
and final read-only584-role verification. Main SH retains its EN31 call; missing
nonEN maps are not fabricated. Importer3890 regressions and actual EN plan pass
`6302ed/session41803/15cc5d`. See `doc/acdc_cardinal_all_locale_adapter.md`.

Bridge remains running, NRestarts0; production FCM/APNs source configuration
already exists in protected files outside Git. Do not recopy/publish secrets or
modify production to test it. Native freshness/durable delivery recovery is
planned, not implemented: `doc/push_bridge_delivery_recovery_plan.md`. Actual
designated-device delivery and all broader release gates remain open.

The older working snapshots below remain historical evidence.

**Bridge deployment follow-up:** source now supports explicit verified AMQPS,
TLS1.2 minimum, certificate/hostname verification and protected CA parsing in
main-SH preflight. All112 bridge tests and dispatch pass `0d2bfe/b60ebe`.
Deploy `1ff54f/02ae6d` and independent verify `9f2d32/f1ad28` pass; current
release `24e085e77183a418ded9df942a6dd16dc5883eacb2e7ca30d85a3cc7e4ab6c76`,
active registered consumer PID323748, automatic restarts0. Existing local
isolated plaintext broker configuration is unchanged; no production writes or
provider push. Real remote AMQPS/mobile delivery and durability/deadline gates
remain open. See `doc/push_bridge_amqp_tls.md`.

Five-locale cardinal media source preflight passes12 EUnit groups and private
production/TEST compilation (`0d2bfe/b60ebe`, `/tmp/kazoo-cardinal-media.i32h6k`).
Complete inventories/intros are verified via an independent catalog/importer
oracle. EN map and announcement dispatch stay unchanged; no fabricated nonEN
map, import or deployment. See `doc/acdc_cardinal_five_locale_media.md` for the
concrete remaining integration boundary.

**Current follow-up:** thirty-second offer acceptance is now a real live PASS,
`2d290a/session16292/db354d`, evidence
`/var/log/kazoo-acceptance/20260907T162617Z`. Installed EN offer5.171s played
at30.054 and60.054s (each correlation0.999993), with no early/extra offer and
quantified quiet audio before29s. Generic interval remained15; position playback
was disabled. Normal76s call teardown, unchanged services/workers, log/core
gates and exact-revision cleanup passed; only marked queue/callflow soft-deleted,
unrelated documents unchanged. See `doc/acdc_callback_thirty_second_acceptance.md`.

Cardinal inventory supersedes16:16UTC below:335 QA (EN31/HE80/FR160/ES25/AR39),
542 attempts and85 cumulative retries. HE51/FR1/ES28/AR42 failed; AR127 still
unattempted. Three AR batches stopped on HTTP500; no indeterminate request.
New38 recordings/76 WAVs and receipts are copied to Git. Whole-ledger/offline
WAV/SoX plus immutable-old-attempt and repo/private equality proof passes
`9c74e0/session36821/e854e2`. No listening or cardinal runtime admission.

**16:16UTC checkpoint:** bridge OAuth update is deployed through the main SH
(`3f5035/session60404/aa39ab`), with independent verification
`67c5ba/session51989/a1b50e`. New release
`/usr/local/lib/kazoo-push-bridge/releases/5d3745fd54bc8297f586c8ebb9c8e917de410957d9f02b6c04070c75997b5afa`;
PID301642, zero automatic restarts and all eight checked core/bridge services
active (`89bb9d`). All103 bridge tests plus installer dispatch pass
`325b4d/c536f1`. OAuth has its own reusable owner, connect/read timeouts,
redirect rejection and decoded64KiB body cap. Total operation deadlines,
durable recovery, AMQP TLS and real designated-device delivery remain OPEN.

The checked-in cardinal ledger now has297 QA recordings: EN31, HE59/131,
FR160/161, ES25/53, AR22/208. Two separate new HE/AR intros also pass. Since
fe02eb0,103 cardinal recordings plus2 intros (210 WAVs) are newly preserved.
All458 attempts and prior successful bytes were independently verified against
fe02eb0 and the private origin (`67c5ba/a1b50e`). Retry budget85. No REQUESTING
rows or live authoring handles remain. FR terminal89 still fails after6 attempts;
do not reset its history or keep retrying through the hard cap. HE35 and AR176
initial roles remain pending, alongside HE37/ES28/AR10 failures.
The locale-aware staging importer passes12 groups/3890 checks (`5ce21d/1d1d70`),
including synthetic complete AR208 and unchanged actual EN map/installer plan.
Five-locale runtime media integration, real import, listening and playback
acceptance remain OPEN; no new cardinal runtime deployment occurred.

**HE/AR voice progress:** two new explicit-position-number intros are authored
and saved in `scripts/assets/acdc-gemini-cardinal-intros-20260907`; both first
attempts passed, copy verification `b13129` passes. Read the new full language
reviews and `doc/acdc_cardinal_he_ar_authoring_20260907.md`. The approved set
now pins all five text/delivery/intro declarations at `452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5`;
old attempted EN/ES/FR records and all listening-PENDING fields are unchanged.
EN installer pin is aligned and actual EN plan/map checks pass. First HE32
batch yielded25 QA/7 incomplete; subsequent batches must inspect the ledger.
The tested explicit recovery CLI now supports opt-in attempt limits2..6;
default2 and all immutable-history/completion gates remain. See
`doc/acdc_cardinal_bounded_recovery.md` before any further retry. No new
cardinal runtime deployment or listening approval has occurred.

**Mobile credential-source clarification:** FCM/APNs keys from10.1.0.28 were
already retrieved read-only and configured under `/etc/kazoo-push-bridge`;
never copy populated configuration or credentials into Git. Fresh independent
main-SH verification `8c6713/session38308/7f467d` passed; service active/running
with zero automatic restarts. No new production access or provider push was
needed. Development consumer remains isolated; real mobile delivery is OPEN.

**Latest French artifact checkpoint:** all161 initial roles attempted and each
of46 first-attempt failures retried once. FR138 QA/23 failed, no pending or
indeterminate FR requests. Added100 accepted recordings/200 WAVs since fdb88cd,
plus six run receipts and full ledger; total292 historical requests, retry
budget47. Offline copy verification and current pinned-Requests9 tests pass
`2bf797/f06077`. EN31/ES25 unchanged, HE131/AR208 still pending. No new cardinal
deployment or listening approval. Failed FR identities reached the existing
two-attempt cap with OTHER; see `doc/acdc_cardinal_fr_authoring_20260907.md`
for exact IDs, receipts and recovery boundary. Do not erase history or bypass
completion checks. All six authoring handles finished; none remains running.

**FCM concurrency/installer checkpoint:** the bridge now leases HTTP sessions
exclusively per send/retry and reuses them from a pool capped at configured FCM
WORKERS. Shutdown waits for active sends before closing all retained sessions;
overflow direct sends return a fixed capacity failure. All88 bridge tests and
installer dispatch pass `0f958e/5f962f`. Main-SH deployment `01728e/abcc83`
and subsequent independent verify-only phase `5a5172/b0c93a` pass. Current
release `/usr/local/lib/kazoo-push-bridge/releases/c36d971f6f8a1630af942cc1e8b7ee51c3adced67d6d124c500caea329a04db2`,
enabled active consumer PID259472, automatic restarts0 (`46b546`); prior release
retained. No production change or provider push. OAuth refresh, total deadlines,
durable retry/recovery, AMQP TLS and designated-device ringing remain OPEN.

**External-route regression on the same harness:** `c26844/session62944/efcaac`
finished exit0, evidence `/var/log/kazoo-acceptance/20260907T153203Z`. The full
single6/audio/unanswered-first/retry/second-agent-bridge packet/media diagnostic
passes in default external mode too. Both new live runs retain their fixtures;
neither is real PSTN, operator MicroSIP1000 or mobile-device acceptance.

**15:30UTC native callback acceptance:** `b6e938/session58987/493a66` finished
exit0. Evidence `/var/log/kazoo-acceptance/20260907T152609Z` proves the isolated
account's registered internal1001 callback: busy agent, single6, full Gemini
confirmation before BYE, busy call released2s after proof, first return left
unanswered with valid CANCEL/487/ACK, durable retry_wait, second return confirmed
with digit1 and reciprocally bridged to the agent. Final strict SIP/RTP gate,
agent-ready and unchanged-service gates pass; scoped errors0/0, new cores0.
Fixture retained, not full cleanup or operator MicroSIP1000 acceptance. No
production Erlang modules changed in this checkpoint. The test harness fixes
native expected SIP identity and preserves both original INVITE Via headers;
see `doc/acdc_internal_extension_callbacks.md` for earlier failed diagnostics.

**French authoring update:** second32-initial-request batch added24 accepted
recordings, rejected8 incomplete results, and retried none. Current pack totals:
EN31 QA; ES25 QA/28 failed; FR38 QA/14 failed/109 pending; HE131 and AR208
pending. All48 new French master/telephony WAVs and immutable history are saved
under `scripts/assets/acdc-gemini-cardinals-20260907`. Historical requests137;
no successful clip regenerated. The fixed210-clip deployed pack is unchanged;
new French cardinal playback/listening and remaining languages are not finished.
Offline verification `ad0253/session21190/516fa8` passes manifest identities,
all accepted WAV hashes and deterministic SoX resampling, with network disabled.
Prior combined run `679ac2/c90d95` passed the helper,48 unanswered,88 retry,
96 confirmation,32 carrier-payload and13 cleanup groups plus shellcheck; its
final artifact check rejected a relative path, corrected to the required
absolute directory in the successful independent run above.

**Latest bridge transport checkpoint:** FCM sends reject3xx in a response hook
before Requests redirect preparation and close streamed responses without
reading bodies. Six real pinned-Requests/fake-adapter tests pass (`be4d36`),
prior79 bridge tests plus installer dispatch pass (`a6ee6e/73b78f`). Main-SH
deployment `515d94/1f29eb` passes and retains previous release; current release
`/usr/local/lib/kazoo-push-bridge/releases/8b6eb7b60923ba295b0ecc074c0ebf78835bbaa201360211fb87c7bb29745d23`.
Service enabled/active consumer PID111917, automatic restarts0, all eight core
services active (`82056a`). No real pushes or production changes. OAuth refresh,
whole-operation bounds, shared-session concurrency, durable recovery/retry,
broker TLS and designated-device ringing remain open. Callback/media checkpoint
committed/pushed to master194442e (`36c153`, `41c73d/4cbbd6`).

**Latest callback deployment:** four account-local callback modules are live,
not the other nine modules in the13-module candidate. `d116f0/6c6bb3` atomic
binary promotion passes installed/loaded hashes; previous code retained at
`/var/lib/kazoo-internal-callback-deployment.i8kMw1`. Two earlier by-name loads
failed new-module lookup and restored baseline; see detailed callback document.
Current account/queue/1000 read-only request probe passes `8a22d5/239d62` with
one native endpoint; it does not dial. OpenAPI contract rebuilt/tested and exact
served `/apis` bytes verified `8a4484`. Real internal ringing/retry remains open.
The separate external-route live retry regression finished exit0
`170c04/session87038/7cfb8b`, evidence
`/var/log/kazoo-acceptance/20260907T144250Z`: busy agent, single6 at about5s,
full5.491s Gemini confirmation before BYE, release busy call2s later, unanswered
first return attempt, durable retry_wait, second reciprocal agent bridge.
The scoped log/core gate reports zero errors/new cores. Fixture retained:
this is not full cleanup, internal1000 acceptance or production certification.
An asynchronous question asks the operator to leave1000 registered, ignore the
first return call and answer the second/press1; no operator response yet.

**French one-time authoring:** first20 requests produced14 accepted recordings,
six rejected incomplete results,141 initial roles still pending. No retries,
no successful WAV regenerated. Copied28 new FR WAVs and run history into repo;
offline manifest/SoX verification passes `2b68ec/342bc8`, total105 historical
requests. EN31/ES25 generated unchanged, ES4/9 reuse separate. See
`doc/acdc_cardinal_fr_authoring_20260907.md`. No new cardinal playback deployed.

**14:24UTC bridge development installation:** provider credentials retrieved
read-only from production10.1.0.28 into protected private storage. Its service
remains enabled/active PID1226; no production changes or notifications. Main SH
`push-bridge` install passed `d789ab/55d3b0`: Python3.11,18 hash-pinned packages,
non-root enabled/running service, actual AMQP consumer readiness. Independent
`--verify-only` passed `d6a984/c0c60f`. Local config uses a separate loopback
acceptance exchange/queue, not the copied production broker URL. Both APNs keys
and FCM credentials load with actual installed SDKs as service user in an
isolated network (`b5fb19`); provider access/device ringing remain untested.
See `doc/push_bridge_development_acceptance.md` for paths and remaining gates.
Never print or commit private provider files or production-unit contents.
Repeat install and selected bridge restart passed `77bcab/1adade`. Passive
broker check `b24480/025319` verifies one consumer/zero ready messages, bridge
PID53666 and automatic restarts0; all eight core/data/web services active.
Current79 bridge tests plus dispatch and13 media-adapter cases pass
`f1da0f/d65ad4`. No handles listed in this latest checkpoint remain running.

**Callback/media checkpoint:** full canonical run03917f/session92746 completed
exit0,87 tests (`d91ac3`). Focused production13-module build completed exit0
`592f91/e0e1cc`, `/tmp/kazoo-callback-media-build.qg16Ob`; the four callback
modules were subsequently deployed as described above. Remaining nine were not.
The strengthened media zero-read regression was rerun: all7 pass
`b5fb19/52a682`, source digest aeeb9f4d35ae86afe69100ca5cfa6144fd07e2c89748c41fc8950f5b948a4116.
Older pending-handle statements below are superseded. Internal caller ID1000
is configured; account-local callback transport needs live ringing acceptance.

**14:07UTC focused work checkpoint:** all three parallel workers stopped at
their product usage limit; root continued locally. No agent build/deployment ran.
Pending source now includes main-SH bridge installation, EN cardinal playback
and account-local extension callbacks; review before any deployment. Internal
callback tests pass29 (`4be707/4261f8`), five-language grammar passes73240 parity
cases (`926abd/1ea276`), announcement suite12 (`11f182/7e0065`), media resolver7
(`bde511/53304e`), installer adapter13 and bridge service15 plus dispatch checks
(`3f15e0`). New malformed-response guard and fixture fixes are included.
The media zero-read assertion was strengthened after that media run: rerun it.
Broader canonical callback run03917f/session92746 was live when this checkpoint
was written; poll that handle, do not assume completion. No new runtime BEAMs
have been promoted in this checkpoint.

Spanish pending-only authoring (`baa541/716050`) added11 successful recordings,
rejected10 incomplete results, and retained all history/22 new WAVs. Spanish25
generated,28 failed,0 initially pending; ES4/9 reuse remains separate. EN unchanged.
Device internal caller ID is now1000 (normal Crossbar PATCH/readback `da514d`),
external identity unchanged; account-local transport still needs live acceptance.
See `doc/acdc_internal_extension_callbacks.md`. Mobile provider credentials/test
device paths were requested asynchronously; no production queue was contacted.

**New important bug UI-03:** Callflows → Users gets404 from the account
`/entitlements` endpoint and displays a generic error. Full sanitized report,
request ID and acceptance requirements are in PROJECT_TASKS.md. Do not copy the
operator's session token into source or logs.

**Post-resize checkpoint September 7:** server has7488MiB usable memory,
5970MiB available at initial check, no swap; synthetic test-agent service is
active/running PID1991 after reboot. Named Kazoo apps/ecallmgr/freeswitch/kamailio
and data/web services are active. Earlier helper pause/PIDs below are historical.
Extension1000 resolves to MicroSIP user12d1a51ac7fddbbc552c693215eda876;
device b9765af7b7ce1e740263900e3fb11bb9 still has no numeric caller ID.
Internal-extension callback routing is actively being fixed; current transport
is offnet-only, and setting caller ID alone cannot resolve that limitation.

**EN cardinal staging verified:** compositor passes5 EUnit tests including14648
parity cases (`0db88b/dc3041`). Importer passes10 groups/605 checks with real SoX,
zero network/provider calls (`0ae241/2ebcc3`). Separate generated map SHA:
`290ce69c163729cf567d2353982066f0518d42045a89b4dfc2125953494c5406`.
Actual configured-CouchDB import (`de5fda/eeb8e2`) created31 immutable EN cardinal
documents, verified31 plus existing intro,74 scoped requests, no queue change.
Runtime position integration remains in progress, not playback-approved.
APNs transport fixtures pass23 tests (`943db9`); all prior41 bridge fixtures pass
again (`76b36d`). These are offline tests, not mobile push delivery acceptance.

**Latest operator scope correction:** callbacks, built-in EN/HE/FR/ES/AR
prerecorded Gemini voices, deployment-script issues **and the mobile bridge**
are critical and active. Only dashboard work is postponed. Keep all other
mandatory release requirements tracked. No install/runtime/provider synthesis.

**Bridge remains part of the deployment stack:** not a separate manual add-on.
The sanitized import is tracked in kz5. Latest bounded fix moves ACKs from worker
threads to the broker owner and never acknowledges failed/uncertain delivery;
stale generations cannot settle or submit into a successor. Root `219760/1a2178`
passes8 config+19 runtime/payload+14 settlement fixtures, no real broker/provider
or service action. First admission e5a68b refused before execution; later admitted
run passed without reducing512MiB reserve or stopping a service. The safety slice
fails closed with manual-recovery status78, **not** a complete retry/availability
policy. Keep durable retry/DLQ, bounded provider transport/deadlines, dependency
pins, protected config, main-SH option/unit enable/start/reboot and real mobile
ringing acceptance open. See `services/push-bridge/README.md`.

**Single-key callback module DEPLOYED:** `cd4e17/6fbfad` verifies
`acdc_callback_menu` on disk and the apps VM at MD5
`f2395173bdf3183659ac45fc0b7fa6c5`; old code released, no service restart or
database/provider write. Protected baseline backup/receipt:
`/tmp/kazoo-single-key-deployment.LKf1lf`. Production source is already in
master0b26789. No unrelated dashboard modules were deployed. Full canonical
rerun `142a1a/654902` passes87 tests and stable source digest
`9d8887b6e3e14d07dd7e251b56f0a228dee57192c93a14d82ca41c75385d36dd`.
Seven offline helper cases pass (`343822`), including rollback, permissions
under umask077, and failure receipts. Earlier56-pass cancellation was not a pass.

**Single-key live callback PASS:** `d26b83/0fcc7e` exited0; protected evidence
`/var/log/kazoo-acceptance/20260907T131946Z`. Only6 at4.995seconds, complete
installed5.491-second EN Gemini success audio before BYE, intentionally unanswered
first return attempt, durable retry_wait, answered second reciprocal bridge,
agent ready, unchanged core service snapshots,0new errors/cores. Fixture retained,
not full cleanup or all-language/production acceptance. See
`doc/acdc_single_key_live_acceptance_20260907.md`. Fresh immutable installed
reference `/var/log/kazoo-acceptance/gemini-reference.xERMt4/` verified without
provider/database writes. Explicit paused-MASTER-test-phone option passes27
service-scope and80 retry groups (`17a4a7/4929f3`); only the independent helper
was paused to preserve512MiB memory reserve. **Helper restored after zero
channels**: `7268a4/898117`, active/running PID1980329, all eight checked
core/web/data services active. There is no running validation job at this point.

**Provider-free exact Spanish reuse verified:** `343822/ea1b9b` passes10 groups/
134 checks with actual SoX and unchanged source/history. Retained evidence
`/tmp/acdc-cardinal-reuse-proof.sbXLgY`. Actual pack check `1cd618` resolves45
generated cardinal roles plus2 existing whole-word ES recordings,537 unresolved;
all64 historical requests/failures remain unchanged. Alias manifest and resolver
are source-only, not imported/activated. Preserve the pinned review document
`doc/acdc_cardinal_exact_word_reuse.md`; do not regenerate those successful clips.

**Development helper restored:** after zero native channels and the temporary
validation-memory pause, `93f4d5/146ae7` confirms kazoo-live-test-agents active/
running (PID1941334) and apps/ecallmgr/FreeSWITCH/Kamailio/CouchDB/RabbitMQ/
HAProxy/nginx all active. No callback candidate BEAM was deployed. The preceding
reviewed artifacts/bridge/voice-policy checkpoint b782dba74ac38161f3db76091e7445c283a63e1d
is pushed to master and independently read back (`3e2562`).

**Single-key6 source fix, not deployed:** `acdc_callback_menu:new/3` now uses
the existing authorized durable-registration action immediately after entry/
correlated pause when alternatives are disabled.17 reducer and22 wrapper tests
pass; strict entry-only/confirm-current harness80+79 checks and actual fixture
policy checks pass. All8 focused production modules compile into
`/tmp/kazoo-callback-media-build.2YgHe7`; private OpenAPI358paths/653operations
validates at `/tmp/kazoo-single-key-openapi.EDdgLJ`, not published. Combined
control+canonical run reached600s before all87 canonical cases/final hash check;
rerun canonical alone, not both suites in the same600s unit. Earlier128MiB
control test OOM was contained;192MiB completed all22 wrappers. See
`doc/acdc_single_key_callback.md` for exact evidence and explicit entry-only
live test. Prior runtime parity refers to pre-single-key source; do not claim
the new menu is already deployed or reuse6+1 evidence for6-only.

**Partial Spanish cardinal authoring, not deployed:** `b6a104/b29f10` made32
initial requests:14 technical-QA passes,18 incomplete OTHER responses rejected.
One bounded retry of number4 also failed (`95ec3f/06a97a`); its two-attempt
limit is exhausted. No blanket retry or weakening of the verifier. Offline
manifest/WAV/SoX check `386c7e/f76721` verifies EN31 unchanged and ES14 valid,
18 failed,21 pending,33 attempts, no indeterminate requests. New28 WAVs and
ledgers are preserved in `scripts/assets/acdc-gemini-cardinals-20260907/`.
See `doc/acdc_cardinal_es_authoring_20260907.md`. Existing210 voices unchanged;
Gemini remains authoring-only. This does not block unrelated callback fixes.

**Bridge source checkpoint:** root network-isolated `edf013/d8b505` passes
8 configuration and19 explicit-startup/payload/lifecycle tests, no provider,
broker or service access. Candidate source under `services/push-bridge/` is
NOT activation-ready: delivery ACK/retry, bounded work/provider responses,
transport/credentials, dependency/service/installer and mobile ringing gates
remain. See its README; do not count these27 tests as delivery acceptance.

**Fresh installed-Gemini callback retry diagnostic PASS:** `f99df0/90042a`
exits0; evidence `/var/log/kazoo-acceptance/20260907T121515Z`. Busy agent,
second caller key6 at4.985s then registration1, full5.491s success phrase before
BYE, deliberately unanswered first return attempt, durable retry_wait and
second-attempt reciprocal native bridge all pass. Agent readiness returned;
five monitored call-service PID/restart snapshots unchanged, new errors/cores0.
Fixture retained: NOT full cleanup or production acceptance. No provider or
restart. See `doc/acdc_gemini_callback_retry_acceptance_20260907.md` for timing
and limitations. Single-key6 remains a distinct implementation/acceptance gap;
the completed test must not be presented as the requested6-only UX.

**Fresh complete Gemini EN offer runner PASS:** `c88ff7/d9b680` exits0,
`/var/log/kazoo-acceptance/20260907T120840Z`. Three complete5.171s offers at
3.069/18.089/33.069s; no early offer, zero capture drops, normal46.011s teardown.
Service PID/restart comparisons, announcement-worker cleanup, fresh journal/
file error and no-new-core checks pass. Exact conditional fixture cleanup passes,
zero agents changed, unrelated documents unchanged. No restart/provider request.
See `doc/acdc_gemini_offer_acceptance_20260907.md`. Key6 confirmation/retries,
real MOH, all languages, new cardinal integration and full release remain open.

**Gemini EN offer audio verified — September7:** retained zero-drop call capture
`/var/log/kazoo-acceptance/20260907T120047Z` passes the corrected40-group-tested
checker (`6071a3/ff00b0`): complete5.171s offers at3.114/18.114/33.114s, no early
offer, normal46.012s teardown and exact conditional cleanup. No provider
request. See `doc/acdc_gemini_offer_acceptance_20260907.md` for limits, earlier
harness failures and numeric startup-gap evidence. Full live runner post-audio
service/log checks and key6/retry acceptance remain separate gates.

**One-time English cardinal authoring completed — September7:**31/31 missing
English number-composition recordings passed technical QA, exactly31 initial
Gemini requests,zero retries (`adff0f/ea936c`). Preserved existing210 callback/
intro/digit recordings. New62 WAVs (24kHz masters and8kHz telephony) and durable
request ledger are copied into `scripts/assets/acdc-gemini-cardinals-20260907/`;
the original authoring directory remains
`/usr/local/src/kazoo5-installer/acdc-cardinal-release-20260907`.
Independent network-isolated verification passes `8b19ab/ac152a`; English
asset-set SHA256 `a84e012ec30e87a5f0a8aa2036185938d8cee405af81bc8499e88416113e3245`.
Approval/text evidence: `doc/acdc-cardinal-approvals-20260907.json` and
`doc/acdc_cardinal_en_release_review.md`. These are authoring artifacts, NOT
listening-approved, runtime integrated or deployed cardinal playback. Other
locales remain pending in this separate584-role catalog. Never regenerate
these successful English identities or invoke Gemini from installer/runtime.

**Current Gemini offer acceptance harness:** root offline29 fixture groups,
36 audio groups and scenario checks pass `d2d1b6/9ff0e4`; prepare-only passes
`99e573/ef7ce0`. First live attempt `86061c/1ca5a4` stopped before fixture
creation/SIP traffic because CouchDB returned multipart attachments to a JSON
parser. Safe read-only probe `58db30/870334` confirms HTTP200 multipart/related.
Evidence directory `/var/log/kazoo-acceptance/20260907T115400Z`; no fixture receipt
was created. Fix explicit JSON content negotiation and rerun; this is a harness
failure, not a callback acceptance result. No service restart occurred.

Follow-up: explicit JSON negotiation plus body-free errors now pass32 fixture
groups,36 audio groups and scenario checks (`667209/ac6781`). Live rerun
`9e03a9/d9377b` placed/completed the isolated call, but audio acceptance correctly
rejected6 kernel capture drops. Evidence:
`/var/log/kazoo-acceptance/20260907T115817Z`. Exact conditional cleanup passed,
zero agents changed, unrelated documents unchanged. Capture buffer is now
bounded8MiB with the zero-drop rule unchanged; scenario/syntax checks pass
`fd51ed`. Await the next live result; do not treat the lossy recording as proof.

**Source-only parallel candidates awaiting root verification:** two new HE/AR
intro authoring identities are implemented separately in
`scripts/acdc-cardinal-intro-pack.cjs`,
`scripts/generate-acdc-gemini-cardinal-intros.cjs`,
`scripts/test-acdc-gemini-cardinal-intros.cjs`, documented in
`doc/acdc_cardinal_intro_authoring.md`. Root read all three source/test files;
offline verification `96b914/64a1be` passes12 groups/215 checks,12 mock requests,
zero real requests/keys, actual SoX with unchanged source hashes. Evidence:
`/tmp/acdc-cardinal-intros-proof.NWjyDb`. Those two real intro recordings are not
yet authored or approved for listening. Bridge explicit
startup/payload validation candidate is in `services/push-bridge/`, with
`scripts/test-push-bridge-runtime.py`; tests and source review remain pending.
Neither candidate is activated, committed or accepted by the voice commit.

Installer media regression rerun `623f42/c7d0bf` passed inventory/13 negative
receipt cases and create-only210 preservation checks, then its128MiB validation
unit was OOM-killed (journal `20c4f9`, unit
`kazoo-validation-fd216e15-2c90-41a0-bd25-de6b11ad968b`). Full installer suite did
not complete; do not report a pass. This was a resource-contained offline test,
not an application service crash or runtime import. Rerun with adequate admitted
memory while retaining the512MiB reserve; no provider calls are required.

**Latest operator reaffirmation — September7:** Gemini is release-authoring only,
used once for missing EN/HE/FR/ES/AR recordings; reuse finished WAVs in Git with
no Gemini at install/startup/account creation/edit/call time. The operator again
confirms this is a development system and authorizes restarting services as
needed. Preserve customer/configuration state, inspect live calls and retain
rollback evidence, but do not pause awaiting redundant restart permission.

**Current callback runtime verified — September7:** all eight focused canonical
callback media modules already match fresh production compilation AND actual
loaded module MD5s (`760395/afb084`, `7b9401/fcf084`, `0ad7ce`). Older statements
that this cohort is undeployed are superseded. Full canonical87 tests pass
`fada33/fee8c1`. See `doc/callback_media_runtime_parity.md` for hashes, retained
build, scope and next actual-call gate. Do not redeploy identical code or deploy
unrelated dashboard candidates as a presumed callback fix. Existing offer
harness prepare-only passes `8d4b3b/70b363`, but its legacy audio references need
an explicit Gemini mode before current built-in playback can be judged.

**Voice-authoring fix tested:** rejected fresh approval now leaves no stranded
empty output directory. Corrected approval can reuse that untouched path.
Root `f3037b/83a87f` passes12 groups/177 checks,11 mock requests,zero real requests
or keys, with actual SoX resampling. Evidence:
`/tmp/acdc-cardinal-generator-proof.bf2n5X`. Historical generator injected only
into a private process require cache fails the new no-output assertion
`6b22f7` (`/tmp/acdc-cardinal-generator-proof.ThBYPt`,zero mock requests).
The earlier baseline wrapper `2e43bd` failed module-cache loading before the
test and is not a product regression proof. No existing WAVs changed.

**Mobile bridge source milestone:** root reviewed sanitized provider/broker
source and configuration example; no populated credentials/endpoints were
imported. Offline configuration validator passes8 tests `71f4f8` with no
provider/broker access. Source import is not activation-ready: failure ACK,
retry/backpressure, TLS, dependency and systemd/installer work remain explicit
requirements in `services/push-bridge/README.md`. Nothing was deployed or sent
to production. All root jobs referenced here are terminal.

**OPERATOR PRIORITY CORRECTION — September7, newest instruction:** callbacks
and built-in Gemini voices are priority #1, followed by deployment/installer
issues and the mobile bridge installer. Live dashboards move to lowest priority.
Only historical dashboard work was postponed; earlier statements pausing
callbacks/voices were an agent interpretation error and are superseded.
All installer and production release gates remain mandatory. Preserve the
unaccepted dashboard sidecar design/source; do not deploy the rejected drain
candidate. Resume canonical callback/media work using the source maps below,
check current runtime/source parity before deployment, and do not regenerate
already valid audio or invoke Gemini during install/runtime. See the corrected
ordering at the top of PROJECT_TASKS.md. This is a scope correction, not evidence
that any additional code/media has been deployed or validated.

**Resumed callback verification — September7:** root media-only canonical runner
`778a35/6d4296` exited0 with22 tests across the actual helper and five-language
callback-contract suites. Production/TEST compilation and source pins passed;
input digest `5bcd7e76678f42988001ad768c391fd272401d2ec8b6d4b48eab975a73759ea8`.
Run used192MiB cap,512MiB reserve,180-second deadline and an isolated network
namespace. An initial256MiB admission (`b25114`) was refused for insufficient
available memory; no payload ran. The successful lower-cap run retained the
reserve and did not stop services. No provider request, import, runtime change
or live-call test occurred. This reconfirms media contracts, not full callback
lifecycle or audible playback. Source-only agents resumed media readiness,
native callback deployment-boundary review and bridge configuration work;
root retains serial execution/deployment ownership. Dashboard sidecar remains
unimplemented/unaccepted and is no longer the next implementation priority.

**Drain candidate REJECTED — September7; no deployment:** root run
`da512e/184d65` failed4 of12 groups, evidence
`/tmp/kazoo-stats-upgrade-drain.UlbYsh`. The classifier reported completion with
zero captured workers while real compiled `kz_process` wrappers remained paused
before metadata/local-fun invocation. Diagnostic `301ed2/872ff5` confirmed their
immutable `initial_call` is `{erlang,apply,2}`, NOT `kz_process`. The experimental
helper is therefore unsafe and has been moved OUT of `applications/acdc/src`.

Manual expected-failure reproducer:
`scripts/experiments/reproduce-stats-upgrade-drain.sh`; candidate:
`scripts/erlang-tests/candidates/acdc_stats_upgrade_drain.erl`; fixture:
`scripts/erlang-tests/acdc_stats_upgrade_drain_tests.erl`.
Relocated run `f41056/47cf55` again failed4/passed8, retained at
`/tmp/kazoo-stats-upgrade-drain.o2itUk`. Both candidate and actual production
`kz_process` were freshly compiled without TEST; no live BEAMs installed.
Do not treat the eight passing cases as worker-drain acceptance, copy this
candidate into production sources, or narrow its failing test assertions.

Read-only target-node metadata RPC `2ac240` found11 anonymous apply/2 processes,
including permanent OTP loader/application/code/error/global/RPC/logger roles
and a media retry scanner. Simply adding apply/2 to the cohort would wait forever
on unrelated infrastructure. Native ETS managers also spawn anonymous successor
finders after inheritance; those wait for a replacement while the proposed gate
requires the stats child stopped. Current stack or late dictionary filtering is
not a sound fix. All root jobs are terminal; no service/account changes occurred.

**Next investigation:** the source-only agent is comparing a retained caller-
metadata sidecar that preserves the existing18-field stats layout with native-
role attestation/targeted keeper suspension. Caller/privacy/API requirements
must remain unchanged; no alternative is accepted yet. A full native keeper
rehearsal and safe coordinated deployment are still required for any chosen
path. There is no accepted worker-drain helper. Installer readiness checkpoint
`0236c57` is pushed and independently read back (`350395/745f88`, `49fbf2`).

**Installer stats readiness — September7, source tested, NOT deployed:**
New `sup acdc_maintenance stats_ready` returns exact `ready` only for the same
current stats child with verified table admission before/after a true native
broker-consumption check. Fixed unavailable/non-consuming errors expose no
private state. `verify_kazoo_apps` now requires this read-only RPC after Erlang
application checks, before API success. Exit-nonzero, legacy/unknown output and
timeouts cannot pass; no delete/restart/repair is attempted. Installer guidance
now also removes an obsolete instruction claiming it fetches separate ACDC.

Root startup17 groups pass `8ecdb9/dff757`, evidence
`/tmp/kazoo-stats-startup.xiLcue` (13 fresh production modules, no TEST).
Installer5 source-gate groups pass `e8f999/b6a8d2`; read-only verifier regressions
pass `f77e99`. Positive readiness protocol uses controlled responses; real native
listener with unavailable mocked broker correctly returns not_consuming. This
does not establish a real broker ACK or installed/fresh-host acceptance.
All root jobs are terminal. No live deployment/service/account changes.

Drain helper review found its first source draft incorrectly assumed registered
ETS manager names. Native `WORKER_NAME_ARGS` sets supervisor child IDs only and
uses unregistered `kazoo_etsmgr_srv:start_link/1`. The agent is correcting it to
the actual child mapping and updating fixtures before root executes it. Treat
the untracked helper/fixture/runner as unaccepted until the next explicit proof.
The previously published checkpoint `457f551` is independently verified on
remote master (`c7a375/d4af49`, readback `c2ae9f`).

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
