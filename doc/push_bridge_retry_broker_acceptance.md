# Isolated counted-retry broker proof — development PASS

Root live execution `feecd1/session48563/ac00b2` passes all four cases below on
September7,2026. Receipt:
`/var/log/kazoo-acceptance/kz5-retry-proof-fba06be0-64dd-4fac-be80-b6edd5d2bf33/receipt.json`.
Source remained stable; original broker counters were absent/false on first
delivery, then1/true and2/true on redelivery. Synthetic dispatch totals were
retry-success2, companion1, exhaustion3 and channel-close2; expired had none.
Temporary vhost and user were removed, no cleanup failure. Zero provider calls
and no production effects. This is not actual phone delivery or broker-restart,
lost-ACK, full-DLQ, or automatic process-recovery acceptance.

The prior `fa9192` run failed at add_user before any case. Its exact vhost was
removed; read-only checks also confirmed the exact user absent. The underlying
cause cannot be recovered because that version discarded command diagnostics.
Do not attribute it to password syntax without evidence. New durable allowlisted
command/status/category diagnostics pass ten offline tests (`debd38/b50cb1`);
the later live run records all six setup/cleanup commands as successful.

`scripts/accept-push-bridge-retry.py` is an explicit development-only acceptance
driver for the already tested, frozen counted-retry source. It uses actual
AMQPStorm messages and actual independently verified RabbitMQ quorum queues,
with separate threads returning synthetic FCM outcomes. It never initializes an
FCM/APNs sender, reads provider keys, sends a notification, imports production
configuration, restarts the broker, or changes legacy routing.

For a new source revision, root must first run the offline fixture and then the live
local-broker proof under its serialized guard:

```text
/usr/local/lib/kazoo-push-bridge/current/venv/bin/python -B -I scripts/test-accept-push-bridge-retry.py
/usr/local/lib/kazoo-push-bridge/current/venv/bin/python -B -I scripts/accept-push-bridge-retry.py --run-isolated-local-proof
```

No agent test, network, or service execution occurred while preparing this
source. The offline test simulates a broker to verify the case driver and
cleanup restrictions; passing it is not RabbitMQ evidence. The live command
requires root and exactly the shown flag; it accepts no broker host, credentials,
vhost, routing, provider, output-path or device overrides.

## Required real-broker observations

The driver uses confirmed persistent publishes into its own exchange and actual
Basic.Get deliveries with manual settlement. It asserts the original body is
unchanged at every work-queue or DLQ readback. Only the owner thread has message
handles; fixture workers capture immutable bodies/outcomes and an isolated
counter, never the channel or message.

1. A synthetic503 is held until the existing2-second owner NACK timer. A second
   synthetic200 message is ACKed before that NACK, proving the delayed message
   does not stall other completed settlement. The first message returns with
   count1/redelivered=true and is ACKed after synthetic200.
2. A second message follows actual count0→1→2 with synthetic503 at each dispatch.
   The existing2/5-second timer/NACK policy runs unchanged. The third failure
   reaches the existing DLQ; exactly three fixture workers ran and no fourth
   dispatch occurs. Both queues are checked empty after DLQ ACK.
3. A message is NACKed from count0, then held unacked at count1. Closing that
   channel and opening a new independently verified channel must return the
   unchanged body with count2, not reset the budget. No worker is submitted for
   the held count1 message. This is channel-close redelivery, not a process-kill
   or registered-consumer crash proof.
4. An already expired original `Push-Freshness` envelope reaches the DLQ with
   zero fixture worker submissions. The deadline is not replaced by receipt time.

Safe receipt fields retain actual counter presence, small integer counts and
boolean redelivery flags. Unknown types become `UNKNOWN`; raw header strings,
payloads and temporary credentials are never saved. Unexpected RabbitMQ counter
semantics fail the proof rather than changing production retry logic or relaxing
the expected count. The complete case driver is bounded to90 seconds, each
receive to10 seconds and each owner-drain to12 seconds. Individual AMQP connection
and broker-control operations retain their own10/30-second bounds.

## Resource ownership and failure handling

The script generates `kz5-retry-proof-<UUIDv4>` and creates only that local vhost
and temporary user on127.0.0.1. Its management URL is fixed loopback. All exchanges,
work/DLQ queues and permissions are inside that new vhost; no existing native
exchange or consumer binding is used. The password exists only in process memory
and the short-lived local setup call, never in a receipt or command output.

A root-owned0700 receipt directory under `/var/log/kazoo-acceptance/` retains
source hashes, phase, fixed failure categories, synthetic dispatch counts,
counter observations, successful resource creations and successful removals.
Receipts use0600 atomic replacement and fsync. On success or failure the connection
is closed and cleanup attempts only the exact generated vhost/user whose creation
was recorded successful. A timeout during creation can leave an uncertain setup
outcome; inspect that exact receipt namespace manually rather than deleting any
broader resource. Cleanup failure or source drift prevents a complete result.

The original counted-retry runtime and installer are not edited by this harness.
`complete=true` means only the listed synthetic broker cases and cleanup passed.
Broker restart, lost ACK/NACK, full/unavailable DLQ, automatic process recovery,
cross-restart backoff, hung workers, provider Retry-After support, APNs retries,
designated-device behavior and exactly-once delivery remain explicitly unproven.
