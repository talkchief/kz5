# Broker connection replacement must register its new PID

## Reproduced failure

The separate controller16 lost its broker heartbeat while a lab snapshot paused
the guest. At17:46:48UTC its connection worker crashed during a `channel_max`
query. OTP restarted that worker and RabbitMQ later showed a running TCP
connection with11 channels, but `kz_amqp_connections:connections/0` was empty and
`is_available/0` was false. The directory fetch listener waited indefinitely for
an AMQP assignment. The healthy controller21 could authenticate the call, but a
round-robin directory request sent to16 timed out after3100ms. No endpoint INVITE
was sent. Native monitor attempts3/4 remain FAILED, not supervision passes.

## Source correction

The old external `add/2` call registered the first worker PID only. An automatic
supervisor replacement never called it. The required core integration patch now
passes the zone in the supervisor's retained start arguments and registers each
worker from its own initialization, before that worker publishes availability.
Existing one-argument entry points retain the local-zone default. No record
layout changes or broad forced application restarts are introduced by the patch.

Normal apps/eCallMgr verification now requires native registered-broker
availability, not merely an active service, a TCP socket or connected media node.
Failures are bounded and do not print broker credentials.

## Evidence and limits

`bash scripts/test-amqp-supervised-registration.sh` compiles the actual three
production modules privately, without overwriting runtime BEAMs. Three real OTP
supervised-child replacements fail on preceding source and pass after the patch:
local, remote zone, and hidden remote broker. Tests mock logging and announce
availability explicitly; they never connect to a broker. Zone/tags/hidden flag
and new-PID availability are verified. Original test evidence is retained under
`/tmp/kazoo-amqp-supervised.icKQ4u` on the source host.

Both separate controllers passed normal installation on source `0957b33`:
`ecallmgr-install-5.log` and `ecallmgr-peer-install-3.log` in the original lab.
The native real-worker fault then PASSed at19:14UTC:
`/var/lib/kazoo5-install-lab/amqp-restart-1788981250927.json`.
The replacement registered, broker availability returned, the Erlang VM stayed
unchanged and normal eCallMgr verification passed without a fallback restart.
No synthetic availability notification was used in that native run.

Main44 normal apps/eCallMgr deployment on `ae12cbf` passed: native unit
`kz5-amqp-registration-deploy-20260909` exited0, terminal normal installer checks
passed, all nine services active, zero calls and zero error-priority apps/eCallMgr
journal entries since19:14UTC at readback. Distributed SIP/RTP supervision then
passed all four modes (`monitor-distributed-5.log`); peer automatic boot passed
(`ecallmgr-peer-boot-1788981642738.log`). This is not a claim about loss of the registry process itself,
an indefinite network partition, or a coordinated rolling upgrade.
