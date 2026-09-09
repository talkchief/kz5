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
- 22 queue-live regressions pass (33e669);13 real local wire/frame checks pass
  (3cc20f). No deployment proof is inferred from these tests.
- All111 private source-transition cases and terminal runner status now PASS
  (0b5bab), evidence `/tmp/kazoo-source-transition-tests.ryzIHz`. Includes the
  previous complete pre-stream upgrade and idempotence. The earlier run's
  stale110-total bookkeeping failure remains recorded, not relabeled a pass.
- Native before-test on main44 reproduced the leak: valid event arrived, then
  the post-expiry marker also arrived (caebc8). Unit
  `kz5-stream-guard-baseline-native-20260909.service`, exit1; protected log
  `/root/kz5-acceptance/stream-guard-baseline-native-20260909.log`.
  Initial test setup had refused a missing fixture identity secret; normal
  signing now initializes only that fixed account if required, never resets it.

`run-blackhole-stream-native.sh` uses pinned installed Playwright, the real WSS
endpoint and a short-lived signed token for the isolated acceptance account.
Its RPC helper sends only fixed marker events to a single session correlated
by a random test request ID. It does not subscribe to company traffic. It checks
valid delivery, no post-expiry marker plus1008, and a bounded owned-mailbox surge
plus1013. Token output is an internal captured protocol and must never be printed
or stored in logs. Normal apps installer unit
`kz5-stream-guard-deploy-20260909.service` completed with exit0 (053096).
No runtime-only BEAM loading was used.

- Native after-unit `kz5-stream-guard-after-native-20260909.service` exited0
  (711103): valid event delivered; expired token received no marker and closed
  1008; owned mailbox surge closed1013. Log:
  `/root/kz5-acceptance/stream-guard-after-native-20260909.log`.
- Command regression unit `kz5-stream-guard-command-regression-20260909.service`
  exited0 (d8cad3), all five anonymous/valid/cached/replaced-token/identity checks
  passed using real HTTPS/WSS. Its log uses the same unit basename under
  `/root/kz5-acceptance/`.
- Normal documentation helper published the committed assets (2a8867); all12
  assets matched repository bytes over verified HTTPS (711103). Reference has
  358 paths /653 operations; that inventory count is not an all-operation test.
- All nine stack services active, FreeSWITCH zero channels (c42013). Apps,
  eCallMgr, FreeSWITCH and Kamailio automatic restart counts were zero; no
  error-priority apps/eCallMgr journal entries since deployment start (d8cad3).
  This is a deployment window check, not a long-running crash/soak guarantee.

The developer contract is in `/apis/blackhole.html` and the OpenAPI
`x-blackhole.outbound_delivery` extension.

Subsequent September9 native acceptance passed7 ordinary-principal HTTP/WSS
scope checks (`kz5-native-principal-20260909.service`) and4 cached-identity
revocation checks (`kz5-native-revocation-20260909.service`). A valid event first
warmed identity caches; exact revision-checked signing-secret rotation for the
isolated acceptance user then denied the next event with1008/no marker leak and
returned HTTP401 before token expiry. The old signing secret is not restored.
These results cover one serving node, not propagation during a multi-node
partition. Real slow-network load and cross-node supervision/audio privacy
remain separate acceptance cases; do not relabel mailbox injection as those tests.
