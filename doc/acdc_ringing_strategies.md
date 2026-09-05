# ACDC ringing strategies

This community ACDC implementation supports the following queue `strategy`
values. These are ACDC settings, not the separate commercial Qubicle router API.

| Value | Selection for each waiting caller |
| --- | --- |
| `round_robin` | One eligible agent, rotating through the manager's ready-agent FIFO. Nonresponding or unavailable agents are skipped. |
| `most_idle` | One eligible agent with the greatest reported idle time. Equal idle times use a stable agent-ID tie-break. This is not simultaneous ringing. |
| `ring_all` | All currently eligible responding agents at once. The first accepted selected agent wins; the other selections are cancelled. |
| `in_order` | One eligible agent at a time, following `agent_order`. A failed/rejected attempt advances to the next eligible agent for this caller. |

The normal authenticated queue API stores these fields:

```json
{
  "data": {
    "strategy": "in_order",
    "agent_order": ["first-agent-user-id", "second-agent-user-id"],
    "agent_ring_timeout": 10
  }
}
```

`agent_order` contains unique **agent user IDs**, not device IDs or extension
numbers. It changes priority, not queue membership or agent login state. Listed
agents who are unavailable, busy, not queue members, or do not respond are
skipped. Eligible roster members not listed follow in stable user-ID order, so
adding a member does not silently make that member unreachable. Each new caller
starts at the first eligible agent. Within a caller's retry cycle, attempted
agents are skipped until all currently eligible responders have been tried,
then a new cycle starts. This is priority routing; lower-priority agents can
receive fewer calls than higher-priority agents. Use round-robin for rotation.

All modes respect the normal agent eligibility, queue connection timeout,
agent ring timeout and wrap-up handling. Strategy/order edits take effect on
the next selection after the queue's configuration refresh. They do not cancel
an already ringing selection, reset queued callers, or log agents out.

`ring_simultaneously` is a legacy schema field that was never consumed by this
backend's selection code. It is **not an implemented batch-size limit**: setting
it does not make round-robin/most-idle/ordered ring multiple agents, and it does
not cap ring-all. The UI should not present it as a working control.

## Ring-all safeguards

Selection uses one atomic manager ready snapshot. Duplicate responses from the
same agent process are discarded; one win is published per selected agent,
containing only that agent's responding process IDs. A normal acceptance must
match the current caller and a selected agent/process after ringing began.
Late acceptances before a new selection and stale ring timers are ignored.
The common ring deadline cancels all remaining selections, not an arbitrary
first agent. The winning agent never receives its own loser cancellation.

Receiving `member_connect_satisfied` because another agent answered is recorded
as `LOSE_RACE`, but does not increment the losing agent's failed-connection
counter or trigger automatic logout. Explicit queued pause/logout commands and
the existing policy for genuine failed connection attempts remain in effect.

The media bridge still uses Kazoo's existing FreeSWITCH
`intercept_unbridged_only` path. Source-level tests do not prove a simultaneous
answer media race safe across multiple FreeSWITCH nodes. Before calling this
release production-accepted, run an isolated live test with multiple answering
agents and prove exactly one customer bridge, cancellation of losing legs,
continued agent availability, and an intact original caller. Repeat for native
callback callers. No such live test is performed by the unit-test script.

## Validation and deployment

Run `bash scripts/test-acdc-strategies.sh`; its temporary TEST beams are private
and it makes no API, service or telephony changes. Existing ACDC unit, logical
member and callback queue scripts also compile the new helper privately.

The source changes add fields to queue-manager and queue-worker state records.
Deploy `acdc_queue_strategy`, `acdc_queue_manager`, `acdc_queue_fsm`, and
`acdc_agent_fsm` together with the queue schema/UI update using a coordinated
ACDC application restart after verifying no calls are active and preserving
agent status. Do not hotload the new record layouts into existing processes.
The update does not require rebuilding or restarting FreeSWITCH.
