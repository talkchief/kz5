# Agent availability recovery

Agents could remain unavailable indefinitely after a direct call or an answered
queue call when the hangup event was lost. Originate failure, ring timeout and
originate success also depended on the originating FSM receiving its own AMQP
broadcast to complete the transition. A delayed notification could affect a
subsequent offer, including another attempt to connect the same caller.

The FSM now completes those originate transitions locally. It sends listener
cleanup before readiness, preserves pending status changes, and broadcasts the
result for the other processes monitoring the agent. Publication failure does
not prevent local completion. Losing a simultaneous answer race does not count
toward the configured connection-failure logout threshold.

Queue wins use the selected agent response's message ID. The same identifier is
carried through originates, shared results, ring timeouts and queue satisfaction
notifications. The FSM ignores notifications for another offer. This also
prevents its own delayed failure broadcast from counting a failure twice.
Agent channel variables carry the offer ID as `Request-ID`, so delayed answer
and bridge events cannot attach an earlier attempt's agent leg to a new offer.

A timer checks tracked channels every 30 seconds using the existing strict
channel-status collector. Queries run in one monitored worker per agent; the
next timer discards a stalled worker and rejects its late results. Call events
and status requests continue while a query is pending. Recovery requires a
complete, correlated, nonempty collection with consistent responders. Timeouts,
temporary node failures, invalid responses and partial collections leave the
agent busy. A changed call/state snapshot invalidates an in-flight result.

Confirmed ended direct calls are removed individually. An answered queue call
finishes only when all its known queue legs are confirmed ended; normal wrapup
and pending pause/logout handling then apply. While ringing, channel checks
only recover a confirmed ended member call: absence of a not-yet-created agent
leg cannot cancel an originate still in progress.

## Source verification

Run these serially from a kz5 checkout with its normal compiled dependencies:

```sh
bash scripts/test-acdc-agent-recovery.sh
bash scripts/test-acdc-unit.sh
bash scripts/test-acdc-strategies.sh
bash scripts/test-acdc-callback-recovery-io.sh
python3 scripts/test-acdc-source-ownership.py
```

The recovery suite compiles the changed modules into a temporary directory and
mocks external I/O. It exercises actual FSM callbacks, a running `gen_statem`,
wire serialization, repeated offers, loss/duplication/reordering of messages,
stalled status queries, multiple direct calls, active queue legs, wrapup,
explicit pauses and the configured failure limit. These tests do not establish
SIP endpoint, FreeSWITCH, broker or cluster behavior under production load.

Verified on 2026-09-06: 22 agent recovery tests, 48 source unit tests, 26
strategy tests, 16 channel recovery I/O tests and 62 historical media/callback
tests passed (174 Erlang tests), along with five source-ownership checks. All
63 top-level production modules compiled with `-Werror`, with TEST helpers
absent from the production FSM and listener exports. The CI-only module under
`src/ci/` is outside that production compile.

Four cases were also compiled and run against the preceding FSM at `83194e7`:
lost failure broadcast, ring timeout recovery, duplicate/stale shared failure,
and stale channel answer/bridge events. All four reproduced incorrect state
transitions in that version and passed against the fixed FSM. The installed
agent FSM BEAM remained unchanged throughout verification.

## Integration and production acceptance

Deploy the affected ACDC FSM, agent listener, queue listener, both ACDC API
modules and channel recovery I/O module together on all ACDC nodes. The new
offer correlation fields require a coordinated upgrade; do not leave old and
new ACDC workers mixed. Prefer draining calls and restarting ACDC processes
under the existing deployment procedure. A state conversion is included for
the preceding FSM record, but loading BEAMs alone is not a coordinated upgrade.

Before production rollout, validate in staging with the same endpoint and
cluster configuration:

1. Repeated normal queued calls, direct calls, transfers, holds, wrapup,
   pause/resume and logout; agents must ring on the next eligible offer.
2. Simultaneous ringing with different agents winning over successive calls;
   losing agents must remain eligible and retain their failure counters.
3. Suppressed hangup and shared-result delivery; ended calls must recover while
   live calls remain busy. Queue retries must not overlap old ringing legs.
4. Broker reconnect, ecallmgr loss/recovery, incomplete status replies and node
   partitions; inspect both channel truth and agent/queue state during recovery.
5. A representative load and soak run long enough to exceed the previously
   observed failure interval, checking queued-call delivery, worker counts,
   AMQP query load and unexpected logouts.

The existing `max_connect_failures` policy still logs out agents after genuine
connection failures. Recovery does not force paused/logged-out agents online,
and deliberately cannot declare a call ended while status evidence is unknown.
No production deployment or live-call validation is performed by these scripts.

## kz5 integration checkpoint — 2026-09-06

Root verified the handoff bundle for commit
`d69cf045ecb1118b6b6e806d93e1b9a4dab5d8e2` (bundle SHA-256
`4bd4d483d8650214be50fbecadbc53e9ee7e382040c8f77785f03196bfde9d81`).
The six production-module changes were integrated unchanged into kz5. The
only merge conflict was the historical media replay helper: retain kz5's
exclusion of uncompiled bundled tests, while adopting the team's media-only
historical reverse checks. Its fixture now proves current agent FSM edits
are preserved and changed media source still fails the historical check.

Against the combined source, root independently observed:

- Recovery session `46426`: exit zero, all 22 tests passed under the unchanged
  384 MiB / zero-swap / 50%-CPU / 120-second validation guard.
- Source-ownership suite: all six tests passed, including real disposable Git
  cleanup and the combined replay projection. ACDC remains directly tracked
  inside kz5, with no nested Git metadata.
- Historical media session `83435`: deterministic 165-asset map and four
  production-module compilation/export/import checks passed, but the complete
  EUnit run exceeded the 120-second outer guard and exited 143. This is a
  failed full-suite run, not an independent confirmation of the team's 62-test
  pass. No assertion failure was reported before termination. Full combined
  historical-suite acceptance requires bounded test phases and remains open.

The team's 174-test and 63-module results above describe its own handoff.
Do not present them as a fresh root run against every combined installer change.
No installed BEAM, service, queue, agent, call or live configuration was changed
by this integration. Coordinated deployment, staging failures and load/soak
acceptance remain mandatory.
