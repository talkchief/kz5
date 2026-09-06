# Live queue summary/detail — source checkpoint

September 6, 2026. Source implementation tested offline; not deployed or accepted
as a complete live dashboard. Historical screens and workforce reporting are
postponed for future ClickHouse work, per the user's scope change.

## Files and behavior

- `monster-ui/acdc/app.js`: `requestLiveDashboard` isolates the read interface;
  `formatLiveDashboard`, `renderLiveDashboard` and `mountLiveDashboard` implement
  the two views and account/navigation generation guards.
- `monster-ui/acdc/views/dashboard.html`: searchable, name-sorted queue cards
  linking to selected queue detail and the existing queue editor.
- `monster-ui/acdc/views/dashboard-detail.html`: back navigation, selected queue
  active-call observations and saved roster with observed global agent status.
- `monster-ui/acdc/style/app.scss` and `i18n/en-US.json`: responsive card/detail
  styling, accessible labels and explicit source/error/stale notices.
- `monster-ui/acdc/tests/live-dashboard.test.cjs`: offline AMD, interaction
  doubles and real Handlebars template checks.

The overview now requests queue inventory and current stats only. Detail adds
the selected roster, agent names and observed global statuses. Neither view
requests historical call/agent statistics. Existing queue editor, callback and
agent controls are preserved. The old formatter remains for compatibility;
the live dashboard rendering path no longer uses its historical requests.

Source failures are unknown, not zero. A valid empty response means only an
empty observed subset. Duplicate/malformed stats and incomplete inventory
responses are rejected. Queue names fall back safely to IDs; API labels are
escaped. Display is capped at 200 calls and 200 roster members with explicit
truncation notices; counts still cover the returned records. Cached data is
scoped to account/queue, and late requests cannot overwrite another view.

## Important limits — do not advertise completion

The read interface still uses existing `/queues/stats`, which is a recent,
single-responder subset and can omit older active calls. The newly tested
`acdc_dashboard_collector` is **not wired to this UI yet**. The screen therefore
labels counts as observations, not complete occupancy. Server response time is
not source observation time. A timer marks responses stale after 30 seconds;
it does not refresh data or establish a WebSocket connection.

Saved roster is not runtime queue membership/eligibility. Global agent status
is not proof an agent can receive this queue's call. No fabricated SLA,
performance ranking, daily totals or handle-time metric is shown. The supplied
designs' full metric and supervision requirements remain open.

Completion requires the authorized bounded snapshot endpoint, scoped native
Blackhole invalidation/update delivery, resource authorization, cluster and
source-coverage handling, OpenAPI/message contracts, a matching production UI
build and actual browser/call-state validation. Polling-only delivery is not
accepted as a substitute for the requested Blackhole integration.

## Test evidence

Root session **11055 exited 0**: JavaScript syntax check, all **22** dashboard
groups and all **20** existing queue-login groups passed. All seven input pins
were unchanged. Evidence retained in `/tmp/kazoo-live-dashboard-ui.a8J2jg/`:
`inputs.sha256`, `live-dashboard.log`, `queue-login.log`.

The first run, 16433, failed syntax validation before tests: the new request
loop lacked its closing `});`. Root corrected it and reran the full checks.
Failure evidence remains `/tmp/kazoo-live-dashboard-ui.Lym2sS/`.

Tests used the existing Monster UI build checkout's Lodash/Handlebars under
Node 18.20.8, a network-isolated validation process, 128 MiB cap, 768 MiB reserve
and 60-second deadline. No provider requests, account writes, production browser
or deployment occurred. Root briefly paused only development eCallMgr for test
memory after checking zero calls, then restored it through an EXIT trap.

From a test workspace with compatible Lodash and Handlebars installed:

```bash
node /opt/kz5/monster-ui/acdc/tests/live-dashboard.test.cjs
node /opt/kz5/monster-ui/acdc/tests/queue-login.test.cjs
```

Use the repository resource guard for tests on the shared development server;
do not automatically stop services on a different/production host.
