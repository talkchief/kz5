# Kazoo 5 acceptance status

Latest progress review: 2026-09-05 13:17 UTC. **Acceptance is incomplete. Do not treat
active services or this document as production certification.**

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
