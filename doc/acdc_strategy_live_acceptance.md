# Isolated live ACDC strategy acceptance

`node scripts/test-acdc-strategies-live.cjs --prepare-only` performs local
read-only preparation. `node scripts/test-acdc-strategies-harness.cjs` tests
scope guards and synthetic SIP handling offline. Neither starts a live call.

The opt-in `--live` mode requires root, the protected existing acceptance tenant
manifest, and deployed strategy/bridge fixes. It borrows only that isolated
tenant's caller 1001 and agents 1002–1004 after verifying their exact user,
device, SIP authentication, and direct callflow identities. It refuses MASTER,
external-number routes, preexisting contacts, busy/paused agents, active tenant
calls, or a concurrent monitor acceptance run. The existing queue2000 is not
edited. A separately ownership-marked queue2700 and ACDC member callflow are
created with collision checks.

The test measures:

- Three ring-all calls with concurrent INVITEs, one selected winner, losing
  CANCEL/BYE events, no surviving losing legs, and agents remaining available.
- A shared answer-time barrier exercising at least two answering agents; one
  stable caller bridge must remain during repeated live observations. A passive
  account-filtered FreeSWITCH event subscription additionally rejects multiple
  distinct winning bridge events, including races between polling samples.
- Ordered 1→2→3 no-answer progression, then skipping explicitly logged-out1.
- Two three-agent round-robin cycles, one offer per call and repeated rotation.
- Most-idle selecting only the agent longest idle after the measured RR cycle.

Evidence contains timestamps, fixture call IDs and checks, never credentials or
arbitrary audio. The caller supplies a synthetic tone; the test agents echo
only local synthetic RTP. Results do not establish production load capacity,
audio quality, cross-FreeSWITCH-node race behavior, or native callback races.
Those remain explicitly unproven unless separately tested.

Cleanup kills only exact fixture channels matched by account, agent, member
call, and private contact; deregisters only the exact fixture contacts; removes
the owned queue membership; restores the original borrowed statuses; and
deletes only marked queue/callflow resources. It never clears a registrar
table, logs out MASTER agents, or restarts a service. If ownership or cleanup
cannot be verified it retains `/etc/kazoo/ring-strategy-acceptance.json` (0600)
for a later explicit `--cleanup`, rather than broadening deletion scope.
Private evidence is retained under `/var/log/kazoo-strategy-acceptance-*`.

## Live-dashboard-only acceptance mode

`--check-live` authenticates and reads the existing isolated fixture, verifies
the borrowed identities, absence of calls/contacts and restorable agent states,
and refuses an unfinished fixture. It performs no queue, user, agent or device
mutation. Authentication still creates an ephemeral token.

`--dashboard-live` uses the same marked queue2700, ownership checks, shared
acceptance lock and scoped cleanup as the strategy suite, but places only one
internal round-robin call. The synthetic agent answers after six seconds, with
a twelve-second ring timeout. A read-only observer subscribes to the selected
queue's native Blackhole binding before the call. It checks production-schema
HTTP snapshots for that exact caller while waiting, after the actual single
FreeSWITCH bridge is verified, and after scoped hangup removes the live row.
Each phase requires a fresh native invalidation and a subsequent snapshot;
events contain no causal call nonce, so this does not prove which mutation
caused a hint. The observer does not inject broker events or change state.

This mode is not the full strategy suite, browser call-transition testing,
PSTN/media-quality acceptance, cross-node failure testing or load/soak evidence.
The source addition has guarded offline validation; actual run79231 below
passed after the handled-state failure43165 was corrected. The mode's presence
alone is not acceptance. Ownership-marked test resources are
deleted only after cleanup is verified; failures retain the protected recovery
ledger rather than broadening cleanup.

The shared lock now requires the child to emit its exact post-acquisition ACK,
not merely remain alive for100ms. Cleanup calls share one promise, including
repeated termination signals, so a second cleanup request cannot cause exit
before the first restoration finishes. The actual CLI control-flow fixture
`scripts/test-acdc-dashboard-live-mode.cjs` substitutes external boundaries and
tests these cases, denied preflight states and explicit mode selection.
Root0c58ba passed the revised forward-safe fixture and original strategy-harness
regression. Pending forward HTTP responses finish bookkeeping before signal
cleanup begins; no new forward work starts afterward. Root10698 passed live
read-only preflight. These are not live-call PASS receipts.

## Live-dashboard result (2026-09-07)

**Latest actual run79231: PASS.** Root2519 first compiled74 ACDC and30 Blackhole
production modules in
`/usr/local/src/kazoo5-installer/live-dashboard-backend.0KplKA`. Root29023 deployed
only the matching corrected FSM; backup:
`/tmp/kazoo-live-rollout.OYdOqh/acdc_queue_fsm.before-native-proof.beam`.
Focused6 bridge-proof tests86399 and16 existing channel-I/O tests26126 passed;
all31 strategy groups passed in16+15 shards before the sixth focused positive
retry test was added. See [the correction and limits](acdc_ordinary_bridge_proof.md).

The isolated `--dashboard-live` run produced15 HTTP requests/15valid snapshots,
three native invalidations and zero timeouts. Waiting → handled → gone each
required a fresh hint and later GET. One offer, one bridge and12 stable FS
samples verified the actual single-winner call. Exact subscribe/unsubscribe
ACKs passed. Cleanup restored all three original agent states, removed owned
resources/contacts, left no recovery ledger or FS calls, and all eight services
were active. Private receipts:
`/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-evidence.json` and
`/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-natural-call-evidence.json`.
This is not browser call-transition rendering, restricted-user authorization,
cross-node failure, full-strategy or load/soak proof.

### Earlier failures retained as baseline evidence

Initial setup exposed a status POST authorization regression (HTTP500).
Two baseline failures90610 and six candidate passes93704 establish the narrow
`cb_agents` abstention fix, compiled in production build4341 and deployed59362.
Cleanup74067 then restored all three borrowed agents and removed only the owned
queue/callflow. One earlier128MiB offline test was OOM-killed inside its guard;
it is not counted as a baseline reproduction. The256MiB rerun is authoritative.

Natural-call run43165 observed waiting with a native invalidation, then proved
one answered agent bridge with12stable FreeSWITCH samples and one bridge event.
However,51valid HTTP snapshots never advanced to handled. The ordinary queue
proof requires a caller-leg bridge event, while native intercept emits it on
the initiating agent leg. This is the valid failing P0-15 baseline, superseded
by79231 above rather than reclassified as a passing dashboard test.
Evidence: `/var/log/kazoo-strategy-acceptance-BMBtU4`. Scoped cleanup succeeded;
original agents were restored, owned contacts/queue/callflow removed, and zero
calls remained. No callback, full-strategy, load or browser-transition proof.

The final shortened HTTP request budget reported `http_timeout` when its phase
deadline expired; the observer now labels this `phase_observation_timeout`
while preserving real five-second HTTP timeout errors. All12 observer groups
12490 passed, including both cases. The diagnostic correction does not turn
the failed live transition into a PASS.

## Latest live result (2026-09-05)

The three ordinary ring-all calls passed: concurrent offers, exactly one stable
winner, losing-leg cleanup and continued agent availability. The subsequent
shared-answer-barrier case failed: three simultaneous answers produced no
stable caller bridge. The test stopped before ordered, round-robin or most-idle
acceptance. Exact fixture calls, contacts, queue and callflow were cleaned up;
the borrowed agents' original memberships and statuses were restored.

Evidence is retained privately in
`/var/log/kazoo-strategy-acceptance-v14xNm/ring-all-answer-race-evidence.json`.
The [atomic answer-selection fix](acdc_atomic_answer_race.md) has source tests
and privately compiled artifacts, but is not yet deployed or live-call proven.
