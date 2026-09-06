# Opt-in Monster socket subscription lifecycle

Status: implemented and offline-tested in source; **not deployed**. This adds
subscription lifecycle reporting to the existing Monster socket connection. It
does not add a dashboard, another WebSocket service, or backend readiness proof.
Ordinary callers without `lifecycle` retain the legacy subscription path.

## API and account scope

```js
const cancel = monster.socket.bind({
    accountId: accountId,
    binding: 'queue_live.changed.' + queueId,
    source: 'acdc',
    callback: onInvalidation,
    lifecycle: {
        timeoutMs: 3000,
        onAck: onSubscriptionAcknowledged,
        onError: onSubscriptionError,
        onDisconnect: onSubscriptionDisconnected
    }
});
// The ordinary monster.socket.connect() opens the configured shared connection.
// Registration may precede that call; bind itself does not open a socket.
// On view/account disposal:
cancel();
```

`callback`, `onAck` and `onError` are required functions; `onDisconnect` is
optional. Account IDs must be 32 lower-case hexadecimal characters. Bindings are
exact, non-wildcard strings of 1–256 characters from `[A-Za-z0-9_.:-]`; `source`
is a nonempty string of at most 128 characters. The existing app convenience
wrapper is unchanged: opt-in callers use `monster.socket.bind` directly.

The registry key is **account plus binding**. Native
`queue_live.changed.QUEUE_ID` does not embed the account in the binding string;
the native request carries it separately. Events are delivered only when their
`data.account_id` and `subscribed_key` match an acknowledged registration.
This client-side check does not replace backend token, account or queue checks.

Request IDs and connection generations correlate replies. Account A can
unsubscribe while account B retains the same binding string: the correlated
reply's `data.unsubscribed` proves which request was acknowledged, even when
`data.subscriptions` still contains that string. Legacy and opt-in registrations
cannot borrow each other's unsettled wire binding.

## Acknowledgement is not readiness

Lifecycle callbacks receive `accountId`, `binding`, `code`,
`connectionGeneration`, `ackScope: 'blackhole_subscription_reply'`, and
`brokerReadinessVerified: false`. ACK means a correlated successful Blackhole
subscription reply, **not** completion of asynchronous broker binding, gap-free
event delivery, a fresh snapshot, or agent eligibility. `socket.connected`
continues to mean the socket opened, not that subscriptions were acknowledged.

An already acknowledged shared registration can invoke `onAck` synchronously.
Callbacks are exception-isolated. Each returned cancellation function identifies
one listener, even when callback functions are identical. Cancellation is
idempotent and stops local delivery immediately; it is not a remote cleanup ACK.
Late replies and reentrant cancellation/disconnect cannot restore that listener.

## Bounds and failure behavior

- Default ACK deadline: 3000ms; explicit integer range: 100–15000ms. Initial
  pre-open waiting consumes the deadline. Timeout/rejection removes the listener.
- Unexpected disconnect reports loss and suspends desired subscriptions. A new
  connection starts one new bounded subscribe attempt. Explicit shared disconnect
  retires opt-in intent; lifecycle failures never force that shared disconnect.
- At most 256 opt-in records, listeners and outstanding requests. Cleanup records
  consume the record budget. Last-listener cancellation may send one unsubscribe.
  Its 15000ms timeout leaves a blocked cleanup record until connection teardown;
  it does not retry indefinitely or permit unsafe reuse.
- Legacy ownership observation is bounded to 256 keys and 256 pending requests
  per key. Exhaustion refuses opt-in admission until disconnect, while legacy
  wire behavior remains unchanged. No opt-in authentication retry/logout is added.

Error codes are `invalid_options`, `configuration_unavailable`, `binding_in_use`,
`legacy_ownership_unknown`, `subscription_limit`, `cleanup_pending`,
`send_failed`, `rejected`, `invalid_reply`, `timeout`, and `disconnected`.
Callbacks do not receive raw server errors, tokens or transport exceptions.

## Required application reconciliation

Treat events as invalidation hints, not counter increments. Keep one bounded
snapshot request in flight and remember intervening invalidations. Mark retained
data stale on disconnect/error; resubscribe and resnapshot on reconnect even if
no event arrives. Cancel exact listeners and invalidate old HTTP callbacks when
the account, queue, page or view changes. Never turn unavailable metrics into zero.

Blackhole's existing asynchronous binding and overloaded-event-drop behavior
requires a separately verified backend readiness barrier and bounded resnapshot
reconciliation. This transport feature alone cannot certify continuous freshness.

## Packaging and proof

`scripts/patches/monster-ui-websocket-subscription-lifecycle.patch` changes only
framework `src/js/lib/monster.socket.js`. The installer applies it after the
socket-configuration patch and includes its digest in the Monster build identity.
The framework pin remains `7ef735eada6fd0e2b96c06f32c0bb868867f7d18`; existing
configured checkouts are not edited or reset by this source change.

Parent-controlled run **27665** passed all **26 lifecycle fixture groups**,
including the complete existing socket-config regression, actual private patch
forward/repeat/reverse checks, legacy trace comparisons, same-binding A/B scope,
deadlines, cleanup caps and reentrant callbacks. Installer wiring also passed
12 groups; the separate installer-preservation run passed all 11 groups.
Root restored development eCallMgr after the complete validation window.

Evidence: `/tmp/monster-socket-lifecycle-proof.YIqRaL/receipt.json`, SHA256
`e12738d9d268f23673aeac4347fe5147edf5acaf8b9519181216154cb561e51f`.
Input pins were stable. Patch SHA256:
`a0fd94d14e56f11ddd530a38dfe0b677c67bdbe39fe5555178782aef85e6fa2e`.
Fixture SHA256:
`d878b4f0655b01787aa2e3201cd57913364a4a6d3f47669ab30bb3149e36b958`.
These are offline fake-socket/clock results, not browser, broker or deployment
acceptance. A serialized offline rerun from the repository root is:

```sh
/usr/bin/bash scripts/run-kazoo-validation.sh --memory-mib 128 --reserve-mib 768 --runtime-sec 60 -- /usr/bin/unshare --net /usr/bin/node /opt/kz5/scripts/test-monster-websocket-lifecycle.cjs /usr/local/src/kazoo5-installer/monster-ui
```
