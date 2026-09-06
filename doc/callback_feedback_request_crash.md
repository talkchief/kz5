# Callback unavailable-feedback crash — 2026-09-06

Status: reproduced, corrected in source, and verified by the isolated feedback suite.
No live code has been loaded or restarted for this investigation.

## Observed incident and cause

Read-only inspection of the existing `kazoo_apps/crash.log` and the bounded
`kazoo-apps.service` journal window found two callflow crashes at 14:29:21 and
14:29:43 UTC. Both followed `callback menu unavailable: invalid_number; resuming
live queue`. The original stack was `kz_json:get_value1/3` →
`get_binary_value/3` → `get_ne_binary_value/3` →
`cf_acdc_member:callback_unavailable_event/4` →
`wait_callback_unavailable/4` → `callback_paused/4`. The callflow executor then
rethrew `badarg`. No new calls were placed to obtain this evidence, and no raw
caller/account identifiers or credentials are copied here.

The feedback handler used a nested `Request.Call-ID` lookup as an eagerly
evaluated default for the top-level `Call-ID`. Ordinary call metadata can carry
a SIP address string in `Request`; only dialplan error envelopes use a command
object there. Traversing a scalar with the JSON object accessor raises `badarg`,
even when a valid top-level call ID makes the fallback unnecessary. The media
error correlation branch had the same assumption for `Request.Msg-ID`.

This identifies a concrete failure in the invalid-number recovery path. It does
not prove that every reported key-6 problem has the same cause, nor establish
the persisted callback-ticket state for the operator's reported call.

## Source correction and tests

`cf_acdc_member` now reads the top-level call ID first. Only when it is absent
does it inspect a nested request, and only if that request is a JSON object.
Nested media-error message-ID lookup uses the same typed helper. Existing
call/noop correlation, queue membership and wait deadlines are unchanged.
An invalid callback number is still not accepted as a successful registration.

The focused feedback suite uses actual JSON accessors and the source wrapper,
with call-control/prompt/AMQP providers replaced by explicit in-memory fixtures.
New cases cover SIP-address requests, six non-object JSON shapes, ignored stale
errors and missing IDs, top-level foreign-call precedence, valid nested error
envelopes, and invalid-number feedback followed by resuming the same member.

Before-fix session `22426` failed three cases with the same JSON-accessor and
feedback stack, while 14 existing/control cases passed. It ran under the
384-MiB, zero-swap, 50%-CPU guard and an isolated network namespace. The separate
post-fix session `9643` passed all 17 tests with the same guard and unchanged
timing/correlation assertions. The full invalid-number path now reaches the
resume acknowledgement and preserves the original queue member in the fixture.
Production compile session `44008` also passed: all 63 ACDC production modules
compiled with `-Werror`, without TEST options or agent test exports. Input
freshness checks passed; no application BEAM was loaded or installed.
The corrected source SHA-256 is
`fb82500f94faa90ee32b20a3ecbb8f8ad683fc49763e2b78ff63df0395b6a622`;
the feedback fixture SHA-256 is
`69b1874c8d0914090c7798d85b6b8f636bd3f584d16cb256e3e5f08ad8567bab`.

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 360 -- /usr/bin/unshare --net -- \
  bash scripts/test-acdc-callback-feedback.sh

bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 180 -- /usr/bin/unshare --net -- \
  bash scripts/test-acdc-production-compile.sh
```

Deployment must include the matching `cf_acdc_member` source/BEAM and relevant
dependencies in the coherent release review. Passing this fixture does not
prove native audio delivery, callback registration/retry, or live fallback
continuity. Those P0 acceptance gates remain open.
