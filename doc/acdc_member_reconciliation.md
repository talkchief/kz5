# Queue member reconciliation

## Defect — found natively September 18, 2026

Queue managers on every node keep their own copy of the waiting members.
Copies are kept in step only by broadcasts (`member_add`, `member_remove`,
`call_success`) that are **not durable**: a manager whose node loses the broker
never receives what was published meanwhile.

`kz5-stage-queue-partition-10` (exit 1) held the apps14 partition for 120 s
instead of 35 s. The first call was handled and ended normally on the healthy
node. After the route returned, apps14's manager still listed that finished
caller `1-144043@...` as a waiting member, indefinitely:

```
apps14  current_member_calls=[<<"1-144043@172.30.253.1">>]  ignored_markers=0
apps20  current_member_calls=[]                            ignored_markers=0
```

Workers and listener dispatch were drained and the cancellation markers were
zero, so this is separate from the marker leak. Effects of a phantom member:
wrong position announcements, a wrong "up next" decision for real callers on
that node, and a maintenance gate that can never drain. The 35-second run did
not show it because the call had not ended before the route returned.

## Correction

The switch is the authority on whether a caller still waits. Each
`acdc_queue_manager` runs a 60-second timer and examines at most five of its
oldest **ordinary** members through `acdc_callback_recovery_io:observe_channels/2`
in one watchdog-bounded probe (20 s); the timer is re-armed first and a probe
that never reports is killed by the next tick.

| Complete evidence for the member's caller | Action |
| --- | --- |
| terminated, with at least one responder | remove locally |
| active and bridged to another leg | remove locally (handled, not waiting) |
| active and unbridged | keep |
| unknown, incomplete, no responders, unexpected shape | keep |

A member is first examined 30 s after this manager first saw it, so a caller
about to be answered is never touched. **Callback members are never examined**:
they deliberately have no caller channel while they wait (`acdc_callback_id`).
Removal is local and publishes nothing; the owning worker still publishes its
own events. The manager record gains `member_reconcile`: cold restart only.

## Verification

Four groups in `applications/acdc/test/acdc_queue_manager_tests.erl`
(`bash scripts/test-acdc-unit.sh`, 64 pass): removal only on complete evidence
with a re-armed timer and stale results ignored; new and callback members never
examined, including a forged result; a hung probe replaced on the next tick; at
most five members per tick. Markers 8, callback-queue 27, ordinary proof 13,
strategies 21/20 and agent-maintenance 138 pass.

Native proof is the same 120-second campaign after deployment
(`KZ5_QUEUE_PARTITION_HOLD_MS=120000`): the strict drain must pass within its
bound. The harness knob is validated to 35000..150000 ms, below the 3-minute
route watchdog.

## Still open from the same campaigns

The redelivery admission (`acdc_redelivered_member_calls.md`) has **not** been
exercised natively: RabbitMQ gives each queued call to a worker on either node,
and in runs 9 and 10 the healthy node's worker owned it, so nothing was
redelivered. The harness always partitions apps14. It must partition the node
that owns the delivery before that gate can close.
