# Blackhole bounded slow-client acceptance — 2026-09-09

Both native tests passed on development44, source `c0c550c`. This tests actual
TCP receive starvation, not the previous artificial mailbox surge. No source
service change was needed for this scenario: existing send timeout and overload
guards removed the stalled socket while another client remained responsive.

| Transport | Paced 256KiB events attempted | Socket process gone after | Largest control ping | Control pings |
| --- | ---: | ---: | ---: | ---: |
| Direct WS / native Blackhole | 104 | 5390ms | 7.6ms | 29 |
| Certificate-verified WSS / nginx | 128 | 6825ms | 9.5ms | 36 |

Both reconnected and authenticated successfully afterward. Peak sampled socket
process memory was63080/109360bytes and mailbox51 each. Process memory does not
include all referenced binary storage, OS/network buffers or nginx memory.
Do not use these numbers as a whole-platform memory measurement.

The fixture authenticates two sockets with an ephemeral120-second token for
the existing isolated acceptance account. It constrains the receiving socket's
TCP buffer before connect, completes authentication, then stops reading only
that socket. A root-scoped helper sends through the actual native emitter,
paced50ms and capped at128x256KiB per transport. No application suspension,
direct mailbox burst, host sysctl, traffic filter, provider API or SIP call is
used. The responsive socket pings throughout. Native process disappearance,
bounded duration/memory, unaffected control pings, token not yet expired and
successful reconnection are mandatory assertions.

The receiving client is intentionally not draining data, so delivery of a
particular WebSocket close frame is not asserted. Reconnect and obtain a fresh
authorized snapshot on **any** transport loss, including abnormal1006; do not
rely exclusively on receiving1013. No durable replay or zero-loss guarantee.

Run explicitly on development44 only:

```sh
timeout --kill-after=10 90 python3 scripts/test-blackhole-slow-client.py --live
```

The root0600 acceptance lock excludes concurrent fixture tests. Helper stdout
contains a token only in a private captured subprocess, never in the test log.
Four local framing/admission tests pass via
`python3 scripts/test-blackhole-slow-client-unit.py`.

This is a bounded two-connection backpressure check, **not** prolonged network
soak, high-fanout broker throughput, distributed call supervision or full
production certification. Existing cross-node revocation results are in
`cluster_identity_revocation.md`.
