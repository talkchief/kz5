# Mobile bridge delivery recovery — open implementation gate

The imported bridge configuration comes from production Kamailio `10.1.0.28`.
The protected copy is outside Git; never embed its credentials, device tokens,
private keys or production unit environment in this repository. The development
consumer is isolated and running. This is not proof of phone delivery.

## Current gap

The settlement owner ACKs exact provider acceptance, but other outcomes can
terminate the consumer with exit 78. A permanent rejection or malformed message
must not indefinitely stop an otherwise healthy consumer. Existing durable queue
declaration alone does not establish bounded retries, expiry or durable quarantine.

Read-only installed-package inspection found RabbitMQ 3.13.7. The following is a
proposed policy, not implemented or accepted production behavior:

- Introduce explicitly selected, versioned quorum topology; do not redeclare an
  existing classic queue as quorum or attach both consumers to the same traffic.
- Bound work/DLQ bytes and message counts, use reject-publish backpressure, and
  verify at-least-once dead-lettering on the actual broker.
- Retain the original message for counted retries instead of a republish/ACK
  sequence. Keep AMQP settlement in its owner thread, never in provider workers.
- ACK exact acceptance; quarantine invalid, expired and permanent failures;
  bound transient/uncertain retries. A timeout after sending is not proof that
  the provider did not receive the request. Retries can duplicate notifications.
- Separate invalid configuration (exit 78) from recoverable connection failures;
  ensure old workers have terminated before restarting the consumer.

Proposed starting limits are three dispatches, 2/5-second retry delays and a
60-second work-queue TTL. These require explicit implementation and test evidence.
Current FCM internal retries must be reconciled with the broker attempt ceiling.
DLQ retention and topology permissions must be specified before deployment.

## Freshness contract required

Native `push_req` does not currently provide a validated, unambiguous expiry
contract. Its optional `Expires` integer must not be guessed to be Unix time.
`kz_amqp_util.erl` uses Gregorian microseconds for the default AMQP timestamp;
that value is not Unix seconds. `pusher_listener` adds a Unix-millisecond payload
timestamp to `endpoint_push_req`, which this bridge does not accept.

Define a versioned producer timestamp and absolute deadline, with bounded future
clock tolerance and maximum age. In strict mode, quarantine absent/invalid
freshness metadata rather than replacing it with now. A persisted first-seen
timestamp bounds observation age only, not original event age.

Check the immutable deadline before scheduling, after credential acquisition,
and immediately before provider dispatch. FCM TTL must reflect remaining lifetime
instead of restarting at 60 seconds. APNs immediate-only storage does not prevent
dispatch of stale broker backlog. Mobile clients also need expiry/deduplication
behavior; provider HTTP acceptance is not exactly-once ringing.

## Required tests before closing INST-13 recovery

Inject lost ACK/NACK, consumer death, broker restart, unavailable/full DLQ,
dead-letter routing failure, exhausted delivery count, expired backlog and expiry
during credential preparation. Prove bounded attempts and durable disposition.
Run these against isolated development topology, never the production broker.
Designated Android/iOS device testing remains a separate release gate.
