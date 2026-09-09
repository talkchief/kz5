# Callback playback: reject invalid bridge partners

September 9, 2026 — source regression fixed; deployment/native acceptance pending.

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

This is a confirmed source bug and a candidate explanation for CALLBACK-RTP-01.
The retained native returned call was parked, yet its log shows broadcast at
01:27:46.768276 and playback at01:27:46.868296. FreeSWITCH's broadcast path adds
five lead frames, read without writing media, before playback. The previous
trace proves accumulated write-timer expirations and the exact timestamp gaps.
The historical ETS peer value was not saved, so do not claim this alone proves
the complete runtime cause.

Required deployment: normal `install-kazoo5.sh ecallmgr`, then runtime/disk
module parity and one isolated short-confirmation callback case. Require the
returned call to use direct playback rather than broadcast, retain unanswered
first attempt/retry bridge, complete prompt before digit1, pass the unchanged
strict RTP check, and restore the fixture timeout. No voice regeneration or
global RTP workaround. See `doc/callback_timerfd_runtime.md` for retained
pre-fix proof. If another gap remains, preserve the failure separately.
