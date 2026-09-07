# Opt-in queue-live wire smoke

`scripts/test-queue-live-wire.cjs` is a read-only HTTP/native Blackhole acceptance
tool. It does not run services, log in with a password, publish broker events,
place calls, alter queues/agents, install dependencies or enable capabilities.
Root65638 executed it against the development backend and passed the HTTP,
subscription, deliberately triggered invalidation/refetch and unsubscribe checks.
The private wrapper authenticates separately; no credential is retained in this
guide. This proves the stated wire scope, not actual call-transition publication.

Provide an explicit account and queue and exactly one token input: an absolute
regular non-symlink token file owned by the current user or root, mode `0600`,
or `--token-env NAME`. The file contains only the token and an optional final
newline. Tokens are never CLI arguments or URL/subprotocol fields. Do not use
shell tracing, verbose HTTP logging, or put a literal secret into shell history.
No existing credential files are discovered or read automatically.

Example (IDs and paths are placeholders; obtain the token separately):

```sh
node scripts/test-queue-live-wire.cjs \
  --account ACCOUNT_32_LOWER_HEX --queue QUEUE_32_LOWER_HEX \
  --api-url http://127.0.0.1:8000/v2 \
  --ws-url ws://127.0.0.1:5555/websocket \
  --token-file /absolute/private/dashboard-token \
  --ws-module /absolute/already-installed/node_modules/ws
```

Use trusted HTTPS/WSS URLs for remote acceptance; normal certificate verification
is required. Cleartext is accepted only on literal loopback/localhost unless the
operator explicitly supplies `--trust-cleartext` for a trusted network. Redirects,
URL credentials, queries and fragments are refused. Both endpoints must be
operator-controlled; selecting them authorizes sending the supplied token there.
Use a clean Node environment (no preload/inspection hooks). The existing
`scripts/api-docs-tooling/node_modules/ajv` and an already installed `ws` module
are prerequisites; `--ws-module` selects an absolute trusted module path if `ws`
is not normally resolvable. No new dependency is installed.

The harness checks unauthenticated overview/detail rejection, authenticated
production OpenAPI DTO shape and account/selected queue scope, `no-store`, and
basic selected-call timeline/order/count invariants. It preserves explicit
partial/unavailable observations as such: a schema PASS is not source consensus
or zero occupancy. Overview checks one bounded page, not a complete inventory.
It then checks anonymous and wildcard subscription rejection, and sequential
correlated exact subscribe/unsubscribe acknowledgements on a fresh socket.
It does not prove a restricted token's cross-tenant/queue authorization policy.

Optional `--wait-event-ms 30000` waits for a matching closed invalidation after
printing `READY_FOR_EXTERNAL_EVENT`, then refetches detail before unsubscribing.
Root may separately inject an authorized exact event or cause a controlled
mutation; the harness has no trigger command or default publication. A hint
has no correlation nonce, so receipt cannot prove which external action caused
it. Synthetic injection proves only downstream delivery, not mutation publisher
coverage. Subscribe ACK is not a broker-ready barrier; a single lost hint can
time out. There is no automatic publication retry or state mutation.

Each HTTP/open/ACK step is bounded to 8 seconds, event wait to 60 seconds and the
whole run to 120 seconds. HTTP bodies are capped at 2 MiB; WebSocket reassembled
frames at 64 KiB and the run at 256 frames/1 MiB. Only fixed diagnostic codes and
sanitized status summaries are printed, never payloads, callers, agent names,
tokens or server error text. Socket termination and request destruction run on
success, failure, interrupt and overall timeout. Explicit unsubscribe ACK is
checked on success; failure relies on native session-close cleanup. Token memory
cannot be securely erased from JavaScript strings. Exit zero is only the stated
smoke scope, not browser acceptance, instant revocation, durable events, TLS
rollout, or full dashboard readiness. Clients still reconcile snapshots every
15 seconds and on reconnect. Public `websocket_updates` may remain false while
this direct native transport is tested.
