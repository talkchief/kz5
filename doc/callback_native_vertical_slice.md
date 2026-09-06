# Native callback audio: next implementation slice

Source-only audit, 2026-09-06. This is an implementation handoff, not a completed
audio fix, native execution result or deployment acceptance. Development service
replacement/restarts are already authorized; the remaining blockers below are
technical, not a request for new deployment permission.

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

### Normal-codec writer: initial compile passed; later fixes untested

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
plus its marker mutation only in the owned path. Both edits are currently
private and **not yet retested**. Do not cite71186 for current-file correctness.

Read-only review left these exact next fixes/tests:

1. Restore bounded codec-mutex admission: the earlier owned entry trylocked the
   negotiated/output codec and input-frame codec. The shared normal writer now
   blocks on those mutexes while holding outer owned-path locks. Retain captured
   codec pointers for cleanup and test foreign contention gives immediate INUSE,
   no encode/send and complete outer-lock release. This is a boundedness
   regression, not a demonstrated live deadlock.
2. Reject owned encoder RESAMPLE before fallthrough/derived-frame mutation,
   matching the decoder rejection. Test injected statuses; no configured live
   encoder was observed producing this case during the review.
3. `switch_channel_ready`/`switch_channel_media_ready` process queued signal data;
   they are not passive reads. The concrete path can enter Sofia dispatch under
   outer codec/control/bug locks and alter SIP/media state. Use a reviewed
   owned-only no-signal readiness boundary and test poisoned signal processing,
   preserving ordinary semantics. Correction to the preliminary review:
   SIGNAL_DATA uses the direct endpoint branch, so a generic receive-hook
   deadlock is **not proven** by this call chain.
4. Add context regression tests: exact derived-frame identity, lease refusal,
   endpoint failure, unsupported/no-send, SUCCESS without send, stale/revoked
   ownership, sticky failure and counter overflow; then recompile current source.
   Helper fixtures remain narrower than whole native execution.
5. Existing private RTP code still advances `timestamp_send` by160 and rejects
   secure output. Codec/ptime widening needs normal timestamp/sample accounting,
   SRTP and full producer/media/session lifetime work, not merely removal of
   these guards. Bridge helpers still need actual bridge-entry/end integration.

No jobs remained running after the transport window was released and agent
edits were frozen for this handoff. Recheck processes before resuming; serialize
resource-capped compilation. Neither derivative was deployed, linked into a
running service, or committed as a release patch at this checkpoint.

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
