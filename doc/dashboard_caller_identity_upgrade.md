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

## Upgrade hazard: not implemented yet

`#call_stat{}` changes from an 18-element to a 19-element tuple. Existing ETS
records do not change when new beams are loaded. New exact record match specs
can silently omit old rows, and index-19 updates or record conversion can fail.

`acdc_stats_sup` starts separate call/status ETS managers. The call-table manager
remains the heir when the unnamed stats worker restarts. Consequently a worker
restart retains old tuples. The current ETS-transfer handler only logs and
`code_change/3` does not migrate. `upgrade_legacy/1` is a pure tested converter
with no production caller; its presence is not migration readiness.

A full application/VM restart instead loses retained ETS. Shutdown archival
excludes waiting/handled records and does not prove all other archival succeeded.
Zero active FreeSWITCH calls is not evidence that all unarchived records are
durable. Never erase the table to make the new reader appear healthy.

## Next implementation and deployment requirements

1. Add staged stats startup with deferred native listener activation and no
   archive/cleanup timers until both expected tables are acquired and verified.
   `gen_listener:start_listener/2` provides the existing deferred activation path.
2. Resolve exact table IDs and require actual call-table ownership. Preflight
   every row; refuse unknown layouts without deleting anything.
3. Convert legacy rows in bounded owner-process batches, appending only
   `undefined`. Preserve the original 18 fields, keys and row count. Mixed
   legacy/current tables must be safely resumable after interruption.
4. Verify no legacy or unknown layouts remain before enabling listeners,
   responders, timers or successful dashboard reads. A failure must preserve
   retained data and expose unavailable readiness, not a successful empty view.
5. Rebuild the complete header-consumer cohort. Stats query/responders,
   dashboard collector/projection, archive and cleanup code must agree. The
   installer already forces full compilation, but that is not runtime migration.
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

Root passed upstream 10 tests, collector 50, native codec/snapshot 36, public
route 30 plus 2 helper tests, 51 production-handler DTO/schema checks, and
27 controlled source-browser groups. Exact evidence directories and later
offline contract runs are recorded in `PROJECT_HANDOFF.md`. These prove the
candidate contracts in their stated scope, not a completed upgrade, deployed
caller identity, fresh distributed installer acceptance, or production readiness.
