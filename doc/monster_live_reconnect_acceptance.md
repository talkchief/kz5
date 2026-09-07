# Deployed live queue reconnect acceptance

September 7, 2026: both deployed views passed controlled connection-loss recovery,
with same-account login and normal company switching, after the P0-18 fix.
This covers live summary/detail delivery, not history or ClickHouse integration.

## Tested behavior

`scripts/test-monster-live-deployed.cjs` accepts the opt-in environment flag
`KAZOO_TEST_RECONNECT=true`. It requires `KAZOO_TEST_REQUIRE_WEBSOCKET=true`
and standalone execution. `KAZOO_TEST_RECONNECT_VIEW` defaults to `detail`;
set it to `summary` to test the visible overview page instead. An explicit view
requires reconnect mode, and other view values are rejected. Natural-call and
summary-call modes reject reconnect mode before browser or credential work.
Without the flag the existing browser/call modes retain their behavior.

In detail mode, the browser uses normal login, the deployed production assets,
the overview, and a normal click into the selected queue. After the initial
real native ACK and snapshot, the probe:

1. Closes only its own two-sided routed connection with WebSocket code 1012.
   It does not restart Blackhole or alter any other client's connection.
2. Observes the existing queue controller retain its actual snapshot, display
   disconnected transport and visibly mark the detail stale. The replacement
   server connection is briefly gated until this observation; no application
   state, ACK, event or API response is injected.
3. Lets the native client reconnect. Exactly the next connection must submit
   one subscription for the same account and exact selected queue. Its real
   correlated success reply must contain only that binding in both the
   `subscribed` and `subscriptions` arrays.
4. Requires a detail GET started after that ACK and within five seconds of it,
   a later successful `Cache-Control: no-store` response validated against the
   current DTO schema, and agreement with the visible, non-stale detail under
   the same controller generation. Visible call counters, ordered call IDs /
   states and the empty-row state are compared independently to that DTO.
   Recovery must finish within 12 seconds.
5. Navigates away normally and verifies the selected unsubscribe ACK on the
   replacement connection. When company switching is requested, normal home
   restoration follows this cleanup.

The observer keeps scope and request identifiers only in memory. Persisted
reconnect evidence contains ordinals, booleans and elapsed milliseconds; no
tokens, DTOs, names, raw frames, screenshots or browser storage are saved.

### Summary mode

Summary mode stays on one visible overview page; it does not click into queue
detail or run a call. Before closing the socket, it requires a quiescent,
acknowledged controller, a valid overview DTO, and exactly the page's unique
queue bindings. It compares independently captured DOM cards, their queue IDs,
waiting/handled counts, page count and selected-queue values to that DTO.
Unavailable metrics must display a dash, not zero. The active-app and account
guards remain required.

The replacement connection must be exactly the next generation and subscribe
sequentially, with at most one request pending, to every original page binding
exactly once. Each real correlated ACK must report the newly subscribed
singleton and a `subscriptions` set equal to all page bindings acknowledged so
far. Only the final page ACK opens the snapshot acceptance barrier. A GET
started before it cannot prove recovery, even if its response arrives later.
The accepted overview GET must start within five seconds after that final ACK;
its schema-valid, no-store response and every recovered visible card must agree
under the same controller generation within the overall 12-second bound. Page
membership changes during this probe fail the comparison.

Closing and reconnecting affect only the test's socket. The harness clears its
own old-connection binding ledger, not application state. Normal navigation
must then send every page unsubscribe on the replacement connection and receive
every correlated ACK plus an empty final subscription set before any home
account restoration. This proves ACK-following resnapshot, not exclusive
causality: periodic reconciliation may also trigger a GET. It does not prove
lost-event replay or event completeness.

## Current deployed evidence

Fresh production stage `monster-owned-build.OxxzgK/source` passed build/artifact
checks `e175b8`. Deployment `e8e212` changed only main/templates, removed nothing
and preserved 1,942 files, including configuration, capabilities and API docs.
Backup: `/usr/local/src/kazoo5-installer/monster-owned-build.OxxzgK/deployment-backup`.

| View / login | Browser result | Recovery | Receipt under `/tmp/` |
| --- | --- | --- | --- |
| Summary / same account | `0cfeb5`, 7 checks | 1412ms | `kazoo-monster-live-deployed.FfHvIy/receipt.json` |
| Summary / company switch | `f7f21e`, 10 checks | 1388ms | `kazoo-monster-live-deployed.ZAKfFq/receipt.json` |
| Detail / same account | `fd684b`, 9 checks | 3123ms | `kazoo-monster-live-deployed.xVlVEO/receipt.json` |
| Detail / company switch | `138a89`, 12 checks | 2708ms | `kazoo-monster-live-deployed.HGRoBP/receipt.json` |

All four retained the controller, matched visible data, acknowledged disposal,
and had zero browser/HTTP/scope errors or supplemental dashboard reads. Both
summary reconnect pages contained one queue; 100 sequential subscriptions are
offline coverage, not a live scale result. Final test-source checks
`f369da`/`03a1c2` passed 19 scope, 24 reconnect and 18 call-observer groups.

The build temporarily paused ecallmgr and simulated phones under the unchanged
384MiB/512MiB-reserve guard; both were restored. Browser tests kept all eight
platform services running and paused only simulated phones. After the detail
same-account browser PASS, phone restoration hit systemd's start-rate limit
because of repeated test pauses (`fd684b` wrapper exit1). Logs showed clean
shutdowns, not a crash; exact-unit reset-failed/start restored it (`adda12`).
No restart policy was changed; the subsequent switched-detail wrapper passed.

The harness waits for native startup routing before initiating navigation,
and does not reopen an already-active default ACDC page. Earlier probes
`rTdBWD`/`e7DYM4` recovered correct snapshots but raced Core's final startup
route, replacing the controller; `ydQzX9` detected redundant routing cleanup.
The first postdeploy `8Ctj8a` probe also counted a Core alerts refresh as a
supplemental dashboard read. Exact current-account `/alerts` reads now remain
in HTTP/error/scope accounting but are excluded from that data-fetch metric.
Active-app, controller, schema, binding and cleanup assertions were retained.
Admin/default-app and explicit switched-hash startup are covered; non-admin
users with no default app opening the app launcher are not covered here.

Deployed SHA256 values:

```text
main.js      5ae7035f5bb4cc963c8f85419c602db76f17297134b257b3d78cb6e237b657c3
templates.js b4affe1d06358720f7bf424f32083cab1e06849c3ba385bffbe3d282e53e993d
config.js    cd4a12cae81ed6cdeda9eb718be47af4f010e23399bd8f4bda9520a2d1484d13
```

## Earlier evidence

Switched-company summary run `45e8a1` passed ten actual browser checks:
`/tmp/kazoo-monster-live-deployed.O0lCKR/receipt.json`. Its visible page contained
one real queue. Recovery took 1314ms, with a replacement-connection ACK, fresh
overview GET, page cleanup and normal home restoration; no errors were
reported. This is not live multi-queue or 100-queue acceptance. The summary
tracker's 100 sequential subscriptions are offline fixture coverage only.

Earlier default-login summary run
(`/tmp/kazoo-monster-live-deployed.QRTECM/receipt.json`) failed its active-app
guard: `myaccount` had replaced ACDC's foreground marker while the other
readiness checks passed. P0-18's focused offline baseline `ef9a77`
(`/tmp/monster-background-app-proof.gFLwnE`) reproduced that overwrite; candidate
`f43e08` (`/tmp/monster-background-app-proof.PVeswA`) passed all 12 groups.
The current deployed retests above supersede that source-only checkpoint; see
[P0-18 source and regression guidance](monster_background_app_load.md).

Same-account run `4a10d5` passed nine actual browser checks:
`/tmp/kazoo-monster-live-deployed.9C6AgQ/receipt.json`.
Recovery took 2780ms, with close/send/ACK/request/response orders 45–49 and a
new connection generation of 2. Three detail GETs, zero supplemental reads,
zero browser/page/HTTP/request/scope errors and normal unsubscribe cleanup.

Switched-company run `20c816` passed 12 checks on the same final test source:
`/tmp/kazoo-monster-live-deployed.3J492k/receipt.json`. Recovery took 3278ms;
orders 60–64 prove close → new subscribe → ACK → GET → response. Normal home
scope was disposed before switching, selected cleanup ran on the new socket,
and the original company was restored afterward. Three detail GETs and zero
supplemental reads or browser/HTTP/scope errors. This uses an administrator's
normal company switch, not a restricted principal.

Initial run `302e3d` (`/tmp/kazoo-monster-live-deployed.lkEgRC/receipt.json`)
passed transport and controller-snapshot checks with all nine services running.
Review then identified that those checks did not independently compare the
captured DOM call values. The final run above includes this stronger assertion;
do not use the initial receipt as proof of that comparison.

Final-run admission `9db524` refused for insufficient available memory before
browser work. Root then temporarily paused only the 30 simulated phone fixtures,
with an EXIT trap restoring their service. All eight platform services stayed
running, with the unchanged 320MiB cap / 512MiB reserve. This is not evidence
that the server can sustain production browser/call load.

The initial exact before/after roster and 31 reported agent status/membership
comparison passed `150314`; no state restoration was necessary. Snapshots are
protected files:

- `/tmp/kazoo-live-rollout.OYdOqh/phone-snapshot-before-reconnect.json`
- `/tmp/kazoo-live-rollout.OYdOqh/phone-snapshot-after-reconnect.json`

After both final runs, snapshot
`/tmp/kazoo-live-rollout.OYdOqh/phone-snapshot-after-final-reconnect.json`
verified the restored 30 simulated phones. Comparison `52c1c7` against the
pre-first-run snapshot confirmed identical roster and all 31 reported
statuses/memberships. No status or membership restore was performed.

Pure tracker regression `f6ea1b` passed 14 groups in
`scripts/test-monster-live-reconnect.cjs`; scoped harness regression `6b42a5`
passed 17 groups, then final-source recheck `744424` passed all 17 again.
These offline checks reject old/third connections, wrong
account/queue, duplicate commands/replies, mismatched requests, extra binding
ACKs, pre-ACK/in-flight snapshots, missing no-store, stale rendered counts/rows,
unknown-as-zero substitutions and evidence disclosure.
They do not substitute for the deployed-browser receipt.

## Running and limits

Use the existing deployed-browser prerequisites and artifact SHA pins described
in [browser/call acceptance](monster_browser_call_acceptance.md). Pass both
flags **inside** the resource guard through `/usr/bin/env`, because the guard
does not forward the caller's environment. Root used the reviewed Node 22 /
Playwright installation with a 320MiB cap and 512MiB reserve. A new deployment
needs its own verified asset pins and local
endpoint/scope inputs, not copied evidence paths.

This proves controlled close/reconnect and an ACK-following resnapshot, not
exclusive causality versus periodic reconciliation, delivery replay or a broker
binding barrier. It is not abrupt packet loss, node/broker failure, restricted
principal isolation, live-call continuity during reconnect, summary-page
reconnect, TLS acceptance or load/soak validation. Those remain separate gates.
See [live UI](acdc_live_dashboard_ui.md) and
[actual natural call tests](monster_browser_call_acceptance.md).
