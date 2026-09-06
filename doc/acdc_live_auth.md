# Live queue authorization helper

`applications/acdc/src/acdc_live_auth.erl` provides shared authorization for the
live queue API and a future native Blackhole caller. It does not create
subscriptions, publish events, collect snapshots, or enable WebSocket updates.

## Existing public route

`cb_acdc_live` delegates its existing checks to `authorize/1` and `permit/2`.
The extraction preserves the public route's behavior, response shape, catalog
validation, and error handling. Authorization still requires a positive result
from the global or resource-specific Crossbar authorizers and rejects malformed
or stop results. A missing resource-specific authorizer is not itself a denial
when a valid global authorizer permits the request. Existing native token-scope
behavior, including an empty required-scope callback list, is unchanged.

`permit/2` evaluates a synthetic read-only queue resource with an empty query,
request data, and document. A denied embedded resource retains the existing
`{live_error,403,<<"queue_live_resource_forbidden">>}` throw contract.

## Fresh-token entry point

`fresh_token(Token, AccountId, QueueId)` returns `{ok, Context}` or a bounded
`{error, Reason}`. Both IDs must be exactly 32 lowercase hexadecimal characters;
the nonempty token is bounded to 16384 bytes and rejects whitespace/control
characters. Invalid input is rejected before binding discovery or provider reads.

Each call creates a new Crossbar context and invokes the actual
`cb_token_auth:early_authenticate/1`. It does not accept an already-authenticated
Blackhole context as authority. It verifies that the returned token, current
authentication account and claims agree, and that the requested account and
tenant database remain unchanged. Delegated access remains a decision of the
current Crossbar authorizers; the authentication account is not rewritten to
the requested account.

The helper checks the selected live resource, `/queues/stats`, and the selected
queue's resource permissions and applicable token scopes. It also reads the
queue document and requires the exact requested ID, matching tenant, queue type,
and neither deletion flag. No snapshot or caller data is returned.

The `cb_token_auth` and `cb_queues` bindings must be active **locally**, before
and after authorization. An empty authorization result never grants access.
Standalone Blackhole without local Crossbar authority fails closed; remote
authorization is not implemented. Binding checks and document reads are not an
atomic reservation against subsequent policy changes.

The returned context contains authentication material. Keep it server-side;
do not serialize it into events, diagnostic payloads, or frontend responses.

## Freshness and execution limits

The helper does not cache an authorization decision or reuse a retained session
identity. It reruns native validation on every call, including native handling
of an expired-token result. However, native JWT/identity providers and the legacy
token-document cache remain unchanged. This is **not** cache-independent
validation or a guarantee of instantaneous global revocation.

This token-only entry point supplies no asserted originating proxy addresses.
Native proxy restrictions remain in force; it does not invent a trusted origin.

Provider and binding calls are synchronous. A caller must supply a bounded
worker/concurrency policy and an outer deadline, discard late results, and
revalidate current subscription ownership before eventual delivery. Do not call
the helper directly from a latency-sensitive stats mutation mailbox or assume
that it enforces its own latency budget.

## Validation evidence

The dedicated runner is `scripts/test-acdc-live-auth.sh`, with ten cases in
`scripts/erlang-tests/acdc_live_auth_tests.erl`. It compiles the production modules
without `TEST`, uses the actual local binding registry and native token-auth
entry point, and controls token, account, database, and scope providers.

Root session `93576` passed all ten cases after compiling 15 production
modules. Evidence: `/tmp/kazoo-live-auth.wI1Qpf`. The earlier `5608` run passed
eight cases and failed two fixture expectations for native unbind return values
(`/tmp/kazoo-live-auth.1J4nwj`). The corrected fixture expects exact
`{ok,deleted_binding}` / `{ok,updated_binding}` results and restores modified
bindings in `after` blocks. The initial runner's missing include path was also
corrected and its headers added to the checked input inventory.

The public-handler suite separately passed nine route groups and two helper
tests in `23014`, compiling 13 production modules and validating 17 actual
handler DTOs against OpenAPI (`/tmp/kazoo-live-snapshot.X7l6nZ`). Providers remain
controlled; this is not an HTTP wire or real-token test.

These fixtures are not proof of live authentication, cryptographic JWT
validation, cache-independent revocation, HTTP behavior, or Blackhole delivery.
No deployment acceptance is claimed by this guide.
