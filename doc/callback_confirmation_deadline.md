# Returned-caller confirmation deadline

September 8, 2026 — P0-CALLBACK-CONFIRM-01, source fixed; deployment pending.

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
