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
The source addition has guarded offline validation; the actual live run below
failed handled-state observation. Do not treat the mode's presence as a PASS. Ownership-marked test resources are
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
the initiating agent leg. This is P0-15, not a passing dashboard test.
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
