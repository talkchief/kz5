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

Native after-fix deployment and receipts are pending. Keep the P0 open until
both modes pass. Never restore a revoked signing secret to tidy a test fixture.
