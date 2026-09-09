# Callback playback: reject invalid bridge partners

September 9, 2026 — fixed, deployed and scoped native callback acceptance passed.

`ecallmgr_fs_channel:is_bridged/1` accepted any binary Other-Leg-Call-ID,
including an empty binary and the channel's own UUID. The mod_kazoo other-leg
definition includes `variable_origination_uuid` as a fallback, so an originate
identifier is not sufficient evidence of a distinct bridged partner.

The root-owned `scripts/patches/ecallmgr-bridge-peer-identity.patch` requires a
nonempty binary different from the queried channel UUID. Undefined/missing
channels stay unbridged; real distinct peers retain prior behavior. No channel
records, routing, account data or FreeSWITCH timer settings are rewritten.

The normal `ensure_kazoo_sources` path applies the patch after the eCallMgr
integration patch, so fresh and repeated shell installations receive the fix.
The pinned ignored eCallMgr checkout is not committed separately.

## Focused evidence

`scripts/test-ecallmgr-bridge-identity.sh [--baseline]` compiles production
`ecallmgr_fs_channel` and `ecallmgr_call_command` into a private temporary
directory, without TEST defines or loading into a running Kazoo node. Tests
use actual isolated ETS channel records and the public dialplan renderer;
only media-path/variable formatting is mocked. Real bridge detection is not.

- Baseline78405/01f34c:4 failures,4 passes. Both invalid peers were treated as
  bridged and selected broadcast instead of ordinary playback.
- Candidate66747/ff3526:8/8 pass in6.644seconds. The actual installer patch
  helper applies to clean pinned source and is idempotent on a second pass.
- Baseline evidence:`/tmp/kazoo-bridge-identity.vZPE06Tq`.
- Candidate evidence:`/tmp/kazoo-bridge-identity.yhseP9K7`.

The additive `assert-callback-direct-playback.cjs RUN` reads only the exact
retained returned-call EXECUTE records, saves numeric/action evidence without
phone numbers or media URLs, and requires park -> playback -> noop -> intercept
with no broadcast. Applied to the retained pre-fix run,8ed28a fails as expected
with broadcast count1. It does not replace the separate strict RTP checker.

Normal CLI deployment `kz5-callback-bridge-identity-install-main44-20260909`
completed successfully63457/8ce274 in4m8.648s. Source4f0b77c was applied by
the normal installer before compilation, and eCallMgr restarted successfully.
Log SHA256:`38c46300947ecad1b3308c8e1114d1a08a8fc97543aa1ae9df4c9365a4e14dcb`.
Runtime/disk parity3ef807 matches MD5`349067bcb00612035743d1f1d64b55a0`,
loaded from `/opt/kz5/applications/ecallmgr/ebin/ecallmgr_fs_channel.beam`.
The source reverse-patch check passes; b75bb7 confirms loaded status and
apps/eCallMgr/FreeSWITCH active. Zero calls before acceptance. Normal role
checks passed native event/intercept inventory, framing and exact-node cleanup.

The single uninstrumented candidate case
`kz5-callback-bridge-identity-case-main44-20260909`,52905/bf7220, exited0 in
4m2.577s,101.1MiB. It used the retained main fixture and
`--short-confirmation-window`. Every existing gate passed: registration audio,
unanswered first attempt, durable retry, reciprocal second bridge, full returned
phrase/strict timestamp continuity, agent-ready, unchanged services, no fresh
journal/file errors and no new cores. The exact timeout15->3->15 restore is
verified. Zero calls afterward; apps/eCallMgr/FreeSWITCH remain active.

Direct-playback335c7e passes: park -> playback -> noop -> kz_intercept, with
zero broadcasts. Playback begins at the command handoff instead of100ms later.
The4.331-second EN recording has34,648 samples and correlation0.999995;
it finishes4.871845s after ACK and1.146848s before digit1, within the3s response
window. No tracer, provider calls, voice changes or weaker checker were used.

Retained evidence:`/var/log/kazoo-acceptance/20260909T014723Z`.
SHA256 pins:

- Case log:`5bdf5407f4c41a42e8efae53f6f3c7487263d9772d145745dfd48b6ed3bcc2d9`.
- Returned capture:`63d9733d66a806523d283fd9ed33a04988ab9dc11fec7e80c58713dea0af1d6a`.
- Restored deadline receipt:`31ba3d18489c35a2a22e0ca458834f519a28f62d9afaeeaa7a3d825c2645a8ab`.
- Direct-playback receipt:`d62330e436bda4889dec42fbf03955c7251d7ed6231e7e3a28fbeaa0aeaf8af3`.

Both deployment and acceptance jobs are terminal. Reuse this result; do not
repeat it without a relevant change. This closes the reproduced callback
playback defect, not all telephony/media or production reliability guarantees.
Native negative confirmation-expiry and cross-node/failure/soak gates remain.

This is a confirmed source bug and a candidate explanation for CALLBACK-RTP-01.
The retained native returned call was parked, yet its log shows broadcast at
01:27:46.768276 and playback at01:27:46.868296. FreeSWITCH's broadcast path adds
five lead frames, read without writing media, before playback. The previous
trace proves accumulated write-timer expirations and the exact timestamp gaps.
The historical ETS peer value was not saved, so do not claim this alone proves
the complete runtime cause.

Acceptance used normal `install-kazoo5.sh ecallmgr`, then runtime/disk
module parity and one isolated short-confirmation callback case. It required the
returned call to use direct playback rather than broadcast, retain unanswered
first attempt/retry bridge, complete prompt before digit1, pass the unchanged
strict RTP check, and restore the fixture timeout. No voice regeneration or
global RTP workaround. See `doc/callback_timerfd_runtime.md` for retained
pre-fix proof. If another gap remains, preserve the failure separately.
