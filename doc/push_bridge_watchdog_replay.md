# Bridge stalled-loop restart safety

September9,2026 — corrected, deployed, targeted native checks pass.

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

Physical FCM/APNs delivery remains user-waived, not a test pass.

## Installer permission correction found during deployment

Normal `push-bridge` deployment under root `umask077` failed before activation
(24aec4): venv/bin were mode0700, so the service-user prerequisite got
`Permission denied`. Existing service PID57635 stayed active with restarts0
(491c28). Do not call that install successful or weaken the service-user check.

The installer now runs only venv/pip creation under a subshell `umask022`.
These are public code dependencies, not credentials. Caller umask and protected
`/etc/kazoo-push-bridge` files are unaffected. Release fingerprint includes the
layout recipe, so the old root-only staging directory is not silently reused
or chmodded recursively. Failed stage is retained, never activated.

Actual helper regressions979dba pass: both stages see022, caller stays077,
venv/pip errors propagate even under conditional invocation, alongside aliases,
standalone/ALL dispatch and all seven activation/rollback cases. Native retry
deliberately used the same restrictive077 launch environment and passed.

## Main-host acceptance

Sourcebd083e5 (watchdog) and01e60eb (installer) are on master and main `/opt/kz5`.
Normal CLI unit `kz5-bridge-watchdog-install-main44-20260909b` completed exit0
(c112d9). It did not bypass preflight, dependency checks, service-user permission
checks, activation or the registered-consumer readiness check.

- Active release:
  `c56fa2ba135a697324a4e9ac0f92c2639cb305039e4546c93a67e6a3f99f79d1`
- Installed/source `bridge.py` SHA256:
  `79ce9f1f961e253738027cd07b4de627cbed0329bcbd3b70e393f65f5054cf93`
- Root-owned venv and bin are0755; actual non-root service PID1098394 is active,
  NRestarts0, status `AMQP consumer registered; mobile delivery not verified`.
- Main install log `/root/kz5-acceptance/bridge-watchdog-install-main44-20260909b.log`:
  SHA256 `2511e3cd1afe7b0e559f816862ad7425b333adbed730306d5bb632bf6c2c756f`.

The separate `kz5-bridge-watchdog-policy-main44-20260909` unit runs the installed
production watchdog as the bridge user, with `PrivateNetwork=yes`, no provider
construction, and no broker connection. It uses the installed unit's verified
`Restart=on-failure`, `RestartPreventExitStatus=2 78`, `RestartSec=10` policy.
Its synthetic last-progress timestamp represents a stalled owner. After one
real five-second watchdog check it exits78; a later observation beyond the
restart interval confirms NRestarts0 (492e8f). Actual bridge PID1098394 remains
unchanged and active. This is real installed-code/systemd policy acceptance,
not injection of a hung actual provider or proof of full delivery recovery.

Protected evidence on main:
`/root/kz5-acceptance/bridge-watchdog-policy-main44-20260909.properties` and
`bridge-watchdog-policy-main44-20260909.log`. Intentional failed fixture-unit
states were reset only after retaining properties/logs; no deployed service
was reset or stopped during the policy check. Failed initial install stage
and log remain preserved. No production10.1.0.28 configuration was touched.

Policy-properties SHA256:
`919e7470ecade0ffee34cf91314c61ac05cb5bdb2c98135c0f4d200a6d949da8`.
Policy-log SHA256:
`fd84afb9f3fd42e56b484c7f42043954b46b44bf9720b7dbee880449639df079`.
