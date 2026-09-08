# Returned-caller confirmation deadline

September 8, 2026 — P0-CALLBACK-CONFIRM-01, source fixed; deployment running.

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

Source `f593ab0` is pushed to master and synced to main. Pre-install93ecc5
confirmed zero native calls. The normal deployment is currently running:

- Unit: `kz5-callback-confirmation-deadline-main44-20260908`.
- Observer:68345; authoritative54cee7 confirms active/running, MainPID741452.
- Log: `/root/kz5-acceptance/callback-confirmation-deadline-main44-20260908.log`.

Observe that exact job; do not restart it because output is quiet. Do not sync
additional source into main during the build. Completion/runtime parity and
static `/apis` publication remain pending.

The existing retry fixture currently installs `confirmation_timeout:15` in
`scripts/test-acdc-callback-fixture.sh`; an ordinary retry PASS therefore cannot
prove the new minimum-window case. Prepare an explicitly armed, exact-fixture
short-window adjustment with fresh readback and conditional restoration before
claiming native validation at3 seconds. The existing >4-second recording must
be retained, not shortened or regenerated to make the test pass.
