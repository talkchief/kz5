# Strict-quorum counted retry — source candidate only

This opt-in source slice retries only exact completed HTTP500/503 responses from
FCM with a definitely absent Retry-After header. No deployment, provider request, broker test, or phone-delivery
claim is made by this change. Agent test execution was not authorized; root
must run the prepared offline suites and the broker acceptance gates below.
Existing legacy and quorum-without-retry behavior remain unchanged.

`PUSH_BRIDGE_RETRY=quorum-counted-v1` requires both `TOPOLOGY=quorum-v1` and
`FRESHNESS=unix-ms-v1`. The owner enables it only after the existing connection's
quorum declaration and independent live topology verification. There are no new
queues, bindings, TTLs, publishers, or republish/ACK sequences. Root added
`delivery_retry.py` to all four main-installer release file lists: fingerprint,
copy, post-copy verification and independent verification. This stages the code;
it does not enable the opt-in retry setting.

## Exact policy

The owner reads AMQPStorm Message.properties.headers[`x-delivery-count`] and
Message.redelivered, never the JSON body or an in-process incremented counter.
The pinned AMQPStorm source exposes these as decoded properties and the incoming
method's redelivered field; an offline real-message fixture checks those accessors
and the single-tag Basic.Nack frame with `multiple=false`.

- Missing headers/counter is zero only when redelivered is exactly false.
- A present counter is an exact integer, not bool/string/float/subclass, in
  0..2^63-1. Zero requires redelivered=false; positive requires true.
- Missing count on redelivery, contradictory flags, malformed metadata or unknown
  types fail stopped before a provider worker. No default resets the budget.
- Counts 0/1/2 admit at most one provider dispatch each. Count >=3 is rejected to
  the existing durable quarantine path before submitting a provider worker.
- Exact `(False, 500|503, "provider_response")` from a known FCM worker is
  retryable. Other outcomes keep existing dispositions. In particular transport
  errors, timeouts, all APNs transient responses, 429, redirects, OAuth/authentication
  failures, cancelled workers and unknown/malformed results still fail stopped.

FCM's [documented503 policy](https://firebase.google.com/docs/cloud-messaging/error-codes)
requires honoring Retry-After when present. This slice does not parse/persist a
header-directed schedule: **any** Retry-After header, including zero, empty,
malformed or date values, returns the fixed `provider_retry_after_required`
category and fails stopped. Unavailable/uninspectable headers do the same.
Only header names are inspected; no value or response body is logged or retained.
APNs retry eligibility/header behavior is deliberately excluded pending separate
provider guidance and transport proof. Its existing permanent quarantine remains.

After a completed transient at count 0/1 the owner retains the original unacked
message, future, immutable freshness lease and prefetch slot. `drain()` schedules
a 2/5-second monotonic due time without sleeping, invoking another worker or
blocking other completed deliveries. At the due time it checks the unchanged
deadline again and sends exactly one owner-thread `nack(requeue=True)`. Only a
new broker delivery can schedule another provider dispatch. Count 2 failure is
quarantined immediately. Expiry, or too little lifetime for the required delay,
also quarantines instead of requeuing. A wall-clock advance can shorten lifetime;
rollback cannot extend the captured lease's monotonic budget.

In opted-in mode FCM performs one POST per broker delivery, including after500/503
or transport failure. Legacy mode retains its existing two-attempt behavior.
FCM TTL still shrinks against the original deadline after credential acquisition;
APNs's existing single-send freshness checks remain unchanged.

ACK/NACK/reject exceptions retain unsettled state and return the existing
manual-recovery failure. No disposition is replayed on another drain. A failed
generation cannot reconnect with outstanding workers; invalidation removes local
handles so late completions cannot settle a successor's deliveries. The service's
exit78/restart/shutdown policy is unchanged.

## Durability and open acceptance gates

Actual isolated quorum-broker counter/expiry/channel-close proof now passes
`feecd1/ac00b2`; see `push_bridge_retry_broker_acceptance.md`. This closes only
those synthetic cases, not provider delivery or the broader faults below.

The intended durable state is the retained original quorum message, immutable
producer deadline and broker delivery counter. An in-memory due time is not a
durable schedule: process death can interrupt a delay. No cross-restart minimum
backoff guarantee or automatic process recovery is claimed. Requeues, lost ACKs
and consumer death may cause duplicate deliveries; HTTP acceptance is not proof
of phone delivery, and this is not exactly-once notification delivery.

Actual RabbitMQ 3.13.7 counter semantics MUST be demonstrated before activation:
initial counter/flag spelling; one NACK increment; count persistence across
consumer/channel death and broker restart; exhaustion without a fourth provider
dispatch. Existing broker `x-delivery-limit=3` alone does not prove that bound.
Test synthetic500→200, three500/503 outcomes, expired backlog, expiry during
delay/authentication, NACK/ACK loss, unavailable/full DLQ, and source retention
until at-least-once dead-letter transfer. Never use production routing or real
device tokens for these proofs. Existing hung-worker shutdown, automatic recovery
and designated-device acceptance remain independent release gates.

## Prepared offline tests

Current development source deployment: `feccd8/4664d3` and independent
verify-only `b0c4d8/02b4a6` pass through the main SH. Release
`b20944143ade6ae0ad3ffb4c4c69094305348d7220f890669ca57606fb3810f8`
registered its consumer with zero restarts at initial readback. Configuration
keeps all topology/freshness/retry opt-ins absent, so this is code deployment,
not activation of counted retry. Isolated real-broker cases pass separately
`feecd1/ac00b2`; see `push_bridge_retry_broker_acceptance.md` for exact scope.
Main-SH rollback now also covers post-start verification failures; seven isolated
failure/success fixtures pass `943abf/2ca19d`. No production restart or real
mobile notification was part of these actions.

Root run `c8be7c/session58849/24fc8c` passes all187 bridge Python tests,
including17 counted-retry tests. Its combined command then failed only because
a new installer fixture expected `rg` after the installer sanitized PATH.
The fixture now uses the existing `awk` dependency; independent rerun
`c73261` passes aliases, standalone/ALL, dry-run, early rejection and all four
retry-module release paths. Installer shell syntax also passed. No broker,
provider, service or production action occurred in these isolated tests.

Use the pinned bridge virtual environment under root's serialized isolated guard:

```text
python -B -I scripts/test-push-bridge-retry.py
python -B -I scripts/test-push-bridge-config.py
python -B -I scripts/test-push-bridge-settlement.py
python -B -I scripts/test-push-bridge-fcm-transport.py
python -B -I scripts/test-push-bridge-freshness-runtime.py
python -B -I scripts/test-push-bridge-runtime.py
```

Fixtures use synthetic clocks/messages/provider outcomes and the real pinned
AMQPStorm frame builder/Requests adapter. They do not establish actual broker
counter durability, execute provider calls, read keys, or activate the setting.
