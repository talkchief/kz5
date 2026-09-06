# Live queue summary/detail — source checkpoint

September 6, 2026. The bounded live DTO adapter and source/template browser
fixture pass offline. This is not a deployment or complete live-dashboard
acceptance. Historical screens and workforce reporting are postponed for future
ClickHouse work, per the user's scope change.

## Files and behavior

- `monster-ui/acdc/app.js`: `requestLiveDashboard` isolates the read interface;
  `formatLiveDashboard`, `renderLiveDashboard` and `mountLiveDashboard` implement
  the two views and account/navigation generation guards.
- `monster-ui/acdc/views/dashboard.html`: page-local search, name-sorted queue
  cards, explicit previous/next navigation, detail and existing editor links.
- `monster-ui/acdc/views/dashboard-detail.html`: back navigation, selected queue
  active-call observations and saved roster with observed global agent status.
- `monster-ui/acdc/style/app.scss` and `i18n/en-US.json`: responsive card/detail
  styling, accessible labels and explicit source/error/stale notices.
- `monster-ui/acdc/tests/live-dashboard.test.cjs`: offline AMD, interaction
  doubles and real Handlebars template checks.
- `scripts/test-monster-acdc-live-dashboard.cjs`: Chromium coverage of the actual
  source app and templates, with in-memory API replies and blocked network.

Overview makes **one GET** to
`/accounts/{accountId}/queues/live?page_size=50`, adding `start_queue_id` only
for a subsequent page. The API/adapter limit is 100; this UI requests 50. It does
not fetch all pages automatically. Search, sorting and displayed queue counts
apply to the current page, not the account's whole inventory.

Detail makes **one GET** to `/accounts/{accountId}/queues/{queueId}/live`.
Only after a valid primary reply for the active view does it make three existing
read-only supplemental requests: saved queue roster, agent names and observed
global agent statuses. Those legacy reads are not a bounded runtime-agent
snapshot. Neither view uses the old `/queues/stats` dashboard seam or requests
historical statistics. Queue editor, callback and agent write controls remain
outside this change.

The adapter validates version/account/queue scope, pagination, capabilities,
source metadata, metrics and call rows. Count cards use DTO metrics, not the
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

## Important limits — do not advertise completion

The UI now consumes the live snapshot endpoint's collector projection. Its
source contract describes compared known replicas and explicitly non-atomic
observations, not complete telephony occupancy. Server generation time is not
source freshness. Capability flags still declare runtime-agent snapshots,
WebSocket updates and historical reporting unavailable. Support for detail call
rows does not imply those rows are available in every response.

Saved roster is not runtime queue membership or eligibility. Global status or
SIP registration is not proof an agent can receive this queue's call. The UI
validates roster IDs up to 1,000 and renders at most 200 with a truncation notice;
an oversized, malformed or incomplete roster is unknown. Name/status failures
fall back to IDs/unknown status. These supplementary reads do not establish
cluster-wide agent coverage. No SLA, performance ranking, daily totals or
historical handle-time metric is fabricated.

Scoped native Blackhole invalidation/update delivery is not connected by this
slice. Completion still requires its authenticated integration, matching API
and message contracts, a production UI build and actual call-state validation.
The synthetic browser fixture does not certify token/resource authorization,
broker delivery, runtime-agent eligibility or production deployment. Polling-only
delivery is not a substitute for the requested native Blackhole integration.

## Test evidence

Current DTO checkpoint: root session **37074 passed all 22** updated offline
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
needed. Root owns the serialized 384 MiB browser window and temporary development
service pauses under a restoration trap, following a zero-call check. Do not
infer completion of the other suites or service restoration from the browser
result alone while that enclosing window remains active.

Historical pre-DTO checkpoint **11055** passed 22 dashboard and 20 queue-login
groups with seven stable input pins, retained in
`/tmp/kazoo-live-dashboard-ui.a8J2jg/`. Its first attempt **16433** failed syntax
validation before tests because a request loop lacked its closing `});`;
corrected before the successful rerun. That failure remains in
`/tmp/kazoo-live-dashboard-ui.Lym2sS/`. These older receipts are not evidence for
the new DTO adapter.

From a test workspace with compatible Lodash and Handlebars installed:

```bash
node /opt/kz5/monster-ui/acdc/tests/live-dashboard.test.cjs
node /opt/kz5/monster-ui/acdc/tests/queue-login.test.cjs
```

Use the repository resource guard for tests on the shared development server.
Browser execution additionally needs the compatible runtime and explicit
`KAZOO_PLAYWRIGHT_MODULE` environment setting. Do not automatically stop services
on a different/production host. No deployment or live account write is claimed
by these fixtures.
