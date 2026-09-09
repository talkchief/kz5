# Callback active-worker loss — September 9 native acceptance

PASS on development host `10.1.0.44`, using only acceptance account
`8310dc3170a18de37f205d0da172df65`. No imported-company or PSTN calls.

The real SIP caller queued behind a busy agent, requested callback with digit6,
received the committed EN Gemini confirmation, and disconnected. After the busy
call released, the first returned call rang without answer. The fixture killed
exactly that active callback worker while its coordinator and durable ticket
still owned the same originating attempt. The old attempt settled before the
saved retry became eligible; the second attempt answered and completed a
reciprocal caller/agent bridge with SIP/RTP evidence. The final agent was ready.
The test did not re-login the agent to manufacture recovery.

Authoritative run:

- Unit `kz5-callback-worker-loss-native-20260909.service`, exit0 (3d4e5c).
- Evidence `/var/log/kazoo-acceptance/20260909T114942Z`.
- Packet receipt: `retry-packet-evidence.json`; kill receipt:
  `retry-worker-loss.json`. Treat the directory as protected fixture evidence.
- Two attempts; configured durable backoff15s. Actual cancellation-to-second
  INVITE21.049s includes settlement; second INVITE arrived0.790s after durable
  eligibility. Do not describe15s as the measured cancellation-to-retry interval.
- Busy-call release was5.331s after complete confirmation audio, satisfying the
  requested at-least2s wait. The endpoint and lifecycle checks passed.

`scripts/test-acdc-callback-retry.sh --worker-loss-during-ringing` retains the
normal retry contract and adds a mutually exclusive explicit fault boundary.
It requires the exact main fixture, internal transport, EN and entry-only
registration, plus the existing verified immutable confirmation reference.
`scripts/test-fixtures/callback-worker-loss.escript` derives record layouts from
the actual loaded production BEAM, verifies disk/runtime identity and exact
queue/ticket/attempt ownership, then monitors the selected worker's termination.
It rejects ambiguous ownership and offers a read-only inspection mode. No
production module is compiled or hot-loaded by the fault helper.

The first two runs refused the fault injection because systemd did not set
`USER`. They remain failed tests, not service bugs. The guard now checks all four
kernel UIDs, not an inherited environment string. Their tickets subsequently
settled cancelled and were not force-cleared. Offline guards,95 retry scenario
groups and14 language/scope groups passed before the final native test.

This closes this active-worker-loss case, not all callback failure modes. The
invalid/alternate-number native paths, broker partitions and old ambiguous
historical ticket remain separate. Nothing here retroactively supplies missing
ownership proof for that ticket. No Gemini provider was called, no voice was
regenerated, and the retained fixture is not a full-cleanup acceptance claim.
