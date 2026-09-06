# Post-reboot acceptance — startup repairs verified, wider acceptance in progress

Queue-login API documentation source is committed as `22b5f94`: the opt-in
runtime-only request, pending POST acknowledgement and fresh GET membership
proof have nine focused groups / 45 positive-negative schema cases passing.
The generated `/apis` artifact and live endpoint are not yet updated by this
source commit. Existing enrollment mutation remains explicitly separate.

Subsequent generation promoted the three changed static assets to the repository:
354 paths / 649 operations, one changed queue-login route and six new schemas.
The full offline documentation suite passed deterministic regeneration, schema
checks and tamper detection, and the focused queue-login suite again passed all
nine groups / 45 cases. New target-path protection (commit `2316f27`) also
rejects symlinked ancestors above `/apis` and hardlinked destination assets;
the regression tests confirm the unrelated linked file is left unchanged.
This is repository artifact acceptance, not live publication or browser proof.
Receipt: `/usr/local/src/kazoo5-installer/queue-login-ui.wAuMpU/docs-full-tests-afb551798339.json`,
SHA256 `2d15cc187340fa85af7045eb95ec00116621324b94591f56714c653afbc35a53`.

After the ACDC direct-source handoff, root revalidated the current artifact in
session `84398` (exit 0): 354 paths, 649 operations, deterministic rebuild,
schema negatives and tamper detection passed. All 120 input fingerprints and
111 source-inventory fingerprints match the current checkout. Focused session
`97556` also exited 0 with nine queue-login groups / 45 schema cases. The pending
artifact delta changes only the agent `queue_status` route and adds six related
schemas; no unrelated path/schema was removed or changed. These generated
assets are being committed in kz5; the route still explicitly says it is not
live-deployed. No `/apis` publication or endpoint activation occurred.

Current artifact SHA-256 values:

```text
d1f180cd88929ca0208d370a30bc93628f6253e856580625048752124f01f81f  openapi.json
df343c480adee7754af5bbbfb1703f83e151bafd44255e6668717108050e3a2a  coverage.json
3c4d20e54aefc7968122d861f9be4a380e2953f1571c546751eb131c58cc070d  manifest.json
```

The callback-offer PCAP checker now rejects missing packets throughout the
observed audio timeline, not only inside the expected spoken phrases. Twenty-six
synthetic gates passed in a 30-second resource-capped invocation, including
loss before, between and after expected phrases, plus missing, duplicate,
nonzero-loss and empty tcpdump completion summaries. The live checker requires
one complete zero-kernel-drop summary before analyzing audio. This strengthens absence
evidence; it does not prove native hold resumption, the operator's 30-second
configuration or successful live callback delivery.

Further root review of the immediate-audio candidate found a native boundary
not exercised by its 58 offline cases. `ecallmgr_call_control:insert_command`
executes immediate playlists synchronously. `mod_kazoo:call/2` has a 5,000 ms
timeout, while the native synchronous command handler directly runs
`switch_ivr_parse_event` and the playback application before replying. On an
unbridged queue call, `play_app` selects playback even with `Leg=A`. A prompt
longer than the RPC deadline can therefore time out before playback completion;
the call-control process also cannot handle another command while waiting.
Source paths: `applications/ecallmgr/src/mod_kazoo.erl`,
`applications/ecallmgr/src/call_control/ecallmgr_call_control.erl`,
`applications/ecallmgr/src/call_cmd/ecallmgr_call_command.erl`, and the pinned
FreeSWITCH `src/mod/outoftree/mod_kazoo/kazoo_node.c` / `src/switch_ivr.c`.
Candidate build/hotload is held for correction and native ownership/ordering
proof. Neither longer timeouts nor truncating prompts qualifies as resolving
the required responsive bridge/ownership behavior.

Observed boot ID: `bdfdd845-3cb5-4578-a2db-43584aabd9a9`.
The server began an externally initiated reboot at 2026-09-06 01:31:04 UTC.
No agent cancelled the reboot or bypassed the validation guard. Work resumed
at 08:20 UTC after systemd reported no pending jobs. Earlier process-ID and
empty-crash-log checkpoints do not certify this boot.

## Original reboot failures (retained evidence)

- All eight requested platform services started automatically with zero systemd
  restarts. `kazoo-applications.service` still resolves to `kazoo-apps.service`.
  This is an observed reboot, not a controlled clean-install/HA test.
- The applications crash log contains 3,647 bytes from Pivot startup failure
  at 01:33:24. Pivot attempted its configured/default TCP port 34512 and received
  `eaddrinuse`. At 08:23, eCallMgr PID 1558 had the established outgoing AMQP
  connection `127.0.0.1:34512 -> 127.0.0.1:5672`; no Pivot listener existed.
  The kernel ephemeral range is 32768–60999 and its reserved list was empty.
  This is a port-allocation collision, not proof that a second Pivot was running.
- The test-phone service failed five restarts during boot. Its initial attempts
  preceded API readiness; later attempts tried the old automatic logout path.
  Its preservation marker was only in `/run`, which does not survive reboot.
  The operator's one-agent queue must not be expanded or its statuses reset as
  part of restoring SIP registrations. At the first checkpoint the test service
  had no main PID; it was the sole failed systemd unit.

The proposed port repair reserves the exact Pivot ports before node startup and
preserves other reservations. Linux excludes reserved ports from automatic
allocation but still allows explicit binding; writing the setting replaces the
whole list, so additive merging is required. See the
[kernel IP sysctl reference](https://docs.kernel.org/networking/ip-sysctl.html#ip-variables).
The original checkpoint preceded reservation and node recovery; the completed
repair below supersedes that runtime state without erasing the crash history.

## Startup repairs verified at 08:51 UTC

The installed additive helper reserved `34512-34513`, with an exact kernel
readback. Both Kazoo node units now require the boot reservation oneshot and
perform its read-only pre-start check. The oneshot runs after systemd-sysctl;
other operator reservations are merged, not overwritten. Nine offline tests
passed, including exact-union, idempotence, race/failure and unit-ordering cases.

After fresh zero-channel proof, only eCallMgr was restarted (PID 1558 to 34939).
`sup kapps_controller start_app pivot` returned `{ok,[gun,pivot]}`. Pivot now
listens on TCP 34512 in the unchanged applications process (PID 1555), and
FreeSWITCH reports its connection to the replacement eCallMgr. TLS port 34513
is reserved but is not claimed as a listener: Pivot TLS is not enabled.

The paired test-phone runner/unit fix is installed and enabled. Its normal
lifecycle now only manages the exact owned registrations and preserves all
agent login/pause statuses and the operator roster, even after `/run` is lost.
It waits on bounded read-only dependency probes before checking ownership;
routine cleanup no longer invokes all-agent logout or native call hangups.
The new lifecycle and explicit state-only snapshot mode passed 20 mock cases,
plus the existing phone-recovery tests, syntax and ShellCheck.

The service was started once and reached ready at 08:50:31: PID 35293, 30/30
exact contacts, zero restarts. Its strict after-snapshot verified 30 SIPp child
processes and all 30 owned loopback phone sockets. Before/after API snapshots
compare equal for the one-agent roster (owned agent 12) and all 31 reported
agent states/memberships: 29 logged out, one ready, one unknown (protected
MicroSIP owner). Unknown is retained as reported, not reclassified as online.
No roster/status restoration or all-agent login was performed.

`systemctl is-system-running` now reports `running`, with zero failed units.
Applications crash.log remains its historical 3,647 bytes and eCallMgr's remains
zero; neither was cleared. Backups and root-only before/after snapshots are in
`/usr/local/src/kazoo5-installer/postboot-runtime-repair.hMtkU7`.
An early state-snapshot invocation against the not-yet-promoted script correctly
rejected the new CLI mode before API access; only the later successful snapshots
are comparison evidence. This recovery is not a second reboot acceptance test.

## Completed post-reboot checks

The current supported-profile Monster build passed independent artifact readback:
1,931 files, 19 app directories, 16 preloads, 10 unchanged metadata documents,
and all 463 source templates represented. Two ACDC template-render fixtures
passed using the pinned Handlebars 4.7.7 runtime. Actual source and output hashes
match the completed build log. The original build payload exited zero while
its outer historical-template comparison exited one; that old failed receipt
is retained, not rewritten as a success. No new UI has been deployed.

Private receipt:
`/usr/local/src/kazoo5-installer/monster-owned-build.2agp5r/artifact-readback-receipt.json`,
SHA256 `be8377046b893c70811ee68a525e52a9516637734ef8d857df5486a134736500`.
The guard observed 151,535,616-byte peak memory, 4.466 CPU seconds, no swap and
zero cgroup OOM/max events. This is static artifact validation, not browser proof.

The tightened English gate passed 26 mock groups. Its first live invocation
failed locally, before database queries, because the historical import capture
contains an extra `reverified:165` field not in the current strict importer
schema. A location-only diagnostic identified the mismatch without logging
credentials/assertion values. The private adapter now checks that exact extra
counter and validates the remaining original fields with the unchanged strict
validator. The retained receipt was not edited.

At 08:30:04 the actual five-query readback passed all 44 English prerequisites:
29 immutable Gemini documents and 15 unambiguous pinned official WAVs with exact
prompt/language identities and attachment bytes. Capability files were unchanged.
Subsequently, all 165 Gemini assets and 330 running resolver mappings passed fresh
read-only verification; all 719 installed speech/hold-music files were present,
`mod_say_en` was loaded and FreeSWITCH reported zero calls. These checks do not
establish native-number playback, native-speaker approval or full five-language
readiness. No cache activation, media import or capability change was performed.

The requested `sup kapps_controller kapps` spelling was found unsupported by the
pinned controller, which exports `running_apps/0`. The installer wrapper now
maps only that exact argument-free pair, preserving all other commands/options.
The first eight argument cases missed an overbroad suffix match: a later full
installer gate found the alias also rewrote `kapps_config get kapps_controller
kapps`. That caused `undefined` even though the actual persisted binary-key
configuration contained all requested applications. The alias now identifies
the module/function position after supported leading options and requires zero
function arguments. All 15 argument cases pass, including the unchanged config
getter. The corrected live getter returns all 21 configured applications; no
database repair was needed. The installed wrapper matches the
installer bytes; backup is `sup-alias-postboot.zxxWGx/sup.before` beneath the
installer build directory. Its guarded real RPC also passed and returned the
running application list (before Pivot was recovered).

The broader seven-backend validation then reached another fresh-boot verifier
issue: `kazoo_maintenance` is available for Erlang's normal lazy loading but is
not yet loaded. The current checker incorrectly equates that with absence.
That run is retained as failed. The read-only available-BEAM/export check is now
installed and passed the real seven-backend verification through both Kazoo
nodes and FreeSWITCH. It does not load code merely to satisfy verification.
Both live node units also explicitly bind `KAZOO_ROOT=/opt/kz5`, matching the
installer's custom-runtime-root fix; daemon-reload did not restart either node.

The 09:39–09:40 seven-backend run passed CouchDB, RabbitMQ, HAProxy, both Kazoo
nodes, all 21 configured applications, Crossbar/ACDC/authentication, all 165
Gemini documents/330 mappings, and the FreeSWITCH/SBC connections. Its final
Kamailio log gate failed on the retained 01:33:18 startup error loading JWT keys.
That failure remains under investigation and is not a full installer PASS.
At 09:40 FreeSWITCH had zero channels and the crash logs remained 3,647/0 bytes.

## Production preload correction — offline source acceptance

Browser preview exposed a writer/reader mismatch not caught by the earlier
static artifact check: the writer emitted `preloadApps`, while the runtime
reads `preloadedApps`. The earlier artifact-readback PASS above is insufficient
for browser acceptance; its receipt and original artifact remain unchanged.

The installer now applies `monster-ui-preloaded-apps.patch` and runs the
production artifact verifier after compilation and before owned activation.
Both patch and verifier participate in the build fingerprint. New artifacts
must use the canonical key, with valid unique app names. Existing legacy
preload lists are accepted only as migration input and remain subject to the
no-dropped-preloaded-app preservation check; conflicting keys are rejected.

Resource-capped offline verification passed the five deployment suites:
24 ownership/preservation groups plus preload-contract cases, 10 installer
preservation groups, 6 ownership-binding groups, 7 directory groups and
8 served-byte groups. `test-monster-preload-contract.cjs` additionally executes
the pinned framework writer and actual runtime reader, verifies modular
artifacts with and without ACDC, compares both ACDC state-template renders,
and rejects legacy or incomplete output preload lists. The patch applies
cleanly to the pinned framework source. Shell syntax and tracked whitespace
checks pass. These tests make no live service, API or web-root writes.

The old UI artifact has not been altered or published. A fresh corrected build
subsequently passed at 11:12 UTC, followed by independent artifact readback at
11:13 UTC. Both ran under the 384 MiB / zero-swap / 50% CPU / 128-task guard;
all recorded commands exited zero and no OOM was reported. The current artifact
contains 1,931 files, 19 app directories, 16 canonical `preloadedApps` entries,
10 metadata documents and 465 compiled templates. Its 73 main-bundle AMD
registrations and two ACDC state-template render fixtures passed. Source,
helpers and build fingerprint were unchanged across the run; live configuration
and language capability files were preserved. Dependencies came from a verified
local cache with native-module smoke checks, so this is not evidence of a
clean-server dependency download/install.

Private stage: `/usr/local/src/kazoo5-installer/monster-owned-build.pfUGAT`.
Build receipt SHA256:
`8c7ba35d106638759bf0849c67159bc5850bcc79ced11bfa9a32c8a7923dc0a3`.
Readback receipt SHA256:
`56d1745e5180212471b3127a2d954d654f4794752bf89b9d6af13a798cde2c7d`.
Artifact inventory SHA256:
`6cb494731de21b2d49b08856a7187825b3ce9a5330a01e765e011edd4c0de4cf`.
This supersedes the earlier artifact only as current static build evidence.
No browser, authenticated live GET or live call proof is implied. Fresh
ownership/adoption planning and browser acceptance are still required before
publication; matching backend integration remains coordinated with the external
team fixing ACDC call acceptance. No live UI or `/apis` publication occurred.

The phone-service preservation source was rechecked independently after this
build: all 20 lifecycle/state-snapshot mock cases and the existing phone-recovery
suite passed again. These offline tests made no SIP, API or service changes and
do not replace the earlier runtime snapshot evidence or a new reboot test.
Subsequent review found successful-but-slow registration lookups could bypass
the shared startup deadline. The source now reserves each probe's five-second
budget and rejects late success before READY. The expanded 23-case suite passes,
including delayed-success and retained-cleanup-marker scenarios. The first
expanded run failed two test diagnostics because its logger mock suppressed the
expected messages; after correcting those fixtures, all precise error, no-READY
and scoped-cleanup assertions passed. Cleanup documentation now distinguishes
preserving roster/status from possible interruption of a stopped phone's dialog.
This additional deadline fix has not been verified through a live service restart.

The eCallMgr-only installer previously treated two existing `.app` files as
proof of compilation. It now builds unless this same invocation already
completed the source-patch/build/production-verification path (as in ALL).
An invocation-local flag is reset regardless of inherited environment and is
not a persisted deployment input. The new offline actual-hook test passes
stale-file/environment refusal, reuse after a successful current build,
failure before service activation, and dry-run behavior. It does not compile
or restart the live eCallMgr node.

## Queue-scoped login — source integration, not live acceptance

The opt-in `runtime_only=true` agent queue-status path is integrated into the
ACDC and Crossbar installer patches. The legacy unflagged roster API remains
unchanged. The new path requires an existing enabled agent enrollment in the
selected queue, never saves roster documents, and responds to POST with HTTP
202 pending. Its GET confirms membership only from a fresh correlated listener
reply for the requested account and agent; availability remains a separate
status, and timeouts/old/malformed replies do not count as confirmation.

Five production modules compiled with `-Werror`; 12 isolated EUnit groups
passed, including broker errors, stale/foreign/oversized status replies,
consumer-side membership revalidation and concurrent process-start handling.
The initial runs with a harness timeout and incomplete test doubles are
retained failures, not passes. Fresh pinned ACDC and Crossbar source replay
reproduced all five promoted modules and the schema exactly, with reverse
patch checks passing. A portable regression runner is included in source.

The queue-selector UI passed 20 focused groups and its full contract suite in
a private candidate, then matching bytes were promoted into source. Its English readiness fixture now supplies the complete
44-record prerequisite set; the runtime readiness gate was not weakened.
Backend source was committed as `4fc2a2b`; UI source as `d263342`.
OpenAPI source integration is committed as noted above; generated publication,
matching deployment, authenticated endpoint checks
and actual selected-agent ringing are still required. No live roster or
agent-session writes were performed in these checks.

The separate callback-audio candidate remains private and held from rollout
after the native synchronous-timeout finding noted above. Exact-call log evidence
shows normal tail playlists waiting behind native endless hold. Its proposed
adapter permits only caller-leg play/say commands and their correlated final
noop, uses the existing immediate execution path in forward order, and never
flushes another owner's command queue. Across bounded runs, 24 command/schedule,
14 feedback, 16 success/ownership and 4 real command-builder cases passed.
This is 58 distinct cases across receipts, not a single full-suite pass. The
include-path failure, timed-out run and corrected test-field assertion remain
recorded failures. Native acoustic ordering, hold resumption and no late prompt
leakage after a bridge/usurp remain mandatory isolated-call gates before this
candidate is described as a live fix. The next implementation must also resolve
the five-second RPC boundary and responsive owner handoff; completing the old
mock suite is not sufficient to release the synchronous candidate.

## Still required

The Kamailio startup-classification repair is committed as `aff66d3`. Eleven
offline groups and the real parsed `--verify-only kamailio` action passed.
The single startup JWT null response remains an explicit warning: same-worker
recovery took 20.092 seconds, the current key table contained seven entries,
and the retry flag was zero. MainPID 974, activation 9413453 microseconds and
the systemd invocation ID matched before/after. The first failed journal-boundary
attempt is retained; the correction inspects the full bounded one-second
pre-activation prefix, rather than discarding records or suppressing its errors.
Receipt: `/tmp/kazoo-jwt-startup-classifier.BIi5d2/FINAL-VERIFICATION.md`,
SHA256 `b0387aee363402e0c6d61cba7ae9829502c0c070fd8838dc283928b076890322`.
No configuration change or service restart was made by either verification.

Deploy the remaining matched queue-login/backend/UI artifacts, repeat browser/SIP/log
and all-module installer gates,
and complete the wider unresolved requirements in
[the task list](deployment_tasks.md). TLS, additional Gemini generation approval,
GitHub write access, sustained-load acceptance, separated-host deployment,
restore and failover remain separate unresolved gates. Do not describe this
checkpoint as finalization or enterprise certification.
