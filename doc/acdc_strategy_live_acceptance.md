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
