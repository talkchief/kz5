# Redelivered queue member calls

## Defect — found natively September 17, 2026

A queue worker holds its caller's `member_call` broker delivery unacknowledged
while it rings agents and until the call is handled. If that worker's node loses
its broker connection, RabbitMQ **redelivers** the delivery to a worker on a
healthy node. That worker had no way to know what happened to the caller and
rang agents for it again.

`kz5-stage-queue-partition-8` (exit 1) shows the consequence. Apps14 was cut off
from the broker while its caller's conversation ended. The healthy apps20 worker
received the redelivery and rang agent 1 for a caller who had already hung up at
23:19:17, 23:19:25 and 23:19:33; each ring timed out. Three "failed connects"
reached `max_connect_failures`, and at 23:19:39 apps20 logged the agent out:

```
automatic logout of agent d757...: 3 consecutive failed connects reached max_connect_failures 3
```

The harness then failed because its pinned agent process no longer existed. A
broker fault on one node therefore logs agents out on another. The warning line
that made this visible was itself added the same day (`acdc_agent_recovery.md`);
before it, the logout was logged at debug.

The same run again showed the unresolved-proof repair working on apps14:
unresolved 23:18:54, released on complete terminated evidence 23:19:54.

## Correction

`acdc_queue_fsm` inspects `#'basic.deliver'.redelivered`. Only for a
redelivery, after the manager's cancellation check and before any agent is
asked, it observes the caller once through
`acdc_callback_recovery_io:observe_channels/2` (5-second watchdog):

| Complete evidence | Action |
| --- | --- |
| caller terminated | acknowledge and drop the stale delivery; nobody rings |
| caller active and bridged to another leg | acknowledge and drop; the original worker still owns that conversation |
| caller active, not bridged | a genuinely waiting caller: continue to agents as before |
| unknown / incomplete | retry after 2 s, at most 3 attempts, then continue as before with a warning |

A first delivery is never probed, so ordinary calls gain no latency. The final
unknown fallback deliberately keeps the old behavior rather than stranding a
caller who may still be waiting. Dropping uses the listener's existing
`ignore_member_call/3`, which acknowledges and announces delivery settlement.
No statistic is published by the dropping worker; the original worker
reconciles its own call. If that node never returns, the waiting statistic of
that call is left to existing expiry. The FSM state record is unchanged.

## Verification

`bash scripts/test-acdc-ordinary-bridge-proof.sh` runs 13 groups. The four
`ordinary_redelivery_*` groups fail on `b7064f2` and pass on the candidate:
terminated caller dropped without ringing; bridged caller left to its owner;
waiting caller and a normal first delivery still ring (and the first delivery is
never probed); unknown retries twice then falls back, ignoring stale and foreign
results. Unit 60, strategies 21/20, callback-queue 27, markers 8,
agent-maintenance 138, callback-announcements 12 and dashboard-events 24 pass.

Native proof is the same partition campaign after deployment: the healthy
node must log the verification and the drop, and must not log an agent out.
