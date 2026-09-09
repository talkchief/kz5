# Kazoo 5 project task register

## Immediate operator follow-up — September8

- **VOICE-01 reseller language fallback — SOURCE PASS, deployment pending (September9):**
  Native `kz_media_util:prompt_language/2` omitted reseller defaults entirely.
  Root-owned installer patch now uses account media.default_language, account
  language, direct reseller media.default_language, reseller language, then the
  existing caller/system fallback. Explicit settings avoid reseller reads;
  disabled overrides retain system behavior. Missing/self/unavailable reseller
  paths cannot recurse or crash this optional fallback. Baseline f6b473:4 failures
  among14 cases. Final f9bb3f:16/16 pass plus exact clean-source/double-patch replay.
  No database migration, regeneration or runtime Gemini dependency. OpenAPI source
  updated. `scripts/test-media-language-live.cjs` prepares two empty, disabled
  main-dev-only tenants, then verifies all five inherited locales and15 shared
  prompt resolutions after deployment; not yet run. See
  `doc/media_reseller_language.md`. The fixture is scoped; native calls/audio
  pronunciation and broader release gates remain separate.

- **VOICE-01 inherited queue edit — DEPLOYED / scoped PASS (September9):**
  An existing queue without a language override, or with an unsupported legacy
  locale, was displayed and silently saved as English when the English pack
  was ready. Baseline d5c05d reproduces this; source contract6f74ba passes after
  preserving the original setting until an explicit language choice. Exactly
  five options remain; a legacy/inherited edit starts with no selected option
  and an explanatory notice, while new queues retain English. Existing supported
  same-language built-in adoption is unchanged. Focused Chromium070f42 passes
  four actual dropdown/change/submit cases with a controlled readiness catalog,
  zero network requests and zero account writes. It caught the legacy jQuery
  null-selection behavior, corrected with explicit selectedIndex=-1. Source
  c009191 deployed through the normal Monster CLI5e3115, exit0 in80.184s.
  HTTPS67b094 matches installed JS/templates/translations and validates the
  compiled selection behavior; nginx/apps/eCallMgr active. No provider calls,
  media regeneration or account/reseller default changes. See
  `doc/queue_language_inherited_edit.md`. Native reseller default resolution is
  still a separate open gap, not addressed by this UI fix. Both browser and
  installer jobs are terminal; do not rerun them without a relevant change.

- **INSTALL-MODULE-SCOPE-01 DEPLOYED / scoped PASS:** native Crossbar
  start/stop read node/zone autoload overrides but overwrote cluster default,
  leaving their own startup list unchanged. Root-owned patch now persists to
  the setting's actual node/zone/default owner and preserves other scopes.
  Baseline f53f5a fails6/9; final039b20 passes9/9 plus clean-source/double-patch
  byte replay. No live overrides changed for testing. Applies to the normal
  installer and SUP module commands, not only storage. Source4fe0dbd synced;
  first unit `kz5-module-scope-install-main44-20260908` is terminal exit1
  (33463a): internal-function invocation omitted preflight, so catalog receiver
  rejected empty naming mode after compilation but before restart. Recovery
  48eee6 regenerated both service units with correct -sname; both remain active.
  New unit-writer guard refuses uninitialized mode before mutations (four
  baseline failures838c7f; all4 unit-runtime tests pass3e7c8c). Supported CLI
  unit `kz5-module-scope-install-main44-20260908b` completed successfully
  (71998/2796d8,11m41.477s,380.5MiB). Runtime/disk module MD5 matches
  adbc0d5a568c471e965e66578e6ca2c1. Final41039e confirms patch applied,
  apps/eCallMgr active/enabled, zero calls and all selected CLI validations
  passed. Both jobs are terminal; reuse this evidence rather than rerunning.
  Concurrent writers and real custom-scope split-host reboot are not proven.
  See `doc/crossbar_module_autoload_scope.md`.

- **UI-01 native storage API installer gap — DEPLOYED / scoped PASS:**
  Main readback f0eb1c confirms `cb_storage` absent from both effective autoload
  and running bindings. The normal API setup now registers it, verifies exact
  membership and preservation of existing modules, and leaves account/provider
  plans untouched. Verify-only checks membership without repair; authenticated
  verification uses `/storage/plans`, not a fabricated account plan. Baseline
  ad354e fails the missing installer wiring; candidate0e35e6 passes14 storage
  registration checks and8 adjacent entitlement checks. Source10455c5 pushed
  and synced; scoped installer132512 exits0 in5.854s. HTTPS6c006e confirms
  authenticated plan collection200/empty, anonymous401 and genuine missing
  account plan404. Browser7e1624 confirms that404 settles the selector, shows
  unavailable and leaves no active indicator, with zero account writes.
  No telephony restart or plan/provider provisioning. FullALL was not rerun;
  this is scoped module/API/browser proof, not every external-storage workflow.

- **P0-CALLBACK-CONFIRM-01 DEPLOYED — returned prompt cut off by valid
  short timeout:** confirmation_timeout3 began before the4.331s English
  instruction completed. Actual worker regression77012/66fe74 fails before;
  final14542/a37868 passes all7 caller tests. A separate30s playback watchdog
  now precedes the configured response window, bound to exact call/noop;
  early digit1 works and duplicate/stale events cannot extend or resurrect it.
  Normal apps installer68345/50b9bf exits0; runtime production BEAM matches
  disk16532/e149bd, `/apis` published/readback verified. The explicitly armed
  native3-second case21843/e6c70b reached unanswered/retry/reciprocal bridge,
  then failed the separate strict RTP-continuity assertion. Timeout restored
  and zero calls; do not label the whole case PASS or rerun blindly. Offline
  replay44e6d4 confirms the complete4.331s recording and digit1 received1.045s
  after completion, with a successful retry bridge and no sequence loss.
  The separate20ms in-prompt timestamp gap remains CALLBACK-RTP-01; native
  negative response-expiry coverage remains unverified. Ordinary15-second retry
  fixtures cannot prove this case. See `doc/callback_confirmation_deadline.md`.

- **VOICE-01 locale spelling UI DEPLOYED:** existing `HE_IL`/`HE-IL`
  queues were selected and adopted as English despite backend Hebrew playback.
  Baseline a9f2bc reproduces it. The dropdown now canonicalizes supported
  spellings; fifteen variant cases preserve the same language on Save, and
  unready packs remain disabled with their original values preserved. Full UI
  contract4ac811 passes. Normal Monster installer21645/6f16cc exits0 in79.083s;
  served bundled AMD checkef38b2 passes all15 variants and unready preservation
  with zero account writes. Source d4eb7ad is on master and main.
  See `doc/queue_language_spelling_fix.md`. Broader inheritance remains
  open; do not equate spelling normalization with changing account defaults.

- **VOICE-01 resumed announcement language DEPLOYED:** a resumed worker
  reapplied current FR queue settings to a serialized EN admission, unlike the
  callback's retained EN language. Baseline1483/ff1843 reproduces the mismatch.
  Queue admission now stores its effective language in existing serialized call
  KVS; resumed workers honor it, next-queue admission replaces it, and legacy
  calls retain fallback behavior. All12 language tests44618/5b971e pass,
  including all five locales and inherited HE_IL normalization. No new audio
  or account defaults. Source18eef3e pushed/synced; normal kazoo-apps deployment
  `kz5-announcement-language-install-main44-20260908` completed successfully
  (35217/1d8bcf, exit0,11m44.063s,383.1MiB peak). Both changed modules match
  running/disk BEAMs86091/c2092a. Apps/eCallMgr active and zero calls7ece16.
  Matching static `/apis` publication completed successfully on main at
  22:25:26 UTC; HTTPS readback confirms the admitted-language contract.
  See
  `doc/acdc_callback_language_snapshot.md`.

- **VOICE-01 callback language snapshot DEPLOYED:** queue edits could
  overwrite the admitted caller language at registration and returned-call
  confirmation. Actual-source regression reproduces EN switching to FR. The
  fix preserves/canonicalizes admitted metadata, restores persisted language
  per attempt and keeps confirmation on that locale. All10 language and6 caller
  tests pass; source OpenAPI regenerated. No new audio generation or schema
  fields. Normal apps/eCallMgr installer84142/09ff6a exits0 in12m6.872s on main;
  all three changed modules match running/disk BEAMs4250/ce4046. Updated `/apis`
  deployed and HTTPS-readback verified. Main native queue-edit case retains EN
  through an FR edit, unanswered first attempt and connected retry; complete
  ordered EN response verified13098/a4b1e3. Strict audio timing fails on a20ms
  in-prompt RTP timestamp advance despite no packet sequence loss; track
  CALLBACK-RTP-01 below, not another blind rerun. Queue restored, zero calls.
  Account/reseller inheritance and actual worker-failure lifecycle acceptance
  remain separate. The resumed-worker source correction is deployed above. See
  `doc/acdc_callback_language_snapshot.md`.

- **CALLBACK-RTP-01 OPEN — focused media timing diagnosis:** retained main run
  `/var/log/kazoo-acceptance/20260908T220213Z` has continuous received packet
  sequence and a complete English prompt, but one20ms timestamp gap within the
  prompt (plus80ms before speech). No tcpdump kernel drops. Native retry and
  language retention work; uninterrupted-playout/strict timing is not accepted.
  Inspect the media playback timestamp path using this capture before any new
  live run. Do not weaken the strict checker or regenerate voices to hide it.
  Pinned-source diagnostic d0c54a now reproduces the exact extra20ms/marker
  through the default timerfd path consuming two expirations, without changing
  audio. This is not captured runtime-branch proof; no global timer/RTP change
  is justified. Any further native investigation must trace that transition,
  not repeat an uninstrumented callback to hunt for a PASS.
  See `doc/acdc_callback_language_snapshot.md` for exact receipts and limits.

- **UI-01 focused source fix DEPLOYED / browser PASS:** Common's storage selector
  never completed its callback on404/other failures and could crash on empty
  successful data. Installer-owned patchf85bb21 fixes both, retains real
  non404 errors and configured-attachment selection. Original fails4/7 focused
  groups; patched passes7/7, including installer-prepared main source. Normal
  Monster deployment22488/383cf4 exits0; native404 browser33704/37350c confirms
  visible unavailable warning, settled callback, inactive bar and zero writes.
  No storage document/module was created and backend404 is not hidden.
  See `doc/monster_optional_storage.md`; current ACDC Save does not call storage.

- **FOCUS: reported bugs and deployment gaps only.** Do not expand into
  unrelated tests or dashboard work. Reuse retained passing evidence; run only
  reproduction and regression checks tied to a named open defect. Keep
  callbacks, installed prerecorded voices and mandatory installer/bridge gaps
  in scope; historical dashboards remain postponed.

- **P0-22 selected-queue Login and failed-read recovery PASS on main:** actual
  Login confirms runtime membership; one deliberately failed verification GET
  shows unavailable and Check again recovers without a second Login POST.
  Selected agent logs out afterward; other29 statuses and memberships remain
  unchanged. Source4b4fcf3, unit72753/569476 exits0 in20.561s. Evidence and
  limits: `doc/queue_login_browser_acceptance.md`. Explicit Logout's stale
  cache is now reproduced in an actual-source event test and fixed in f820d18;
  all27 focused groups pass. Normal Monster installer87070/c84568 exits0;
  deployed browser77891/5350d1 passes immediate post-Logout label invalidation
  as well as Login/recovery, with the other29 agents unchanged. Scope closed;
  restricted principals/arbitrary network reordering are separate release gates.

- **P0-26 / EDITOR-MAIN44-LANGUAGE-01 ACTUAL BROWSER SAVE PASS:** real create,
  EN/HE/AR/FR/ES saves, fresh readbacks and final reopened form succeed on main.
  Generic17/callback30 intervals persist; final sixth Save disables callbacks.
  No injected requests/responses, exact editor body guard, no captured browser
  errors and inactive blue bar. Unit97969/d810a2 exits0 in20.619s, source6ebb5fd.
  One test queue51765a97f9c6dcdffbab1d80cd5d0ef8 is retained in the isolated fixture,
  empty roster/no extension/callbacks disabled; copied Talkchief untouched.
  Evidence and replay: `doc/queue_browser_save_acceptance.md`.
  Restricted principals, inherited defaults and uncertain-save recovery remain
  separate gaps; this is not a whole-platform release sign-off.

- **P0-26 / UI-01 focused current-form check PASS:** actual Add queue click on
  kz5-dev renders the create form, accepts the named draft with default HTML
  validation, offers exactly EN/HE/AR/FR/ES, makes zero `/storage` requests,
  captures no page/HTTP/insecure-request errors and leaves the blue indicator
  inactive. Cancel completes; all mutations were blocked. Unit
  `kz5-queue-create-form-main44-20260908`, sourcef9b5bf7,64600/e4b274 exits0
  in10.969s. This does NOT prove browser Save or close every storage workflow.
  Current ACDC source does not call `storage.get`; separate Monster optional
  storage consumers exist in SmartPBX recording, fax/voicemail and Common.
  `cb_storage` is absent from main's running/effective modules; its native GET
  also returns404 for a genuinely absent account plan, so registration alone
  would not establish a fix. No module/plan/config was changed for this check.
  Do not fabricate a storage document or success response to hide the error.
  Replay: `bash scripts/run-dev44-company-browser.sh --queue-create-form`.
  Actual browser Save subsequently passed in the focused sequence above.

- **UI-03 FIXED / MAIN BROWSER PASS:** Callflows → Users entitlement404 was
  missing Crossbar registration. Registration also exposed master ancestry
  `tl([])` HTTP500; both are fixed in installer-owned source. Real master/company
  entitlement responses succeed; anonymous remains401. Actual Users clicks
  pass on main with1/15 visible users, no captured browser errors and inactive
  blue bar (51327/211278, sourceb2d014c,17.682s). No service restart or user edits.
  Full source, retained backup and focused replay commands:
  `doc/callflows_users_entitlements_fix.md`.

- **DEV44-BROWSER-TOOLS-01 INSTALLED / USED ON MAIN:** retain reproducible acceptance tooling on
  the replacement main host, not the original server's temporary directories.
  New optional Rocky9/x64 setup locks private Node22.23.2/Playwright1.62.1 and
  its headless browser, disables npm lifecycle scripts, leaves global Node and
  Kazoo services unchanged, smoke-tests before activation, and provides a
  tracked local company-browser launcher. Bash syntax, ShellCheck and JS syntax
  pass; native setup91666/b39938 exits0 and the focused Users browser test now
  runs entirely on main. Initial npm setup failed before activation because
  npm rejects the same empty config path for user/global; corrected to separate
  protected empty files in7db656f. Prior stage retained, system Node unchanged.
  Guidance:
  `doc/main44_browser_tools.md`. Focused actual browser Save now passes above.

- **EDITOR-MAIN44-LANGUAGE-01 NATIVE MASTER-ADMIN API PASS:** port the armed
  unified-editor acceptance to the main host's protected fixture and locally
  assigned CouchDB address. New wrapper requires explicit account, virgin
  internal extension, run directory and write arming; clears inherited target
  overrides and holds the shared acceptance lock. `run-languages` adds all-five
  language PATCH/replay/fresh-GET checks with generic interval17 and callback30,
  no agent writes, exact raw-revision ownership and conditional cleanup.
  Three new cases fail against the prior harnessa231fd; all13 pass1d9f70 and
  with another synthetic account5e8498. Real private flock/CLI refusal tests
  pass010d6c. Incorrect readback or ambiguous reply retains evidence, never
  resends or deletes blindly. Native58571/fb64fd completed all26 API/language
  checks and cleanup, but its outer generic log gate failed on INFO401/409/404
  negative-test envelopes; failed run retained. The second native run7180 also
  completed the API sequence but rejected journald's different coloured format.
  Corrected exact-ID file / unique timestamp-module-status-reason journal
  correlation passes20 tests51747c. Final unit51137/e145bc exits0 in24.676s:
  all26 checks, eight complete intents, all-five save/replay/reload, separate
  intervals, exact cleanup, unchanged source/services and no unexpected errors
  or new cores. Both log streams match exactly five intended negative responses.
  Independentabfdf1 confirms0 calls and all nine enabled/active services.
  Final evidence `/var/log/kazoo-acceptance/queue-editor-main44-journal.S257Izfx/`.
  Not browser-save, restricted-token, inherited-language or all-feature proof.
  No production logging was weakened. Earlier failed evidence:
  `/var/log/kazoo-acceptance/queue-editor-main44.GUsWUsus/`.
  See `doc/queue_editor_acceptance.md`; this is acceptance tooling, not a new
  production editor behavior claim.

- **VOICE-MAIN44-SCHEDULE-01 FIVE-LANGUAGE NATIVE PASS:** the periodic
  callback-offer/full-position-one harness now supports explicit protected
  fixture selection, absent manual-phone helper, non-truncating shared lock,
  caller-contact absence and live resource ownership gates. It accepts only
  local assigned CouchDB addresses. `prepare-installed` reconstructs references
  from the current capability ownership marker and exact retained runtime proof,
  rejecting changed media/BEAM/input hashes; no provider or new runtime proof.
  Original new-account refusal reproducedeb643e; actual entry/service wiring
  tests1596ad,metadata trust-chain tests and existing33ownership/52audio/10reference
  cases pass8c37ce. Native main-host30/60s callback offers and45/75s full
  position-one audio now pass in all five locales: English48661/2cb3e8 and
  remaining-locale45450/07eef3 exit0. No entry/extra speech, complete received
  audio, normal teardown, unchanged services,0 errors/cores and conditional
  owned queue/callflow cleanup pass. Independent4f7417 confirms0 calls, terminal
  batchPID0 and all nine enabled/active services; all30 agents remain logged
  out7c439e. Browser0b7f2c checks exactly five selectable language choices and
  separate interval controls without saves. Not native pronunciation/wider
  number/wait/MOH/all-response or inheritance acceptance. See
  `doc/main44_periodic_audio_acceptance_20260908.md`.
  Actual installed-reference CLI subsequently passes10b220; all-five index
  `/root/kazoo-prerecorded-reference.main44-cli.crP0f4Ny/index.json`, SHA256
  `62ba5a55668dd60a52a8f3470ffa2dc09fe314ac4e7a138228e66877172d887b`.
  No provider call, new runtime probe, DB write or live call during preparation.
  Preparation is terminal, not running. Earlier empty-dir invocation failed
  safely; protected evidence retained, not counted as a pass.

- **CALLBACK-MAIN44-01 SOURCE FIX / FIVE-LANGUAGE RETRY PASS:** the retained retry
  harness, explicit-language setup and internal endpoint preflight previously pinned
  the old development tenant `7807ad61761269a1ccec833dde63f621` in
  `scripts/test-acdc-callback-retry.sh`, `scripts/test-acdc-callback-fixture.sh`
  and `scripts/test-fixtures/callback-internal-scenarios.cjs`. New explicit
  `--fixture-account` binds protected state, live account/resource ownership,
  saved restoration identity and final evidence. Old/new fixtures, refusals,
  preserved locks,25 SUP preflight and38 absent/paused-helper tests pass.
  Main-host EN retry/audio passes20300/8ddb7e: single key6,complete confirmation,
  unanswered first attempt,durable retry,second bridge,clean logs and0 calls.
  HE/FR/ES/AR sequential batch54480 is terminal success/inactive/PID0 (449b40).
  Independent receipts1c8f56/ba1160 confirm each locale, key6, two attempts,
  durable retry,2/0 caller and2/0 agent counts,0/0 log errors and0 new cores.
  Zero calls118998; all30 fixture agents logged outba1160 with no repair writes.
  Fixture resources intentionally retained: not full deletion or production/HA
  acceptance. The periodic offer/position harness has a separate native gate. Details:
  `doc/main44_callback_acceptance_20260908.md`.
  Preserve prior five-language proof as old-host evidence, not a main-host pass.
  This is test portability, not evidence that the deployed callback API fails.

- **SEC-LAUNCHER-01 SOURCE FIX / MAIN SYNCED AND TESTED:** legacy
  `scripts/dev/kazoo.sh` printed the Erlang cookie. Removed only that output;
  runtime child still receives its configured cookie/node/command. Actual
  wrapper regression fails before675873 and passes after124f23 using an isolated
  executable and synthetic cookie. No real secret or service is involved.
  Main systemd services use `scripts/dev-start-apps.sh`, not this legacy wrapper.
  Synced with ec2ec69; actual isolated wrapper regression passes on main57cdbf.

- **CB-CONTENT-01 DEPLOYED / UI AND LOG PASS:** explicit default JSON callbacks
  for apps-store collection/item, voicemail collection/item and directory
  collection; optional absent apps-store overrides preserve inherited permissions
  without error logging or GET-time writes. Real datastore errors still log and
  existing blacklists still apply. Production-compiled regression: six failures
  before (`0946ad`), all nine cases pass after (`63cef2`), including PDF/audio
  representations. Installer fresh/repeat/reverse/conflict byte replay passes
  `7a0528`. Tracked `crossbar-optional-content-defaults.patch` is applied by the
  normal installer; no separate Crossbar commit. Normal main apps/eCallMgr
  deployment failed before restart in `build-dev-release`: named builder node
  requires missing HOME. That unit is terminal. Source38cbb03 removes unnecessary
  distribution; real relx/no-HOME regression passes483f67. Retry98460 assembled
  the full release, then failed before restart in SUP completion with the same
  named-node dependency. It is terminal. The completion generator is now fixed
  via installer patch; actual no-HOME make target plus pinned patch replay pass
  70253/f26aa0. Third normal installer74822 passes09fb22/2cde08, including full
  release, SUP completion, activation and selected-role verification. Native
  callback exports pass83083/dabfb9; HTTPS browser passes76601/52c6e4. A mixed
  log window counted the simultaneous verifier's intentional informational401;
  a separate isolated browser/log repeat passed below. ALL44779 failed retained16:50 Kamailio errors
  from the fixed negative SIP fixture. With0 calls, dev Kamailio restarted;
  read-only ALL retry64780 passesfe58e6. Isolated UI79330 passes e6baef with0
  file/journal matchesb50240. All installers terminal. Combined30+5 capacity
  with browser activity subsequently passes76609/e61e37, without overlapping
  unauthenticated installer probes. Broader release gates remain. Details:
  `doc/crossbar_content_defaults_acceptance_20260908.md`.

- **LOAD-01 BOUNDED30+5 PASS:** source8a5329b run
  `kz5-capacity-contentfix-20260908` is terminal exit0, observer76609/e61e37.
  Independent summary6fe435 confirms35/0 caller and35/0 agent counts,180s hold,
  bidirectional RTP at all30 agents,zero file/journal errors and new cores.
  Browser20147/40da16 passes during calls. Peak sampled CPU28%, minimum available
  memory20693076KiB; zero calls after cleanup and unit inactive/MainPID0.
  No capacity job remains. This is not CPS, long-soak or HA certification.
  Previous terminal10423 run:30+5 calls completed with35/0
  caller and35/0 agent successes/failures,180s concurrent hold, RTP and ready
  checks passed. Final gate failed on eight application error lines during
  overlapping browser acceptance. Seven are missing Crossbar content-type
  callback arities; one is missing apps-store doc handling for the imported
  company. Those source fixes are now deployed and browser/log validated;
  do not hide the errors or retroactively mark the old run passed. Old unit
  was inactive/PID0, with zero calls and all nine services enabled/active.
  See `doc/main44_call_acceptance_20260908.md`.

- **DEV-HTTPS-PATH-01 OPEN:** source-host public-IP HTTPS probe to46.225.31.248
  times out, including explicit no-proxy curl; private HTTPS browser works.
  Prior destination capture saw no incoming SYN. Check route/provider filtering
  or intentional source restrictions; do not infer universal public outage or
  change firewall policy without establishing the intended exposure.

- **HANDOFF CALLBACK EVIDENCE PRESERVED:** five original language runs are now
  archived root-only on .44; matching SHA/readback a8b60d and paths recorded in
  `doc/focused_acceptance_20260908.md`. P0-10/VOICE-05/INST-13 rows reconciled
  with later live evidence, retaining the narrower untested gates explicitly.

- **CALL-MAIN44-01 FUNCTIONAL PASS:** `.44` actual functional
  SIP/RTP run `91284/2464e2` passes queue wait, answer/bridge, RTP, hangup/ready
  and clean logs/core gate. Source fixes `5167a32` and `ae87595` are pushed and
  synced: exact pinned SIPp tag, all-fixture logout isolation, explicit negative
  REGISTER outcome without spurious BYE. Offline real-SIPp rejection cases pass.
  Zero calls after cleanup. Current capacity status is the first LOAD-01 entry;
  older observer handles are historical, not running jobs. Protected paths and
  failed runs remain in `doc/main44_call_acceptance_20260908.md`.

- **DEV-SOURCE-01 / UI-PROGRESS-01 REVERIFIED:** main dev `/opt/kz5` and GitHub
  master match `557505a` before this documentation checkpoint (`383cbf`). Actual
  HTTPS browser `94388/725a1f` passes Talkchief selection, SmartPBX/ACDC and
  inactive top blue line with no captured insecure requests or page errors.
  Before/after source regression `76e569` passes, including installer wiring.
  All nine main services active; ACDC remains ordinary kz5 source. See the
  latest section of `PROJECT_HANDOFF.md` for evidence and separate unfinished
  SIPp/call-validation work; this does not close the load gate.

- **BRIDGE-REMOTE-03 IN-FLIGHT FAIL-STOP CONTAINMENT PASS:**42712/afe573 uses
  native consumer/settlements and a real loopback HTTP acceptance with response
  held. Only the verified child's AMQP connection is closed. Exit 78 in3.532s,
  one POST, unchanged broker body redelivered/count1; no automatic replay.
  Source pins stable; only synthetic body/resources cleaned after readback.
  Six scope/HTTP tests pass68f213. Receipt/CA copied to `.44`, SHA independently
  matchedd6edd0. Main services untouched and active; test broker stopped.
  This is a standalone child with synthetic provider adapter, not actual
  FCM/APNs or installed systemd restart-policy proof. Manual uncertain-send
  recovery, loss after receiving an HTTP result, and HA/duplicate coordination
  remain open. Full scope in the remote TLS acceptance report.
- **BRIDGE-REMOTE-02 IDLE BROKER OUTAGE / SAME-PROCESS RECOVERY PASS:** actual
  installed bridge `53408/858b7f` survives stop/start of only the isolated `.44`
  broker. Bridge PID 2437369 stays constant, disconnected status persists at
  least five seconds, then TLS 1.3/one consumer passes six stability samples.
  Normal SH restores original config/provider bytes and active local consumer.
  No messages were published: provider-in-flight loss, duplicates, queued work
  and node failover remain open. Eighteen regression tests pass `e08181`.
  Protected receipt and SHA independently copied/verified on `.44` (`41de81`),
  test broker stopped, all nine main services active (`b419b5`). Main broker
  PID 2355/restarts 0 unchanged. Controlled test instructions and expected
  socket-close warning analysis are in the remote TLS acceptance report.
- **DEV-SOURCE-01 MAIN-HOST SOURCE RETENTION:** canonical development checkout
  is `/opt/kz5` on10.1.0.44 (`kz5-dev.talkchief.io`), branch master. Independent
  authenticated Git fetch/fast-forward to `1f30654` passed; follow-up commits
  are synced there as well. Loading-bar, HTTPS and dialog fixes are tracked
  with installer wiring, and ACDC remains part of kz5. See `PROJECT_HANDOFF.md`
  and `doc/dev44_git_handoff.md` before deleting the old server.
  Fresh browser21399/fcaa6a passes the company selector, exact15/82/4/89
  collection counts, both apps, and inactive top loading bar with no insecure
  requests/page errors. Actual-source lifecycle regression170acf passes.
  All nine main services remain enabled/active (c307a2).
- **BRIDGE-REMOTE-01 NORMAL REMOTE INSTALL / RESTORATION PASS:**65096/3e586e
  installed through the normal main SH against the isolated remote broker;
  actual service PID/socket correlated with TLS1.3 and exactly one consumer.
  Normal SH restored original config/provider bytes and active local consumer.
  No push publishes or provider requests. CRB setup is now idempotent; both
  installs preserve rocky.repo mtime. CRB, main installer and bridge rollback
  regression suites pass35756/edd5be. Protected passing/previous failed receipts
  are on .44 under `/root/kz5-acceptance/bridge-service-remote/`. The previous
  timeout/orphan correction is retained, not hidden. Temporary broker stopped;
  main RabbitMQ PID2355/restarts0 and all nine services unchanged. Idle outage
  recovery now passes BRIDGE-REMOTE-02; in-flight duplicate-dispatch recovery
  remains open; details in `PROJECT_HANDOFF.md`.
  Main .44 normal bridge redeployment at `2b2043c` also passes14352/30a1d9,
  with current source/dependencies, registered service and unchanged CRB mtime.
- **BRIDGE-REMOTE-01 NATIVE REMOTE TLS/CONSUMER PASS:** actual .26 client to
  isolated native .44 RabbitMQ6035/ef7ad0 passes TLS1.3, certificate negative
  cases, authenticated HTTPS exact-broker checks, registered consumer,503→200
  retry/companion progress and three-attempt exhaustion/DLQ readback. No provider
  constructors/requests, production routing or main broker changes. Source
  pins stable; passing run's empty UUID resources removed. Temporary broker
  stoppedab490b; main RabbitPID2355/restarts0 and all nine services unchanged.
  Receipts preserved on .44 under `/root/kz5-acceptance/bridge-remote-tls/`.
  Normal installed-service remote topology now passes65096; idle reconnect
  passes BRIDGE-REMOTE-02, while in-flight recovery remains open;
  this runtime acceptance does not close all INST-13 gates. Details and failed
  setup/identity/cleanup attempts: `doc/push_bridge_remote_tls_acceptance_20260908.md`.
- **REL-GATES-01 CURRENT VERIFIER PASS / TRACKER RECONCILED:** independent
  .44 normal `--verify-only ALL`66591/18787a passed in1m40.208s, peak293.1MiB,
  without deploying/restarting services. Datastore/broker, apps/SUP/auth/APIs,
  prerecorded media, native eCallMgr/FreeSWITCH inventory/link, Kamailio,
  HTTPS/catalog and bridge consumer checks pass. This is current readiness,
  not a fresh install, live supervision/callback conversation, distributed
  topology or sustained-load test. Installer status rows below now distinguish
  completed fresh/repeat/reboot publication from remaining rolling-upgrade,
  remote-broker and recovery work. Physical mobile delivery remains user-waived.
  See `doc/release_gate_reconciliation_20260908.md` for the outstanding matrix.
- **UI-PROGRESS-01 FIXED / DEPLOYED / BROWSER PASS:** the thin blue global loading line remained active
  in SmartPBX and ACDC even after their content loads. Actual browser77543 and
  28271 reproduce `core.request.counter=-1` and `.progress-indicator.active`.
  Earlier spinner acceptance inspected in-app loading elements only and did
  not cover this global indicator. Source patch prevents counter underflow,
  rejects negative counts as active work, and clears the pending start timer
  when requests drain. Actual-handler regression reproduces the old failure;
  fixed lifecycle tests pass303420. Source/installer fix `2a593ee` is pushed.
  All12 wiring and11 preservation groups pass15196/f35d93. Normal UI installer
  on .44 passes81343/73a371 (86s,849MiB peak). Postdeployment browser20021/2b3a50
  verifies counter0, inactive top indicator, no underflows, no in-app loaders
  and no HTTP/page errors in both SmartPBX and ACDC after15 seconds per app.
  Correct/incorrect login recovery, HTTPS/WSS, `/apis/`, ACDC live200 and dialog
  close also pass. All nine main services active; no telephone/DB restart.
- **DEV-COMPANY-01 VISIBLE / INSPECTION BROWSER PASS:** operator expects Talkchief
  in the main `kz5-dev` account selector. It is now available as **Talkchief
  (Development copy)** under KazooMaster; account ID remains the supplied company
  ID. Calling and copied user/device logins are intentionally disabled pending
  separate development-phone setup and review of external callflow behavior.
  Original snapshots and lab baseline remain unchanged; no production services
  or copied production outbound/push/webhook behavior were activated.
  `prepare-dev-company-copy.py` now implements a fixed-host/account two-phase
  copy: GET-only preparation in the existing lab, explicit application on .44's
  main datastore, exact-plan ownership, no overwrite, protected receipts and
  per-document readback. Account is initially disabled for calling; SIP/user
  credentials replaced, device push/provisioning removed, realm changed to
  `talkchief-dev44.invalid`, parent set to development master. Source baseline
  remains untouched. Eleven offline transformation/scope/recovery tests pass
  a72ee4. Actual preparation98211/866b95 and copy20867/d08bff pass:1,757 documents
  verified,56 excluded designs/runtime/catalog records; native scoped account
  refresh45388 passes. Whole lab source hash unchangedd54b2d. Browser81140/36603d
  selects the visible account and loads both apps/four queue cards without errors
  or top-line animation. Reusable tracked browser test90232/e44a28 additionally
  verifies exact API counts:15 users,82 devices,4 queues,89 callflows. This is
  inspection acceptance, not live-call or shared writable CouchDB approval.
  Full guidance: `doc/dev44_company_visible_copy_20260908.md`.
- **HOST-HANDOFF-01 SOURCE CHECKPOINT PRESERVED:** original development server will be deleted.
  Canonical checkout and installed stack must remain on10.1.0.44 at `/opt/kz5`,
  latest pushed master. Preserve outstanding source work and durable guidance on
  that host; do not leave required changes solely in original-host `/tmp` files.
  `8decc5f` is pushed and synced with clean tracked status on .44; ACDC has no
  nested Git metadata. Paused diagnostic source/tests are committed, not left
  as an original-host-only diff. Unrelated untracked team design was copied,
  without committing it, to .44
  `/root/kz5-handoff/preserved-untracked/dashboard_caller_sidecar_design.md`;
  SHA256 matches `ec0170466fd1f0235112f91eb0c03487594c8e4fb3769fb4023ffd35fb46bfe4`.
  Main runtime secrets, TLS files and company snapshots already reside on .44.
  `/root/key.key` remains absent there. This gap is now resolved without copying
  that mixed file: only the GitHub credential was provisioned over protected
  stdin as `/root/.config/kz5/github.token` (root0600), consumed by the tracked
  exact-repository Git helper `0bdb1c8`. Eleven regression groups pass08f6db;
  actual .44 authenticated push dry-run6aa3fc passes. The helper and repo-local
  configuration no longer depend on the original host. See
  `doc/dev44_git_handoff.md`; no other secrets were copied by this Git handover.
- Compatibility refresh-write diagnostic has now run in the lab only,
  8037/36fadb: static refresh removes the generated number-service view, native
  updater restores exactly equal final content with a new revision, and aggregate
  account content stays equal while its revision advances. Offline workflow,
  return-shape and namespace tests pass94834/382d12. View restoration verified;
  no main/production writes by this diagnostic. See COMPAT-01 findings.

## Primary development host — September8 operator decision

- `10.1.0.44` is now the main Kazoo5 development server. Retain the stack and
  Git checkout at `/opt/kz5`; use canonical kz5 `master`, including tracked ACDC.
- Normal ALL48019/6236b8 and post-reboot ALL76710/8722b4 passed. The checkout
  was fast-forwarded to latest pushed `b393f62` with clean tracked state before
  reboot; subsequent documentation checkpoints are synced after publishing.
  Do not erase installed data or copy secrets into Git.
- Existing public hostname/DNS/TLS remains on the original host; migration of
  that public endpoint is a separate decision, not implied by retaining .44.

### New development hostname HTTPS — September8 continuation

- Operator approved `kz5-dev.talkchief.io` for .44 after reporting that HTTPS
  by public IP failed. Existing DNS resolves to `46.225.31.248`; the supplied
  wildcard certificate covers the hostname, not the IP literal. No DNS changes.
- Initial inspection confirmed .44 had only port80. Prior HTTPS acceptance
  concerned the original `kz5.talkchief.io`, not this new host. The earlier
  wording suggesting private-network TLS on .44 was incorrect.
- Normal UI TLS installation now passes50206/267490 with HTTPS API and WSS,
  redirect308, trusted certificate, preserved catalog/assets/language readiness,
  and persisted root-only deployment settings. nginx alone was restarted.
- First attempt53694/f9ca92 exposed SUP failure without HOME in a root systemd
  environment. Fixed in installer-generated wrapper `f2e6f4a`: resolve the
  invoking user's real NSS home only when absent/empty; preserve explicit HOME.
  Fifteen argument tests, four home/NSS cases and bootstrap tests pass1872cb.
  Actual empty-environment SUP readback passesebbe3f. Fix pushed and synced .44.
- Browser55182/108dd9 passes wrong-account401/error/retry, correct login,
  HTTPS API/WSS, `/apis/`, and ACDC live queue200 without insecure requests.
  Exact login account name is `KazooMaster`, not realm `master.dev-testing`;
  earlier credential response was corrected. Password unchanged.
- Existing ten catalog URLs still used HTTP after create-only installation.
  Browser reproduced mixed-content requests; `9861f4b` adds exact reviewed
  `.44` migration profile. All41 regression groups pass per profile (three
  profiles). Actual24378 migrated/verified ten entries with private recovery
  receipt; other app fields preserved. Reload old browser metadata.
- Separate delayed dialog-resize exception reproduced74294/de43b6. Fix
  `c7ecf0a` cancels pending debounce and ignores destroyed dialog instances;
  actual-source before/after and12 pinned-framework wiring groups pass, plus
  11 preservation groups. Normal installer25232/ec4d2b passes (85.5s,
  848.2MiB peak); all nine main services remain active. Postdeployment browser
  90351/a3c1e3 passes login/retry, HTTPS/WSS, `/apis/`, ACDC live200 and delayed
  resize-after-close with zero insecure requests/page exceptions. The master
  account has zero queues and correctly shows its empty state without a spinner;
  the probe was corrected to assert that API-backed state, not a search box.
- The user reached the public hostname and supplied browser errors. Direct
  public connections from the original dev host time out for80/443 despite
  ACCEPT host rules; our automated browser uses private routing with normal
  certificate validation. Do not claim independent public-ingress verification.
- `VM38 reportAllChanges/startTime` is not yet attributed to a shipped source
  file or reproduced in clean-browser tests. Track separately if it recurs.
- Full commands/evidence: [dev44 HTTPS acceptance](doc/dev44_https_acceptance_20260908.md).

## Active — Kazoo 4/5 CouchDB coexistence assessment

| ID | Status | Requirement / acceptance |
| --- | --- | --- |
| COMPAT-01 | ACTIVE — API/edit and selected migration evidence captured; NO-GO for shared writable production DBs | Assess whether an isolated Kazoo5 zone can safely coexist with existing Kazoo4 infrastructure without incompatible shared CouchDB writes. Authorized production read source:10.1.0.10, company/account d8520ce3f29c5b6db692289e782c92af. Use existing protected SSH credentials and separately supplied CouchDB administrator credentials; never put secrets or customer records in Git/log output. Inventory and copy only databases belonging to this exact account, including its account database and any account-scoped MODB/ACDC data actually present. Keep production strictly read-only; do not refresh views, migrate, write, restart, replicate back, or connect development Kazoo5 to production brokers/databases. Restore to an isolated development CouchDB instance or collision-safe namespace, not over active development data. Record snapshot consistency/update sequences and protected backup locations. Capture before/after documents, design documents, view/index definitions, schema/type/version fields and relevant migrations, then exercise normal Kazoo5 maintenance and representative account/queue/device/callflow API operations against the copy. Compare with the current production Kazoo4 source/runtime contract and, where available, an isolated Kazoo4 runtime using the changed copy. Identify shared system/config/design-document effects separately; copying or mutating global production databases is not authorized by this account-scoped task. Produce a clear compatibility report with exact changes, breaking/unknown cases, required isolation boundaries, recovery plan and a GO/NO-GO recommendation. A passing account-only test is not proof of whole-cluster coexistence; unresolved global effects must remain explicit. |

Detailed assessment plan: [Kazoo4/5 CouchDB coexistence](doc/kazoo4_kazoo5_couchdb_coexistence_plan.md).

September8 checkpoint: source metadata475ad5 confirms CouchDB3.3.2 and exactly
seven company databases. GET-only exporter and private receiver now tracked in
`scripts/`;19 offline source-safety/integrity tests passfcdbd3 after fixing the
live-discovered canonical design URL. Account-only export26720/e97565 passes:
1,847 leaf revisions, stable source metadata, protected verified .44 file
`/var/lib/kazoo-compat/snapshots/company-b05rg4rz.ndjson`. Monthly copy55565/c9e79e
also passes:27,762 leaf revisions, all six unchanged;29,609 total. Isolated
account and monthly baseline/working restores pass, final5405/120ead. Native
Kazoo5 account refresh35650/7e39fb changes38 designs/adds8 and writes isolated
shared globals. Real queries16978/039f93 prove two old view endpoints become404,
user features change and queue strategy is additive; sampled device/callflow
rows match. Separate lab network/user/data verified; no production writes or
global production copies. Lab setup/resource fixes and42 tests are in source.
See `doc/kazoo4_kazoo5_couchdb_findings.md`: interim NO-GO for shared writable
production DBs.

API/migration continuation: native authenticated collection/detail reads cover
15 users/82 devices/4 queues/89 callflows. Representative user PATCH initially
fails400 on legacy `call_forward.failover`; the other four resource types edit
and restore successfully (90319/6cf15e). Selected native migration components
99861/408605 migrate15 users and9 devices; one enabled legacy failover becomes
`call_failover` with its number preserved. Each monthly DB changes21 designs and
adds3, with no existing monthly non-design changes. All baseline hashes remain
unchanged (48886/cad73a). Post-migration all five representative edits and restore
readbacks pass200 (93347/340c36). Two additional legacy service-view endpoints
return200 on baseline and404 on working in all six MODBs (64718/b919f6).
Tools and regression coverage are in kz5; raw journals remain private on .44.
Remaining: exact deployed Kazoo4 version/runtime contract (operator asked),
additional view/call edge cases, full system/global
semantics, and rollout/rollback decision. The seven-DB native component test
does not run broad global `migrate/0`; no whole-cluster coexistence approval.

Repeat-check continuation: strict hook checking exposed `undef` in the media
migration responder: only `/0` existed, while company-scoped dispatch calls `/1`.
The earlier outer normal return did not establish hook success. Fixed through
required installer patch `kazoo-media-scoped-migration.patch` in kz5 (core itself
is a pinned dependency, not root-tracked source). Four regressions fail before
and pass after; clean installer patch apply/reapply/rejection and native
production compile pass86339/3811e6. Installer base/modular/deployment suites
pass61019/36b389. Lab-only deployed artifact/runtime proof68481/dec473 verifies
actual origin/MD5, production transform and Media/Crossbar/ACDC/Callflow/Blackhole
running. Final native repeat98564/4be170 returns hook statuses `[ok,ok]`; all
seven content hashes and baseline metadata remain unchanged. This is content
stability, not write-free idempotence: `_design/numbers` and synthetic aggregate
account revisions still advance. See findings for the fixed lab override path,
upgrade precautions, private evidence and deployment/recovery boundaries. Main
stack binaries/services were not changed by this compatibility-lab fix; future
normal module compilation receives the required tracked patch.

Native write-decomposition8037/36fadb now confirms the static/generated numbers
view replacement window and aggregate-account revision churn described in the
findings. Final generated view restored and content equality verified. This is
not a measured Kazoo4 call outage or production-compatible fix. Exact Kazoo4
application host/release was requested again for the remaining runtime contract
checks; company-only inspection copy in main .44 is separately documented above.

## Fresh-server and TLS continuation — 2026-09-08

- Physical FCM/APNs testing: **WAIVED / closed by user**, not a delivery pass.
- Matching TLS key: **DONE**. HTTPS UI and `/apis/`, HTTP redirect, browser WSS
  upgrade and ten existing catalog HTTP-to-HTTPS migrations pass.
- Fresh 10.1.0.44: CouchDB/RabbitMQ/HAProxy install and independent verification
  **PASS**. Source fixes cover root-umask RabbitMQ plugin permissions, Node.js
  first-install selection and bounded UI build heap. Separate UI install and
  independent verification **PASS**, including pinned remote catalog access.
  Fresh bridge installation **PASS**, isolated registered consumer; no phone send.
  Fresh apps audio prerequisite fixed (`5ee63e1`), full inventory verified;
  MIME dependency-order failure fixed (`1cca106`), full fresh compilation passed.
  First startup exposed config-parent traversal and Erlang option precedence;
  corrected in `ee7877c`. Rerun24127 exposed a directory/file validation mix-up
  before compilation; corrected with the real directory validator and negative
  symlink/file/non-root-directory regression checks (70666/a6a153), pushed
  `b6d8bae`. Rerun88880 passed compilation/private binding/datastore, but fresh
  account bootstrap failed. A later protected retry created the master account.
  Exact RPC-result checking and a Crossbar startup gate are pushed (`cdedba2`);
  rerun85919 exposed JSON formatting dropping public datastore file permissions
  under umask077 and triggered fresh-node restarts. Apps stopped on .44 to end
  the loop. Formatter mode preservation/public runtime JSON repair are pushed
  (`1e7e40b`); normal rerun23557/5db474 **PASS**, including apps/eCallMgr,
  fresh administrator/API/SUP checks and 796 shared prerecorded media documents.
  Both services are enabled/active with zero automatic restarts; the requested
  `kazoo-applications.service` alias resolves correctly. SIP template permissions under
  umask077 are also fixed/tested (`c40fd2d`), with untouched secrets/custom files.
  FreeSWITCH sound traversal/readability and existing-audio preservation are
  fixed/tested (`237716e`). Normal FreeSWITCH/Kamailio install84616 on .44
  completed compilation but failed13c663 before startup: the sound
  verifier could not traverse the private installer manifest directory, and
  inspection found restrictive public binary parents. Focused stdin-manifest
  and runtime-directory fixes pass77793/eea832 and are pushed `bc8f969`.
  Rerun62607/2c4b73 **PASS** for FreeSWITCH and Kamailio, including actual
  eCallMgr link, SIP OPTIONS, AMQP consumers, dispatcher and JWT readiness.
  Current local-stack UI96182/c9749c **PASS**, with all ten missing catalog
  entries created in the independent fresh account. Independent fresh ALL
  verification66513/f83cde and actual browser48355/8df633 **PASS**.
  First reboot exposed delayed private-IP assignment: HAProxy stayed failed;
  CouchDB/apps/eCallMgr/Kamailio recovered after one restart. Exact-address
  startup gate and regression tests are pushed `30daaab`; normal ALL48019/6236b8
  **PASS**. Second reboot: all nine units active, restarts0, no address-bind
  recurrence (a833e2). Post-reboot ALL76710/8722b4 and actual browser login/
  API/socket30795/7b71ff **PASS**. No installer job remains.
  The user confirms HTTPS
  login works on the original hostname. At this earlier checkpoint .44's own
  page was HTTP-only; see the new development-hostname HTTPS continuation above.
- [Detailed evidence, commands and recovery paths](doc/fresh_host_tls_acceptance_20260908.md).
- FWD branch through `52c8d85` merged into master; no local redeployment performed.

## New task — account language for forwarded-call confirmation — 2026-09-08

User requested assessment/planning first for the “press 1 to accept” audio heard
when a call is forwarded to a cellphone: EN/HE/AR, later extended to ES/FR, one preference per account,
MonsterUI control, and API/OpenAPI support for the custom frontend. Assessment
finds a feasible, moderate change using existing confirmation/media/account
infrastructure; four endpoint/directory forwarding/failover selectors must agree.
Implementation and source/offline checks are complete for all five languages.
The five packaged recordings each completed internal extension1000 press-1
confirmation; the user identified EN/HE/AR. Normal development installation,
20 live API/call checks and ten final deployed browser checks pass. UI and `/apis/`
are ready. Branch: `feat/account-forward-confirmation-languages`; merged into master at `2b07609` and pushed. See [implementation evidence](doc/call_forward_confirmation_acceptance.md).
Detailed design, API/reset, risks and acceptance:
[forwarded-call confirmation plan](doc/call_forward_confirmation_language_plan.md).

| ID | Status | Requirement / acceptance |
| --- | --- | --- |
| FWD-01 | ASSESSED — planning complete | Source assessment identifies `ivr-group_confirm`, account-aware resolution, all four selectors and existing account API/UI seams. Feasible with moderate effort; zero operational risk is not established by source review. |
| FWD-02 | DEPLOYED / API PASS | Account-only EN/HE/AR/ES/FR preference with validated GET/PATCH/reset, server-side permission checks, shared prompt selection across endpoint v4/v5 and directory forwarding/failover, and cache invalidation. Preserve absent-setting/custom-media behavior and keypress/timing/routing. |
| FWD-03 | PACKAGED / IMPORT VERIFIED | Five Gemini recordings authored once, immutable/versioned shared assets, create-only import and exact readback/readiness. Reuse for all accounts; no generation on save/install/call. Five initial provider requests succeeded; original EN/HE/AR bytes unchanged when ES/FR were added. Formal native-speaker certification is not claimed. |
| FWD-04 | DEPLOYED / BROWSER PASS | Visible section header and associated label, native EN/HE/AR/ES/FR options aligned left, default/reset and missing-locale fallback. Dedicated PATCH and main Update both save. Update stays on the form, includes only a changed preference, preserves a newer API value when untouched, and retains pending selection on failure. Actual formatter/handler tests and ten deployed follow-up browser checks pass; test account fully restored. |
| FWD-05 | PUBLISHED / VERIFIED | Document the account field through existing GET/PATCH routes, envelopes, locales, reset/defaults, permissions and errors; add a custom-frontend example and source-reviewed schema overlay. Served HTTPS specification matches the validated generated artifact and live account behavior. |
| FWD-06 | DEVELOPMENT ACCEPTANCE PASS | All five internal phone recordings accepted digit 1; live account/cache/media selection and complete RTP waveform checks pass for five synthetic calls. Wrong digit/no digit/hangup prevented connection. API isolation/permissions/reset/older-client preservation and deployed browser saves pass; original preferences restored and temporary users deleted. Real cellphone/PSTN, mobile voicemail, formal native-speaker certification and every physical routing combination were not tested on this development host. |

## Current focused release checkpoint — 2026-09-08

- **Standalone UI catalog transport implemented:** fixed-command pinned SSH
  to the existing create-only SUP importer; missing/partial standalone authority
  fails preflight, local ALL remains local, and explicit `false` is assets-only.
  Apps-role installation deploys the receiver without creating SSH trust/users
  or sudoers.19 transport tests plus actual installer routing/smoke/modular/
  read-only/persistence suites pass. Actual receiver readiness/wrong-master/
  preserved-ACDC/readback passes18673/066c23. Real loopback SSH with installer
  remote routing passes16602/47fb93: ten preserved apps, twenty verifies,
  wrong host-key/master/source-version rejection, no retained pending stages.
  Temporary SSH daemon/config/test keys removed; app PIDs unchanged. Receiver
  reinstall/source-hash verification passesa9e7ef. Genuine second-host and
  absent-catalog creation remain pending; see `doc/monster_ui_remote_catalog.md`.
- **External acceptance inputs requested:** designated Android/iPhone test
  tokens with APNs topic/environment, and a clean Rocky9 development SSH target.
  No response yet; do not send test notifications to production users or use
  production bridge SSH credentials for catalog/server acceptance.

- **Full normal apps/eCallMgr installer PASS:** pushed981f317, session48353,
  terminal `f4275e`, exit0 at~06:52UTC September8. Compilation, release,
  apps/eCallMgr restarts, runtime/API/SUP readiness,796 prerecorded documents
  in both maps, five-language capability publication, final verification and
  root-only deployment settings persistence all completed. No Gemini calls.
  Same-host pass only; no fresh/split-host or production-ready claim.
- **Independent `--verify-only ALL` PASS:**56291/3f1242, exit0 at~07:04UTC,
  384MiB/512MiB admission reserve/900s. All nine component checks passed,
  including Kamailio journal/JWT, served UI/catalog and bridge consumer.
  All nine units enabled/active with restart counters0 in0a2d67. No live job
  remains; do not repeat the build/check merely to refresh this evidence.
- **Focused Kamailio verification fix:** first ALL45977/bc78ef exited1 on
  journal aggregate input limit, after service/AMQP/ACL checks passed. Stream
  full activation history with bounded retained state/per-record size and
  existing30s deadline; do not discard old errors.13 regression tests and43
  AMQP fixtures pass34186/2eb247. Corrected actual ALL rerun passes above.

This newest checkpoint supersedes older chronological snapshots below; a
historical ACTIVE/OPEN label is not a fresh runtime observation. Reproduction
commands and exact scope: `doc/focused_acceptance_20260908.md`.

- **Operator priority reset — finalize ASAP:** stop adding implementation scope
  and validation tooling. Tested callback, bridge and guard work is pushed in
  `981f317`; the normal apps/eCallMgr installer passed with the
  verified3600s outer window and independent ALL verification passed. Commit/
  push the final status. Do not start another build to refresh evidence.
  Existing five-language callback registration/retry and broker-recovery
  results remain accepted only within their documented scope. Returned-audio
  supplemental proof is incomplete: HE replay50498 failed strict RTP coverage;
  diagnostic79134/7eacd4 found one160-sample gap inside the matched phrase
  despite0.999992 correlation. Do not label full returned-phrase coverage proved
  or substitute the untested phrase-only private relaxation (it cannot fix an
  inside-phrase gap). Original call evidence is unchanged. Standalone catalog
  automation has since been integrated and tested to the newest scope above;
  its earlier private handoff is no longer current.

- **Bridge registered-consumer acceptance PASS:**83390/9d4620 exercises the
  actual runtime against UUID-isolated local broker resources. Counts0→1
  recover503→200 without blocking a companion; exhaustion0→1→2 reaches DLQ.
  One consumer, zero work Basic.Get, zero provider calls, stable sources and
  both temporary resources removed. Receipt db017d0e-c514-4bbe-8874-296d8a0d69fe
  under `/var/log/kazoo-acceptance/kz5-retry-proof-*/receipt.json`.
- **Missing-DLQ-route acceptance needs corrected window:**40711/644081 exited1
  with recovery_deadline after the route was restored. The test waited60s;
  installed RabbitMQ's no-route retry timer is180s. This does not establish
  loss or recovery. Both UUID resources were cleaned; no provider calls.
- **Callback language extension integrated, regressions PASS:**53441/32d30a
  completes92 guard cases,8 locale groups,88 retry groups,13 cleanup groups,
 79 registration-audio cases,96 packet cases and27 service-scope cases.
  New explicit `--language` is limited to the isolated retry account; inherited
  overrides cannot mutate queue language. Hebrew8443/53f15d and French
 15515/f1b8d1 and Spanish37303/93b8d4 pass using installed references and
  entry-only key6. Evidence `20260908T010737Z`, `20260908T011230Z` and
 `20260908T011714Z` under `/var/log/kazoo-acceptance`.
  Arabic56725/d5de4c also passes at`20260908T012152Z`. These passes prove registration
  success audio and retries, not complete returned-confirmation audio. An
  additive read-only replay checker for retained PCAPs is being prepared;
  existing callback projections omit language, so historical persisted-language
  continuity is not claimed.

- **Corrected unbound-DLQ acceptance PASS:**52763/f08152, runtime420s guard,
  recovery240s/case300s/channelRPC10s. Private cf725c and repository e2026b
  pass12 cases, including the180s broker timer. Actual readback ac566a confirms
  one publish/dispatch, no republish, exact retained-body recovery174934ms
  after restoration, stable sources and both temporary resources removed.
  Receipt209af0aa-e241-441e-9b65-5e30b9a6438a under the protected acceptance
  root. No provider sends/full-DLQ/restart claim. Actual guard e2026b confirms the optional
 1h RuntimeMaxSec with unchanged CPU/memory/swap/task constraints.

- **Full apps/eCallMgr rerun timed out, not accepted:** committed/pushed9642413
  (`10480/872635`), no unrelated files staged. Guarded normal installer
  session4728, initialf18428, unit
  `kazoo-validation-e15ec615-0dda-496a-9e29-05367204c3fb.service`, started
 around00:29UTC. Zero FreeSWITCH channels verified first; one build worker,
 384MiB validation cap and1800s deadline. Terminal session result b741fb is
 exit1; journal f5c7d5 confirms runtime timeout at00:59:06UTC, not a compiler
 failure. Compilation/release assembly, apps startup/datastore readiness and
 796 media documents/1592 mappings passed before timeout. Apps, eCallMgr and
 bridge remain active. Full installer finalization/eCallMgr dispatch was not
 completed; an explicit longer bounded validation window is being reviewed.
 Source freeze is released now that the exact job is terminal. The only unrelated untracked file remains
  `doc/dashboard_caller_sidecar_design.md` and must not be staged.
- **Earlier private bridge preparation (now tested above):**
  `/opt/kz5-bridge-consumer-proposal.lb2qJ4` adds a real
  `BridgeRuntime.run`/basic.consume harness using synthetic provider outcomes,
  exact UUID-isolated broker resources and existing protected cleanup. Proposed
  cases:503→200 with companion progress,0→1→2 exhaustion/DLQ, one consumer
  registration and no work-queue Basic.Get. Root reviewed; separate offline
  regressions are prepared and read by root. Use `proposal-v2.patch` plus
  `tests.patch` (exact pins in PROJECT_HANDOFF.md). Both files are now integrated;
  repository10 consumer +9 DLQ +10 baseline cases passed21449/6e9d43.
- **Earlier installer phase:** at~00:35UTC4728 passed210
  fixed voices,584 cardinals/approved intros and current Crossbar integration;
  core compilation subsequently completed before the timeout above. Capability file was preserved at its verified
 198866b70bc0805b32ae8eab385355a172931e114939960c59ea1c69d1290221 hash.
  No provider calls were made. This phase result is not final installer success.
- **Prepared acceptance gaps (updated by results above):** private unbound-DLQ driver
  and nine offline cases are at `/opt/kz5-bridge-dlq-retention.Hkh8Ez`; root
  reviewed. The test-only language option is now integrated for the existing
  EN-only retry/reference harness, so HE/FR/ES/AR full confirmation and retry
  can be tested live without touching runtime logic or generating any audio.
  Existing all-five position/offer results are not substituted for those tests.

- **Bridge deadline deployed through main SH:** repository205 tests and main
  installer smoke checks pass82499/98c851; bridge dispatch/rollback checks
  pass82966. Normal `install-kazoo5.sh push-bridge` followed by independent
  `--verify-only push-bridge` pass74779/c9f0f1. Release
  `0a3a5ba26bdf26caa9fea2343fb565c3ce218079cf976eb5be801ac9143e94da`,
  PID1172968, active, restart count0; installed bridge/settlement hashes match
  repository source (`4aaccc`). Registered-consumer readiness, protected config
  and18 locked dependency versions pass. No actual provider sends or production
  server changes. Phone, remote-broker and failure/recovery gates stay open.
- **Actual Crossbar formatter transition PASS:**82966/00c47b successfully
  normalized the known build-formatted schemas on this server after private
  preflight, retaining `/tmp/kazoo-integration-preflight.LLkrRB`. No services
  restarted in this step. Full apps/eCallMgr main-SH run still required.

- **Formatter transition regression PASS:** session26154/15c456 exited0:
  all110 source-transition cases, main installer smoke checks and12 catalog
  tests pass. Evidence `/tmp/kazoo-source-transition-tests.x7UYvz` includes
  actual install/format/reinstall and rejection of duplicate keys, semantic
  edits and partial formatting. Read-only independent review found no blocker.
  An interrupted formatter's mixed state is intentionally refused and still
  needs inspected recovery; full normal apps/eCallMgr rerun is next.
- **Bridge deadline candidate PASS, applied to source:** private12055/09efad
  exited0 with205 tests across14 suites, including18 new deadline/fail-stop
  tests and real private-process exit78 despite blocked worker and cleanup.
  No provider/broker traffic. New default60s `PUSH_BRIDGE_DELIVERY_TIMEOUT`
  bounds unfinished workers when the owner loop is healthy; uncertain sends
  remain unacknowledged and are not automatically replayed. Source-suite rerun,
  main-SH deployment and actual consumer/broker/device acceptance remain open.
  See `doc/push_bridge_worker_deadline.md`.

- **Full apps/eCallMgr installer stopped before compilation:** session39751, guarded unit
  `kazoo-validation-819270c4-30cf-4304-98c5-22c3a9bf5178.service`, started
  00:02:46UTC from pushed918cf6e with one build job; terminal exit1 `8e209c`.
  All210 fixed and584 cardinal assets/approved intros passed source/import/
  readback checks. Crossbar preflight then rejected build-generated formatting
  in three schemas; no compilation or service restart occurred. The real
  `scripts/format-json.py` output exactly matches those source bytes. Evidence:
  `/tmp/kazoo-crossbar-compare.TG5HL2`,
  `/tmp/kazoo-crossbar-format-proof.a9OjwO`, and failed private preflight
  `/tmp/kazoo-integration-preflight.QvDWgx`. A known whole-file formatting
  transition is being added; arbitrary JSON/user changes must still be refused.
- **Bridge worker-deadline gap identified:** unfinished provider futures are
  skipped by `OwnerSettlements.drain`, while the broker loop continues updating
  its watchdog. A permanently blocked refresh/worker can exhaust capacity
  without failing consumer readiness. A focused private proposal is in progress;
  require synthetic blocked-worker/clock tests and bounded fail-stop with no
  ACK/replay of uncertain delivery, preserving exit78 and generation fencing.
  Also still open: actual basic.consume retry-loop proof (prior broker test
  uses Basic.Get), and retention when the isolated DLQ is full/unavailable.

- **Final focused checks PASS:** `90006/cb79bd` reran15 replay-cache cases,
  26 readiness cases, current-build ordering/failure checks,32 finalization
  cases, actual deployed queue-editor language verification, and main-SH
  `--verify-only push-bridge`. Bridge source/dependency lock, protected config
  and actual broker-consumer readiness pass; no real mobile delivery claimed.
  Apps (including kazoo-applications alias), eCallMgr, bridge and nginx are
  loaded/active with restart counters0 (`de94d7`).

- **Normal Monster UI installer PASS:** `44420/6ef89a` exited0 after the
  stateless catalog helper fix was production-compiled and deployed with exact
  loaded MD5 verification. All ten catalog entries preserved and verified,
  served index/main/config match the owned artifact, same-origin Crossbar JSON
  proxy passes, nginx enabled/active, deployment settings saved normally.
  Recoverable old BEAMs: `/root/kazoo-catalog-deploy.Q6EBiJ`; new BEAM SHA256
  `79528cf9362e9742c74b62bb079f091e5372fa316da59400258c066e2db19a95`.
  Crossbar aggregate/source transitions preserve this fix on later builds.
  Twelve catalog tests, all87 transition cases and installer smoke checks
  passed in `24414` before deployment; evidence
  `/tmp/kazoo-source-transition-tests.BhqEPa`. The first transition test run
  passed the cases but failed its stale81-case total; corrected to87 and rerun.
  This closes the UI catalog blocker, not full stack/fresh-server acceptance.

- **New-build callback retry PASS:** `1297/784164`, evidence
  `/var/log/kazoo-acceptance/20260907T232852Z`: busy-agent call, five-second
  wait, key6, full recorded Gemini confirmation before BYE, two-second wait,
  agent release, unanswered first return, durable retry_wait, then second
  return accepted with key1 and reciprocal native bridge. Runtime/log and
  teardown gates pass. Isolated internal1001 fixture retained intentionally;
  this is not physical operator1000 or complete fixture cleanup acceptance.
- **eCallMgr cold start PASS:** `34255/656bb8` restarted with zero channels,
  passed the actual bounded datastore-readiness gate and complete eCallMgr
  verification. PID1036743, active/enabled, restart count0. Apps cold startup
  and an uninterrupted apps/eCallMgr installer run remain open.
- **Deployed language selector PASS:** `59484/322097` authenticates against
  the actual unified new-queue editor API, verifies the exact published
  capability bytes and210 media entries, extracts the ACDC AMD module from
  deployed `js/main.js`, and confirms all five choices enabled. No queue writes
  or provider requests. This is deployed-function/API proof, not an interactive
  browser or native-speaker listening approval. The first probe failed because
  it incorrectly expected an unbundled app.js; the deployed bundle is valid.
- **UI deployment succeeded; installer catalog blocker being fixed:** initial
  npm resolution OOM was confirmed in systemd journal. Bounded npm heap and
  download concurrency allowed retry `73828/bc2596` to build and deploy the UI
  and `/apis` (358paths/653operations). Installation then stopped because CSV
  Onboarding has a valid empty icon string. The focused catalog fix treats
  that string as no icon; screenshot/security checks remain. Twelve isolated
  catalog tests and production compilation pass; transition suite and normal
  UI installer subsequently passed as recorded above.
- **Offline installer fixes:** complete real-DSP synthetic voice-pack check
  passes15groups/4926assertions; cached input bytes match the prior native
  proof. Legacy capability migration32cases, cache15cases, readiness26cases,
  and main installer smoke checks pass (`98366`, `40048/5990dc`). No persistent
  validation cache and no runtime Gemini generation introduced.

### Earlier checkpoints (superseded where explicitly updated above)

- **All-five live position/offer audio PASS:** English71221/06d203 and
  remaining-locale batch75174/44d3e7 both exit0. HE/FR/ES/AR first offers arrived
  at30.049/30.051/30.065/30.046seconds; their second offers at60seconds plus
  the same offsets. Complete position-one phrases started at45/75seconds plus
  those offsets. Every run passed negotiated PCMU correlation, entry/extra-audio
  checks,86second normal teardown, runtime/log checks and conditional cleanup
  with no agent changes. Evidence directories under `/var/log/kazoo-acceptance/`:
  `20260907T231909Z`(EN), `20260907T232112Z`(HE), `20260907T232304Z`(FR),
  `20260907T232456Z`(ES), `20260907T232647Z`(AR). This proves position-one and
  offer-six, not all numeric audio, native listening, live wait-time, or every
  callback response. Post-build key6/retry test1297 is now running.

- **Actual five-language runtime proof and publication:** `95443/8dee1a`
  passed all796 documents,1592 mappings,95 position playlists,10 callback
  preparations and80 wait cases against eleven pinned loaded production modules.
  Receipt `/root/kazoo-prerecorded-release.F8qJut/runtime-receipt.json`, SHA256
  `f0f59a60be6fb8607ff15f146e35fbdf4c2dbe51aaed2e17eee4453cfe3f7db0`.
  Initial evidence location was rejected because `/var/lib/kazoo` is service-owned;
  moved the task-owned directory under protected `/root` before proof.
  Publication `71766/1727f7` then migrated the exact inspected all-negative legacy
  web-root setting to `/etc/kazoo/acdc/language-capabilities.json`, SHA256
  `198866b70bc0805b32ae8eab385355a172931e114939960c59ea1c69d1290221`.
  All five languages are selection-ready; native listening/full readiness remain
  false. Real receipt and installer ownership marker are retained. This was an
  explicit post-build continuation, not a successful uninterrupted installer run.
- **Startup readiness and timing fixes:**26 isolated readiness cases and actual
  read-only checks on both apps/eCallMgr pass (`8d2cfd`, `659e2b`). Cold startup
  remains to test. Private32MiB conversion replay reuse within one release-plan
  call passes15 isolated cases (`1e41d2`), preserving source reads, byte/QA checks,
  per-scope deadlines and exact telephony comparisons. Current-build and16
  finalizer fixtures pass `8bd940`. Real complete-pack timing/byte parity and
  full installer acceptance remain open; no persisted validation cache is used.
- **Installed references and English live audio pass:**12519/e2951a prepared
  all-five references from actual installed attachments, provider requests0.
  `/root/kazoo-prerecorded-reference.PvNvXj/index.json`, SHA256
  `588d9e5ab556ee1cc7968d6d646f0e21d2fa55c5257c307dc69dab95acd2f78a`.
  Cached full input equals the pre-cache successful native proof exactly
  (`de3c3d`). English live71221/06d203 passed offer30.042/60.042 and full
  position-one45.042/75.042seconds, exact negotiated audio, no early/extra offer,
  normal teardown, runtime/log gates and conditional cleanup. Evidence:
  `/var/log/kazoo-acceptance/20260907T231909Z`. Native listening/wait-time and
  callback registration/retry are separate, still-open acceptance gates.
- **Next:** finish callback retry1297, matching UI deployment, legacy-path
  migration regression and cold-start checks. Full normal installer still open.

- **Actual new build deployed, finalization still pending (22:55 UTC):**
  source `dd39d90` is pushed. Normal installer `5f658d/session54282` passed
  complete audio import/readback, one forced core traversal, all applications,
  release assembly and production-BEAM checks. Apps restarted asPID944670 and
  all configured apps passed startup checks. The outer resource guard reached
  its30minute runtime limit at22:49:13 during cardinal mapping verification
  (journal confirms `timeout`,245MiB peak,14min49.916s CPU). A collected unit's
  later default `Result=success` is not evidence of installer success.
  No full installer acceptance is claimed.
- **Bounded continuation:** all586 cardinal/intro documents and1172 mappings
  independently pass on the new apps node, missing0 (`9e200f/7263e9`); the
 210fixed/420mapping check passed before the deadline. The eleven actual
  production BEAM pins and real probe arguments are saved privately under
  `/root/kazoo-prerecorded-release.F8qJut`; subsequent runtime proof and
  capability publication are recorded above.
- **eCallMgr activated and verified:** PID960600, enabled/active; production
  BEAM, node/application, callback cleanup, framing, FreeSWITCH connection and
  native atomic-intercept gates pass (`77dbc2/c006ca`). First configuration
  attempt after the installer's fixed5second delay failed while datastore ETS
  was unavailable (`784267/6011ed`, server=>ok). Bounded native connection wait
  then returnedok (`cd5b3e/87507b`), and configuration succeeded. Replace the
  fixed sleep with an actual bounded datastore-readiness gate before claiming
  reliable cold-start deployment.

- **Pre-deployment verifier and live-audio harness fixes:** build-order fix
  `36876c3` is pushed. The following normal installer attempt
  `dc71ad/session30156` was deliberately stopped during media preparation when
  read-only review found a guaranteed native probe bug: OTP returns
  `{ok, {Module, MD5}}`, not a singleton list. Corrected production template
  passes its actual `CheckBeams` closure against a real compiled/loaded module,
  including wrong path/hash and loaded-code mismatch refusals
  (`022310/031fb5`, private fixture `/root/kazoo-runtime-reader.aSXaUC`).
  No service activation occurred in that stopped attempt.
- **Five-language call-test harness integrated and offline-tested:** explicit
  position-one/offer-six profiles, installed-byte/model/index binding and exact
  SIP/RTP checks pass52 audio,10 reference and33 fixture groups
  (`7ac1fc/session14947/d39a06`). Prior synthetic failures found an incorrect
  2.5Flash allowlist (actual saved originals are2.5Pro), and an extra offer
  truncated by BYE escaping complete-phrase counting. Both are fixed without
  changing saved audio or relaxing readiness. Live runs remain open. See
  `doc/acdc_five_language_live_audio_acceptance.md`; wait-time/native listening
  and callback registration/retry are separate gates.

- **Next deployment attempt, 22:10 UTC:** tested integration code is committed
  and pushed to master as `99eafe5` (80 files; staged secret/whitespace checks
  passed). Normal main-SH run `8a1b8e/session36819` passed both complete voice
  packs, source reconciliation, and the first core/webhooks compilation. It was
  deliberately stopped before any service activation when the top-level `apps`
  target began a redundant second forced core build. This is not a successful
  installer result despite the explicitly stopped transient unit returning zero.
  Apps/eCallMgr/FreeSWITCH PIDs remained1983/1982/809116. A focused installer
  change now calls the applications aggregate directly after core/webhooks,
  retaining forced application compilation. Ordering/failure tests, real Erlang
  forced-rebuild checks (12 commands), and modular installer checks pass
  `9e8c1e/session49848`. The subsequent isolated live-audio draft test failed
  because its new fixture used a default pro-model document against flash-model
  expectations; that draft is not deployed. The next full installer run must
  pass before claiming deployment.

- **Atomic installer blocker repaired and native prerequisite deployed:** all81
  source-transition cases and exact eCallMgr patch replay pass `37fef8/3ba923`.
  The same run freshly compiles the updated mod_kazoo. Module-only promotion
  `012ab4/session71356/805728` passes; actual `kz_intercept` is registered,
  PID809116, automatic restarts0. Installed SHA256
  `4ac9d4af50deca7a4163bb158befaecbbdcd59f23e137fe49aaf9d213810cfec`.
  Previous module and libtool archive are backed up under
  `/var/lib/kazoo-mod-kazoo-upgrade.dU80a1`; installed/source core and eight
  headers matched before promotion. Full FreeSWITCH build marker deliberately
  remains unchanged: this is not full-engine installer/rebuild acceptance.
- **Remote native gate verified:** `d58bb9/e31aba` passes the corrected20-case
  Erlang fixture, shell scope/refusal/permission fixtures, modular installer
  checks and the actual eCallMgr-to-FreeSWITCH atomic inventory request.
  Initial gate fixture `70c0c3/e19034` exposed file:script's rejection of a local
  named fun; explicit `fun erlang:is_binary/1` fixes it without weakening checks.
  No live call was made. Empty configured media scope stays explicitly unverified.
- **Verification timeouts corrected:** SUP uses seconds, not milliseconds.
  The cardinal mapper and prerecorded probe now request180seconds, retaining
  their190000ms local and150second native bounds. Probe9 Node groups pass
  `b41a85/978e65`; full seven-group mapper plus native586/1172 fixture passes
  `d58bb9/e31aba`. Initial direct mapper .cjs invocation correctly refused
  to replace its required two-phase .sh test. Finalization16, initialization10
  and production-BEAM safety fixtures pass `59eb68/59a139`.

- **Coherent deployment stopped before compilation/restart:** normal
  `install-kazoo5.sh kazoo-apps ecallmgr`, `a87725/session80615/4c095b`, passed
  both installed voice packs but refused the eCallMgr aggregate. Current nested
  source is the old aggregate plus the checked-in atomic-answer delta; installer
  reconciliation was subsequently fixed without discarding that work. Native inventory
  `a4f5b9` confirms the running FreeSWITCH lacks `kz_intercept`: deploy that
  module before the dependent eCallMgr cohort (now done above). Six Erlang reconciliation tests
  and100 concurrent three-answer native-boundary races pass `ad7f8b/35c78b`;
  these are not actual live simultaneous-call acceptance.
- **Pre-restart preservation:** no active FreeSWITCH calls; native ETS had22 call
  rows (9 unarchived,13 archived) and685 archived status rows (`cfe9ae/84fcf8`).
  All rows saved using synchronous ETS snapshots with MD5/object-count metadata
  (`ffd4d7/4daa23`) under protected
  `/var/lib/kazoo/predeploy-check.BRAAd0/snapshot`. These private snapshots contain
  call data, must not enter Git, and are not an automatic restore/migration claim.
- **Finalization fixes tested:**16 synthetic main-SH orchestration cases plus
  cardinal and bridge shell fixtures pass `0e861a/5dea78`. Bounded runtime-reader
  and initialization fixtures pass `ccf782/7a8dad`. Review found launcher paths
  retained `scripts/../`, conflicting with exact loaded-BEAM verification; both
  launchers now canonicalize their root. Canonical library/config paths, logging
  and reloader behavior pass `2d89e6/9e6811`. Native proof still awaits deployment.

- **Saved and pushed:** all584 position roles across EN/HE/FR/ES/AR;
  artifact-only commit `d09d697` is on `origin/master` (`9114e3/6504c4`).
  No further Gemini generation is needed for this inventory. This does not
  claim the complete pack is deployed or listening-approved.
- **Bridge deployed:** main-SH install `feccd8/4664d3` and independent
  verify-only `b0c4d8/02b4a6` pass. Active release
  `b20944143ade6ae0ad3ffb4c4c69094305348d7220f890669ca57606fb3810f8`,
  PID679049, zero restarts at readback; broker consumer registered.
  The isolated development queue had zero ready/unacknowledged messages before
  restart. Protected topology/freshness/retry opt-ins remain absent. No real
  provider sends or production-server changes. Android/iOS acceptance remains open.
- **Media installed and independently verified:** actual main-SH media routine
  `96ba63/session31524/e25b08` passes all584 cardinals,210 fixed assets and two
  new intros. Final read-only cardinal receipt SHA256
  `a629cbb24bd4ed2ae235adc72002419fb0affd1deb267fe12cfe371116e052bd`;
  fixed receipt SHA256
  `294fd51eb3cb4d7de42b0bc4dfdcba1a8ccd548c5a63b888d470d56508a91f9e`.
  Both are under `/usr/local/share/kazoo5-installer/`; no provider request,
  account/queue mutation, or runtime readiness publication occurred.
- **Runtime mappings activated and checked:** `f7bee8/session67837/e30111`
  verifies all210 fixed/420 mappings plus586 cardinal/intro documents and1172
  mappings. Activation added1172 missing owned paths; the independent read-only
  cardinal check finds zero missing. No database/queue write or language
  readiness publication. First sourced attempt `31175c/9bac13` omitted node-name
  initialization and stopped before mappings; corrected `-sname` driver passed.
- **Voice integration still open:** deploy matching apps/UI and publish
  evidence-backed language capabilities.
  Both earlier cache-helper tests hit the384MiB validation limit; neither was a
  live Kazoo service crash. The bounded-sidecar fix now passes its full586-document/
  1172-map Node and actual Erlang scope `72fdba/8501c9`, under the unchanged cap.
- **Current regression evidence:** capability/UI/backend/path/initializer and
  cardinal grammar checks pass `060f9a/2b2583`, including73,240 JS parity cases.
  New wait-time/cardinal/callback-scheduler/announcement/language suites all pass
  `0c9112/21885e` (56 EUnit cases). Bridge post-start failure rollback and exact
  cardinal release-pin shell fixtures pass `943abf/2ca19d`. OpenAPI source rebuild
  and deterministic/schema/tamper checks pass `eda5ac/0d8037` (358paths,
  653operations,506schemas,1603references); live publication awaits matched runtime.
- **Final gates still open:** five-language live/listening acceptance, extension1000
  callback acceptance after final deployment, real mobile delivery and broader
  fresh/separate-server installation/reboot/recovery/load checks. Publish matching
  OpenAPI and commit remaining tested code. Dashboards stay postponed.

The dated/count-based entries below retain earlier evidence; this section is
the current priority summary and does not turn historical passes into release approval.

Latest focused integration: all584 position roles have saved audio, including
Arabic208/208. Final authoring `20e177/5e5503` and59-receipt read-only resolver/
planner replay `d5f2f4/467d44` leave zero missing roles or further proposed
Gemini requests. Final index SHA256:
`b6c4e2a2ef515be72d378a239086b4421992a095447003c1c397c925d98c1e51`.
Original412 +170 new-model recordings +2 reviewed Spanish aliases =584.
All-five main-SH source
preflight now precedes any media database effects; shell fixture and ten bridge
acceptance harness tests pass `debd38/b50cb1`. Final index pin is frozen and the
real Arabic map emitted. Complete-source preflight, current regression, runtime
deployment and listening acceptance are not yet closed at this checkpoint.

Actual isolated bridge retry acceptance passes `feecd1/ac00b2` with stable source,
broker counters0→1→2, companion progress, three-attempt exhaustion quarantine,
channel-close recovery and original-deadline expiry. Exact temporary vhost/user
removed. No provider calls or production effects. The prior setup failure is
retained, cause unproven; safe command diagnostics now preserve future failures.
Real devices, full broker restart/lost-ACK/DLQ faults remain open. See
`doc/push_bridge_retry_broker_acceptance.md`.

**Earlier artifact checkpoint:**529/584 (EN31/31, HE131/131, FR161/161,
ES53/53, AR153/208). Arabic55 still missing; every accepted recording saved.
Actual complete HE/FR/ES source maps are prepared and independently reviewed,
but not included/activated yet. Current40-receipt replay and all nine running
services pass `de95f2/fb1089`. See `doc/acdc_cardinal_ar_model_recovery.md`.

Current focused source fixes: per-recording mixed-model cardinal admission passes
23 importer groups/8,233 checks and17 current-source EUnit tests plus installer
adapter regression (`38195b/4482a3`). Fixed210/EN behavior is retained; no new
runtime maps are activated. See `doc/acdc_cardinal_model_runtime_admission.md`.
Opt-in bridge counted FCM500/503 retry passes all187 bridge tests; main-SH
includes the retry module in all release paths and its fixture passes `c73261`.
Actual broker counter/recovery and header-directed/APNs/uncertain-outcome retry
remain open; no opt-in activation or real phone delivery. See
`doc/push_bridge_counted_retry.md`. Arabic recovery latest checkpoint is in
`doc/acdc_cardinal_ar_model_recovery.md`; older counts below are historical.

Latest combined voice checkpoint: **481/584 technical artifacts**, EN31/31,
HE131/131, FR161/161, ES53/53, AR105/208. Hebrew recovery saved36 new clips;
actual complete HE131 source plan passes `4842e8/8770e2`. Arabic103, listening,
runtime admission/maps and full deployment remain open. Mixed five-locale adapter
offline checks pass `b086d2/31b376`; existing EN documents are preserved.
See `doc/acdc_cardinal_he_model_recovery.md`. Counts below are older checkpoints
or explicitly the unchanged original2.5 ledger, not current combined coverage.

Original 2.5 voice ledger (not combined artifact coverage): **412/584 technical QA**,697 historical requests and
113 retries; EN31/HE92/FR160/ES25/AR104. Five bounded HE concise-v2 requests
recovered three recordings (six WAVs); two still incomplete. No pending provider
job or initial identities remain. Failed172; listening/complete cardinal runtime open.
See `doc/acdc_cardinal_concise_synthesis.md`. Older counts below are historical.
Authoring diagnostics now retain only allowlisted prompt-block categories and
finish-message presence, never raw provider text.19 groups/377 checks pass
`a40011/893835`; that offline test made no provider request. Voice completion remains open.

Exact Spanish whole-word reuse is integrated in the separate staging importer:
19 groups / 5,962 checks and installer adapter regression pass. Actual resolution
at that earlier checkpoint was 412 generated + 2 reused, 170 unresolved; no complete-language deployment is
claimed. See `doc/acdc_cardinal_reuse_import_integration.md`.
Separate model-trial results are in `doc/acdc_cardinal_31_model_trial.md`.
Additional trial calls never reset the original ledger or its failed histories.
Gemini3.1 format compatibility is fixed in the isolated authoring tool;637
offline checks pass. There are now31 separate QA candidates/62 WAVs,32 additional
requests and12 terminal receipts. Spanish artifact coverage is53/53:25 original,
26 new-model candidates and2 reviewed exact-word aliases. No runtime deployment
or listening approval, legacy412 count unchanged. The read-only candidate
verifier passes447 checks, planner204 checks; real replay passes. See
`doc/acdc_cardinal_model_recovery.md` and the pinned model-trial asset index.
FR89 one-shot succeeds. EN31/31, ES53/53 and FR161/161 technical artifact coverage;
HE95/131 and AR105/208 remain open. Original412 ledger unchanged. Latest
authoring637/verifier447/planner204 checks pass. See
`doc/acdc_cardinal_fr89_one_shot.md`; no listening/runtime approval.
Mixed-model candidate staging is implemented, preserving real3.1 metadata and
safe idempotence as the index grows.23 importer groups/8,016 checks pass; see
`doc/acdc_cardinal_model_trial_staging.md`. No database import or runtime
activation follows from these fixture tests.
Actual complete ES53/FR161 read-only plans also pass (`cd6452/f2a5bf`), with
zero unresolved roles and no provider/database requests. Exact candidate hashes
are recorded in the staging document. HE/AR recovery and runtime release remain open.

INST-13 producer/consumer freshness is implemented in code and the main-SH file
lists/patch sequence.166 offline bridge tests,35 producer checks, actual isolated
Kamailio timestamp/unchanged-payload execution and real isolated broker expiry
quarantine all pass. See `doc/push_bridge_freshness.md` for configuration,
evidence and boundaries. Strict mode requires explicit quorum configuration;
do not treat legacy development routing as an activated freshness deployment.
Bridge deployment through main SH passes `d092dc/1e7b45`; independent verify-only
passes `b9e8bb/be5ab7`. Releasec9d8055d8f92, PID448604, NRestarts0. All nine
stack services active at readback. Detailed receipt in the freshness document.
Main-SH Kamailio producer deployment also passes `0de2e3/95d41c`, including
SIP/AMQP/dispatcher/database/RPC/SBC and current journal/JWT checks. PID451713,
NRestarts0; protected backup retained. Earlier malformed-Via attribution remains
open and its logs preserved; no acceptance gate was weakened.

Latest post-deployment internal1001 callback retry passes `21d377/55fb32`:
full confirmation, missed first return, durable retry, second native bridge and
final agent/service/log gates. Evidence `/var/log/kazoo-acceptance/20260907T181123Z`.
An initial rerun used an obsolete legacy audio reference; corrected read-only
analysis proves Gemini was delivered. New preflight rejects that operator error
before calls. See `doc/development_warmup_20260907.md` for both outcomes.

Earlier focused stabilization: live isolated internal1001 callback retry passes
`6e1abf/session73991/6fd51b`, including full Gemini confirmation, unanswered first
return, durable retry and second reciprocal agent bridge. Extension1000 read-only
routing passes. Warm-up verifies210 installed Gemini clips and420 running mappings,
with nine services active. See `doc/development_warmup_20260907.md`.

Bridge permanent-message quarantine in verified quorum mode passes145 offline
tests and actual isolated broker DLQ/continued-acceptance proof
`51559a/session54486/3e77be`. Legacy behavior remains unchanged; no production
pushes. See `doc/push_bridge_permanent_quarantine.md`. Main-SH deployment
`e1b349/session76962/b94ad2` passes; release51d97e626ef2, active PID423856,
NRestarts0. Transient recovery/freshness/phones stay OPEN; dev routing unchanged.
Independent main-SH verify-only also passes `55f252/session16031/cbbb2c`.
INST-13 freshness audit confirms native Kamailio pushes carry no trusted event
time; explicit additive producer metadata is required, not an Expires/timestamp
guess. Also reproduce/fix the optional four-argument AMQP header-buffer lifetime
finding before using that path. Neither is a reproduced live crash. Details in
`doc/push_bridge_delivery_recovery_plan.md`.

Latest voice checkpoint: **404/584 recordings pass technical QA** (EN31,
HE84, FR160, ES25, AR104). All584 planned identities have had an initial
attempt;180 remain FAILED, with no PENDING or REQUESTING entries. Historical
requests676, cumulative retries92. This checkpoint adds65 successful Arabic
recordings/130 WAVs without regenerating any earlier success. Full five-language
cardinal packaging, listening review and runtime deployment remain OPEN.
See `doc/acdc_cardinal_ar_initial_completion.md`. Gemini remains authoring-only.

Latest bridge/installer checkpoint: explicit quorum topology and live broker
verification are implemented, all132 bridge tests pass (`37a62e/fb9511`), and
isolated actual RabbitMQ declaration/confirmed-publish/DLQ readback/unsafe-policy
refusal pass (`852b0d/f8265c`). Main-SH deployment `eddec8/cdcd63` and separate
verification `e02540/9a1a1c` pass; active consumer PID381466, NRestarts0, release
`734ca0203eff1bc9da4ca4932d2375ce404b187b0c399222f3ae33edb6217880`.
Current dev binding remains isolated legacy; production unchanged. Temporary
test vhosts/users were removed, protected receipts retained. Retry/expiry,
broker failure recovery, remote TLS and real devices remain mandatory OPEN.
See `doc/push_bridge_quorum_topology.md`.

Final checkpoint regression `0fad16/session97479/43a0e0` passes installer syntax,
pins, aliases, modular/security/ALL/error paths, bridge dispatch and43 effective
Kamailio endpoint cases. Voice preservation/hash/SoX verification passes
`4e6f91/session99094/fbe779`. These fixtures do not replace fresh-server or
real-device release acceptance.

INST-03/08 focused distributed-Kamailio fix passes43 fixtures and modular tests.
Verification now follows the effective URI host/port/vhost and never substitutes
unrelated local broker queues for remote evidence. Actual `--verify-only kamailio`
passes those endpoint/queue/SBC checks but still FAILS the unmodified journal
gate on4 earlier malformed SIP replies with missing/invalid Via. Their origin
is unproven; no logs/gates were removed or Kamailio restart performed. See
`doc/kamailio_effective_amqp_verification.md`. Nine checked services are active.

Latest September7 checkpoint: prerecorded cardinal inventory is339/584 QA
(EN31 HE84 FR160 ES25 AR39),553 historical requests and92 cumulative retries.
New concise-recipe experiment saved4 HE recordings/8 WAVs;2 HE and4 AR attempts
still returned incomplete output. Diagnostic HE attempt2 returned OTHER with
zero audio/text parts. No provider root cause or listening/runtime completion
is claimed. Failed: HE47/FR1/ES28/AR46; AR123 still initial-PENDING. Preserve
FR89's six failures; no seventh request/history reset is permitted by current
policy. See `doc/acdc_cardinal_concise_synthesis.md`.

All-locale installer adapter is implemented and offline-tested, not activated by
main SH: all five complete sources/maps are required before writes, then fresh
584-role verification. Guard `6a52f3/e5dc60` passes15 verifier groups/4926
assertions,18 generator groups/299 checks and retained/new adapter cases.
Importer3890 checks and actual unchanged EN plan pass `6302ed/15cc5d`.
Missing nonEN recordings/maps, listening, runtime integration and deployment
remain OPEN. See `doc/acdc_cardinal_all_locale_adapter.md`.

Production10.1.0.28 remains read-only; its FCM/APNs configuration is already
stored outside Git. Dev bridge active/running, NRestarts0. Quorum topology is
implemented and tested as described above. Remaining provider retry/freshness
work is tracked in `doc/push_bridge_delivery_recovery_plan.md`; topology tests
are not proof of Android/iOS phone delivery.

The snapshots below are historical where superseded by this checkpoint.

Bridge AMQPS support is deployed through main SH (`1ff54f/02ae6d`) and separately
verified (`9f2d32/f1ad28`). All112 bridge tests plus installer dispatch pass;
active consumer PID323748, zero automatic restarts. Production untouched;
local development binding remains isolated/plaintext. Remote TLS and real phone
delivery, durable recovery and whole-operation deadlines remain open. Five-locale
cardinal-media preflight also passes12 EUnit groups and production/TEST compile
(`0d2bfe/b60ebe`); actual nonEN maps and dispatch are not activated.

Current September7 follow-up: actual thirty-second callback-offer acceptance
PASS `2d290a/session16292/db354d`. Complete built-in EN audio at30.054/60.054s,
quiet pre-offer wait through29s, no extra offer, unchanged services, zero scoped
errors/new cores; marked test queue/callflow conditionally cleaned. See
`doc/acdc_callback_thirty_second_acceptance.md`. This closes that timing slice,
not combined position/MOH, all-language playback or production acceptance.

Voice inventory now335/584 QA (EN31 HE80 FR160 ES25 AR39);542 historical
requests,85 retries, no indeterminate attempt. All131 initial HE identities are
attempted; HE51, ES28, FR1 and AR42 are FAILED; AR127 still initial-PENDING.
Last three AR batches stopped on provider HTTP500. All38 new recordings/76 WAVs
since17946f2 are preserved, with whole-ledger/old-success/readback verification
`9c74e0/session36821/e854e2`. No new cardinal runtime activation or listening
approval. All later sections below are historical unless explicitly updated.

Latest16:16UTC: bridge OAuth transport fix deployed via main SH and separately
verified (`3f5035/aa39ab`, `67c5ba/a1b50e`);103 bridge tests and installer dispatch
PASS. Service PID301642 active, zero automatic restarts; all8 checked services
active. No production change or provider notification. Total deadlines,
durable recovery, AMQP TLS and real phone delivery still required.

Voices:297/584 cardinal recordings pass technical QA (EN31, HE59, FR160, ES25,
AR22), plus both new intros. All prior attempts/successes preserved and repo
matches private origin; no pending provider process or indeterminate attempt.
Remaining initial roles: HE35, AR176. Failed: HE37, FR1, ES28, AR10; FR89 reached
6-attempt cap and needs a reviewed recovery decision, not history reset.
All210 new WAVs since fe02eb0 are saved. Five-locale staging importer passes
3890 checks; real full-pack import/runtime, listening and playback remain OPEN.

Voice checkpoint September7: new HE/AR introductions generated successfully
once and saved as four WAVs; independent offline hash/SoX verification PASS
`b13129`. Source-backed language reviews are recorded; no listening approval
is implied. HE first32 number requests yielded25 QA/7 incomplete; all50 new
WAVs and history preserved. Five-locale authoring pin and EN installer pin are
aligned; actual EN plan retains its exact map. Explicit bounded failed-only
recovery passes16 generator groups/260 checks plus2542 verifier assertions
`4f8aa5/4bdc8c`. See `doc/acdc_cardinal_he_ar_authoring_20260907.md` and
`doc/acdc_cardinal_bounded_recovery.md`. Remaining generation, listening,
five-locale import/runtime and live playback remain OPEN.

INST-13 credential-source clarification: FCM/APNs configuration from production
10.1.0.28 is already copied to protected local files, not Git. Repeat main-SH
`--verify-only push-bridge` passes `8c6713/session38308/7f467d`; active/running,
zero automatic restarts. No new production connection or provider notification.
Real designated-device delivery and the remaining reliability gates stay OPEN.

Latest voice follow-up: FR138/161 recordings pass technical QA;23 failed after
two bounded attempts, no FR jobs remain unattempted or indeterminate. All200 new
WAV files since fdb88cd and six authoring receipts are preserved in the repo.
Offline manifest/hash/SoX verification passes `2bf797/f06077`. Exact failed
IDs and evidence are in `doc/acdc_cardinal_fr_authoring_20260907.md`. EN31/ES25
unchanged; HE131/AR208 review and authoring, FR/ES recovery, listening, complete
five-language packaging and cardinal runtime deployment remain OPEN. Existing
210 fixed/digit clips and callback playback are unchanged. No runtime Gemini.

Latest bridge follow-up: exclusive reusable FCM HTTP leases and worker-count
pool cap are implemented/tested/deployed. All88 bridge tests plus installer
dispatch pass `0f958e/5f962f`; main-SH deployment `01728e/abcc83` and separate
verify-only phase `5a5172/b0c93a` pass. Enabled active consumer PID259472,
automatic restarts0; old release retained. No production or mobile-send changes.
The shared-session concurrency gap is closed for FCM sends. OAuth/whole-send
deadlines, durable retries/recovery, AMQP TLS and real test-device ringing
remain mandatory INST-13 gates.

External-route compatibility rerun also PASS on the same updated harness:
`c26844/session62944/efcaac`, `/var/log/kazoo-acceptance/20260907T153203Z`.
This is the isolated loopback carrier, not actual PSTN. Fixture remains retained.

Latest15:30UTC callback follow-up: internal1001 live retry diagnostic PASS
(`b6e938/session58987/493a66`, `/var/log/kazoo-acceptance/20260907T152609Z`).
Single6, complete Gemini confirmation before hangup, busy-call release2s later,
unanswered first native return, durable retry_wait and second confirmed return
bridged to the agent all pass strict SIP/RTP validation. Agent returns ready;
service state unchanged, scoped errors0/0 and new cores0. Fixture retained;
operator MicroSIP1000 and full cleanup/production acceptance remain OPEN.
Harness now tests internal vs external routes explicitly and preserves both
INVITE Via headers in the unanswered native endpoint. No new runtime deployment.

Current cardinal asset counts supersede the older snapshot below: EN31 accepted,
ES25 accepted/28 failed, FR38 accepted/14 failed/109 pending, HE131 pending and
AR208 pending. New48 French WAV files and authoring history are preserved for
Git; no successful clip regenerated, no runtime/provider integration introduced.
Listening, remaining authoring and new cardinal runtime deployment remain OPEN.
Offline accepted-file hashes/SoX conversion verification passes
`ad0253/516fa8`, no provider access. All affected callback helper/48 unanswered/
88 retry/96 confirmation/32 carrier-payload/13 cleanup groups and shellcheck
pass `679ac2/c90d95`; the same run's relative-path artifact invocation was
rejected and separately rerun successfully with the required absolute path.

Latest execution checkpoint September7: bridge installed through main SH with
hash-pinned dependencies, protected copied FCM/APNs keys, enabled non-root
service and actual local isolated AMQP consumer readiness; independent verify
passes. Production10.1.0.28 remains unchanged. No real mobile sends/acceptance.
Extension1000 internal caller ID is configured; four account-local callback
modules are deployed with exact disk/runtime verification. Current account
request probe authorizes1000 and builds one native endpoint; actual internal
ringing/confirmation/retry remains open. Source passes29 internal/external
policy tests, full canonical87 and13 production-module build. All five pure
cardinal grammars pass73240 parity cases; EN31 immutable assets are imported,
ES25 and FR14 generated plus two Spanish reuse identities. Remaining language
assets/runtime still incomplete. `/apis` now documents internal callback routing.
External-route live regression passed after deployment (7cfb8b): single6,
complete Gemini confirmation before hangup, unanswered first attempt and second
attempt connected to agent; zero scoped log errors/new cores. Evidence:
`/var/log/kazoo-acceptance/20260907T144250Z`. Test fixture retained; not internal
1000 live acceptance, complete cleanup or a production release pass.
See latest PROJECT_HANDOFF.md and doc/push_bridge_development_acceptance.md.

Bridge follow-up: FCM3xx and unused response bodies are now rejected/closed
before redirect processing. Six pinned-Requests transport tests pass, as do
all79 earlier bridge regressions and main-SH dispatch. Main-SH redeployment
515d94/1f29eb passes with enabled active consumer and zero automatic restarts.
OAuth refresh/total deadlines, shared HTTP session concurrency, durable retries,
AMQP TLS and designated-device mobile ringing remain INST-13 release gates.

New or returning contributors: read [the engineering handoff](PROJECT_HANDOFF.md)
first for achieved work, deployment status, source locations and next steps.

## Handover checkpoint — 2026-09-07

### Operator priority correction — 2026-09-07 (supersedes older priorities)

Latest clarification: mobile bridge remains **critical**, alongside callbacks,
the five prerecorded Gemini language packs and deployment-script fixes. Only
dashboard work is postponed; do not read the brief focus narrowing as dropping
bridge delivery or any mandatory installer/release requirement.

**Operator reaffirmed September7:** Gemini is permitted only for the one-time
authoring of missing release recordings. Reuse the completed WAV artifacts;
never call Gemini during installation, startup, queue editing, account or
sub-account creation, or calls. The supported built-in languages remain exactly
EN/HE/FR/ES/AR. No service/runtime TTS dependency or provider-key requirement may
be introduced. This is a development system; the operator explicitly permits
service restarts needed for implementation, deployment and testing. Preserve
account/configuration data and inspect current calls before disruptive changes;
do not treat restart permission as a reason to repeatedly ask for approval.

The operator clarified that ONLY historical dashboards were postponed. The
previous interpretation pausing callbacks and voices was incorrect.

1. **Priority 1: callbacks and built-in Gemini voices.** Finish key-6 handling,
   durable registration, confirmation audio, independent offer interval,
   valid-destination return calls and unanswered-first-attempt retries. Complete
   EN/HE/FR/ES/AR prerecorded female packs and language selection/inheritance;
   generate missing artifacts once, commit WAVs, and require no Gemini at
   install/runtime. Deploy matching code/UI/media and prove actual playback.
2. **Deployment and modular installer:** resolve coherent build/deployment gaps,
   service readiness and fresh standalone/distributed/ALL installation acceptance.
3. **Mobile bridge:** finish the sanitized import and reviewed installer/service
   integration, including isolated failure/retry and ringing acceptance. Do not
   mutate the production source server or send production notifications.
4. **Mandatory release gates:** security/TLS, supervision/API acceptance,
   30-concurrent-call load, recovery/restore and all other open requirements stay
   in scope; none is waived by this ordering.
5. **Dashboard work postponed**, retain existing live work and outstanding
   acceptance. Historical dashboards remain postponed too; do not resume
   storage/WFM implementation without operator direction.

This ordering overrides the dashboard-only/paused statements in older snapshots
below. Source-tested work is not deployed or accepted merely by reprioritization.

Resumption evidence: canonical callback media-only check `778a35/6d4296`
passed22 tests with current production/TEST compilation and unchanged source
digest on September7; no network/provider/runtime writes. Full lifecycle,
deployment, actual audio and retry acceptance remain open. See newest handoff.

Subsequent root checkpoint: full canonical87 tests pass `fada33/fee8c1`.
Fresh production build and actual loaded MD5 comparison prove all eight focused
callback media modules already match current source (`0ad7ce`); blanket
undeployed claims for that cohort are stale. Actual playback remains open;
the old offer harness needs Gemini rather than legacy reference bytes.
Voice generator no-output/retry fix passes12 groups/177 checks and reproduces
failure with the historical generator. Sanitized mobile bridge import and its
configuration preflight (8 offline tests) are ready to track, NOT activate.
See `doc/callback_media_runtime_parity.md` and latest handoff for exact evidence.

Keep this register current whenever implementation, deployment, testing or a
blocker changes. Each task must retain its stable ID, requested behavior,
source/document locations, evidence, remaining acceptance and next action.
Distinguish source complete, deployed, verified and remotely delivered; do not
close a task on a unit-test pass alone. Older snapshots below are historical;
the latest engineering handoff takes precedence for current deployment state.

Priority1 media checkpoint September7: missing English cardinal31/31 recordings
have been authored once (31requests,no retries) and verified offline. WAVs and
ledger: `scripts/assets/acdc-gemini-cardinals-20260907/`. These preserve the210
existing callback/intro/digit artifacts; remaining locales, composed listening,
runtime integration/import and live position playback are still open. Current
Gemini offer harness offline checks pass; initial live attempt stopped before
SIP because its Couch attachment GET needed explicit JSON content negotiation.
Exact evidence/next action are at the top of `PROJECT_HANDOFF.md`.

Subsequent ES checkpoint:14/53 cardinal recordings technically verified and
preserved;18 identities failed with incomplete provider responses,21 pending.
One bounded number4 retry also failed; its attempt limit is exhausted. No live
media changed and no successful recordings regenerated. See
`doc/acdc_cardinal_es_authoring_20260907.md` for exact durable evidence and
provider-free verification. The complete five-language release remains open.

Gemini EN offer audio now verified from the zero-drop live capture: complete
5.171s phrases at3.114/18.114/33.114s, no early offer, normal46.012s call teardown
(`6071a3/ff00b0`). Exact conditional fixture cleanup passed. This is offer-only
over silence hold, not key6 registration/confirmation/retry or all-language
acceptance. See `doc/acdc_gemini_offer_acceptance_20260907.md`; keep P0 callback
and full language/runtime integration tasks open.

Fresh full EN offer runner subsequently passed `c88ff7/d9b680`, including
service/log/core/worker checks and exact conditional cleanup. Evidence:
`/var/log/kazoo-acceptance/20260907T120840Z`. Only this offer-over-silence slice
is accepted; key6/retry, real MOH, five-language and installer/release gates remain.

Newer callback checkpoint: installed Gemini EN confirmation/retry diagnostic
`f99df0/90042a` passed with a busy agent, key6 then registration1, complete5.491s
success audio before BYE, deliberately unanswered first return attempt,
durable retry_wait and second-attempt reciprocal native bridge. Agent readiness
returned; monitored call-service PID/restart snapshots unchanged, new errors/
cores0. Fixture retained, not full cleanup or production acceptance. See
`doc/acdc_gemini_callback_retry_acceptance_20260907.md`. Keep single-key6 UX,
30-second configured offers, valid user return-number configuration, all-language
playback and release gates open. No Gemini call or restart was needed.

Single-key6 follow-up is source-fixed:17 reducer/22 wrapper tests and strict
harness80+79 checks pass, focused8-module production build passes. Private
OpenAPI regeneration validates the new tracked overlay descriptions. Deployment
and actual entry-only live acceptance remain open; combined control/canonical
validation hit600s before the broad suite finished, so do not claim87 complete
for this candidate. See `doc/acdc_single_key_callback.md`. ACDC remains tracked
directly in kz5 and compiled from there by the installer.

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
- **P0-22 scoped closure:** actual Login confirmation, failed verification-read
  recovery and immediate Logout proof invalidation pass on main (f820d18;
  27 offline groups and browser77891/5350d1). Runtime-only login preserved;
  no other agent changed. Broader authorization/cluster cases stay separate.
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
  **Drain candidate rejected:** root `da512e/184d65` failed4/12 groups by missing
  live paused anonymous wrappers. Relocated manual reproducer `f41056/47cf55`
  repeats the failure. Candidate is quarantined under
  `scripts/erlang-tests/candidates`, not production sources. Actual target
  metadata `2ac240` shows permanent unrelated apply/2 processes, so broadening
  that classifier is not a usable fix. Compare retained sidecar/compatible
  record storage against authoritative role attestation before further rollout;
  requirements and caller/privacy acceptance stay unchanged.
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

**Current priority — corrected 2026-09-07:** callbacks, Gemini voices and their
deployment first; installer and mobile bridge remain mandatory. Live dashboards
are last priority. Historical work remains postponed. See the operator priority
correction above and the latest deployment evidence in PROJECT_HANDOFF.md.

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

### Important UI regression — Callflows → Users entitlements lookup

**UI-03 — FIXED on main, browser verified September8; reported September7 at13:54:21UTC.** Opening the Callflows app
and then Users requests `GET /v2/accounts/302ae5a70c403124f764cbc54229cfcd/entitlements`.
The server returns404 `not_found` with `data.message: not found`; the frontend
shows “An unknown error happened, please try again in a few seconds!”
Correlation request ID: `cb1c717e99cab3b78e149d081d312652`.
The supplied response contains a login token: deliberately excluded from this
register and all repository evidence.
This issue was previously mislabeled UI-02, which already identifies the closed
dashboard wording fix. UI-03 is the unique entitlement-regression identifier.

Resolved missing module registration and the subsequently reproduced master
empty-ancestry crash. Installer registers/verifies/probes the actual endpoint;
root-owned core patch preserves descendant ancestry and capability semantics.
Main master/company GETs succeed, anonymous remains401, actual Users clicks
render1/15 users without captured browser errors or active loading indicator.
Three focused ancestry tests and8 registration cases pass. Broader restricted
principals/enrollment-write cases are not claimed by this fix.
See `doc/callflows_users_entitlements_fix.md` for source, deployment and replay.

| ID | Status / owner | Work and acceptance requirement |
| --- | --- | --- |
| P0-21 | DEPLOYED — restricted-user acceptance open | Corrected legacy module spelling with an admin-only management guard. Installer refuses old unguarded backends and preserves unrelated modules. Installer22groups66cc53/cea08b and backend7groupsbcc947/c5cf88 pass; pinned baseline fails5. Deployment209651/1e3fc6 verifies actual bytes/capability/running+effective registration and unchanged31-agent states. Actual admin policy CRUD revision probe7c9f07/47ce1f passes stale412, weak412 and current-delete200+absence. Earlier run2 policy retained after harness POST-replacement mismatch. Ordinary-user HTTP denial and restricted-dashboard matrix remain unverified. See doc/scope_management_dashboard_acceptance.md. |
| P0-22 | CLOSED — scoped main login-display acceptance | Actual selected-queue Login, interrupted proof GET / Check again recovery and immediate post-Logout table-label invalidation pass on main with exactly one Login POST; other29 statuses/memberships unchanged. Logout stale-proof regression fails before f820d18 and27 groups pass after. Normal installer87070/c84568 and deployed browser77891/5350d1 exit0. Source and retained evidence: doc/queue_login_browser_acceptance.md. Restricted principals, arbitrary stale navigation and live delayed-response reordering remain separate release gates. Runtime-only Login preserved; roster assignment is not login proof. |
| P0-25 | FIXES DEPLOYED — scoped browser PASS; outage acceptance open | September 7 indefinite loading traced to both unbounded GET waits and overlapping native app construction clearing ACDC translations. Bounded GET fix is deployed; installer-owned singleflight patch b02f7fe passes16 actual-loader groups including original failure reproduction. Fresh production MwsDYg bundle deployed ec9a75/9f9af6. Initial dashboard/login-dialog probe passes without page errors3ff064/eefb87; standard default and account-switch production probes pass7/10 checks e5b91d/2241b2 and45576a/e20ac1 with zero page/console/HTTP errors. All four home/switched summary/detail reconnect cases pass7/9/10/12 checks with zero errors; receipts hltOHJ,jDrUgY,hcjYc6,2rApWe. Controlled unavailable-API/late-reply browser recovery and never-settling loader behavior remain open. See doc/monster_app_load_singleflight.md. |
| P0-26 | FIX DEPLOYED — actual create/readback PASS | September 7 repeated PUT /queues/editor400 logged editor_body_requires_exact_fields; actual Monster serializer adds unwanted ui_metadata. Local requestQueueEditor opt-out preserves strict five-field backend body, request identity and explicit retries; eight real-serializer fixture groups pass e412fe. Matching UI deployed6d7352/d9a24c. Actual form PUT created one owned empty-roster/no-extension queue with HTTP201 (7f91f3/816240); harness incorrectly expected200, but completed operation was durably captured. Recovery09a4d6/131789 verified saved settings/empty roster/no callflow, deleted exact owned queue and confirmed404; no create retry. Receipt retained. Validation failures, PATCH and uncertain receipt recovery remain open; normal owned cleanup is not conditional-delete proof. |
| UI-01 | DEPLOYED — selector error fixed; capability gating remains open | Current ACDC Save does not request storage. SmartPBX call-recording/Common plan manager handle absent optional plans, but Common selector had no error completion and crashed on empty successful data. Installer patchf85bb21 fixes these; baseline4/7 failures, candidate7/7 pass including main build source. Normal installer22488/383cf4 and native404 browser33704/37350c pass; visible warning, settled callback, inactive bar, zero writes. Backend404 remains truthful; no dummy storage document or module registration. External-storage configuration/capability gating remain separate. See doc/monster_optional_storage.md. |
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
| P0-03 | DEPLOYED — single-key five-language retry PASS on main | Main44 EN20300/8ddb7e and HE/FR/ES/AR54480/449b40 pass: one digit6, complete installed prerecorded success audio before BYE, first attempt deliberately unanswered, durable retry_wait and second reciprocal bridge. Each locale has2/0 caller and agent results, no fresh errors/cores; zero remaining calls and all30 fixture agents logged out were independently verified. Use doc/main44_callback_acceptance_20260908.md rather than repeat the older EN-only test. This does not close invalid/alternate-number variants, native-speaker approval, HA/soak, or the newer queue-edit language-snapshot case in doc/acdc_callback_language_snapshot.md. |
| P0-04 | DEPLOYED — five-language independent intervals PASS on main | Main44 native EN/HE/FR/ES/AR calls prove complete prerecorded callback offers at30/60 seconds, independently scheduled full position-one audio at45/75 seconds and no offer on entry. Units48661/2cb3e8 and45450/07eef3 exit0; owned queue/callflow cleanup and unchanged services verified. This supersedes the older EN-only/position-disabled acceptance status. Real music-on-hold mixing, wider spoken numbers and failure/overload scenarios remain separate. See doc/main44_periodic_audio_acceptance_20260908.md. |
| P0-11 | DEPLOYED — focused regression verified; broader acceptance open | Announcement worker mailbox starvation: elapsed deadlines run before another receive; bounded pre-playback drains stop the temporary worker after256 handled events plus one overflow probe. Two regressions fail before the fix; all12 scheduler/worker tests pass afterward. Fresh production/loaded MD5 parity0ad7ce proves current acdc_announcements is deployed. Actual EN offers pass c88ff7/d9b680 at3/15-second settings over silence hold. This does not close real MOH, all-language, overload or actual30-second acceptance. See doc/acdc_announcement_mailbox_fairness.md and doc/callback_media_runtime_parity.md. |
| P0-12 | DEPLOYED — canonical regression/runtime parity verified | Removed synchronous auxiliary metadata lookup from timed unavailable/retry/alternate branches. Built-in preflight retains its three auxiliary paths from42 reads; legacy custom menus preflight three optional assets before queue entry. Missing cache fails quietly without fallback or false registration. Full87 tests pass fada33/fee8c1, including poisoned datastore/resolver access,30ms budgets and21s ownership/completion cases. Fresh production/loaded MD5 parity0ad7ce proves this callback cohort is deployed. Actual EN offer and6+1 retry slices pass; arbitrary synchronous publishing, native audio alternatives and all-language/failure acceptance are not implied. See doc/callback_media_runtime_parity.md. |
| P0-05 | OPEN — ACDC | Agent stability: one answered call must not log unrelated agents out. Test failed ringing, reconnect, queue-specific logout, pause/resume and reboot recovery. |
| P0-06 | OPEN — ACDC | Resolve retained ambiguous callback cleanup/reconciliation ticket without losing evidence or falsely marking a live leg settled. |
| P0-10 | DEPLOYED — single-key success/retry PASS; fallback variants remain open | Original badarg fallback crash has typed/lazy lookup fix and 17 feedback regressions (baseline22426, fixed9643). Later deployed single-key6 runs prove durable registration, complete prerecorded success audio before BYE, unanswered first callback, persisted retry and second native bridge: EN1297/784164, HE8443/53f15d, FR15515/f1b8d1, ES37303/93b8d4, AR56725/d5de4c. This supersedes the old claim that deployment and every live path remain untested. It does not prove every invalid-number/unavailable branch or settle historical ambiguous tickets. See doc/callback_feedback_request_crash.md and doc/focused_acceptance_20260908.md. |
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
| ACDC-01 | NATIVE MASTER-ADMIN API AND BROWSER SAVE PASS — broader auth/recovery open | Unified queue create/edit/read. Main-host51137/e145bc passes actual create/edit/replay/conflict and all-five language persistence. Later deployed browser97969/d810a2 passes six actual writes: create EN, save HE/AR/FR/ES, then disable callback; fresh reads and reopening confirm persistence with no browser errors or stuck bar. This supersedes the earlier read/select/cancel-only limitation. Restricted principals and live uncertain-write recovery remain open. See doc/queue_editor_acceptance.md and doc/queue_browser_save_acceptance.md; do not repeat successful saves without a new defect. |
| ACDC-02 | OPEN — UI | Reliable Callflows ACDC action and internal extension routing; dropdowns instead of technical free-text fields; default prompt selection must not trigger required-field errors. Preserve existing customer recordings. |
| ACDC-03 | OPEN — ACDC | Verify/build supported ring strategies: ring-all, ordered, round-robin and existing alternatives. Resolve simultaneous-answer/DTMF exit ownership candidates; test fairness, single winner and cleanup. |
| VOICE-01 | OPEN — media + UI | Finalize EN/HE/AR/FR/ES prompt-language override, queue/call/account defaults and reseller/sub-account inheritance; report incomplete packs rather than enabling unverified choices. |
| VOICE-05 | DEPLOYED — five-language single-key registration audio/retry PASS; broader composition open | Immutable built-in callback media and recorded digits are deployed; no runtime Gemini requests. Full87 canonical regressions pass fada33/fee8c1. Later EN/HE/FR/ES/AR runs listed in P0-10 prove exactly key6, complete locale-specific installed success audio before BYE, durable retry and second bridge. Receipt readback0aa77b confirms PASS and only digit6 for all five; evidence is now archived root-only on .44 (see focused acceptance). Complete prerecorded position/MOH composition and all alternate responses are separate; additive returned-confirmation HE waveform proof failed strict packet coverage and is not silently counted as passed. See doc/focused_acceptance_20260908.md. |
| VOICE-02 | VERIFIED — generated assets and installer byte check | Existing165 effective Gemini entries /330 WAVs remain unchanged. September6 supplemental generation completed45 missing callback clips /90 WAVs in47 requests (two French digits retried once, previous failures retained). Combined immutable lookup210 assets /420 WAVs, committed0904240. Actual installer media-import19674 verified210, preserved210 and created0; nonsecret receipt at /usr/local/share/kazoo5-installer/acdc-gemini-media.json. This is not runtime mapping activation, five-language playback certification or complete prerecorded queue-position speech. |
| VOICE-03 | DEPLOYED SHARED ARTIFACTS — broader language acceptance open | Shared fixed/cardinal packs are checked into kz5 and installed on .44 through the normal SH; retained runtime proof covers796 media documents and1,592 mappings. Main-host all-five callback success/retry passes; periodic offer/position validation is tracked in VOICE-MAIN44-SCHEDULE-01. Native listening, wider spoken numbers/wait-time/alternate-response call paths and explicit new-account/sub-account inheritance acceptance remain open. Never generate during installation, account creation, queue editing or calls. |
| VOICE-04 | HISTORICAL AUTHORING AUTHORITY — no generation job active | September6 authorization allowed one-time authoring of missing release WAVs; those saved assets are now in the deployed fixed/cardinal packs. Reuse them without provider credentials. This row is not a request to regenerate completed clips or introduce runtime TTS. Native language review and remaining call-path gates are distinct from generation. |
| VOICE-06 | DEPLOYED — five-choice selection AND SAVE/RELOAD PASS; inheritance open | One Queue language dropdown offers exactly EN/HE/AR/FR/ES with separate callback/position interval controls. Earlier browser0b7f2c proves selection/cancel. Later isolated-fixture browser97969/d810a2 proves actual create/save for all five languages and fresh readback, then callback disable and reopening ES with generic17/callback30 intervals. No copied-company writes, browser errors or stuck indicator. See doc/queue_browser_save_acceptance.md. New-account/sub-account inheritance, every prompt branch and native pronunciation remain separate gates; this row no longer treats Save as untested. |
| VOICE-07 | DEPLOYED IMMUTABLE PACK — full linguistic/call-path gate open | Fixed/numeric/auxiliary release assets, PCM16 masters, telephony WAVs, transcripts, provenance and hashes are retained in Git. Normal .44 installer validates796 installed media documents; read-only native preparation10b220 reuses the installed/source-pinned packs with0 provider requests. Five-language callback success/retry is measured separately. Full natural-female-voice review, wider number/telephone composition, all auxiliary responses and wait-time audio remain unproven; no broad linguistic certification. No native robotic SAY or mixed-voice fallback may substitute for missing built-ins. Missing artifacts fail readiness/installation, never trigger online synthesis or require a provider key. Do not regenerate completed assets. |
| VOICE-08 | DEPLOYED CANONICAL SOURCE — distributed/inheritance acceptance open | ACDC, prerecorded maps, shared WAVs, import/readback logic and installer wiring are tracked in kz5; .44 has no nested ACDC Git metadata. Normal apps/eCallMgr deployment and actual runtime media/map proof passed; all-five callback success tests retain the selected language. Explicit new-account/sub-account inheritance, every response path and separated apps-node installation remain required. A passing single-host install does not close distributed deployment or all language-context paths. |
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
| INST-13 | PASS — fresh/repeat/reboot, remote TLS install and idle recovery; broader failure gates open | Main SH supports push-bridge/aliases/ALL. Fresh .44 install71358/87daf7, normal ALL48019/6236b8 and reboot76710/8722b4 pass. Protected provider files, locked dependencies, non-root service and registered consumer verified. Synthetic native retry83390/9d4620, unavailable-DLQ retention52763/f08152 and remote TLS consumer6035/ef7ad0 pass. Later normal cross-host installed-service deployment/restoration65096/3e586e and idle broker outage/same-process reconnect53408/858b7f pass. In-flight native child42712/afe573 exits78 after AMQP loss, retains its body and makes no second HTTP POST: containment, not automatic recovery or installed restart-policy proof. Fresh remote-topology reboot, post-response settlement loss, filled-DLQ behavior, HA and production routing remain open. Physical FCM/APNs delivery is user-WAIVED. See doc/push_bridge_remote_tls_acceptance_20260908.md. |
| INST-01 | PASS — measured fresh/repeat/reboot scope | One modular main SH supports all nine roles including bridge and ALL. Normal fresh roles, repeated normal ALL48019/6236b8 and post-reboot independent ALL76710/8722b4 pass, with source fixes for restrictive umask, dependencies, readiness, standalone catalog routing and delayed IP assignment. See doc/fresh_host_tls_acceptance_20260908.md. Arbitrary topology, HA and production capacity are not certified. |
| INST-02 | VERIFIED — current/fresh/reboot scope | All nine named services enabled/active, zero automatic restarts after second fresh reboot (a833e2); `kazoo-applications` alias and SUP pass. Pivot port reservation and previous test-phone preservation fixes retained. Custom-root and remaining topology variations are separate acceptance. |
| INST-03 | VERIFIED — fresh and current SIP integration | Fresh normal FreeSWITCH/Kamailio62607/2c4b73 passes SIP OPTIONS, eCallMgr link, dispatcher, exact AMQP endpoint/consumer queues, module inventory, database/RPC and JWT-cache/journal checks. Combined fresh66513/f83cde, post-reboot76710/8722b4 and current66591/18787a ALL verification have finished successfully, not still running. No live-call/capacity claim from these probes. |
| INST-04 | DEPLOYED — fresh build and actual browser pass; outage cases separate | Normal fresh .44 UI96182/c9749c built/published matching backend/catalog/assets. Actual login/browser48355/8df633 and later HTTPS/UI fixes81343/73a371 plus20021/2b3a50 pass without API mocks. Company-switch browser90232/e44a28 covers SmartPBX, four ACDC queues and exact API counts. The earlier72306/15995/88551 artifact and mocked recovery results remain historical evidence, not the latest deployment state. Controlled unavailable-API/late-reply browser recovery remains P0-25; see fresh-host and dev44 HTTPS/company reports. |
| INST-05 | VERIFIED — fresh and real repeated combined build | Post-build artifact verification is wired before activation and included in the fingerprint; modular fixtures with/without ACDC pass. eCallMgr current-invocation build reuse, environment reset and failure-before-activation regressions retained. Actual fresh apps/eCallMgr23557/5db474 and normal repeated ALL48019/6236b8 complete dependency/core/app compilation, release and production-BEAM checks; shared same-invocation eCallMgr reuse is exercised. Arbitrary concurrent source changes/crash-atomic publication are not certified. |
| INST-06 | DEPLOYED — restart-based development rollout; rolling-upgrade gate open | Matching backend/UI are published through normal apps/eCallMgr48353/f4275e on the original dev host and fresh/repeated .44 ALL48019/6236b8, independently verified after reboot76710/8722b4. Earlier old-code probe29950 and UI hold are superseded. Native conversion/timer/pause/refusal tests17426 and isolated old/new replacement41876 remain evidence for the source fixes, not proof of a live clustered rolling upgrade. Multi-module hot replacement, admission/drain under live load and cross-node state preservation remain unverified; see doc/acdc_coherent_upgrade_readiness.md. |
| INST-07 | PASS — measured fresh/repeat/reboot and split-UI scope; matrix open | Rocky9.8 .44 normal roles, combined ALL, repeat install and second reboot/post-boot ALL pass. Split UI to original apps passes pinned SSH catalog/HTTPS API; subsequent local UI creates ten missing catalog entries. Actual fresh browser login/API/WebSocket passes before and after reboot. Remaining fully separated-role/upgrade/failure-recovery matrix is unverified. Evidence: doc/fresh_host_tls_acceptance_20260908.md. |
| INST-08 | ACTIVE — staging acceptance | False-success checks fixed in code: RabbitMQ selected-vhost permissions/exact AMQP bind (65 runtime + 32 password cases pass); external UI API envelope and early API/WebSocket validation (71 cases + main ALL smoke pass). No-route fallback fixed; dry-run no longer claims live validation. Read-only/modular/runtime-config/12 UI wiring groups pass. Actual separated-server connection/install acceptance remains required. |
| INST-09 | VERIFIED — source transition scope | Main installer now handles clean/current/known-previous Blackhole and Crossbar integrations with explicit old-to-new patches, protected private preflight and final full-patch checks. Session 36178 passed all 42 tests against the extracted actual installer helper, then the main installer smoke: partial/unsafe states and staging failures stop without target changes, unrelated edits survive, repeat install is unchanged, inherited Git redirects are isolated. See doc/installer_source_transitions.md. No live checkout upgrade, clean-server deployment or crash-atomic filesystem guarantee; those remain INST-06/07. |
| INST-10 | VERIFIED — mod_kazoo source transition scope | Fixed repeated-install failure from overlapping individual patches by validating the complete integration, preserving unrelated edits and refusing partial/unknown source. Added module-only version namespace fix and rebuild fingerprint. Run 46313 passes 15 actual-helper cases, including independent all-13-patches/aggregate equivalence and linked/missing/out-of-inventory rejection; 33997 reruns all 42 Blackhole/Crossbar cases successfully. See doc/mod_kazoo_version_namespace.md. Real fetch/checkout, native linking and clean/distributed install remain INST-01/06/07, not certified by these fixtures. |
| INST-11 | VERIFIED — local Git fetch/checkout scope | Reproduced fresh-fetch false success under conditional helper callers in 72775; explicit error handling and exact pinned HEAD verification fix it without forced reset or discarding conflicting edits. Run 79712 passes ten actual-Git local repository cases, including failed fetch, retry, branch clone and dirty-source preservation, then main installer smoke. See doc/installer_git_sync_acceptance.md. GitHub authentication/network availability and fresh/distributed deployment remain open. |
| INST-12 | DEPLOYED — forced-build/source checks retained; atomicity open | Installer forces Erlang recompilation and selected number/MIME regeneration despite restored input mtimes or future-dated artifacts; content snapshots reject changed inputs/artifacts before same-invocation ecallmgr reuse. September6 Make/erlc fixtures remain valid evidence (doc/installer_build_identity.md). Full fresh23557/5db474 and repeated ALL48019/6236b8 builds now pass, including immutable prerecorded media and native runtime checks; deployment is no longer held by the earlier voice-build gate. Concurrent mutation/crash-atomic build/deploy snapshots and broader linguistic readiness remain separate unproven requirements. |
| SEC-01 | DEPLOYED — original and .44 HTTPS/WSS PASS; renewal open | Original-host TLS90345/4232b3 and browser72297/af0738 pass. New .44 hostname kz5-dev.talkchief.io independently deployed50206/267490; ten catalog URLs migrated with CAS receipts; real normal-TLS browser90351/a3c1e3 and subsequent20021/2b3a50 pass HTTPS API/WSS and UI. Tests route that hostname to private .44 without bypassing certificate validation; public-IP certificate validity is not claimed. Renewal lifecycle remains unverified. See doc/dev44_https_acceptance_20260908.md. |
| SEC-02 | OPEN — operations | Network exposure, least privilege, secrets, SELinux policy, auth/tenant isolation, audit logs, backups, retention, monitoring/alerts and resource/disk limits. Do not equate active services with enterprise certification. |
| LOAD-01 | BOUNDED CONCURRENCY PASS — broader load/soak open | Main .44 1/5/10/20 stages passed earlier. Source8a5329b30+5 run76609/e61e37 terminal exit0:35/0 caller and35/0 agent counts,180s simultaneous hold,bidirectional RTP30 endpoints,zero file/journal errors/cores. Browser20147/40da16 passes during load; cleanup0calls/PID0. Peak sampled host CPU28%,minimum available memory20693076KiB. Failed earlier10423 evidence retained. See doc/main44_call_acceptance_20260908.md. At2 call starts/sec, not30/80CPS, long soak, HA or old-host incident closure. |
| HA-01 | OPEN — acceptance | Backup/restore, failure injection, multi-node ownership, distributed queues/broker/database failover, reconnect and no duplicate callbacks/bridges. |
| REL-01 | OPEN — release | Review and credential-scan all task changes, commit source/tests/assets/docs and record exact build/test evidence. Update this register rather than marking untested features done. |
| REL-02 | ACTIVE — reviewed master checkpoints pushed; release pending | Protected GitHub authentication is verified. Latest prior checkpoint9288a780cd034373b1bcc2fb472fa5bd751b0d02 pushed to master and independently read back73e135; earlier b190ba7 and27e7c69 are also remote. Continue explicit reviewed staging, credential-free scans, commits and verified non-force master pushes. New dirty candidates are not automatically included or accepted. Full requested release remains open. Select provider-specific credentials from protected storage without printing/committing them; never reuse the exposed chat token. |

## Work order and release rules

1. Callbacks and the five built-in prerecorded language packs are first:
   complete remaining announcement/response/language acceptance. Preserve
   already verified main-host key6, retry and audio results; no runtime Gemini.
2. P0 live acceptance without interrupting operator calls or changing rosters
   without an explicit selection; queue-login API and UI ship together.
3. Correct production UI build and installer gates; matching deployment/browser
   checks; complete language handling without recurring TTS calls.
4. Mobile bridge remains mandatory as an installable stack role, alongside
   clean/distributed installation, security, sustained load, restore/failover
   and authenticated release. The physical-phone push check was user-waived;
   do not turn that waiver into a provider-delivery pass or waive other gates.
5. Live queue summary/detail dashboards are the lowest priority, after the
   callback/voice/installer/bridge work. Historical dashboards, separate agent
   history and workforce reports remain postponed for future ClickHouse work.
   Do not promote older dashboard-first plans over the operator's correction.
