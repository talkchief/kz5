# Live queue invalidation hints

Source candidate only; not deployed. This adds no historical, WFM or archive
pipeline and does not make a dashboard snapshot atomic or cluster-complete.

Root62617 passed all24 focused EUnit groups and11 production-module compiles
with stable inputs in `/tmp/kazoo-dashboard-events.gK9IkK`. This uses controlled
broker/pool and queue lifecycle boundaries, not a live broker delivery proof.
The earlier root96553 run passed21 groups then hit the empty-object validator
loop; that overall failure is retained in `/tmp/kazoo-dashboard-events.oLAFKR`.
Narrow guards now reject empty/malformed input before the legacy validator;
the passing suite includes bounded regressions for those cases.

The native `callmgr` routing key is
`acdc.dashboard.changed.ACCOUNT_ID.QUEUE_ID`. The new
`kapi_acdc_dashboard_events` API exports `changed/1`, `changed_v/1`,
`publish_changed/1`, `bind_q/2`, `unbind_q/2`, `declare_exchanges/0`.
The business body is exactly integer `Version: 1`, lowercase 32-hex
`Account-ID`, and lowercase 32-hex `Queue-ID`. Duplicate or unknown fields are
rejected. Required native headers are App-Name, App-Version, Event-Category
(`acdc_dashboard`), Event-Name (`changed`), Msg-ID. Bounded optional transport
headers are Node, Server-ID, Server-Queue-ID, AMQP-Broker, AMQP-Broker-Zone,
AMQP-Zone. These are internal; Blackhole must emit only the closed public hint
`{version:1,account_id,queue_id}` after independently validating routing scope.

Bindings require one `account_id` and one `queue_id`, with optional bare
`federate` or `{federate,true}` for existing listener federation. No wildcard,
empty scope, duplicate property, or broad resync topic is accepted. The same
queue ID in two accounts has two distinct routing keys. Subscription ACK is
not broker readiness or a data snapshot.

## Required reconciliation and loss semantics

Applications must obtain a fresh authorized snapshot on initial subscription,
after ACK/reconnect, after relevant hints, and at least every **15 seconds**
even if no hint arrives. Requests must be coalesced/bounded by the application.
Hints are invalidations only, not counts, revisions, replay cursors, or an
event-completeness guarantee. Losing a hint never justifies retaining an old
snapshot as fresh. HTTP permission checks remain authoritative.

`acdc_dashboard_events` is one supervised worker under `acdc_stats_sup`, before
the stats child. Producer work is bounded ETS operations only: no database,
pool checkout, cast, waiting on the publisher, or per-event process. A fixed
1024-slot hash table coalesces exact account/queue identities. Collisions or
compare-and-replace contention drop the new hint and increment a bounded local
counter; producers do not retry. A same-scope update refreshes a unique token,
so an in-flight old attempt cannot erase a newer mark. Storage is at most 1024
pending records plus one diagnostics row, not an unbounded identity map.

One timer attempts at most one native `kz_amqp_worker:cast/2` at a time from the
publisher, never from the mutation process. The next timer is installed only
after return (100 ms normally, 1000 ms after a local error). The existing worker
API waits synchronously in that isolated publisher; producer mailboxes do not
grow while it blocks. Pending slots are visited cyclically, including after
failure, so one failing low slot does not prevent attempts for other slots.

Native `kz_amqp_channel:basic_publish` can return `ok` after dropping a payload
for lack of a channel. Therefore `ok` removes only its exact pending token and
counts as **unconfirmed**, never delivered. Local errors retain that token for
a later bounded attempt. Broker/federation/Blackhole drops remain possible.
`diagnostics/0` exposes bounded local counters, not identities, source coverage
or an authoritative delivery receipt. Counters and pending hints are memory-only
and reset on publisher restart; producer calls while it is absent fail closed
without affecting the stats mutation. Snapshot reconciliation covers the gap.

## Mutation scope

Stats create marks only a successful insert. Update marks after ETS success and
only if content changed (excluding the internal is_archived flag). Flush marks
only a previously present row after deletion. If account/queue identity changes,
both old and new scopes are marked, subject to the same explicit bounded loss.
No call ID, caller data, agent data or metric is copied into a hint.

Bulk `ets:select_delete` retains its existing archive/cleanup behavior. After
removing rows it records a bulk operation and row count locally; it does not
scan/copy arbitrary removed scopes, invent a queue ID, or publish a cross-tenant
event. Deleting the last row of a queue can therefore produce no exact hint;
the mandatory 15-second snapshot reconciliation handles that gap. Archive-only
bookkeeping and zero-row/no-op changes do not emit hints.

The existing validated `acdc_queue_handler:handle_config_change/2` marks its
scope only after successful handling, preserving the original result and
failure behavior. Global queue creation and per-queue manager edit/delete
listeners already invoke this handler. A configuration event that is missed,
or whose existing local handling fails, is not guaranteed to produce a hint;
reconciliation must refresh queue inventory as well as metrics. This hook
does not claim completion of asynchronous worker refreshes.

## Offline proof status

Root run 96553 retained `/tmp/kazoo-dashboard-events.oLAFKR`: all eleven production
modules compiled under the 128 MiB cap/768 MiB reserve and 21 groups passed, but
the overall run failed when empty configuration JSON reached a legacy validator
recursion. This is not a passing suite. The narrow candidate correction guards
empty/malformed configuration objects and empty changed-hint input before that
legacy API, with individual 200 ms negative-case deadlines. The global validator
is unchanged.

Corrected root run **62617 passed all 24 groups and eleven production-module
compiles**, with stable inputs, under the same 128 MiB cap/768 MiB reserve and
network namespace. Evidence: `/tmp/kazoo-dashboard-events.gK9IkK`; receipt SHA256
`f4bed4aeb5e2cfc57d5732ae429ea4cec02a90874e0d73551685c2cca5bf9456`,
EUnit log SHA256
`0732193fe4c250951238667fe594a1f2c4a21910eb6aefc73b8e8696803ee3bd`.
This is the scoped offline proof below, not native broker delivery, deployed
subscription, service, or browser acceptance. The earlier failed evidence is
preserved rather than relabeled as a pass.

Root-coordinated command, with unchanged resource reserve and network isolation:

```sh
cd /opt/kz5
/usr/bin/bash scripts/run-kazoo-validation.sh --memory-mib 128 --reserve-mib 768 --runtime-sec 90 -- /usr/bin/unshare --net /usr/bin/bash /opt/kz5/scripts/test-acdc-dashboard-events.sh
```

The runner creates a protected `/tmp/kazoo-dashboard-events.*` output directory,
pins its source/dependencies before and after (also on failure), compiles eleven
production modules with `-Werror` and no TEST/export_all, checks exact private
loaded paths, then runs 24 focused EUnit groups. Actual KAPI/JSON, ETS/coalescer,
stats callbacks, configuration validation/handler and supervisor specification
are exercised; broker/pool and existing queue lifecycle side effects are local
doubles. Cases cover closed wire/federation/account scope, overload/concurrency,
token races, unconfirmed success/local failures, fairness, no-op and failed
mutations, mark-time ordering, bulk loss, archive preservation, config handling,
and producer progress while the actual publisher process is blocked. Evidence
is retained on failure. No provider, live broker, service or deployment is tested.
