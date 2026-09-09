# Native Blackhole outbound delivery guard

Source patches are mandatory in `scripts/install-kazoo5.sh`, not a runtime-only
edit. `blackhole-kazoo5-integration.patch` contains the socket hook; the reviewed
`blackhole-stream-guard-transition.patch` upgrades the previous complete source
state, and `blackhole-outbound-guard.patch` supplies the emitter guard. Legacy
and fresh installs retain the existing private preflight/idempotence checks.

Before every generic native `event` is emitted, the socket requires a successful
current token validation with the same authenticated account. It holds at most
one validator for that delivery, with an independent3s timeout. Invalid/missing
identity, changed account, rejection or timeout emits no event and closes1008.
This does not remove Kazoo's identity caches or add an idle-socket expiry timer.
Queue-live continues to apply its separate fresh resource-scope checks.

At the configured mailbox threshold the consumer closes1013 and tells the
frontend to reconnect and resynchronize. Default50; invalid consumer limits
fall back to50. This prevents silently continuing a known incomplete stream.
It is not persistent replay, a durable cursor, a socket-buffer bound, or a claim
of slow-network/federated-load acceptance. Replies no longer log arbitrary data.

## Evidence

- Four outbound cases fail on the old handler/emitter (88db9e); all18 public
  entry-point checks pass after the fix (e42f6e), including expiry/account
  mismatch, timeout/worker removal and mailbox close. Eight production modules
  compile with warnings-as-errors; providers are substituted only in a private VM.
-22 queue-live regressions pass (33e669);13 real local wire/frame checks pass
  (3cc20f). No deployment proof is inferred from these tests.
-111 private source-transition cases ran successfully, including the newly
  added complete pre-stream upgrade. The runner ended failed because its old
  expected total was110; that bookkeeping assertion is corrected to111.

`run-blackhole-stream-native.sh` uses pinned installed Playwright, the real WSS
endpoint and a short-lived signed token for the isolated acceptance account.
Its RPC helper sends only fixed marker events to a single session correlated
by a random test request ID. It does not subscribe to company traffic. It checks
valid delivery, no post-expiry marker plus1008, and a bounded owned-mailbox surge
plus1013. Token output is an internal captured protocol and must never be printed
or stored in logs. Native before/after deployment results remain pending.

The developer contract is in `/apis/blackhole.html` and the OpenAPI
`x-blackhole.outbound_delivery` extension. Native token revocation propagation,
restricted-principal scopes and cross-node supervision/audio privacy remain
separate acceptance cases; do not relabel this fix as proof of those cases.
