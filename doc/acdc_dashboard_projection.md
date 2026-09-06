# Dashboard call-stat projection

Status: pure backend implementation tested, not an HTTP endpoint, live snapshot
collector, Blackhole binding or rendered dashboard. DASH-03 remains active.

Source: `applications/acdc/src/acdc_dashboard_projection.erl`.
Tests: `scripts/erlang-tests/acdc_dashboard_projection_tests.erl` and
`scripts/test-acdc-dashboard-projection.sh`.

## What it computes

The module consumes the actual `#call_stat{}` shape from `acdc_stats.hrl`, not
browser response approximations. The caller supplies an already-authorized
account and selected queue set. It has no database, messaging, service or
authorization side effects. `new/5`, `add/2` and `finish/2` support incremental
collection with at most100 selected queues,10,000 input records (including
duplicates), and a24-hour cohort window. These bounds do not make an upstream
unbounded ETS query safe: the collector must bound its own scan/allocation.

Live occupancy is separate from the entry cohort. Older waiting/handled records
remain in `current_waiting`/`current_handled`; the window applies only to
`records_entered` and the four status counts within that cohort. The interval is
entered timestamp >= from and < to. All timestamps are explicitly native Kazoo
Gregorian seconds, not Unix seconds. An HTTP adapter must document/convert its
public representation rather than silently mixing epochs.

- Current maximum wait uses the supplied as-of time minus entered time.
- Average answered wait uses valid handled and processed records in the entry
  cohort, based on handled minus entered timestamp.
- Average processed talk uses processed minus handled timestamp for processed
  records in that same cohort. It is **not handle time** or workforce time.
- Empty averages/maximum wait are undefined, not fabricated zero averages.
- A non-exhausted collection retains explicitly observed counts but withholds
  the `metrics` object. Missing/incomplete data is not a complete zero result.

Exact duplicate statistical observations are deduplicated, while conflicting
observations for the same identity fail with `conflicting_observation` so the
collector can resnapshot. Foreign account/queue records, forged IDs, malformed
timelines and contradictory terminal states fail without returning partial
success. Observation end cannot precede the newest supplied transition.
Caller names/numbers, agent identities and other record details are not emitted.

## Deliberate limits and integration requirements

Current ACDC identity is call_id::queue_id, not a durable unique visit. Output
therefore says `identity_semantics=call_queue_pair` and
`distinct_visit_metrics_available=false`. Do not rename record counts as offered
visits or claim re-entry accounting is fixed. Full visit tracking remains needed.
The projection does not claim atomic snapshots, queue eligibility, workforce
hours, SLA, archive coverage, event ordering or cluster completeness.

Next integration work must implement bounded source collection and source-health
metadata; enforce tenant/resource/queue permissions before reads; preserve
current occupancy outside the historical window; define and test cluster
coverage and resnapshot behavior; then expose the versioned HTTP/OpenAPI and
Blackhole contracts. Only then wire the actual overview/detail UI. These pure
tests do not replace any of those acceptance requirements.

## Evidence — September 6, 2026

Session39271 initially passed37 EUnit cases and production compilation under
`-Werror +warn_missing_spec`. Review added a source-time ordering check. Updated
session **60072 exited0 with38 cases**, production compilation and unchanged
source/header/test input hashes. Evidence retained at
`/tmp/kazoo-dashboard-projection.AJlaEz/inputs.sha256` and `eunit.log`; earlier
evidence remains `/tmp/kazoo-dashboard-projection.tj0vLA`.

Both successful runs used128MiB validation caps,768MiB reserve,60-second
deadlines and private network namespaces. The host lacked cap-plus-reserve
headroom with all services running; an intervening request was refused69 before
payload. After verifying no active FreeSWITCH calls, root briefly stopped only
development `kazoo-ecallmgr`, restored it with an EXIT trap, and verified it
active afterward. No code/media was deployed, no account/queue was modified and
the guard reserve was not reduced. Session39271 also ran the separately scoped
offline cardinal generator tests; that is not dashboard evidence.

```bash
bash scripts/run-kazoo-validation.sh \
  --memory-mib 128 --reserve-mib 768 --runtime-sec 60 -- \
  /usr/bin/unshare --net /usr/bin/bash \
  /opt/kz5/scripts/test-acdc-dashboard-projection.sh
```

Do not automatically stop services to run this command on another host. Schedule
adequate test capacity or an authorized maintenance window; guard refusal is not
permission to interrupt production calls.
