# Explicit quorum topology and live broker verification

Main-SH deployment `eddec8/session40843/cdcd63` and independent verification
`e02540/session45092/9a1a1c` pass. Current release:
`734ca0203eff1bc9da4ca4932d2375ce404b187b0c399222f3ae33edb6217880`.
Enabled active dev consumer PID381466, NRestarts0. Previous release retained;
existing isolated legacy binding unchanged. Opt-in quorum mode was accepted in
the isolated test below, not enabled silently for the live consumer.

This is the topology part of the mobile bridge recovery work. It does not finish
provider retries, event freshness, process/broker fault recovery or phone delivery.
Existing installations retain their legacy topology unless explicitly configured.

## Configuration

In the protected `/etc/kazoo-push-bridge/config.json`, set
`PUSH_BRIDGE_TOPOLOGY` to `quorum-v1`, choose a new `PUSH_BRIDGE_QUEUE` ending in
`.quorum-v1`, and supply `PUSH_BRIDGE_AMQP_MANAGEMENT_URL`. Management and AMQP
must use the same hostname and cluster; different ports are allowed. Management
requires HTTPS except for an explicit loopback host. The URL must have no
userinfo, path, query or fragment. The existing AMQP user/password must have
management read access. A monitoring-tagged synthetic user passed local proof.

Optional `PUSH_BRIDGE_AMQP_MANAGEMENT_CA_FILE` is a protected, root-owned PEM
bundle in the service configuration directory, admitted by the same file and
certificate parser as broker TLS trust. Omit it to use system trust. Redirects,
environment proxies and disabled certificate verification are not permitted.

The operator-owned ingress exchange must already exist as durable topic type.
The bridge creates a durable direct `<queue>.dlx` and durable quorum
`<queue>.dlq`, bound with routing key `dead`, plus the versioned work queue.
No classic queue is redeclared, deleted, drained or silently rebound. Explicit
migration must prevent old/new consumers both receiving the same native traffic.

| Setting suffix after `PUSH_BRIDGE_` | Default | Allowed range |
| --- | ---: | ---: |
| `TOPOLOGY_WORK_MAX_MESSAGES` | 1000 | 1–100000 |
| `TOPOLOGY_WORK_MAX_BYTES` | 33554432 | 32768–268435456 |
| `TOPOLOGY_DLQ_MAX_MESSAGES` | 10000 | 1–100000 |
| `TOPOLOGY_DLQ_MAX_BYTES` | 67108864 | 32768–268435456 |

Quorum settings without explicit opt-in fail configuration preflight. The work
queue uses message TTL60000ms, delivery-limit3, reject-publish overflow and
at-least-once dead-letter strategy. The DLQ has reject-publish limits and no
automatic expiry, forwarding or replay. Its retention remains an operator task.
Broker delivery-limit3 is not a three-provider-request promise; existing provider
retry behavior is unchanged. Queue TTL is not an in-flight call expiry contract.
Broker limits provide backpressure, not an exact hard ceiling on in-flight bytes.

## Fresh startup checks

Every quorum connection performs eight fresh bounded management GETs before
ingress binding and consumer readiness: regular/operator policy lists, work/DLQ
metadata, DLX/ingress exchanges, dead-letter bindings and the stream_queue flag.
This initial version deliberately requires a **policy-free vhost**, refusing
even unrelated policies instead of guessing regular/operator PCRE precedence.
Critical queue arguments/types, durable flags and routing must match exactly.
Missing/conflicting evidence or a failed probe causes fixed exit78 before consume.

RabbitMQ queue statistics can lag declarations and policy updates. Omitted
policy fields alone therefore cannot establish absence of a policy. Direct
policy-list endpoints provide independent current evidence; both must return
empty arrays. Present contradictory queue metadata still fails. Source:
[queue endpoint](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_management/src/rabbit_mgmt_wm_queue.erl),
[policy endpoint](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_management/src/rabbit_mgmt_wm_policies.erl),
[operator policies](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_management/src/rabbit_mgmt_wm_operator_policies.erl).

The probe has3.05s connect/5s read socket limits,128KiB decoded response caps,
duplicate-key JSON rejection and a30s checked budget. This is not a hard bound
on OS DNS/TLS or blocking reads. Policy checks are point-in-time, not atomic
protection against a later administrator change. Quorum declarations and
at-least-once semantics are source-backed in
[RabbitMQ3.13.7](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbit/src/rabbit_quorum_queue.erl).

## Verified development evidence

`37a62e/session13700/fb9511`: all132 bridge tests, main-SH bridge dispatch and43
Kamailio effective-endpoint cases passed. Network was isolated for these tests.

`852b0d/session65965/f8265c`: actual isolated local RabbitMQ proof passed using
`scripts/accept-push-bridge-quorum.py --run-isolated-local-proof`. It declared
and verified the real topology, confirmed a synthetic publish, rejected the
message into the DLQ, read it back, refused an unsafe overflow policy and verified
the restored state. Receipt:
`/var/log/kazoo-acceptance/kz5-topology-proof-ca8c985b-ca20-4589-b7d1-8ac986a0962a/receipt.json`.
No provider worker or phone notification was started. Only the generated vhost
and user were removed; the receipt is retained. Three earlier failed probes
also cleaned their own resources and led to the policy-statistics correction.

Main SH fingerprints, stages and compares both new modules. Production10.1.0.28
is untouched. The existing dev service remains on its isolated legacy binding;
the opt-in mode is tested separately, not silently activated for native traffic.
