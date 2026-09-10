# ACDC terminal agent-leg cleanup

## Native finding — September 10, 2026

Following the two-applications-VM cold restore, two actual queue2000 calls
passed audio and same-FSM recovery in `kz5-stage-queue-after-cold-restore-1`.
Independent maintenance collection correctly refused apps20 afterwards.
Read-only inspection of all six fixture replicas found exactly one listener
with two retained `{CallId, undefined}` control-queue placeholders. Its FSM
was ready and otherwise drained; the other five FSM/listener pairs were drained.
No state was cleared or hotloaded to conceal this result.

The scoped diagnostic is
`scripts/test-fixtures/distributed-lab/agent-drain-diagnostic.escript`.
It allows only the original private apps14/apps20 guests and owned synthetic
account, reads the installed BEAM record definitions, and emits booleans/counts
and leg-entry types, not call IDs or credentials. It unwraps the real
`gen_listener` callback state. There is no mutation or recovery command.

## Source correction

- The validated `CHANNEL_DESTROY` handler explicitly notifies the listener
  to retire the exact ended agent leg, including a pending control-queue entry.
  This is separate from `channel_hungup`, which can request cancellation of
  still-live legs. It neither clears unrelated work nor sends a hangup command.
- A control-queue notification may arrive after a native bridge has already
  moved the FSM into answered or wrap-up. Those states now forward it to the
  listener instead of dropping it.
- The listener updates control queues only for tracked origination intent.
  Late notifications cannot recreate already-retired legs.
- The strict maintenance predicate is unchanged. Missing terminal evidence
  still cannot be treated as proof that pending work is drained.

## Acceptance

`scripts/test-acdc-listener-terminal.sh` compiles the three production modules
privately with `-Werror +warn_missing_spec`, and tests pending/duplicate/unknown
terminal events, delayed and current control queues, actual validated handler
delivery, and answered/wrap-up forwarding. External broker/event I/O is mocked;
this suite is not a native call test. Five regressions failed against the
previous production source; an initial invalid handler-event fixture was
corrected separately and is not counted as a production regression.

All eight focused cases pass; evidence `/tmp/kazoo-acdc-terminal.z4yxn8` on the
source host. The queue-call harness now requires strict native inventories of
all six replicas, including actual listener bindings, before reporting PASS.

Normal private installers completed successfully on `8343d47`:
`kz5-stage-install-kazoo-apps-16` and `kz5-stage-install-apps-peer-12`.
Both terminal results were collected in `kazoo-apps-install-16.log` and
`apps-peer-install-12.log` under `/var/lib/kazoo5-install-lab` on dev44.
Main44 `/opt/kz5` is synced; this does not deploy its main runtime.
The maintenance/restore suite,27 recovery tests and13 channel-event tests
also passed before deployment.

**Native healthy acceptance PASS:** `kz5-stage-queue-terminal-cleanup-1`,
runner `6b4216e`; evidence `/var/log/kazoo-monitor-acceptance-5ZZRCj`.
Two actual queue2000 calls passed both audio directions using the same agent
FSMs, without re-login or SIP registration between calls. Independent RTP
reanalysis and fresh installed collectors confirmed all six replicas ready,
drained, consuming, with expected actual queue bindings and unchanged epochs.

**Native missed-hangup acceptance PASS:** `kz5-stage-queue-terminal-partition-1`,
runner `6b4216e`; evidence `/var/log/kazoo-monitor-acceptance-e3Y5w1`.
An applications14 broker-only interruption retained applications20. The exact
synthetic call ended during the interruption;15 samples confirmed the isolated
replica remained conservatively answered. Both original FSMs recovered after
connectivity returned and a second real queued conversation passed audio without
re-login/registration. The strict all-six-replica drain check passed, including
independent post-test collection. The exact broker routes were restored.

Both units exited0 and removed owned temporary users/registrations; independent
checks confirmed open media admission, zero sessions and no retained monitor
fixture. The earlier strict-drain failure remains failed, not rewritten.
These component tests do not close full cluster maintenance/coordinated rollback.

**Supervision regression PASS:** `kz5-stage-monitor-terminal-cleanup-1`, runner
`6b4216e`, tested all four supervision modes on the same installed apps source.
Independent analysis of `/var/log/kazoo-monitor-acceptance-CXndtt` confirms
audio privacy, supervisor stop202 and original bridge survival. All six strict
agent/listener inventories still pass after these direct calls. See
`channel_monitor_acceptance.md` for the exact scope.
