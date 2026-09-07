# Native queue-live invalidation candidate

The client subscribes to exactly `queue_live.changed.QUEUE_ID`, with an explicit
`data.account_id`. IDs must be 32 lowercase hexadecimal characters. One binding
is allowed per subscribe/unsubscribe frame; wildcards and mixed/multiple bindings
are rejected. The existing frame-size limit still applies. Clients should use
distinct request IDs, retry a busy authorization with bounded backoff, and keep
at most 100 queue-live subscriptions per socket.

`bh_queue_live` resolves the exact federated callmgr binding
`acdc.dashboard.changed.ACCOUNT_ID.QUEUE_ID`. Its native event envelope uses
`name: "changed"`; `data` contains only `version: 1`, `account_id`, and `queue_id`.
Transport headers, tokens, callers, counts, queue positions and agent data are
not forwarded. Events are invalidations: refetch the authorized HTTP snapshot.

## Authorization and lifetime

Subscribe and each coalesced delivery call `acdc_live_auth:fresh_token/3` in a
worker, not in the websocket mailbox. There is one authorization worker per
session, a 3-second result deadline, an independent worker watchdog, and at most
100 coalesced dirty scopes. A concurrent subscribe gets an explicit busy error.
Unsubscribe cancels an exact pending authorization, acknowledges its cancellation,
and removes the binding using the existing module-specific resource ownership.
Session close cancels its worker and uses the existing binding cleanup callback.

Before applying a worker result, the session checks its reference, deadline,
current token digest and retained identity. Delivery also requires the current
subscription generation, freshly returned authentication account, and actual
binding/resource ownership. A fresh subscription updates the effective account
identity from the helper; generic cached hierarchy authorization cannot admit
this namespace. Tokens are not put into binding payloads or global registries.
The event is returned directly to Cowboy after those checks, not queued as an
unchecked later `send_data` message.

The helper requires active Crossbar token/queue authorization bindings locally.
It preserves native cache and scope policy: this is not instant global token
revocation or a policy reservation after authorization. See
[the authorization guide](acdc_live_auth.md). A standalone Blackhole node with
no local Crossbar authority fails closed. Provider work already delegated by
native libraries is not claimed to be cancelled transitively by killing the
calling worker.

## Loss and rollout limits

These are bounded, lossy hints without acknowledgement, sequence, replay or
ordering guarantees. Broker outages, listener readiness races, federation gaps,
the session mailbox threshold, publisher overload and bulk/config mutation gaps
can lose hints. A successful subscribe reply is not a broker binding barrier.
There is no broad cross-tenant resync topic. The client must reconcile by HTTP
at least every 15 seconds and refetch on reconnect; it must never infer current
state by counting hints. Public WebSocket readiness is a separate acceptance
decision, not enabled by this module.

The private `bh_context` record gained a field. Rebuild the coherent Blackhole
source set and restart its sessions during an authorized rollout; this is not
old-record hot-upgrade support. The default module list includes `bh_queue_live`;
an installation with an explicit custom autoload list also needs that module
loaded. Crossbar/ACDC helper and KAPI availability are rollout prerequisites.

## Packaging and scoped proof

`blackhole-kazoo5-integration.patch` is the aggregate for pinned upstream
`4e3f02a5ab01c09a44c287f4f93b15d2782f5614`.
`blackhole-pre-queue-live-integration.patch` retains its exact previous state;
`blackhole-queue-live.patch` is the ordered transition from that state. The
transition overlaps older context/socket hunks and must not be treated as an
independent unordered installer delta. The installer now normalizes recognized
older states to the retained predecessor before applying this transition.
Root82855 passed all60 migration cases, including preservation, idempotence
and rejection of partial upgrades (`/tmp/kazoo-source-transition-tests.0ikZuF`).

`scripts/test-blackhole-queue-live.sh` is prepared to compare baseline aggregate
replay and prior-state transition replay with current source, compile 11
production modules without `TEST`, and run 22 actual socket-callback/binding
cases. Authorization, rate, logging and broker-listener providers are controlled;
the KAPI validator, session state, socket dispatch and binding registry are real.
The no-transform runtime build observes raw logging providers; a separate
production build retains the Lager transform and warnings-as-errors.

Root62617 passed all22 cases and11 production compiles with stable inputs
(`/tmp/kazoo-blackhole-queue-live.R6eO36`). An earlier run14311 passed the cases
but was invalidated by an input change during execution; only62617 is accepted.
This candidate has **not been deployed or tested against live delivery**. Existing
frame/redaction/cleanup runners were updated only as necessary for the new module,
header and ordered replay. Root25154 reran all three successfully:10 redaction
cases (`/tmp/kazoo-blackhole-redaction.sBxLgB`),10 cleanup cases
(`/tmp/kazoo-blackhole-cleanup.sliBz5`) and13 frame/wire cases
(`/tmp/kazoo-blackhole-frames.ofXsIc`). These fixtures do not establish
real JWT cryptography, live broker federation, Cowboy wire delivery or complete
mutation coverage.
