# Live queue caller identity: source candidate and upgrade gate

Status: source candidate, September 7, 2026. Not deployed. This is not an
instruction to hot-load the changed modules or restart the whole application.

## Contract

The selected-queue live API supplies `caller_id_name` and `caller_id_number` as
required nullable fields. They come only from an explicit privacy-filtered
marker attached to the waiting event. Name is bounded to 256 UTF-8 bytes and
number to 64; malformed UTF-8, blank text, controls and bidi formatting/isolate
characters are rejected. Missing legacy provenance means unknown, not permission
to copy historical caller fields. Existing occupancy must survive bad metadata.

The native codec accepts either the exact legacy five-field row or the new
seven-field row. Legacy rows normalize to null identity. Conflicting known
identity or known-versus-unknown replicas make the snapshot inconsistent rather
than arbitrarily selecting one identity. Overview and Blackhole invalidation
events do not carry caller identity. The browser escapes displayed text and
retains call IDs only for internal row identification, not as caller labels.

Source locations:

- `applications/acdc/src/acdc_dashboard_caller.erl`: privacy marker, validation,
  compact stored tuple, and pure legacy-record conversion.
- `acdc_queue_manager.erl`, `kapi_acdc_stats.erl`, `acdc_stats.erl`: event
  production, optional metadata sanitation, storage and revocation on legacy
  or malformed repeated waiting events.
- `acdc_dashboard_collector.erl`, `acdc_dashboard_snapshot.erl`,
  `kapi_acdc_dashboard.erl`, `cb_acdc_live.erl`: bounded selected projection,
  native transport, replica agreement and public DTO.
- `monster-ui/acdc/`: caller display; `scripts/api-docs-queue-live.cjs`: schema
  source. Generated `/apis` artifacts must be rebuilt and published with the
  implementation, not assumed to match this candidate already.

## Upgrade hazard and source implementation

`#call_stat{}` changes from an 18-element to a 19-element tuple. Existing ETS
records do not change when new beams are loaded. New exact record match specs
can silently omit old rows, and index-19 updates or record conversion can fail.

`acdc_stats_sup` starts separate call/status ETS managers. The call-table manager
remains the heir when the unnamed stats worker restarts. Consequently a worker
restart retains old tuples. The previously installed ETS-transfer handler only
logs. The new staged startup calls `acdc_stats_migration` before listener
activation; that helper uses `upgrade_legacy/1` for conversion. Neither path is
deployed yet. Native `gen_listener:code_change/3` does not delegate to the stats
client callback, so `sys:change_code` is not a substitute for this restart path.

A full application/VM restart instead loses retained ETS. Shutdown archival
excludes waiting/handled records and does not prove all other archival succeeded.
Zero active FreeSWITCH calls is not evidence that all unarchived records are
durable. Never erase the table to make the new reader appear healthy.

## Next implementation and deployment requirements

1. Source implemented and isolated lifecycle tested: staged stats startup with deferred native listener activation and no
   archive/cleanup timers until both expected tables are acquired and verified.
   `gen_listener:start_listener/2` provides the existing deferred activation path.
2. Source implemented and helper tested: resolve exact table IDs and require actual call-table ownership. Preflight
   every row; refuse unknown layouts without deleting anything.
3. Source implemented and helper tested: convert legacy rows in bounded owner-process batches, appending only
   `undefined`. Preserve the original 18 fields, keys and row count. Mixed
   legacy/current tables must be safely resumable after interruption.
4. Source implemented and isolated lifecycle tested: verify no legacy or unknown layouts remain before enabling listeners,
   responders, timers or successful dashboard reads. A failure must preserve
   retained data and expose unavailable readiness, not a successful empty view.
5. Rebuild the complete header-consumer cohort. Stats query/responders,
   dashboard collector/projection, archive and cleanup code must agree. The
   installer already forces full compilation, but that is not runtime migration.
   Kazoo-apps installer readiness now calls `acdc_maintenance:stats_ready/0`,
   requiring verified stats admission and native broker consumption before exact
   `ready` is accepted. Runtime protocol and actual shell-hook tests pass;
   live/fresh-host installer acceptance remains a release gate. An active
   systemd unit alone is not proof.
6. Implement explicit old responder/archive-worker drain and read admission for
   the controlled stats-child restart while ETS managers remain alive. Pausing
   broker consumers alone does not drain independently spawned workers or old
   archive acknowledgements. Do not deploy until this mechanism is tested.
7. Verify actual ordinary and privacy-enabled call payloads on the target
   runtime, then deploy matched backend, UI and OpenAPI and prove visible
   Name/Number for an authorized selected queue without cross-account leakage.

Required regression coverage: empty/legacy/current/mixed tables; repeated and
interrupted migration; preservation of unarchived waiting/handled and failed
archive records; unknown layouts; wrong owner/table; bounded deadline; real
heir transfer and resumption; no early listener/timer/read admission; stale
responder/archive acknowledgements; pre-fix omitted-row/index-update failures
and post-migration successful queries/updates.

## Existing evidence and its limits

### Installer readiness source checkpoint

`acdc_maintenance:stats_ready/0` obtains the current supervisor child, requires
ready-table admission, checks the native `is_consuming` result with a 1000ms
call timeout, then rechecks the same tid and current child. It returns only
`ready`, `{error,not_consuming}` or `{error,source_unavailable}`, never private
state. `verify_acdc_stats_ready` invokes this through the existing protected
local `erl_call` path; only exit-zero plus exact `ready` passes. Polling is
bounded by `KAZOO_START_TIMEOUT`, with an outer 10-second per-RPC cap and
two-second retries. The overall deadline can be exceeded by a final in-flight
RPC/retry; this is not a hard real-time deadline. Verification performs no
repair or migration itself.

Root startup17 groups pass `8ecdb9/dff757`, evidence
`/tmp/kazoo-stats-startup.xiLcue`, with13 fresh production compiles. Nine
controlled readiness protocol cases cover success, legacy/malformed/refused
admission, non-consuming/invalid broker state, second-source change and replaced
supervisor child. The actual native listener still has a controlled unavailable
broker and correctly fails overall readiness after local migration succeeds.
This is not a successful real broker-ACK test. Installer5 source-gate groups
pass `e8f999/b6a8d2`, including exact response/exit-code rejection, retry,
cookie/tool failure, dry run and verifier ordering. Read-only installer safety
regressions pass `f77e99`; shell syntax and diff whitespace also pass.

### Direct maintenance reads and first-replacement drain

`acdc_stats:find_call/1` now asks the stats supervisor for the actual worker,
obtains `stats_call_read_source` admission from that worker, and pins the opaque
call-table tid. The potentially large select stays outside the collector
mailbox. After conversion to the existing maintenance JSON, the reader asks the
same worker again and checks the same name/tid/owner identities. Only a ready
worker that still owns both verified tables grants admission. A legacy worker's
unknown-request `ok`, a missing/dead worker, either admission timeout, revoked
admission, or a replacement table returns `{error, source_unavailable}` instead
of a misleading `undefined` or stale JSON. Each admission call has a 1000ms
timeout; this is not a 1000ms total operation bound (supervisor lookup and the
existing ETS select/sort also take time). Maintenance prints unavailable and
does not publish abandonment in that case. This is a maintenance read, not the
public caller-identity/privacy contract.

These are before/after non-atomic admission checks, not a worker reservation or
proof that a source cannot change immediately after the final check. They do
not drain old responders or archive tasks and do not replace the complete
cohort upgrade requirement. The new ready worker does not migrate again in
place; a future same-owner re-entry protocol must add a non-reusable generation
or reservation rather than treating a ready→closed→ready cycle as equivalent.

Source audit of the first replacement found that a consumer-PID dictionary scan
and successful `soft_purge` are insufficient: native responders start through a
`kz_process` wrapper before installing consumer metadata, and periodic archives
hold delayed local funs in that wrapper. Purge is not acknowledgement that
those workers completed. The next helper must run only after actual old-worker
termination and exact retained-heir ownership verification, conservatively
monitor the surviving `kz_process`/native `acdc_stats` initial-call cohort, and
require actual termination before conversion/purge. It must refuse on a bounded
deadline rather than kill workers or narrow the scan to late metadata. This
argument is specific to the audited closed spawn graph; a one-time process
scan is not generic quiescence proof. Dynamic reader entry gates and old direct
code-reader checks remain separate requirements.

Root startup suite now passes16 groups `156530/e8b860`, retained at
`/tmp/kazoo-stats-startup.fTo5ct`, rebuilding13 listed production modules without
TEST. New evidence includes actual native listener success/not-found/newest-row
lookups; unavailable/dead/legacy owner handling; first and second admission
timeouts; second refusal with unchanged pid/tid; actual table replacement after
the first select; and maintenance unavailable with AMQP publication poisoned.
The real source tables and native listener are exercised; supervisor lookup and
external broker/config/monitor dependencies are controlled. This does not prove
installed upgrade, full responder admission, broker consumption or live caller
display. Invocation is through `/bin/bash scripts/test-acdc-stats-startup.sh`
inside the root resource guard and network namespace.

Migration helper11 tests passed `68e9e6/c09393`, retained at
`/tmp/kazoo-stats-migration.YErKbj`. They use real protected ETS and actual heir
transfer, not a mocked converter. They cover existing current identity, all
original fields, unarchived waiting/handled records, invalid layouts before any
mutation, owner/tid/table/options/deadline refusal, interrupted mixed-table retry,
content/count drift and pre-fix select/index-update failures. The hash/count
verification is not an admission lock; bounds are cooperative between ETS/hash
BIFs, not a hard per-record heap or latency guarantee.

The staged source obtains both exact owned table IDs, advances owner-local
migration in mailbox steps, enables the unchanged native listener configuration
only on verification success and then starts archive/cleanup timers. Startup
failure retains the tables without starting listeners or attempting archival on
mixed records. `stats_readiness` returns phase/reason, not broker health. OTP
status formatting omits the migration continuation's internal key/digest.
Root full compilation passed76 production modules with `-Werror`, no TEST
options/agent test exports and unchanged source inputs (`67b393/bf1080`); no
BEAM was loaded or installed. After correcting named-table transfer handling,
the lifecycle runner rebuilt12 production modules and passed10 groups
(`5e37b0/2a5f12`, `/tmp/kazoo-stats-startup.P2O8a8`). It uses actual named ETS
donations, actual migration and a real `gen_listener` process; broker channel
requisition is controlled false. Both transfer orders, failure retention,
mutation/timer rejection, timeout tokens, private status redaction and deferred
native responder setup pass. Named transfer messages are resolved only at
acquisition; opaque IDs are retained and checked throughout migration. This is
not real broker consumption or a live old/new replacement test. Old worker
drain, direct-reader admission and deployment are still pending.

Root passed upstream 10 tests, collector 50, native codec/snapshot 36, public
route 30 plus 2 helper tests, 51 production-handler DTO/schema checks, and
27 controlled source-browser groups. Exact evidence directories and later
offline contract runs are recorded in `PROJECT_HANDOFF.md`. These prove the
candidate contracts in their stated scope, not a completed upgrade, deployed
caller identity, fresh distributed installer acceptance, or production readiness.
