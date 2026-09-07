# Deployed live queue reconnect acceptance

September 7, 2026: the actual development queue-detail browser passed a
controlled connection-loss/recovery check. This covers the live summary/detail
delivery, not historical reporting or ClickHouse integration.

## Tested behavior

`scripts/test-monster-live-deployed.cjs` accepts the opt-in environment flag
`KAZOO_TEST_RECONNECT=true`. It requires `KAZOO_TEST_REQUIRE_WEBSOCKET=true`
and standalone execution; natural-call and summary-call modes reject this
combination before browser or credential work. Without the flag the existing
browser/call modes retain their behavior.

The browser uses normal login, the deployed production assets, the overview,
and a normal click into the selected queue. After the initial real native ACK
and snapshot, the probe:

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

## Evidence

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
