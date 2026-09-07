# Mobile bridge delivery recovery — open implementation gate

New narrow source candidate: `push_bridge_counted_retry.md` specifies explicit
strict-quorum broker-counted retries for completed FCM500/503 without Retry-After only, with one FCM
POST per delivery and nonblocking owner-thread delay/NACK scheduling. It is not
activated; actual counter/durability and failure-recovery proofs remain open.
Producer freshness and strict bridge deadline checks now exist (see
`push_bridge_freshness.md`); the historical producer audit below explains why
that additive contract was necessary, not a request to reimplement it.

Update: the explicit quorum topology, limits, live no-policy verification and
synthetic dead-letter routing portion is now implemented and tested. See
`push_bridge_quorum_topology.md` for deployment and evidence. This plan's
provider outcome/retry, source freshness and failure-recovery parts remain OPEN;
do not redo the completed topology work or infer that it closes the whole gate.

Further focused source change: explicit verified-quorum mode now quarantines
local malformed payloads and a conservative provider-specific set of permanent
rejections, while leaving legacy and transient/uncertain behavior unchanged.
See `push_bridge_permanent_quarantine.md` for exact dispositions and evidence.
This closes only that classification/owner-settlement slice, not the full plan.

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

Read-only producer audit (September7): the pinned
`kazoo-configs-kamailio/kamailio/pusher-role.cfg` builds native `push_req` without
a timestamp, expiry or deadline (lines143–144), then uses three-argument
`kazoo_publish` (line158). Its SHA-256 is
`0a27014d9582e4e7af00d027b5e68ff61e2298a694444bd3e31f828f5cfd1350`.
The local Kamailio source `src/modules/kazoo/kz_amqp.c`, SHA-256
`798cefdca441ed7f73487d8bbf65683d6bec3c40337b8a59ba673b57cb614782`, sets content
type but no AMQP timestamp/expiration in `kz_amqp_send_ex`. Therefore the
Gregorian timestamp from the Erlang publisher does not cover this actual
Kamailio producer path. Do not infer freshness from arrival time or Msg-ID.

Next implementation boundary: additive, explicitly versioned producer metadata
in the JSON envelope, independently validated by strict bridge mode. Preserve
legacy fields and make missing freshness fail closed only in the new explicit
mode. Producer changes belong in the tracked installer patch/config pipeline,
not a private edit on production10.1.0.28. No such change has been deployed.

Additional source-review finding to reproduce/fix before using the optional
four-argument header path: `add_amqp_headers` stores string pointers into a
temporary buffer that it frees before publish. This is a suspected header
lifetime defect, not a reproduced crash or evidence about current three-argument
push traffic. Keep it out of the freshness implementation path; add a bounded
regression and tracked build patch before admitting that API.

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
