# Returned-caller confirmation deadline

September 8–9, 2026 — P0-CALLBACK-CONFIRM-01 deployed; positive native
short-window strict-media acceptance now passes after the bridge-identity fix.
See `doc/ecallmgr_bridge_identity.md`:52905/bf7220 passes full prompt, strict RTP,
confirmation1.146848s after completion, unanswered-first/retry bridge and restore.
The older failed evidence below is unchanged. Native negative final-attempt
expiry now passes as documented next.

## Native no-confirmation expiry — September9

Committed harness85fd6c2 with file-mode endpoint correction5a4d0ea is installed
on main10.1.0.44. No production rebuild/restart was needed for this acceptance:
the already deployed worker and bridge-identity corrections are exercised.
Terminal unit `kz5-callback-confirmation-expiry-main44-20260909b` exited0
(a606c9); cleanup/runtime check7a3f37 confirms zero calls and active services.
Run: `/var/log/kazoo-acceptance/20260909T021207Z`.

- Original caller registers callback while the only agent is busy, hears the
  full built-in success prompt and hangs up. Busy call ends after the proved
  prompt plus the required two seconds.
- First callback attempt deliberately goes unanswered, settles to durable
  `retry_wait`, and retries at the saved due time (1.007088s after due).
- Second caller answers but sends neither RTP DTMF nor SIP INFO. Agent remains
  logged in with its endpoint listening throughout; capture proves no agent
  INVITE and native evidence proves no agent leg.
- Full34648-sample/4.331s EN prompt matches installed audio (correlation.999995)
  with strict RTP timestamp coverage. Prompt ends4.870326s after ACK; Kazoo BYE
  follows3.031146s later, matching the three-second response timeout.
- Ticket ends `failed`, attempts2, `last_cause=confirmation_timeout`, runtime
  caller/agent/selected-agent fields cleared and no reconciliation flag.
- Real SIPp exits/counters pass; agent ready, unchanged services, fresh journal
  and file errors0/0, new cores0. Exact isolated queue edit restored15->3->15.
  `callback-confirmation-deadline-edit.json.verified=false` belongs to the
  separate positive digit1 verifier, which this negative case intentionally
  does not invoke; the independent negative proof is
  `callback-confirmation-expiry.json`.

Replay command (not a request to rerun an already passed case):

```sh
bash scripts/test-acdc-callback-retry.sh --live --keep-fixture \
  --fixture-account 8310dc3170a18de37f205d0da172df65 \
  --transport internal --language en-us --registration-mode entry-only \
  --short-confirmation-window --confirmation-expiry \
  --allow-absent-master-test-phones \
  --confirmation-reference /var/log/kazoo-acceptance/gemini-reference.main44-en-us.P5mWcmOn/acdc-callback-success.ulaw
```

Root-owned helper `scripts/test-fixtures/callback-confirmation-expiry.cjs`
builds only local synthetic PCMU silence and validates retained SIP/RTP and
durable-state receipts. No Gemini/API voice synthesis occurs. Generator,
timeout boundaries, missing-proof rejection and CLI restrictions pass; existing
88 retry groups and12 locale/reference groups still pass.

Receipt SHA256 values:

- `callback-confirmation-expiry.json`:
  `bae4858ce20efea1f156d1ac3e81d76475dcb10eb1205297982a7215490ed17a`
- `retry-returned.pcap`:
  `2ecf1f562a217b7a6c7250b681767f51f0f3cd0163bebe2bebea37996f9237ee`
- Restored `callback-confirmation-deadline-edit.json`:
  `18fa644a770da62ac8da2bd39c91dfa98cc1c7334e8eb342ee75d09ab7f62eec`
- `/root/kz5-acceptance/callback-confirmation-expiry-main44-20260909b.log`:
  `a218316a909b8fddffc2c5defc30b4360dd721f49252c3834aee516d39d00083`

Earlier run020712Z stays **FAIL**: SIP signalling, native terminal state and
offline full-prompt/3.030839s expiry checks passed, but SIPp exited253. Its pinned
3.7.7 `EXIT_RTPCHECK_FAILED=-3` graded the received speech as a failed echo of
the transmitted pattern. Corrected only this no-agent endpoint to file-mode
silence, as existing announcement acceptance already does; no tolerance increase
or ignored process exit. The strict received-audio gate is unchanged.

Scope: final-attempt response expiry and cleanup are now proved natively.
This is not proof that a first confirmation-timeout attempt retries correctly,
nor node/broker failure recovery, all language branches or production readiness.

The API permits `callback.confirmation_timeout=3`. The worker previously
started that three-second timer when it submitted playback, although the
installed English returned-confirmation recording alone is 4.331 seconds.
Consequently a caller waiting to hear the complete instruction could have
their attempt ended before they could respond. This is separate from the
retained RTP timestamp-gap investigation.

## Correction

- Keep a separate 30-second playback watchdog while awaiting the exact queued
  noop completion for this returned call and prompt.
- Start the configured 3–30-second response window once after that completion.
- Continue accepting digit1 during playback; no additional digit is required.
- Ignore foreign-call, foreign-noop, ordinary play completion, duplicate noop
  and stale timer events. Duplicate answer events cannot restart confirmation
  after handoff or while cleanup is in progress.
- Missing completion or invalid playback acknowledgement follows the existing
  `media_failed` cleanup policy; response expiry remains `confirmation_timeout`.
  Neither case connects an agent. Cleanup and retry ownership are unchanged.

The worker record gains private in-memory correlation fields; there is no new
queue/database field or migration. Deploy by normal service restart, not a
manual hot load of the changed record layout. Prerecorded WAVs are unchanged.

## Evidence and limits

Actual worker transition regression `77012/66fe74/f3caa1` fails before the fix:
the initial playback timer is only three seconds. Six existing tests pass.
Final candidate `14542/a37868` passes all7 caller tests in7.207s, including
matching completion, stale/foreign/duplicate events, early confirmation,
playback watchdog expiry, response expiry, and invalid playback acknowledgement.
These are isolated Erlang transitions with mocked media submission, not live
SIP playback or broker-delivery acceptance.

OpenAPI generation `2949/d80fc6` passes:358 paths,653 operations,509 schemas,
1,653 references. The root-owned overlay documents the timing semantics;
no ignored upstream schema file was edited.

Required next acceptance: normal `kazoo-apps` deployment plus runtime module
parity, publish `/apis`, then one scoped native returned-call case with
confirmation_timeout3 and the existing >4-second prompt. Require full prompt,
digit1 after completion but within the response window, a single agent bridge,
and exact fixture restoration. Do not rerun unrelated load/voice suites or
mark the separate strict RTP-timing failure passed.

Source `f593ab0` is pushed to master and deployed on main. Pre-install93ecc5
confirmed zero native calls. The normal deployment completed successfully:

- Unit: `kz5-callback-confirmation-deadline-main44-20260908`.
- Observer:68345/50b9bf, exit0 in11m44.842s,368.2MiB peak.
- Log: `/root/kz5-acceptance/callback-confirmation-deadline-main44-20260908.log`.
- Log SHA256: `feb5b47cf818460776ac4eb9458d2d0df9fb1a92806d3c12fffcf881fb176f7e`.

Runtime check16532/e149bd confirms `acdc_callback_caller` is loaded from its
production BEAM in `/opt/kz5/applications/acdc/ebin/`, matching disk MD5
`c36359252aa5033a4bfc1acbf2828d7f`. Test-only helpers are not exported. Both
apps/eCallMgr were active; post-deployb43491 confirmed zero calls before testing.
This installer job is terminal; do not poll or repeat it.

Static `/apis` publication also passed (unit
`kz5-callback-deadline-docs-main44-20260908`,87971/df0dc1,834ms). HTTPS readback
383c7f confirms the queue confirmation-timeout description. This uses the
private main address with certificate validation, not a public-routing test.

The ordinary retry fixture installs `confirmation_timeout:15`; an ordinary
retry PASS therefore cannot prove this minimum-window case. The new explicit
`--short-confirmation-window` mode uses the same retained main fixture and
busy-agent/unanswered-first/retry flow, but adjusts only that field15->3 through
the unified editor after queued registration. It verifies the saved value,
keeps EN and the exact installed >4-second recording, and schedules digit1
six seconds after ACK rather than the normal eight. The existing strict full
returned-audio gate must prove completion before digit1 with a positive gap
of at most3 seconds. The recording must not be shortened or regenerated.

The option requires explicit main fixture, EN, internal transport and entry-only
registration, rejects duplicates, and cannot combine with the queue-language
edit case. Existing private shared-lock, tenant, revision and ambiguous-write
guards are reused. Cleanup settles the owned call first, then restores3->15
only if the exact edited queue revision/content/roster still match. Uncertain
or intervening writes are retained for inspection, not automatically overwritten.
This restores the timeout adjustment, not every retained historical fixture.

Pre-live checks: deadline patch/prior-value/revision guards pass50d4f3; all12
synthetic CLI/reference/configuration/CSV groups pass54990/f32637. The first CSV
test used `/dev/stdout`, which is not reopenable for that spawned output handle
(e05b61); the corrected test uses a private temporary CSV and checks0600 mode.
No database, provider or SIP activity occurred in those checks.

On main, after deployment completes, add the mode to the existing native flow:

```sh
bash scripts/test-acdc-callback-retry.sh --live --keep-fixture \
  --fixture-account 8310dc3170a18de37f205d0da172df65 \
  --transport internal --language en-us --registration-mode entry-only \
  --short-confirmation-window --allow-absent-master-test-phones \
  --confirmation-reference /var/log/kazoo-acceptance/gemini-reference.main44-en-us.P5mWcmOn/acdc-callback-success.ulaw
```

Use a bounded unit and protected log. The mode retains
`callback-confirmation-deadline-edit.json` alongside normal packet/bridge
evidence. Source0615e50 is synced to main. Preparation43222/e62431 passed with
no API writes or SIP traffic. Native unit `kz5-callback-short-window-main44-20260908`
completed (observer21843/e6c70b, exit1 in3m56.375s,70.4MiB peak), log
`/root/kz5-acceptance/callback-short-window-main44-20260908.log`.
Observation8acc59 confirms timeout edit, original audio, unanswered first attempt,
durable retry and reciprocal second bridge. The lifecycle/phase-scoped SIP/RTP
gate passed, but the full returned-audio gate failed `covered.every(Boolean)`
at `assert-callback-returned-audio.cjs:62`. The conditional timeout restoration
completed with state=restored, verified=false (925311). Independent e16c85
confirms zero calls and active apps/eCallMgr. The later aggregate log/core and
agent-readiness gates were not reached; do not claim full acceptance.

Evidence directory: `/var/log/kazoo-acceptance/20260908T231049Z`.
Run-log SHA256:
`ed0c3069bc5ac8a48c8f9788e8e44963b74aa369133426639067acbe09489f73`.
Do not repeat this call to hunt for a PASS. The additive offline diagnostic
now accepts the `deadline` scenario, checks the exact15->3->15 receipt and
actual complete ordered English payload/digit timing, and preserves the strict
failure independently. It explicitly does not claim native negative-expiry
coverage.

Offline replay44e6d4 completed successfully with zero database writes, provider
requests or new calls. Its additive receipt is
`/var/log/kazoo-acceptance/20260908T231049Z/callback-deadline-payload-diagnosis.json`.
The entire4.331s installed English recording matches the ordered received
payload (correlation0.999995). Playback completed4.971535s after ACK; digit1
arrived6.016987s after ACK,1.045452s after completion. The saved three-second
setting therefore permits the full instruction and subsequent confirmation,
and the second attempt connects. The15->3->15 restoration is verified.

This is positive deadline/lifecycle evidence only. Packet sequence loss is zero,
but RTP timestamps advance80ms at payload sample4160 and20ms at sample5760,
the latter inside the prompt. The strict timing failure is unchanged; no native
negative response-expiry claim is made. Capture SHA256:
`65ffaf8f8fb2963389b1f70c60b7992d589e513101f15caf52dd8f313446f677`.
Use these retained captures for CALLBACK-RTP-01 source diagnosis; do not rerun
the native case merely to obtain a PASS or regenerate the prerecorded voices.
