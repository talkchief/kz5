# Bridge stalled-loop restart safety

September9,2026 — source correction; native deployment pending.

The service already excludes exit78 from automatic restarts because an
unsettled delivery might have reached FCM/APNs. However, the separate broker-loop
watchdog used exit1. If the owner stalls inside dispatch, ACK or broker I/O while
a provider worker is active, that exit lets systemd restart and redeliver the
same push without knowing whether it was accepted. This is a source-policy
inconsistency, not evidence that a real phone received a duplicate.

`BridgeRuntime.start_self_watchdog()` now exits78 and logs the fixed category
`broker_loop_stalled_manual_recovery_required`, plus elapsed seconds only.
Do not infer idle safety from a stale progress timestamp or inspect owner-only
settlement state from the watchdog thread. A hard stall cannot prove either.
Ordinary idle broker disconnect/reconnect is unchanged. The configured stall
timeout, five-second watchdog check, delivery deadlines and provider behavior
are unchanged. No queue migration or credential change is needed.

Operational tradeoff: a hard owner-loop stall requires investigation and explicit
recovery, including genuinely idle hard stalls. This prevents the known unsafe
automatic replay path; it is not high-availability or exactly-once delivery.
Do not blindly restart a failed bridge after an uncertain send. Preserve queue
bodies, delivery metadata and logs; use the existing recovery plan. This patch
does not implement automatic resolution of uncertain provider outcomes.

Regression in `scripts/test-push-bridge-deadline.py` uses the actual watchdog:

- Baseline64767/0fb10a:21 tests,2 fail. The actual isolated child exits1 rather
  than78; direct watchdog policy also returns1. The other19 tests pass.
- Tests cover the exact timeout boundary, healthy/stopped state, daemon thread,
  fixed diagnostic and the unit's `RestartPreventExitStatus=2 78` contract.
- The real child runs the production watchdog for one five-second check; it
  constructs no provider, connection, socket or credentials.
- Candidate7105/044fc0: all21 deadline/watchdog tests pass in8.326s, including
  actual child exit78. All27 settlement/owner-loop tests pass in0.121s.

Deploy via the normal modular entry point, not by replacing a live Python file:

```sh
bash scripts/install-kazoo5.sh push-bridge
```

Candidate results and main-host deployment evidence will be recorded here after
completion. Physical FCM/APNs delivery remains user-waived, not a test pass.
