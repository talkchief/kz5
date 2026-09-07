# Live queue summary/detail — development deployment

## Current live-only acceptance — September 7, 2026

The deployed summary and clicked-queue detail have both passed actual browser
call-transition checks: waiting → handled → gone, driven by native Blackhole
hints followed by authorized snapshot GETs. Summary evidence is
`/tmp/kazoo-monster-live-deployed.4jYi2Y/receipt.json`; the final shared-source
detail recheck is `/tmp/kazoo-monster-live-deployed.IBFBXo/receipt.json`.
See [the browser/call acceptance guide](monster_browser_call_acceptance.md)
for exact scope, call proof and cleanup evidence. Restricted-user isolation,
cross-node failure and load/soak acceptance remain open.

The deployed detail now also passes controlled connection-loss recovery under
the same account and after normal company switching: visible stale state,
new native ACK, fresh no-store GET, independently matched call counts/rows and
normal unsubscribe cleanup. See [reconnect acceptance](monster_live_reconnect_acceptance.md).
Summary-page reconnect and restricted-user isolation remain separate tests.

Live-only scope recheck on September 7 passed all 46 offline UI groups with the
current patched framework (completion `b0c8ae`). This was network-isolated,
192MiB-capped validation with a 512MiB reserve, not a new browser or call test.
Initial invocations lacked dependency resolution (`c233c1`) and then the
required lifecycle source input (`cd1fd5`); the explicit inputs below resolved
both harness setup errors without application changes or service restarts.

Only the live queue summary and selected queue detail are current delivery
work. Agent observations inside queue detail remain included; separate agent
dashboards, history, workforce reports and ClickHouse integration are postponed.
Existing historical storage is unchanged. The earlier deployment checkpoint
below is retained as evidence, not the latest acceptance status.

## Earlier deployment checkpoint

September 7, 2026. The corrected single-GET adapter and sequential native
subscriptions passed 46 offline and 24 Chromium fixture groups (root24147).
The fresh production build in `monster-owned-build.Fd3cY7/source` passed and
was deployed32580 with exact ownership/configuration readback. Real browser65670
passed all seven checks against the served production bytes and native socket,
with zero console/page/HTTP errors, supplemental reads or late overview GETs.
Historical screens and workforce reporting remain postponed for future
ClickHouse work. A separate real-call HTTP/native-WebSocket test79231 now
passes waiting → handled → removed against the deployed backend, with15 valid
snapshots,3 natural invalidations and verified single-agent media bridge. See
`doc/acdc_ordinary_bridge_proof.md`. This does not yet prove browser rendering
during a call, restricted-user isolation, load or production readiness.

## Files and behavior

- `monster-ui/acdc/app.js`: `requestLiveDashboard` isolates the read interface;
  `formatLiveDashboard`, `renderLiveDashboard` and `mountLiveDashboard` implement
  the two views and account/navigation generation guards.
- `monster-ui/acdc/views/dashboard.html`: page-local search, name-sorted queue
  cards, explicit previous/next navigation, detail and existing editor links.
- `monster-ui/acdc/views/dashboard-detail.html`: back navigation, selected queue
  active-call observations and authorized saved roster with separate observed
  runtime state and queue membership.
- `monster-ui/acdc/style/app.scss` and `i18n/en-US.json`: responsive card/detail
  styling, accessible labels and explicit source/error/stale notices.
- `monster-ui/acdc/tests/live-dashboard.test.cjs`: offline AMD, interaction
  doubles and real Handlebars template checks.
- `scripts/test-monster-acdc-live-dashboard.cjs`: Chromium coverage of the actual
  source app and templates, with in-memory API replies and blocked network.
- `scripts/test-monster-live-deployed.cjs`: opt-in browser acceptance against
  actual served production assets and native Blackhole, without application
  overlays, fake API replies or injected socket events.

Overview makes **one GET** to
`/accounts/{accountId}/queues/live?page_size=50`, adding `start_queue_id` only
for a subsequent page. The API/adapter limit is 100; this UI requests 50. It does
not fetch all pages automatically. Search, sorting and displayed queue counts
apply to the current page, not the account's whole inventory.

Detail makes **exactly one GET** to
`/accounts/{accountId}/queues/{queueId}/live`, including on reconciliation. Its
`agents` object contains authorized roster identities/names and bounded runtime
observations. There are no supplemental roster, global-status or name HTTP
reads, and no fallback to them. The strict current version-1 contract requires
detail `agent_runtime=true` and an agents object; overview requires
`agent_runtime=false` and `agents=null`. An older incompatible detail response
fails validation rather than invoking legacy reads. Neither view uses the old
`/queues/stats` dashboard seam or requests historical statistics. Queue editor,
callback and agent write controls remain outside this change.

The three live resource definitions explicitly use `cache: true` to suppress
Monster/jQuery's automatic `_` cache-buster query parameter. This does not add a
client snapshot cache: the API's `Cache-Control: no-store` still governs HTTP
caching. The backend continues to reject unknown query keys; overview accepts
only `page_size`/`start_queue_id`, and detail accepts none.

The adapter validates version/account/queue scope, pagination, capabilities,
source metadata, metrics, call rows and agents. Call count cards use DTO metrics, not the
length of a capped call list. Detail distinguishes unavailable, available empty
and truncated calls; at most 200 rows are shown, ordered by entry time rather
than queue position. The DTO's observed count can exceed the row cap. Unix
timestamps and the source observation-window end determine displayed durations;
the UI does not invent caller identity, assigned agent or ticking call state.

Valid partial/unavailable replies retain queue configuration but show unknown
metrics and the source reason, not zero. Malformed replies or request failures
retain only a matching previous snapshot marked stale; without one they show an
error. Recognized 401/403/404 failures clear that cache. Cache and late-response
guards include account, queue, page and navigation generation. API labels are
escaped. A timer marks data stale after 30 seconds; it does not fetch updates.
Same-scope refresh preserves overview search text, filtering, and the current
search focus/selection, including edits made while a GET is held. It does not
steal focus moved elsewhere. Queue, page and account navigation reset search.

## Native invalidation controller

`renderLiveDashboard` owns one account/queue/page controller. Only a validated DTO
with `capabilities.websocket_updates: true` permits `monster.socket.bind` using
the tested [subscription lifecycle API](monster_socket_lifecycle.md). The account
is a separate `accountId` option; the exact binding is
`queue_live.changed.QUEUE_ID`. Overview registers only the current authorized
page's queue IDs (50 by default, at most 100); detail registers one. At most 100
local desired records exist, but only one subscription authorization is pending:
the next call to `bind` waits for the preceding ACK/error. An event must
match `{version: 1, account_id, queue_id}`. It invalidates the snapshot, never
increments counters or supplies displayable call/agent data.

The first authorized snapshot discovers the capability and scope. Subscription
ACKs, including reconnect ACKs, and invalidations request the same authorized
snapshot through 100ms coalescing. At most one snapshot batch is in flight; a
dirty flag retains one follow-up request. Unchanged subscriptions survive
same-scope refreshes, avoiding ACK/rebind loops. While support remains true,
15-second reconciliation also repairs missing events and transient subscription
failures. Server, authentication and transport failures have a 15-second retry
floor, even if other queues keep emitting events or the user refreshes. Only
the framework's local `cleanup_pending` result permits up to three one-second
retries while the previous view's unsubscribe finishes; subsequent failures
return to the 15-second floor. A successful ACK resets that bounded allowance.
Admission is also paced by one second after an error. Failed handles, including `connect() => false`, are cancelled
immediately so they cannot be replayed by the framework between retries.

On disconnect, the controller cancels its own framework handles and keeps only
bounded local intent. This prevents the framework's automatic reconnect from
submitting every retained subscription in parallel. After a one-second delay it
admits one fresh handle, which awaits its actual lifecycle ACK/error (including
the existing three-second deadline), without per-second handle churn. Further
subscriptions follow sequentially. First/reconnect ACKs still request a snapshot;
the app never disconnects the shared socket to manage its own listeners.

ACK is only a correlated Blackhole reply, not a broker-binding barrier, replay
or gap-free-delivery guarantee. The screen separately reports pending,
acknowledged, disconnected, rejected/unavailable and unsupported transport
states. Disconnect/error makes retained values stale, not zero. Capability
true-to-false removes subscriptions and reconciliation; unsupported responses
retain manual Refresh. Recognized snapshot HTTP 401/403/404 cancels the controller
and clears its cache immediately. Partial source counts remain unknown regardless
of transport state.

Queue/page/tab navigation and app rendering cancel exact returned listener
handles; account/generation checks and DOM-detachment observation retire stale
controllers. Disposed callbacks cannot mount data, schedule repair or advance
subscription admission. No shared socket disconnect, automatic login,
agent-state mutation, editor write or callback write is added. HTTP requests
already sent are ignored after disposal, not claimed remotely cancelled.

## Important limits — do not advertise completion

The UI now consumes the live snapshot endpoint's collector projection. Its
source contract describes compared known replicas and explicitly non-atomic
observations, not complete telephony occupancy. Server generation time is not
source freshness. Historical reporting remains unavailable. The backend
WebSocket capability is controlled by the backend; this UI does not turn it on.
The latest dynamic capability change is compiled and activated on the development
server. It reports local Blackhole module registration, not end-to-end transport
health. The corrected production UI build is deployed and owned-content verified.
Live call-transition and full acceptance remain open. Support for detail
call rows does not imply those rows are available in every response.

Saved roster is not runtime queue membership or eligibility. The server queries
at most 201 selected-queue user documents, authorizes the identities and their
status resources including the lookahead, and returns at most 200 unique,
ID-sorted rows. Names come from those authorized documents, not broker payloads.
The UI validates the exact bounded agents/row shapes. A truncated roster has an
unknown total count, not an invented total of 200.

Observed runtime states are exactly `wait`, `sync`, `ready`, `ringing`,
`answered`, `wrapup`, `paused` and `outbound`. An observed row has a separate
boolean `queue_member`; an unobserved row has null state/membership and reason
`not_observed`, `inconsistent_sources` or `source_unavailable`. Unknown never
means logged out. Roster completeness, runtime completeness and agent observation
time are displayed separately from call-source availability. Null runtime times
mean unavailable observations, even for an empty roster; an available empty
roster can be runtime-complete. Truncation prevents runtime completeness.
Even a complete observation with `ready` plus queue membership does not prove
endpoint reachability or ready-to-ring eligibility; the DTO explicitly keeps
`endpoint_reachability_verified=false`. No SIP/global-status inference, SLA,
performance ranking, daily totals or historical handle-time metric is fabricated.

The client lifecycle integration does not by itself prove scoped native
Blackhole delivery. A separate authenticated live wire test (root65638) passed
scoped subscription, a deliberately triggered invalidation, detail refetch and
unsubscribe, plus anonymous/wildcard rejection. The matching production build
and deployed browser navigation acceptance now pass; actual call-state validation
and isolation/load acceptance remain open.
The synthetic browser fixture does not certify token/resource authorization,
broker delivery, runtime-agent eligibility or production deployment. Polling-only
delivery is not a substitute for the requested native Blackhole integration.

## Test evidence

Latest source `220b37b`: root24147 passed46 offline groups and24 Chromium groups
(`/tmp/kazoo-monster-live-dashboard.JhP4tA`). Root32580 deployed two bundles from
`monster-owned-build.Fd3cY7`, preserving1942 files and removing none. Root65670
passed the actual deployed runner, with receipt
`/tmp/kazoo-monster-live-deployed.tWj7DM/receipt.json`: seven checks, two detail
GETs (initial and native ACK-followup), zero supplemental/late-overview reads,
three subscribe ACKs and three unsubscribe ACKs across the exercised navigation.
No natural events occurred during this browser run; it does not prove their
delivery. Source lifecycle regression46 reproduces delayed old-view cleanup with
the actual patched framework and verifies the new bounded retry; server/auth
and transport failures retain the existing15-second floor.

Earlier browser90297 failed before that fix, after rendering valid detail but
without a selected subscription within10 seconds. Receipt:
`/tmp/kazoo-monster-live-deployed.79ZvMD/receipt.json`. The old-view unsubscribe
was still pending when detail bound; the app previously delayed that local
`cleanup_pending` failure for15 seconds. This was a real app issue, distinct
from browser53986's earlier test-phase correlation problem.

The deployed browser runner requires Node 20+, Playwright, explicit
`KAZOO_TEST_ACCOUNT_ID` and `KAZOO_TEST_QUEUE_ID`, and expected production
`KAZOO_TEST_EXPECT_MAIN_SHA256` / `KAZOO_TEST_EXPECT_TEMPLATES_SHA256` hashes.
Use `KAZOO_TEST_REQUIRE_WEBSOCKET=true` for native acceptance. It reads the
root-owned mode-0600 installer credential file privately, authenticates normally,
and restricts endpoints to this server. It permits only that authentication
write and actual scoped subscribe/unsubscribe frames; it does not change calls,
agents, queues or saved browser sessions. Optional external fonts are omitted
and counted. Receipts contain fixed diagnostic categories, hashes and counts,
not credentials, raw frames, screenshots or response payloads.

Its acceptance requires valid overview/detail rendering, one initial detail
GET without supplemental reads, a correlated selected-queue native ACK followed
by an accepted detail refetch before the 15-second repair interval, and normal
navigation with an acknowledged selected unsubscribe. New overview requests
after detail entry fail acceptance; late completion of earlier requests does
not. This proves the exercised navigation lifecycle, not a broker delivery
barrier, natural call-transition delivery, cross-tenant isolation or soak/load.

Resolved query bug: the first actual deployed browser run **14971**
authenticated normally but failed at overview, with two HTTP 400 responses and
no WebSocket connection. Its retained receipt is
`/tmp/kazoo-monster-live-deployed.EaRjAT/receipt.json`. Root confirmed the emitted
query contained `page_size=50` plus `_`; direct-API wire run **32168** passed
without that extra key. Actual Monster `defineRequest` defaults `cache` to false,
and `request` appends `_cacheString` before jQuery sends the request. The narrow
three-resource fix above passed43 offline/24 Chromium groups and a fresh production
build in root12274, then deployed97771 (only main/templates changed).
Two added offline groups guard the resource definitions and load the actual
Monster AMD request constructor (only its AJAX boundary is substituted): all
three corrected queries must omit `_`, while deleting the flags must reproduce
it. All43 groups passed. The second deployed browser run53986 confirmed zero
console/page/HTTP errors and valid overview/detail rendering; its failing native
ACK-order assertion is being corrected in the harness, not treated as a PASS.

Pre-cache-buster-fix checkpoint: root session **5676 passed all 41 offline groups** on the
frozen agents/sequential-admission source. Root session **63756 passed all
24 Chromium groups**, retained in
`/tmp/kazoo-monster-live-dashboard.8MsOwE/`. These fixtures include
strict agents contradictions, all eight states with either membership value,
unknown/empty/truncated controls, search/focus preservation, one-pending native
authorization, reconnect cancellation and failed-connect cleanup. The browser
fixture delivers 50 queue ACKs in separate browser turns through a synthetic
socket; it does not prove real multi-queue broker delivery.

Pre-controller DTO checkpoint: root session **37074 passed all 22** updated offline
dashboard groups and all **20** existing queue-login groups.

Root session **5608 passed all 12 Chromium groups**, with stable source pins;
evidence is retained in `/tmp/kazoo-monster-live-dashboard.OiYWds/`. It used
Node 22.23.2, actual app/vendor/template code, synthetic API responses and blocked
network. This is source/template coverage, not boot of a production-built
artifact. The preceding browser attempt **62976** stopped on incompatible
Node 18 before assertions; an earlier memory-admission refusal also ran no
browser assertions. Neither is a regression reproduction.

The browser runner requires a compatible Node 20+ runtime. The successful run
used the existing cached executable
`/tmp/kazoo-ui-browser.eXdEqS/node_modules/node/bin/node` and Playwright at
`/tmp/kazoo-ui-browser.eXdEqS/node_modules/playwright`; no global Node upgrade was
needed. Root owns serialized resource windows and any temporary development
service pauses under a restoration trap, following a zero-call check.

Historical pre-agents/pre-sequential controller checkpoint: root64066 passed all32 offline groups (22 existing plus
10 fake-clock/socket groups). Root55555 passed all18 Chromium groups (12 existing
plus six synthetic lifecycle/clock groups), with stable source/vendor hashes;
evidence `/tmp/kazoo-monster-live-dashboard.u5WbOa`. The same window passed all20
unchanged queue-login groups. These cover scope/capability gates, burst/held-request coalescing,
synchronous ACK, disconnect/reconnect, retry/reconciliation bounds, capability
removal, denial and navigation/detachment. Existing queue-login coverage remains
a separate compatibility gate. None
of those socket fixtures proves a live broker or authenticated WebSocket, and
those receipts do not validate the current agents/sequential-admission changes.

Historical pre-DTO checkpoint **11055** passed 22 dashboard and 20 queue-login
groups with seven stable input pins, retained in
`/tmp/kazoo-live-dashboard-ui.a8J2jg/`. Its first attempt **16433** failed syntax
validation before tests because a request loop lacked its closing `});`;
corrected before the successful rerun. That failure remains in
`/tmp/kazoo-live-dashboard-ui.Lym2sS/`. These older receipts are not evidence for
the new DTO adapter.

From a test workspace with compatible Lodash and Handlebars installed, set
`KAZOO_MONSTER_LIFECYCLE_SOURCE` to the absolute `src/js/lib/monster.socket.js`
path in a source stage prepared with the repository's current framework patches.
The lifecycle regression intentionally fails if this input is absent; an
unpatched upstream checkout is not a substitute. For the current September 7
development build, run from `/opt/kz5` with explicit dependency paths inside
the guard (which intentionally strips the caller's environment):

```bash
bash scripts/run-kazoo-validation.sh \
  --memory-mib 192 --reserve-mib 512 --runtime-sec 90 -- \
  /usr/bin/unshare --net /usr/bin/env \
  NODE_PATH=/usr/local/src/kazoo5-installer/monster-owned-build.nUolDS/source/node_modules \
  KAZOO_MONSTER_LIFECYCLE_SOURCE=/usr/local/src/kazoo5-installer/monster-owned-build.nUolDS/source/src/js/lib/monster.socket.js \
  /tmp/kazoo-ui-browser.eXdEqS/node_modules/node/bin/node \
  /opt/kz5/monster-ui/acdc/tests/live-dashboard.test.cjs
```

These build/runtime paths are local evidence locations, not portable installer
defaults; a new test host must provide its own reviewed patched stage and runtime.
Use the repository resource guard for tests on the shared development server.
Browser execution additionally needs the compatible runtime and explicit
`KAZOO_PLAYWRIGHT_MODULE` environment setting. Do not automatically stop services
on a different/production host. No deployment or live account write is claimed
by these fixtures.
