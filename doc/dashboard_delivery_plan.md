# Call-center dashboards and workforce report

Status: implementation brief / open backlog, not deployed functionality.
Parent register: [PROJECT_TASKS.md](../PROJECT_TASKS.md), DASH-01–07 and WFM-01–04.
Destination is the existing Monster UI ACDC application, not a separate hosted
analytics product. Audience: account-authorized supervisors and workforce staff.
The supplied screenshots define appearance and navigation, not production data.

## Supplied designs and navigation

| Reference | Required behavior |
| --- | --- |
| [Live overview](<../dashboards design/Queues Live Dashboard Main.png>) | Sortable queue cards; service level, waiting, handled, abandoned, average wait/handle time. New queue and scoped administration menu. Click a queue card/title to open its live detail. |
| [Live queue detail](<../dashboards design/Queues Live Dashboard.png>) | Back to queues; eight KPI cards; agent/call state tabs and rows, search/sort, performance ranking; authorized supervision actions. Subscribe only to the selected account/queue and unsubscribe when leaving. |
| [Queue history](<../dashboards design/Queue Historical Dashboard.png>) | Date/queue filters, reconciled outcome chart and timing/SLA cards; details and export. |
| [Agent history](<../dashboards design/Agent Historical Dashboard.png>) | Date/agent/queue filters, identity/last activity, outcomes, talk/break/idle durations, details and export. |
| Workforce report — new, matching visual style | Session table with login/logout, working duration, queue memberships, break start/end/type/duration; summary cards, filters, per-agent drilldown and export. |

Do not copy screenshot numbers into runtime fixtures or dashboards. For example,
the queue-history image's 601 answered plus 96 abandoned does not equal its
641 total. Real data must reconcile using explicitly defined cohorts. The live
detail also mixes caller waiting and agent states; these are different entities
and need clear labels rather than an ambiguous aggregate "All" count.

## Source map and missing contracts

Source inventory inspected in this repository:

- `applications/acdc/src/acdc_stats.erl`, `acdc_stats.hrl`, `acdc_agent_stats.erl`
  and `acdc_stats_archive.erl`: call transitions/current stats and archived
  history; reconcile recent in-memory data with durable archived records.
- `applications/acdc/src/cb_acdc_call_stats.erl` and the call/agent Couch views:
  existing historical reads; verify time-range, paging, retention and completeness.
- `applications/acdc/src/cb_agents.erl`: global availability and queue status
  differ. Queue readiness must use membership plus current runtime state, not
  global status alone or SIP registration.
- Existing queue/editor/callback APIs supply configuration and durable callback
  states. Existing members/devices provides registration observation, not hours
  worked or queue eligibility.
- `applications/blackhole/src/modules/bh_call.erl` supplies account-scoped call
  events; `bh_object.erl` supplies object change bindings. Neither alone is a
  complete queue metrics/agent-session event contract. Extend the existing event
  service with reviewed ACDC bindings/projections rather than exposing raw AMQP.
- `bh_authz_subscribe.erl` supplies hierarchy-aware subscription authorization;
  dashboard permissions must also enforce the intended queue/role scope.
- Existing channel supervision APIs can be reused with server-authorized device
  routing. "Spy" maps to `eavesdrop`; don't invent an unimplemented `spy` action.

This inventory does not establish that all required metrics/events are already
available. Dedicated snapshot, history aggregation, workforce session/break
catalog and export contracts must be designed/tested where existing routes lack
them. Record exact implemented routes in OpenAPI only after source review;
unimplemented proposals belong in the clearly marked planned catalog.

## HTTP and WebSocket contract requirements

- Initial account overview and selected-queue snapshot: stable entity IDs,
  account/queue scope, generated/observed timestamps, data window, snapshot/event
  cursor, completeness and source-health fields. Bound query size and pagination.
- Live transport: authenticated WebSocket subscription/acknowledgement, snapshot
  handoff, versioned message schema, event ID, entity revision/sequence, scope,
  event time and observation time. Guarantee ordering only within its documented
  scope. Deduplicate, detect gaps and resync after reconnect or retention loss.
- Update call/agent/queue/callback state without a full-page refresh. Use shared
  server aggregation or safe event deltas, not one expensive database query per
  browser per raw event. Bound fanout, buffers and slow consumers; clean up on
  navigation/logout/token expiry. Indicate disconnected/stale/incomplete data.
- HTTP errors and asynchronous action results: unauthorized, forbidden, missing
  queue/agent, conflict, unavailable source and partial/incomplete response.
  An accepted command is not confirmed runtime login or audio connection.
- OpenAPI at `/apis`: snapshots/history/workforce/catalog/export schemas,
  filters, limits, auth, examples and errors. Link versioned WebSocket message
  and lifecycle documentation (optionally AsyncAPI); OpenAPI HTTP descriptions
  alone do not specify every WebSocket message or delivery guarantee.
- Exports: same filters/timezone/definitions as the screen, explicit coverage,
  bounded synchronous size or controlled asynchronous jobs, scoped downloads,
  auditability and CSV formula-injection protection.

## Metric and working-hours decisions required before acceptance

- Define service-level threshold, numerator/denominator, window and handling of
  short abandonments, callbacks, transfers and queue re-entry. Show the threshold
  and measurement window; represent an empty denominator as no data, not 100%.
- Define offered/handled/processed/abandoned and whether callbacks are separate;
  count unique queue visits rather than duplicate call legs or repeated events.
- Define wait, talk, hold, wrap-up and handle durations and whether maximums
  refer to active calls or completed calls in the selected period. Do not label
  talk-only duration as handle time when wrap-up/hold are required but absent.
- Queue-scoped eligible/ready counts must not include globally ready nonmembers.
  Keep agent status, active customer-call state and device registration separate.
- Workforce time is the union of eligible session intervals per agent, never
  the sum of overlapping queue logins. Keep explicit login and logout events;
  flag missing logout/uncertain intervals after disconnect or reboot.
- Define break types and paid/unpaid policy, working versus available/idle time,
  agent attribution across queues, timezone/DST/overnight boundaries and late
  corrections. Do not invent a break reason from a generic pause event or assume
  SIP online time is attendance. Raw observed time and policy-derived totals
  must be distinguishable; payroll correctness is not implied.
- Define retention, export permissions, PII masking and correction audit history.
  Supervisors must not obtain another account's caller/session details through
  a filter, subscription wildcard, cursor or export link.

## Acceptance checklist

- [ ] Source-backed snapshot and event contracts with schema tests and explicit gaps.
- [ ] Real overview click → selected queue detail, scoped live updates and back navigation.
- [ ] State transitions verified against actual ACDC/FreeSWITCH evidence, including
  ready-but-unassigned agent, ringing, answer, pause, wrap-up, logout and callback.
- [ ] Reconnect, duplicate/out-of-order events, missing sequence, token expiry,
  partial source outage, multi-node events and bounded load tests.
- [ ] Historical tiles, chart totals, detail rows and exports reconcile under the
  same timezone/cohort definitions, including empty windows and late arrivals.
- [ ] Working-hour/break/session interval tests including overlapping queue
  membership, absent logout, overnight/DST shifts and explicit break types.
- [ ] Responsive/readable design, keyboard access, non-color status labels,
  loading/empty/error/stale states; no fabricated production figures.
- [ ] Matching source, tests, installer integration, versioned design references
  and developer documentation committed/pushed and deployed with rollback proof.
