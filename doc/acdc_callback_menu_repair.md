# Callback menu and live-queue resume repair

Status: the narrow backend repairs below are deployed. This is **not** an end-to-end callback acceptance result or a claim that the reported MASTER-account callback problem is resolved. A separate returned-call handoff repair is deployed but still awaits a new live acceptance run.

## Changes and safety boundaries

The queue FSM now restores `Account-ID` and `Queue-ID` alongside `Call` when a paused callback menu resumes a caller into the live queue. Previously, the ready-to-manager path received an unscoped envelope; the manager's unmatched request returned `ok`, which caused the queue worker's case expression to fail. Both explicit resume and menu-deadline resume retain the original account and queue scope.

The callback menu now accepts an unavailable or nonnumeric current caller ID **only when** `allow_alternate_number` is explicitly `true`. It enters number collection directly, never offers confirmation of the unusable caller ID, and never infers a target from a SIP username, device, owner, or unrelated number.

Both direct alternate-only entry and the ordinary alternate-number menu key play the existing `cf-enter_number` prompt:

> Enter the number to forward to, followed by the pound key.

This is an existing forwarding prompt reused for number entry, not a new callback-specific recording. It plays when the input buffer is empty, including after invalid input resets that buffer, but not between valid digits. The live `system_media/en-us/cf-enter_number` document was verified read-only: one `audio/x-wav` attachment, 50,518 bytes. This receipt proves the installed media asset exists; it is not a recording of a completed live alternate-number interaction.

The wrapper uses the existing `wait_for_dtmf/1` with the reducer's remaining absolute deadline. Playback noops and unrelated events cannot renew that receive budget. `#` and `*` reach the reducer unchanged. Number entry remains digits-only, bounded to 15 digits, and requires `#` followed by a separate confirmation before registration. Empty input and invalid digits retain the bounded retry policy; `*` resumes the live queue; hangup abandons the paused leg; deadline expiry resumes the live queue. Existing correlated acknowledgement and outbound authorization checks remain in place.

No account settings, caller IDs, owned numbers, routing permissions, or callback targets were changed. A missing, false, or invalid alternate-number policy still rejects an unusable current caller ID. In particular, the MASTER queue's policy was not overridden, and this repair does not manufacture a callable number for the reported caller/account.

## Verification

- Queue strategy suite: 26 tests passed, including two new regressions that exercise the actual ready-state to manager branch for explicit resume and menu-deadline resume. The regressions show why the old unscoped envelope failed and verify the restored scope.
- Standalone callback reducer: all 15 tests passed, including unavailable caller IDs, explicit opt-in, false/default rejection, validation, separate confirmation, retry limits, cancellation, and absolute deadlines.
- Callback wrapper integration: all 6 tests passed. The added tests exercise direct and ordinary alternate entry, prompt frequency, empty `#`, invalid DTMF, `*`, deadline expiry, missing/unrelated playback noops, and hangup. Playback is mocked; digit waiting uses the real `wait_for_dtmf/1` and a private process mailbox.
- Baseline-only private compilation and combined reducer/wrapper suite: all 21 tests passed. This build excludes staged language and atomic-answer changes.
- Layered patch verification passed forward application, exact source reproduction, and reverse replay for ACDC, Crossbar, ecallmgr, and CDR. `git diff --check` passed.

## Production receipts

The queue resume fix was built separately from the staged atomic-answer queue FSM. Its production beam SHA-256 is:

```text
acdc_queue_fsm.beam
783469a6291cedc70cb2fcc71a33c6c1ee7a3e79da2c783945348f9df5035ade
```

Its reconstructed pre-fix baseline bytecode MD5 matched the loaded module (`d44b6263a13d9353e7279f278c2e4ac1`). The narrow change affects only `callback_resume/2`, with no record-layout change. The coordinator deployed this repair before the alternate-entry update.

On **2026-09-05 at 12:57:47 UTC**, the coordinator hotloaded the following two baseline-only beams under the shared deployment lock, with zero FreeSWITCH calls and the apps process ID unchanged. The deployed SHA-256 values matched the private build exactly:

```text
cf_acdc_member.beam
ae9ad1a66ef2039de07cafa16b746e5b11deae9d75b78202185c70432b9bd094

acdc_callback_menu.beam
0797ef59bb3535be9eb986c5a0e230de3c224719c719adde0401ef0a9a9a78fa
```

Before deployment, rebuilding the unmodified baseline reproduced both saved and live-loaded bytecode MD5 values exactly:

| Module | Pre-update loaded/rebuilt bytecode MD5 |
| --- | --- |
| `cf_acdc_member` | `74100a618b407e5c06e13ee3ffd1422a` |
| `acdc_callback_menu` | `9bb2df88f82e8835e165e84a15f62b74` |

Production artifacts have no TEST flags or test exports and preserve all record layouts. After normalizing source locations and the logging transform's generated variable suffixes, executable changes are limited to `run_callback_actions/4`, new `collect_callback_alternate/2`, and reducer `new/3`.

The narrow changes are in the default ACDC integration patch; the language wrapper patch was rebased without promoting its language behavior. **Neither the staged language layer nor the staged atomic-answer layer was activated by this repair.**

## Originate settlement parser follow-up

The isolated fixture exposed a second, independent defect in cancellation recovery. Fresh channel observations correctly showed both original and returned caller terminated, but the recovery API reported unknown originate settlement. A direct, exactly correlated native registry query returned `SETTLED success` with the expected caller UUID and module epoch.

The cause was `mod_kazoo:api/4` transport normalization: it removes `+OK` from successful native replies. The ecallmgr reconciliation parser only recognized success replies that still included that prefix. It therefore discarded real settlement proof, and the fail-closed queue correctly retained the ticket as `cancelling` rather than inventing evidence.

The parser now accepts the same exact `PENDING`, `SETTLED success`, and `SETTLED failure` shapes both with and without the transport prefix. Error-tagged responses, malformed or extra fields, unknown outcomes, and conflicting media-node claims remain non-authoritative. The existing UUID/request/caller correlation checks are unchanged. All six focused ecallmgr tests passed, including normalized transport replies and negative cases.

The baseline-only production beam was deployed by the coordinator during **2026-09-05 13:11:55–13:12:04 UTC**, alongside the independently built returned-call boundary fix, under the shared lock with zero FreeSWITCH calls. SHA checks and module loads passed; process IDs and service restart counts were unchanged. Parser artifact:

```text
ecallmgr_fs_channels.beam
8b4873326c873a63ce02927b8ba5987418d746bf3be5e39aacecef6f4bf16f81
```

Its rebuilt pre-fix baseline matched the saved and live-loaded bytecode MD5 (`368fa8bb20bf547197f4427ad9916c9e`). Production records are unchanged, there are no TEST flags/exports, and the sole normalized executable change is `parse_originate_reconcile_tokens/2`. No staged atomic-answer behavior was activated.

Immediately after deployment, a read-only check showed the ordinary reconciler had changed the exact retained fixture ticket to `cancelled`, removed its lease, and cleared `reconciliation_required`. Fresh existing recovery API queries returned complete, exactly correlated successful originate settlement and complete termination evidence for both call legs. **No manual ticket advance, CouchDB rewrite, forged settlement, registry modification, or TTL change was used.**

Native settled-registry entries have a 15-minute retention period; pending entries do not expire. Positive offnet settlement is currently held in the caller worker rather than a separately persisted durable settlement receipt. Recovery after loss of that worker and expiry of registry evidence remains a durability-hardening concern; the parser repair does not relax the fail-closed behavior for truly unavailable evidence.

## Remaining acceptance work

The isolated live callback test reached same-number selection and returned-leg DTMF using payload type 101. It then failed the actual agent handoff: the returned call retained `resource_type = offnet-termination`, causing `kz_endpoint_v5:maybe_owner_called_self/4` to fail before an agent INVITE. The separate construction-boundary repair has since been deployed, and the retained ticket's cancellation is now verified as described above. A new live acceptance run must still prove the agent bridge and complete callback lifecycle. No MASTER-user callback recovery is claimed here.
