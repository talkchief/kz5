# Live queue snapshot API — integration checkpoint

September 6, 2026. This is source under integration, not a deployed dashboard
or production acceptance report. Historical reporting, workforce reports and
ClickHouse ingestion are postponed at the operator's request.

## Current HTTP slice

`applications/acdc/src/cb_acdc_live.erl` implements the GET handlers registered
by `cb_queues.erl`:

- `/v2/accounts/{ACCOUNT_ID}/queues/live`: bounded queue-summary page.
- `/v2/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/live`: the selected queue's
  summary in the same envelope. Detailed calls and runtime agents are the next
  integration slice; this route does **not** yet provide those collections.

Overview accepts only `page_size` (1–100, default 50) and optional inclusive
`start_queue_id`. Use the returned `next_start_queue_id` unchanged. Detail
accepts no query parameters and returns one queue. IDs are lowercase 32-digit
hexadecimal account/queue IDs. Responses use Crossbar's usual data envelope
and `Cache-Control: no-store`.

The existing authentication pipeline remains mandatory. The handler reapplies
authorization for its own route, queue statistics, queue listing or the selected
queue, and every returned queue, including the pagination lookahead. A list
grant does not imply permission to inspect every queue. Documents are checked
for tenant ownership, type and deletion; the query cannot select another DB.

## Snapshot transport and meaning

`kapi_acdc_dashboard.erl` defines an internal broker request/response contract.
`acdc_stats.erl` dispatches requests to `acdc_dashboard_snapshot.erl` in a
listener responder. The handler verifies the current statistics process and
ETS owner before and after the bounded local collector runs. Internal broker
source/incarnation identities and node metadata are never public DTO fields.

Crossbar discovers known ACDC sources before and after collection. Collection
requests intentionally use Kazoo's native federated listener binding so
advertised remote-zone sources can receive them. The transport preserves the
native consumer-prefixed reply route back to the requesting broker.
Collection
has a 3-second broker timeout, a 64-response rejection ceiling, at most 32
expected sources and 100 selected queues. Each local scan is capped at 10,000
visited records and a cooperative 1-second budget. These limits do not establish
an end-to-end latency SLA; node discovery and datastore operations also cost
time. Discovery uses Kazoo's existing node inventory, not a new cluster registry.

Replicas are **not summed**. Metrics are exposed only when all known sources
reply with matching scope/correlation, complete projections and agreeing values.
Different observation instants are normalized for maximum current wait when
comparing replicas. Source loss, timeout, malformed responses, changed inventory,
incomplete scans, conflicting incarnations or counts make metrics unknown
(`null`), never a fabricated zero. Agreement still does not prove delivery of
every broker event or physical call state. Coverage is `observed_replicas` and
`atomic_snapshot` is always false.

Current waiting/handled occupancy includes observed active records that entered
before the one-hour cohort. Cohort measures use the fixed preceding hour;
there is no client-selectable historical range. Public timestamps are Unix
seconds; native broker/ETS timestamps are Kazoo Gregorian seconds. Records use
legacy call/queue-pair identity, not a guaranteed distinct queue visit.

## Remaining delivery requirements

The four capabilities currently report false: `live_call_details`,
`agent_runtime`, `websocket_updates`, and `historical_reporting`. The first
three remain required for live delivery; historical reporting is postponed.
Do not wire this summary-only slice as though it completes queue detail.

Next: bounded active-call and runtime queue-agent data; tenant/queue-authorized
native Blackhole invalidation events; snapshot recovery after reconnect or
missed events; matching Monster UI integration; OpenAPI generation; coherent
build/deployment and actual browser/call-state tests. The existing live UI source
still uses legacy observations, as documented in `acdc_live_dashboard_ui.md`.

Source tests use private build directories and controlled providers; they do
not establish a real authenticated HTTP/broker/WebSocket round trip. Preserve
that distinction in deployment and developer documentation.

## Verified source checkpoint

Root's serialized, network-isolated validations used a 128 MiB memory cap and
768 MiB reserve. Development ecallmgr was briefly paused only after checking
zero calls, then restored through an EXIT trap. No new source was deployed.

| Validation | Result and evidence |
| --- | --- |
| Internal transport, root4405 | 24 tests passed, including native federator forwarding/reply-route behavior with substituted broker delivery. `/tmp/kazoo-dashboard-amqp.FvM34k/`. |
| HTTP handler, root70142 | 12 production modules compiled; 8 public-route tests passed using the production handler without TEST exports. A separate VM passed 2 pure helper tests. `/tmp/kazoo-live-snapshot.1bZKPw/`. |
| Complete private OpenAPI catalog, root92359 | 11 focused groups/135 schema cases, all 11 asset hashes, 358 paths/653 operations/1,579 internal references, and 250 unique current source inputs verified. `/tmp/kazoo-api-live-catalog.u6yT2M/`. |

Public-route fixtures use actual route/context/JSON/response code with controlled
datastore, broker and authorization providers. They are not real JWT/restricted
token, HTTP wire or mixed-zone broker acceptance. The runner explicitly labels
remaining prebuilt dependencies as unrebuilt/unpinned. The initial AMQP test
failure was in malformed-fixture construction, not counted as a product fix;
its evidence remains `/tmp/kazoo-dashboard-amqp.SJ6gYN/`.

Run `scripts/test-acdc-dashboard-amqp.sh`,
`scripts/test-acdc-live-snapshot.sh` and
`scripts/test-api-docs-queue-live-catalog.sh` through the resource guard. The
existing `scripts/test-acdc-live.sh` is a different live lifecycle/storage test;
it was preserved unchanged and was not run for this checkpoint.

Root10036 regenerated `scripts/assets/api-docs/{openapi,coverage,manifest}.json`
and verified all 11 catalog assets. The manifest is byte-identical to the
private verified catalog above. These repository artifacts describe source
implementation; the running `/apis` portal has not been republished here.
