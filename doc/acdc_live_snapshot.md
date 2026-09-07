# Live queue snapshot API — integration checkpoint

September 7, 2026. The live dashboard backend is deployed on development and
the real HTTP/Blackhole wire smoke passed. This is not complete browser,
call-transition, load or production acceptance. Historical reporting, workforce reports and
ClickHouse ingestion are postponed at the operator's request.

## Current HTTP slice

`applications/acdc/src/cb_acdc_live.erl` implements the GET handlers registered
by `cb_queues.erl`:

- `/v2/accounts/{ACCOUNT_ID}/queues/live`: bounded queue-summary page.
- `/v2/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/live`: the selected queue's
  summary, bounded observed active calls and authorized saved roster/runtime-agent
  observations in the same envelope.

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

## Detail and transport capabilities

The detail route advertises `live_call_details=true`; overview reports false
and `calls=null`. Detail returns at most 200 observed waiting/handled calls,
ordered by queue ID, entry timestamp and call ID. Rows expose only call ID,
queue ID, status, `entered_at` and nullable `handled_at` (Unix seconds).
It does not expose caller identity, agent identity or infer queue position.
Calls are compared across the same replicas as metrics, not concatenated.
`observed_count` retains the full observed active count even when rows are
capped; `truncated=true` then implies `complete=false`. Unavailable calls have
`available=false`, null count and empty rows; this is not complete zero.
The source's non-atomic, observed-replica limits still apply to complete lists.

Detail now reports `agent_runtime=true` and returns an `agents` object;
overview reports false and `agents=null`. The selected saved roster and
authorized names are read once, capped at200 plus an authorized lookahead.
Runtime observations use the same bounded broker request as queue metrics/calls.
Each row distinguishes observed FSM state, runtime queue membership and unknown
status. Device reachability is explicitly unverified. Missing/conflicting
sources are not interpreted as logout or readiness. See
`acdc_dashboard_runtime_agents.md` for the collector's limits.

`websocket_updates` is now dynamic in the deployed handler: true means
`bh_queue_live` appears in the local Blackhole binding registry; lookup failure
or absent registration yields false. It is a local protocol capability, not a
probe of broker delivery, token authorization, remote Blackhole, browser health
or complete event coverage. `historical_reporting` remains false. Clients must
still reconcile snapshots every 15 seconds and on reconnect.

The current Monster UI source consumes the single-response calls/agents DTO and
uses sequential native subscriptions, as documented in
`acdc_live_dashboard_ui.md`. Backend wire acceptance below does not establish
that the matching built UI has been accepted in a real browser. Real call-state
transitions, missed-event/reconnect recovery and load acceptance remain required.

Source tests use private build directories and controlled providers; they do
not establish a real authenticated HTTP/broker/WebSocket round trip. Preserve
that distinction in deployment and developer documentation. The later live
checkpoint below supplies separate wire evidence; it does not convert older
controlled-provider tests into live acceptance.

## Development deployment and live wire checkpoint

Root deployed a private production build containing 74 ACDC and 30 Blackhole
modules, then activated the latest `cb_acdc_live.beam` with the dynamic local
registration capability. Rollout files and pre-change beam backups are retained
under `/tmp/kazoo-live-rollout.OYdOqh`. Root reported the actual wire smoke PASS:
anonymous HTTP access was rejected, authenticated overview/detail returned
valid scoped snapshots with source available, and the native Blackhole smoke
passed. The tool's checks and bounds are documented in
`queue_live_wire_smoke.md`; raw tokens and response payloads are not evidence
output. The rollout directory is not claimed to contain a standalone smoke log.

The initial authorized subscription failed because the existing persisted
Blackhole autoload list masked the newly added default module. Fresh queue
authorization had passed; the binding handler was absent. Root loaded and
persisted `bh_queue_live` through native maintenance, preserving the other
modules, before the passing retry. See `blackhole_queue_live.md`.

This establishes development backend deployment and the tested real wire path,
not actual call-transition/publisher coverage, restricted-token isolation,
multi-zone/failover, sustained load, browser acceptance or production readiness.
An explicitly injected invalidation is not evidence of a real call mutation.

## Earlier verified source checkpoints

The following receipts are historical source-only checks. Their statements
about no deployment apply to those runs, not to the later rollout above.

September7 runtime-agent integration: root15218 rebuilt16 production modules,
passed26 public-route/roster groups,24 actual-handler DTO/OpenAPI checks and
2 separate helper tests (`/tmp/kazoo-live-snapshot.PUEw1v`). Focused OpenAPI
passed15 groups/297 schema cases. Root36984 separately passed14 authorization
groups with actual `cb_agents` binding registration (`/tmp/kazoo-live-auth.0W0PcZ`).
Root82855 passed34 transport tests including final source identity checks after
agent collection (`/tmp/kazoo-dashboard-amqp.hIW7Q4`). These are controlled-provider
source checks, not live HTTP/broker acceptance. Initial helper syntax and invalid
UTF-8 fixture errors were corrected before the passing rerun; no runtime source
was deployed during these tests.

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

### Selected active-call extension

The next source checkpoint supersedes the summary-only capability contract:

| Validation | Result and evidence |
| --- | --- |
| Collector, root83794 | 42 tests passed, including deterministic top-200 active rows, older calls, truncation and incomplete scans. `/tmp/kazoo-dashboard-collector.EdmiJm/`. |
| Transport, root52933 | 28 tests passed, including opt-in single-queue rows, strict schema and federated reply routing. `/tmp/kazoo-dashboard-amqp.0Z6cX6/`. |
| HTTP, root52933 | 12 production modules compiled; 9 production-handler route groups and 2 separate helper tests passed. `/tmp/kazoo-live-snapshot.eiexlE/`. |
| Private catalog, root62421 | 13 focused groups/214 schema cases; full catalog 358 paths, 653 operations, 498 schemas and 1,585 references passed. `/tmp/kazoo-api-live-catalog.ynOpUx/`. |

Initial extension failures remain retained: the null-field transport fixture
silently removed its field until corrected (`/tmp/kazoo-dashboard-amqp.XHXQjs`);
the first public compilation found two new syntax errors, corrected before
the passing run (`/tmp/kazoo-live-snapshot.CYokzJ`). These are not live incidents.
No new backend/UI deployment or authenticated browser acceptance was established
by these isolated tests. The later runtime-agent and development wire checkpoints
above supersede the then-open backend integration status.

Root7042 regenerated the repository catalog. Its first verification invocation
used an unsupported CLI option and exited2; corrected root67333 verified all11
assets and byte-identical manifest against the private62421 catalog. This
updates repository artifacts only, not the running `/apis` portal.
