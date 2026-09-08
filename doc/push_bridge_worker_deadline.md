# Mobile bridge unfinished-worker deadline

The bridge now bounds how long a healthy broker owner loop can leave unfinished
provider work pending. Configure `PUSH_BRIDGE_DELIVERY_TIMEOUT` in the protected
bridge environment: integer seconds, default60, minimum10, maximum300. No secret
or new production dependency is required. The existing main SH bridge installer
includes all three changed runtime modules in its release inventory.

Each admitted worker receives an immutable monotonic deadline before submission,
covering executor queue and OAuth token-lock waiting. At the deadline an unfinished
future is uncertain, not a failed send: no ACK, NACK, rejection or automatic
replay is issued. Known completed provider outcomes retain their existing
settlement policy, even when observed after the deadline. Completed transient
outcomes awaiting the existing retry delay are not unfinished worker timeouts.
Pending bookkeeping remains bounded by the existing prefetch/admission limit.

On a detected unsettled generation the production entry point arms a three-second
daemon exit78 timer before connection, notification or executor cleanup. This
also terminates a process with blocked executor threads or blocked cleanup.
Failure to start that timer exits78 immediately. New delivery/provider-send
entry points are fenced and queued tasks are cancelled during cleanup. A later
SIGTERM cannot replace the armed exit78 with exit0. The existing systemd
`RestartPreventExitStatus=2 78` deliberately prevents automatic uncertain replay.

## Scope and operational recovery

This is not a hard whole-process delivery SLA. Detection depends on the owner
loop continuing to drain. Blocked broker dispatch, scheduling starvation, the
separate STALL_TIMEOUT watchdog, broker retention/failover and actual device
delivery need their own acceptance. Already-started provider I/O may have reached
the provider; cancellation or absence of delivery is not proven. Preserve broker
and provider evidence before manually recovering exit78. Replaying an uncertain
push may duplicate a send. This fail-stop policy is not high availability.

## Regression evidence

Private candidate run12055/09efad passed205 tests across14 isolated Python suites
with the installed pinned Python3.11 dependencies and networking disabled.
The18 new deadline cases cover exact boundaries, queued/running work, independent
admission times, completed outcomes, clock failure/rollback, ownership, late
completion fencing, companion settlement, configuration, provider-send fences,
timer failure, signal behavior and production entry-point selection. A real
private child with a blocked executor worker and blocked synthetic connection
cleanup exited78 within the eight-second parent limit. No broker, provider,
credential file or actual phone was used by this test.

Deployment and actual basic.consume/broker/device acceptance are recorded in
PROJECT_TASKS.md; these offline tests alone do not close those release gates.

Repository-source rerun82499/98c851 passed the same205 cases plus main installer
smoke checks. Main-SH bridge install and separate verify74779/c9f0f1 passed;
release `0a3a5ba26bdf26caa9fea2343fb565c3ce218079cf976eb5be801ac9143e94da`
is active on the development server with exact source parity and registered
broker-consumer readiness. Dispatch/rollback tests82966 also pass. No actual
FCM/APNs send was performed; production broker/server were not changed.
