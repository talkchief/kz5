# Cluster identity signing-secret revocation

The native two-node check found a security defect before this fix: rotating an
isolated user's signing secret on the primary produced HTTP401 and WS1008 there,
but the peer still returned HTTP200 and delivered a post-revocation marker.
Both caches were warmed first; the JWT was unexpired and both apps PIDs remained
unchanged. No broker partition was needed. Original failing receipt on dev44:
`/var/lib/kazoo5-install-lab/cluster-auth-1788973933046.json`.

`scripts/patches/kazoo-identity-authoritative-read.patch` is mandatory in the
normal installer. It changes the Kazoo identity provider's document lookup in
`kz_auth_identity` from `open_cache_doc` to `open_doc`. Signing and verification
therefore read the current user/device/account signing secret without depending
on delayed or lost AMQP cache notifications. Datastore errors fail closed and
never fall back to an old cached secret. Signature mismatch logs omit signatures.
Third-party provider profile caching is unchanged.

This is one additional datastore read per identity validation, including native
Blackhole outbound-event revalidation. Provision CouchDB and measure throughput
accordingly. A disconnected datastore may deny otherwise valid authentication;
continuing to authorize revoked identities is not an availability fallback.
This does not promise atomic revocation against a request already validated
before the update, or solve conflicting CouchDB replicas or global provider-key
rotation. Do not advertise this as a distributed cache invalidation protocol.

Verification:

- `bash scripts/test-identity-revocation.sh`: six actual-production-module
  regressions with a deliberately stale cache and rotated authoritative value;
  user/device/account keys and not-found/timeout/connection failures covered.
- `bash scripts/test-identity-revocation-install.sh`: all six fail against the
  pinned pristine core and pass after the real installer applies its required
  patch. Reapplication is unchanged and missing source is rejected. Receipt:
  `/tmp/kazoo-identity-install.kRUz6o` on the source host. This private test does
  not contact a live database or application node.
- `bash scripts/run-cluster-auth-native.sh --revocation`: fixed isolated lab
  only, both nodes warmed, exact fixture-user CAS, HTTP and WS checks before JWT
  expiry. Tokens and signatures stay in captured private memory.
- `bash scripts/run-cluster-auth-native.sh --partition`: the same check while
  only the peer's broker route is blocked; independent restoration timer and
  reconnect verification. Not a SIP/RTP agent-recovery partition test.

## Native after-fix acceptance

Both normal lab apps installations passed on source `b8523ec`:
`kazoo-apps-install-7.log` and `apps-peer-install-3.log`. Both runs used the
required installer patch and full production rebuild, not runtime BEAM injection.
Receipts below are in `/var/lib/kazoo5-install-lab` on dev44:

| Mode | Receipt | HTTP before → after | WebSocket after |
| --- | --- | --- | --- |
| Healthy two-node cluster | `cluster-auth-1788975173069.json` | 200/200 → 401/401 | Both1008; no revoked marker |
| Peer cannot reach RabbitMQ | `cluster-auth-1788975191194.json` | 200/200 → 401/401 | Both1008; no revoked marker |

Both checks passed before JWT expiry with unchanged application PIDs. The
partition check verified no established peer AMQP connection during the fault,
then restored the exact route and verified broker reconnection. Only the fixed
isolated QA user's signing secret was rotated; no production or main company
document was changed. Native backend HTTP/WS was used here, not the HTTPS/WSS
front door. This does not claim SIP/RTP partition recovery or call-supervision
privacy. Never restore a revoked signing secret to tidy a test fixture.

Main44 normal deployment also passed: unit
`kz5-identity-authoritative-deploy-20260909`, source `2b52bd7`, Result=success,
exit0. Protected backup/source/install log and HTTPS/WSS receipt are in
`/root/kz5-acceptance/identity-authoritative-20260909/`. Four actual frontdoor
checks passed: valid delivery, exact fixture-user CAS, revoked delivery1008/no
marker, and HTTP401 before expiry. All9 stack services were active afterward,
zero calls, and apps/eCallMgr error-priority journal entries0 since17:28UTC at
readback. Updated `/apis/openapi.json` matches committed bytes over verified TLS.
This is a deployment-window check, not an indefinite stability guarantee.
