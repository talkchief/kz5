# Versioned push expiry — September 7, 2026

This is an opt-in safeguard, not a claim of complete mobile delivery reliability.
Production Kamailio10.1.0.28 is unchanged. Existing development routing is not
silently rebound or converted to quorum mode.

Main-SH development bridge deployment `d092dc/session29625/1e7b45` passes;
independent `--verify-only` passes `b9e8bb/session36502/be5ab7`. Installed release:
`c9d8055d8f922ef87eddc4098f5cbda751cc2fad9abe95a762347a8bb118c142`,
active consumer PID448604, NRestarts0. Previous release retained. These checks
verify deployed source/dependencies/protected configuration and registration,
not strict-mode activation or real phone delivery. Current dev routing remains
isolated legacy. Read-only independent review found no must-fix defect and
confirmed the wire-deadline/non-delivery caveats below.

Main-SH development Kamailio deployment `0de2e3/session54822/95d41c` passes
with the producer patch applied to source and installed configuration. SIP,
effective AMQP/vhost queues, dispatcher, SQLite, RPC, SBC and current journal/JWT
checks pass; PID451713, NRestarts0, zero FreeSWITCH channels at final readback.
Predeployment configuration is retained at
`/var/lib/kazoo-kamailio-freshness.5xk2fp/kamailio`. The necessary configuration
deployment restarted development Kamailio; older malformed-Via journal entries
remain preserved and their source is still unproven. Current activation checks
passing is not retrospective resolution of those entries.
Independent post-deployment main-SH `--verify-only kamailio` also passes
`b5bd83/session14632/032593`, including the unchanged journal/JWT gate.

## Producer and configuration

The main installer applies `scripts/patches/kamailio-push-freshness.patch` to the
pinned Kazoo Kamailio configuration. The producer samples one wall-clock instant
and saves this additional native JSON field with the transaction's push payload:

```json
{"Push-Freshness":{"version":1,"created_at_ms":1788800000000,"deadline_ms":1788800060000}}
```

All values are integers. Reusing the saved payload must not regenerate either
timestamp. The existing three-argument AMQP publish remains unchanged. This
patch targets the pinned Kamailio6.1.4 x86-64 LP64 build; portability to 32-bit
arithmetic has not been established.

Only after all producers supply this envelope, explicitly configure protected
bridge JSON with `PUSH_BRIDGE_FRESHNESS` set to `unix-ms-v1`, alongside
`PUSH_BRIDGE_TOPOLOGY` set to `quorum-v1` and that mode's verified topology inputs.
See [quorum setup](push_bridge_quorum_topology.md). Install using
`bash scripts/install-kazoo5.sh push-bridge`, then independently run
`bash scripts/install-kazoo5.sh --verify-only push-bridge`.
Omitting freshness preserves legacy behavior. Do not enable strict mode against
unpatched producers: undated messages will be quarantined, not delivered.

## Enforcement

- Duplicate/invalid JSON and non-integer, unknown-version or malformed envelope
  fields are rejected. Lifetime must be positive and at most60 seconds; permitted
  future producer-clock skew is at most5 seconds without adding to the lifetime.
- Capture occurs before a message enters the worker queue. The immutable local
  lease combines the original Unix deadline with an admission monotonic budget.
  Queue waiting and retries consume that budget; wall-clock rollback cannot
  renew it within that worker process.
- FCM checks before and after authentication and before each POST. Retry TTL
  shrinks to remaining lifetime. APNs checks around authentication, connection
  and frame construction, with its transport deadline clamped to remaining life.
- Verified quorum mode rejects invalid/expired messages without requeue so the
  existing at-least-once dead-letter route can retain them. Legacy handling is
  unchanged. Only the AMQP owner thread settles deliveries.

FCM accepts duration strings with fractional seconds, though it rounds TTL down
to whole seconds; see [the official AndroidConfig reference](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidConfig).
Provider acceptance is not proof of phone display, ringing or an active call.

## Evidence

- `7274c2/session93131/017836`:166 offline bridge tests,35 producer patch/wire
  checks, pinned-source LP64 inspection, actual Kamailio configuration syntax,
  installer fixtures and bridge dispatch all pass under network isolation.
- `9f0db0/session77650/3aea13`: actual private Kamailio synthetic SIP route
  produces numeric post-int32 Unix milliseconds within the send/receive window,
  a60000-ms deadline and byte-identical saved payload after1202ms. The fixture
  uses loopback-only private networking, no production includes or AMQP. Its
  private child/process group and files were cleaned. An earlier precondition
  failure was corrected by using the absolute installed `ip` path.
- `806085/session9036/b9d4bb`: actual isolated RabbitMQ proof includes strict
  runtime admission of missing/expired metadata, real dead-letter readback,
  continued acceptance and unsafe-policy refusal/restoration. No provider calls.
  Receipt: `/var/log/kazoo-acceptance/kz5-topology-proof-e273bbbf-b4f3-439d-8dbc-680d49c980ef/receipt.json`.
  The generated vhost and user were removed; the protected receipt remains.

## Remaining release boundaries

Producer and bridge tests above are separate checks, not an end-to-end real
mobile call. Freshness is not original INVITE-age verification, call cancellation,
cross-boot monotonic persistence, client deduplication or exactly-once delivery.
OAuth/DNS whole-operation latency, uncertain earlier provider writes, durable
transient retries, broker/node failure, full DLQ and designated Android/iOS
acceptance remain open. Clock synchronization is required on distributed nodes.
The FCM check immediately before POST is not a wire-level deadline: Requests
connection/preparation may overrun it. An expired result after an earlier send
attempt does not prove non-delivery and must not trigger blind replay.
Never substitute arrival time, SIP Expires or an unrelated AMQP timestamp for
the producer envelope, and never renew the envelope when retrying a message.
