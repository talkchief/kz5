# Native callback audio: next implementation slice

Source-only audit, 2026-09-06. This is an implementation handoff, not a completed
audio fix, native execution result or deployment acceptance. Development service
replacement/restarts are already authorized; the remaining blockers below are
technical, not a request for new deployment permission.

## Priority correction: reproduce current WAV behavior before choosing a native lane

The private owned-audio implementation below is an experimental solution, **not
an established prerequisite** for callbacks or Gemini recordings. Normal
FreeSWITCH playback already uses the normal codec/RTP/SRTP path. Restrictions of
the private writer must not be attributed to ordinary WAV playback.

There is narrower historical real-call evidence on the existing transport:
[callback controls deployment](callback_controls_deployment.md) records the
`20260905T193537Z` independent-offer/position audio PASS, and the
`20260905T210254Z` legacy-English callback PASS: complete6.124-second confirmation,
unanswered first attempt and confirmed/bridged retry after the configured
minimum backoff. These do not certify current canonical Gemini playlists,
arbitrary/custom endless hold, all five languages or ownership races.

The current source still exposes a concrete transport question:

- `acdc_announcements:maybe_play_announcements/2` calls
  `kapps_call_command:audio_macro/2`. Member menu/readback/feedback and returned
  confirmation likewise use ordinary queued PLAY/noop commands. Those queue
  envelopes omit `Insert-At`, whose call-control default is `tail`.
- `ecallmgr_call_command:get_fs_app/4` maps hold to `kz_endless_playback`.
  `acdc_queue_fsm:callback_pause_request/3` pauses selection and stops the
  announcement producer; it does not itself terminate native hold.
- Simply changing insertion to `now` is not a verified fix:
  `ecallmgr_call_control:insert_command/3` sets `call_cmd_sync(true)` and executes
  from the control process. Native `kazoo_node.c:execute_or_queue_command`
  then calls `switch_ivr_parse_event` synchronously. Conversely, `sync=false`
  queues a private event; enqueue success is not playback/ordering/ownership
  proof. `flush` performs `uuid_break ... all` and clears the control queue,
  so it is not owner-scoped cancellation.

The immediate gate is therefore a measured **current-source, normal-transport
WAV test**, not completion of a new RTP framework. Required behavior remains:
audible independent offers while waiting, complete registration confirmation,
responsive call control throughout playback, safe terminal/ownership handling,
and settled unanswered-first-attempt retry. Keep every private admission gate
closed unless that implementation separately satisfies its acceptance criteria.

### Bounded parity and reproduction plan (root-run only)

1. Before changing runtime, establish zero calls and retain non-secret loaded
   module MD5/path parity. For example, `sup -e cf_acdc_member module_info md5`
   and equivalent checks for `acdc_gemini_prompts`, `acdc_announcements`,
   `acdc_announcements_sup`, `acdc_callback_caller`, `acdc_callback_menu`,
   `acdc_language` and `kapi_acdc_callback`; check `kapps_call_command`,
   `kapi_dialplan`, `ecallmgr_call_control` and `ecallmgr_call_command` on their
   actual owning nodes. Compare with freshly compiled no-TEST artifacts and
   verify actual `code:which/1` paths, not only files on disk. Read only the
   selected queue's language/callback/offer settings and scoped asset metadata;
   do not dump complete call/config documents or credentials.
2. Those eight ACDC modules form the focused canonical media test cohort in
   `scripts/test-acdc-gemini-canonical-callback.sh`. They are not a replacement
   for checking the installed queue FSM/listener/manager/member and callback
   store/policy/recovery/probe dependencies. Deploy only a reviewed coherent
   callback delta after parity checks. In particular, do not deploy the entire
   current ACDC directory merely to update audio: unrelated DASH-10 queue-manager
   and stats-layout candidates require separate coordination.
3. Re-run the full canonical callback suite before deployment. Root's latest
   media-only run `778a35/6d4296` passed22 tests with unchanged input digest
   `5bcd7e76678f42988001ad768c391fd272401d2ec8b6d4b48eab975a73759ea8`;
   it did not deploy code or execute native media/lifecycle acceptance.
4. Prepare the existing isolated offer harness with
   `bash scripts/test-acdc-callback-offer-calls.sh --prepare-only`. Its armed
   form requires `--live --runtime-md5 HEX`. First reproduce its independent
   schedules with the current playlist/normal transport; then verify the actual
   configured30-second initial offer separately. Capture received RTP against
   the exact installed WAV, noop ordering, hold continuation and producer
   cleanup. A scheduler timestamp or native enqueue acknowledgement is not
   audible-media evidence.
5. Use one authorized, dialable return destination; the recent `kz5_test`
   nonnumeric caller with alternate entry disabled correctly failed validation.
   Do not weaken that check. Prepare
   `scripts/test-acdc-callback-retry.sh --prepare-only --confirmation-reference FILE`
   using a protected verified reference for the selected actual recording.
   The armed historical runner additionally requires `--live --keep-fixture`;
   review its retained-resource constraints before reuse. Verify key6/menu,
   durable registration before complete success audio/BYE, first-attempt
   CANCEL/settlement, configured backoff, second confirmation and one bridge.
   Do not rewrite ambiguous historical tickets to make cleanup pass.
6. Target the missing regression directly: a current built-in playlist longer
   than five seconds over the actual endless hold, with an ownership/terminal
   event during playback. Prove control responsiveness, no late queued audio
   after bridge/usurp, correlated completion and preserved queue position on
   resume. Repeat with the configured normal codec/security mode; a PCMU-only
   capture does not establish every codec/SRTP combination. This may identify a
   bounded normal-transport correction; choose it from evidence rather than
   assuming the private owned lane is necessary.

## Canonical scope

Current tracked callback code (`a75806c`, following `81b7c15`) uses recorded
telephone digits for built-in readback in all five locales: EN, ES, FR, AR and
HE. See `applications/acdc/src/acdc_gemini_prompts.erl`:
`callback_defaults/5`, `callback_builtin_assets/1` and `callback_readback/2`.
The separately preserved fully explicit custom-audio branch can still select
legacy SAY; it is not the built-in contract or part of this first slice.

Implement **PLAY-only owned execution**, including the canonical recorded-digit
playlist. Do not restore the older private candidate's locale-dependent SAY
mapping, generate new audio, or require general SAY/module-unload work before
this recorded-audio path can advance. P0-12 metadata/preflight checks are separate
from native media execution and must remain intact.

## Exact inspected native boundaries

Private paths below are relative to
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/`:

- `native-say-scope.MfDQMl/switch_ivr_owned_audio.c`: `owned_complete` (line 275),
  `owned_atomic_lane_implemented` (392), `switch_ivr_owned_audio_submit` (398),
  `switch_ivr_owned_audio_dispatch` (549), and both-leg bridge helpers (623 onward).
  Admission remains hard closed. Reuse its single slot, exact owner/hold epoch,
  original hold arguments/depth, and full-producer-stack ACTIVE lifetime.
- `native-say-scope.MfDQMl/switch_ivr_play_say.c`: `switch_ivr_play_file` captures
  ownership near 1295, drains the fixed mailbox near 1717, selects the owned
  writer at 2019, and rejects empty individual fragments at 2120.
- `native-codec-fence.E48ZvD/source/src/switch_core_media.c`:
  `switch_core_session_write_owned_frame` (7250) requires 320-byte mono L16 at
  8 kHz/20 ms and emits 160-byte PCMU/PCMA. Compare `perform_write` (7159) and
  normal `switch_core_session_write_frame` (15981).
- `native-write-extractor.DmBWMY/source/src/switch_rtp.c`:
  `owned_rtp_mode_supported` (8765), `owned_rtp_sendto` (8776), and
  `rtp_common_write` reject secure owned output, including the SRTP branch near
  9189. These are restrictions of this private owned lane, **not** a claim that
  FreeSWITCH or the deployed platform lacks codec/SRTP support.

## Bounded source change

Replace the bespoke G.711 owned writer with an owner-scoped entry through the
existing normal codec/packet/SRTP processing. This is not merely removing its
guards or calling the normal writer: that writer substitutes frame pointers,
resamples/buffers data, can enqueue frames, and has SUCCESS returns with no send.
Carry the exact operation identity through derived frames and any retained
audio; cancellation must discard or drain only that operation's retained work.
Keep actual-output evidence, per-file completion and full producer unwind as
separate requirements. Preserve the original hold's handle/state and never use
global `CF_BREAK`, `uuid_break all`, queue flushing or channel-variable changes
as owner-scoped cancellation. Reserve media/codec/crypto lifetime before mutations
that can race this producer; frame completion alone is insufficient.

Bridge helpers are not yet wired into actual bridge execution: the accepted
incremental link retained the unchanged `switch_ivr_bridge` object. In native
`/usr/local/src/kazoo5-installer/freeswitch-1.11.3/src/switch_ivr_bridge.c`, bind
the actual ACDC intercept (2257), UUID bridge (2005), media bridge (1613) and
their handoff/end/abort paths to the same exact both-leg ticket **before**
answer/unhold/state effects. Other reachable public entries, including signal
bridge and B-leg resume, must not bypass ownership; unsupported owned transitions
must fail before effects, while ordinary unowned behavior stays unchanged.
Same-stack cancellation must defer rather than wait on itself. Propagate that
distinct result through
`native-version-tu.RAKTfm/mod-kazoo/kazoo_intercept.h:112`, whose existing generic
failure branch releases the claim and hangs the answered agent. Do not turn a
benign deferral into that failure or into false bridge success.

Connect the existing `native-wire.0fjPpv/kazoo_queue_audio_wire.c` decoder and
Erlang counterpart to trusted controller ownership and this fixed mailbox.
The later private typed-transport derivative below registers the decoder;
this has not been promoted into the deployed module. Use the actual `kazoo_node.c` request
boundary, not ordinary recursive private-event execution. Preserve one in-flight
item, exact retry/inspect/cancel identity and correlated completion. Integrate
the canonical callback playlist without changing its assets or menu semantics.

## Latest private-source checkpoint — continuation map

These files are **outside Git**. Their presence on this development host is not
reproducibility from a kz5 clone. Preserve them for review; accepted changes,
regression harnesses and installer integration must eventually enter kz5 before
release. Do not enable either lane by deleting its safety gates.

### Typed EI transport: source compiled, admission closed

Directory: `native-ei-dispatch.S4NXF3/` under the private root above.
Start with its `README.md`, `test-dispatch.cjs`, and
`proof.xTp4ZL/receipt.json`. Source changes include the actual `kazoo_node.c`
request table/switch, strict wire decoder/typed dispatcher, Makefile integration
and a minimal read-only hold snapshot in owned-audio core/header. No producer,
normal-codec, RTP or bridge changes belong to this derivative.

Guarded session7634 exited0: four complete production translation units compiled
with real headers,-O2,-fPIC,-Werror;7,962 checks passed in each plain and
ASan/UBSan fixture. All native core boundary calls were poisoned and remained0.
Input digest for263 stable inputs:
`6ebc5f671172261c24c90284116c55463753d60e73e4ffe81e3caaef21723c31`.
The guard used128MiB, unchanged768MiB reserve,120s and an offline network namespace.
Earlier40889 failed fixture linking on an omitted `switch_copy_string` stub;
that stub was added before the successful rerun. A256MiB retry was refused at
memory admission; that refusal did not start a payload or count as a test pass.

This proves full-object compilation and actual encoder/decoder/handler behavior
against fake FreeSWITCH boundaries, **not** dynamic execution of the complete
node router, a full module link, distributed EI, worker calls or audible media.
Literal `ownership_not_implemented` and existing native-lane gates stay closed.

Authority still needs incarnation-safe publication and atomic revoke/usurp:
`ecallmgr_call_control:set_control_info` publishes Call-Control-Node/PID and
Fetch-UUID, but `pid_to_list` omits BEAM creation and deferred multivariable
publication is not an atomic ownership transaction. Matching channel fields and
actual distribution sender is necessary, not sufficient. Do not infer worker
delegation from a shared node. Scoped zero-wait revoke is not producer quiescence.

### Normal-codec writer: reviewed fixes compiled; behavior acceptance pending

Directory: `native-normal-codec.nZYBwT/` under the same private root.
Files: `switch_core_media.c`, `check.cjs`,
`compile-proof.Terkba/receipt.json`. The derivative starts from the
`native-codec-fence.E48ZvD` source named above, whose SHA256 is
`1fc04633f9de34a7d98ce9714862b74ee4a27d930a7d7a9d47ae058595feb819`.

The initial implementation routes owned writes through a shared normal writer
with an explicit operation context. Six actual `perform_write` boundaries
lease/check/report the final derived frame. The ordinary public writer passes
NULL context; the harness normalizes only intended owned-only changes and
compares the original ordinary body. The first slice rejects buffered,
resampled, asynchronous, media-bug/write-hook and incompatible input lanes; it
does not establish general codec or SRTP support.

Session71186 exited0: actual full-TU compilation and source comparison passed,
353 pinned inputs,256MiB cap/768MiB reserve/150s/offline. **That receipt predates
two subsequent edits:** preserving non-success status instead of flattening
NOTIMPL/BREAK to FALSE, and suppressing first-transcode synchronous notification
plus its marker mutation only in the owned path. Do not cite71186 for later
source correctness.

The subsequent correction also restores outer nonblocking codec trylocks with
captured-mutex cleanup, refuses encoder RESAMPLE, preserves endpoint error
statuses and checks sent-counter overflow before acquiring/sending a frame.
Session27998 exited0 with full native translation-unit compilation and unchanged
ordinary-body comparison,353 stable inputs. Receipt:
`native-normal-codec.nZYBwT/compile-proof.Cp4Y6Q/receipt.json`.
Source SHA256:
`0963843b9da2c21dfbb3dcac8363517d02ad81d026a0a409045e1a9c4bf293bd`.
The run used224MiB with the same768MiB reserve/150s/offline. Earlier21632 exited1
because its128MiB cgroup was OOM-killed; journal evidence identifies unit
`kazoo-validation-214e2afd-3d15-4c0d-93a9-199911568ebd.service` and confirms the
test group terminated. Its partial `compile-proof.Q6HVPS` has no passing receipt.
This was a test cap failure, not evidence of a platform service crash.

Session93022 then exited0 with62 extracted helper/wrapper cases under strict
GCC/UBSan, including actual pthread recursive-lock contention and foreign-thread
cleanup probes. Receipt:
`native-normal-codec.nZYBwT/owned-write-context-proof.JMUsPt/receipt.json`.
This covers source `0963843b...` above, with inner normal writer, registry and
endpoint doubles; it is not whole native encoding or cancellation acceptance.

The separate passive-readiness candidate passed23159: complete queue translation
unit compilation plus182 checks each plain and ASan/UBSan using actual APR
queue/mutex operations and controlled channel accessors. Receipt:
`native-passive-ready.jpGiQK/proof.TO8WUM/receipt.json`;259-input digest
`ed78f186541defd11b35d051bc8a19bae96bc0b037c145c1264009f1bcb87b38`.
It explicitly tests that pending signals are not consumed, contention fails
closed, and enqueue after a successful snapshot remains possible. Earlier
source-whitespace normalization failures were fixture failures, not passes.

Root integrated that helper at wrapper admission, normal owned readiness and
before the final derived-frame lease. Session17639 exited0: full native TU,
355 stable inputs, ordinary-body comparison, normalized exact equality to the
tested helper and selection of the real-header overlay (`switch.h` plus updated
`switch_apr.h`) all passed. Receipt:
`native-normal-codec.nZYBwT/compile-proof.ae3biy/receipt.json`.
Integrated source SHA256:
`9c0a94afac58b6ef225ac0b1c21dd0b97698c9ff054f5acd251ca8f83fa51fed`.
The queue TU must be linked with this writer; a header-only deployment is not
complete. The updated wrapper fixture then passed session64711: all62 prior
cases plus2 controlled-readiness transition cases, strict GCC/UBSan, six stable
input identities. Receipt:
`native-normal-codec.nZYBwT/owned-write-context-proof.vp4cUN/receipt.json`, SHA256
`6f7077501d97a618a1f77c3c5da8d74417f47d59bb0118906c41bf2afb14b0d3`.
Pending-before-entry produces no writer/lease/send; readiness lost before the
derived lease returns BREAK, sends nothing and releases all outer locks. This
uses a controlled readiness double: actual passive queue/accessor behavior is
the separate23159 evidence, not silently included in these64 cases.
Neither successful check opens admission.

Review left these exact next fixes/tests:

1. Preserve tested bounded codec-mutex admission: the earlier owned entry trylocked the
   negotiated/output codec and input-frame codec. The shared normal writer now
   blocked on those mutexes while holding outer owned-path locks. The correction
   retains captured mutexes for cleanup;93022 verified foreign contention gives INUSE before release,
   no encode/send and complete outer-lock release. This is a boundedness
   regression, not a demonstrated live deadlock.
2. Behavior-test owned encoder RESAMPLE rejection before fallthrough/derived-frame
   mutation, matching the decoder rejection. No configured live
   encoder was observed producing this case during the review.
3. `switch_channel_ready`/`switch_channel_media_ready` process queued signal data;
   they are not passive reads. The concrete path can enter Sofia dispatch under
   outer codec/control/bug locks and alter SIP/media state. Use a reviewed
   owned-only no-signal readiness boundary (now compiled/tested as scoped above),
   preserving ordinary semantics. Atomic enqueue/mutation fencing is still open.
   Correction to the preliminary review:
   SIGNAL_DATA uses the direct endpoint branch, so a generic receive-hook
   deadlock is **not proven** by this call chain.
4. Preserve context regression tests: exact derived-frame identity, lease refusal,
   endpoint failure, unsupported/no-send, SUCCESS without send, stale/revoked
   ownership, sticky failure and counter overflow; then recompile current source.
   The updated64-case fixture passed in64711. Helper fixtures remain narrower
   than whole native execution; actual encoder branch execution remains open.
5. The earlier private RTP baseline advances `timestamp_send` by160 and rejects
   secure output. The later compile-only derivative below changes these paths.
   Codec/ptime widening still needs validated normal timestamp/sample accounting,
   SRTP and full producer/media/session lifetime work, not merely removal of
   these guards. Bridge helpers still need actual bridge-entry/end integration.

Work resumed after the documentation freeze: the root owns normal-writer source,
the browser-harness reviewer is preparing helper/wrapper behavior tests, and the
native reviewer completed the separate passive-readiness/queue-observation
candidate at `native-passive-ready.jpGiQK/`. Its `INTEGRATION.md` explicitly
distinguishes a non-dequeuing observation from an atomic enqueue/output fence.
That helper is now integrated as described above; the reviewer is auditing the
remaining actual producer/dispatch lifetime boundaries. Recheck agent messages
and actual process handles before resuming; serialize resource-capped validation.
Neither derivative was deployed, linked into a running service, or committed as
a release patch at this checkpoint.

### Next implementation: signal-processing lifetime

The native reviewer is implementing a separate derivative, not changing this
writer. The current proposal checks pending signal work under the queue mutex,
then reserves mutation **before dequeue**. Verified empty observations must not
allocate/revoke ACTIVE or PENDING audio; contention/error processes nothing.
If actual work conflicts with ACTIVE playback, revoke that group but leave its
producer ACTIVE until full unwind. Valid queued SIP data stays untouched.
The eventual exact serial/thread ticket spans the full endpoint callback.

Do not reject signal enqueue: Sofia callers at `sofia.c:2528,2620,2628` ignore
enqueue return values and could orphan saved event/handle references. The
reattach resets near2525–2527 already mutate endpoint state before enqueue and
must move into reserved processing using an internal reattach marker. The
processing chain is `switch_ivr_parse_signal_data` near869 →
`mod_sofia.c` SIGNAL_DATA handler near1363 → `sofia_process_dispatch_event` near2233;
saved references must be freed exactly once after the entire callback.

Allocation/registry initialization failure must defer/error before dequeue with
no unguarded fallback; retry may process once allocation succeeds. Persistent
allocation failure would stall signaling and is an explicit unclosed recovery
case, not unchanged failure behavior. A separate nonallocating quarantine field
is not part of this bounded proposal.

Legitimate nested codec and bridge work must be compatible with the same exact
processing scope. Merely reusing `codec_active` rejects legitimate nested setup.
Allowing A's scope must never bypass B's ACTIVE/foreign reservation. Existing
Sofia UUID-bridge callers can ignore failure after already mutating A; correct
cross-leg deferral/continuation is still unaccepted, not permission to report
success, drop events, hang the agent or replay the entire partially applied event.
No global all-call blocking is an acceptable substitute. These are proposed
changes/tests, not implemented or passing evidence at this checkpoint.

## Latest private RTP/codec checkpoint — compile only

September 6, 2026, after local documentation commit `57b55e1`. Root's derivative:

```text
/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-rtp-packets.OiCUA5/
  switch_core_media.c
  switch_rtp.c
  check.cjs
  compile-proof.Yg86gt/receipt.json
```

This directory is outside the repository, not installed code, not a release
patch and not reproducible from a fresh clone yet. Its inputs derive from
`native-normal-codec.nZYBwT` and `native-write-extractor.DmBWMY`, with the real
passive-readiness/header overlay. The older cached PIC/link checkpoint does not
include these new objects and cannot certify them.

Implemented candidate changes:

- Stack-local owned RTP packet storage, encoded-payload bounds with reserved
  SRTP trailer space, negotiated RTP payload validation and positive frame
  metadata checks, removing the earlier G.711/160-byte-only restriction.
- Try-lock reservation in write → ICE → flag order through owned output, with
  captured cleanup on rejected paths. Unsupported modes and secure-send reset
  remain rejected; this is not a proof that every lifecycle mutator is fenced.
- Existing native SRTP protection path with explicit context/error/length checks:
  failed protection must not fall through to plaintext output. Protected packet
  or ambiguous-send failures must not rewind sequence state for owned output.
- Owned media timestamp accounting based on the negotiated read implementation
  and complete encoded packet count, rather than an unconditional160 increment.
  Actual RTP timestamp generation still uses the normal native path.

Guarded offline session **13529 exited0**, 192MiB cap,768MiB reserve,180-second
deadline. A preceding224MiB request was refused with exit69 **before payload
execution**; the reserve was not reduced. The successful harness compiled both
actual full production translation units with configured real headers,
`-O2 -fPIC -Werror`, checked390 inputs and compared the ordinary core writer body.
It did not establish unchanged behavior of every RTP branch.

| Identity | SHA-256 |
| --- | --- |
| `switch_core_media.c` | `c8790f105b51c504a5b96128d7d373c0261b8b48c480125ec74edea7ed057414` |
| `switch_rtp.c` | `d87ef277d4912ce54f4e5a55ebe322b32bd7461d54be93db31cc00300298ce0f` |
| `compile-proof.Yg86gt/receipt.json` | `eb3928835d03b7a916d626796c66cd647f6cf205518da283f3e4a5ed0f6b2e51` |

**Not tested/accepted:** actual SRTP encrypt/decrypt, local UDP send and received
bytes, short/failed sends, mutex-contention cleanup, all dynamic payload/codec/
ptime cases, full producer/session lifetime, canonical combined linking, module
load or a real call. `switch_socket_sendto` boundedness remains open: keeping
locks through a potentially blocking socket call is not accepted merely because
compilation passed. Native admission stays hard closed; nothing was deployed.

Next root slice: exercise actual production packet/protection/send boundaries
with real local libSRTP/UDP where feasible and explicit labels for any doubles;
add failure and contention controls; review lifetime and bounded socket behavior;
then integrate one canonical source/header tree with the signal-processing and
installer owners. Preserve strict rejection rather than opening a deployment
gate to make a test pass. Before running `check.cjs`, inspect its resource/input
requirements and acquire the serialized validation window.

### Single-attempt socket output — subsequent checkpoint

The RTP candidate above has a later derivative at
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-nowait.HICDXv`.
It contains `switch_apr.c`, the additive `switch_apr.h` declaration, the updated
`switch_rtp.c`, `test_nowait.c` and `proof.cjs`. `switch.h` is an unchanged
include-routing copy. These private files remain outside the release tree.

Source inspection confirmed that `fspr_socket_sendto` retries EINTR and, with a
positive socket timeout, waits/retries on EAGAIN even with MSG_DONTWAIT. The new
`switch_socket_sendto_nowait` obtains the native descriptor and performs exactly
one per-call nonblocking datagram attempt, without changing shared socket flags
or timeouts. It reports accepted bytes only, does not retry EINTR and rejects
unsupported platforms rather than falling back to a blocking call. The caller
must still retain socket/address lifetime. Owned RTP uses this helper; ordinary
RTP and the existing APR wrapper are unchanged.

Guarded offline session **48223 exited0**,128MiB cap,768MiB reserve,180-second
deadline. Both complete production APR/RTP translation units compiled against
real headers with-O2/-fPIC/-Werror and explicit-g0 proof flags. The actual full
APR object was linked with real APR into plain and ASan/UBSan executables.
Four groups passed in each: actual IPv4 UDP bytes, unchanged flags/timeouts;
wrapped syscall errors EAGAIN/EWOULDBLOCK/EINTR/ENOBUFS/EBADF with one attempt;
wrapped short-send byte reporting; and invalid inputs with no send syscall.
All380 selected source/dependency pins remained stable. Loopback was enabled
only inside the isolated test network namespace.

Receipt: `native-nowait.HICDXv/proof.2CRkLx/receipt.json` under the private root.
SHA-256: `701a5d1af0f46b7f074e79819527dc3cfa1209cc297d13b069534273c1aeec03`.

| Source | SHA-256 |
| --- | --- |
| `switch_apr.c` | `c6c7b57efc0b36e24d3ae6ffc3387c694ba50bf228c5e5c84fa02e6e1211ffac` |
| `switch_apr.h` | `37129b5bae887f7b777d0e4d7091b76cd4e205194e78d5e982471bf45525b335` |
| `switch_rtp.c` | `ded97736f8137ed76c9e5cee014f146be006286de56d97bd47a5e48ddc58a7d5` |

This removes the observed wrapper's user-space retry/wait behavior; it is not
a hard realtime guarantee for a kernel syscall or proof of complete native
lifetime. The RTP send/protect branches themselves were compiled, not executed
by these wrapper tests. Full SRTP, owned-frame reporting, producer/bridge races,
canonical linking, module loading and live callback acceptance remain open.
The browser-harness agent next owns a separate RTP/libSRTP boundary fixture;
root's successful source/proof is frozen. Admission remains closed and nothing
was deployed.

## Acceptance that advances deployment

After reviewed native compilation/linking, run an actual isolated native call,
not only extracted functions: custom endless hold → a prompt longer than five
seconds → ordered recorded telephone digits → confirmation → the original hold
resumes. Observe real output through negotiated SRTP and a representative
non-G.711 codec; do not substitute a fake send or claim every codec is certified.
Exercise real key 6 once, stale-owner retries, cancellation between fragments
and during output, hangup/usurp, and agent bridging with either leg busy. Require
exact ticket cleanup, no false completion, and no old prompt emitted into the
connected bridge after both producer stacks have quiesced.

Then perform the development deployment and requested durable registration,
spoken confirmation and unanswered-first-attempt retry scenario. General SAY,
an exhaustive codec matrix or a generic hot-upgrade executor are not prerequisites
for implementing this slice. Ownership, native lifetime, both-leg exclusion and
truthful completion are. Existing readiness documents retain the narrower scope
of their earlier compile/link/helper receipts.
