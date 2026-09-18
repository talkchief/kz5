# A paused agent must stay paused when its processes restart

## How it was found

The first native run of the service-fault profile (readiness plan C3,
`KZ5_QUEUE_FAULT=apps-kill`, private lab, September 18, 2026) killed the
applications node that owned a bridged queue call. The active agent recovered on
both nodes, but the campaign's "no unrelated agent state change" check failed:

```
An unrelated paused agent did not come back paused after apps-kill:
["172.30.253.14=sync","172.30.253.20=paused","172.30.253.14=sync","172.30.253.20=paused"]
```

Units `kz5-stage-queue-fault-apps-kill-1` and `-2` (both FAIL, retained).

## Two defects

**1. One applications node: a paused agent returns to rotation.** Reproduced by
hand with the peer node stopped:

| Step | Agent FSM | Stored status |
| --- | --- | --- |
| before | `ready` | `ready` |
| `sup acdc_maintenance agent_pause ACCOUNT AGENT` | `paused` | `paused` |
| `systemctl restart kazoo-apps` (12:10:52) | `sync`, then **`ready`** | overwritten with **`ready`** |

Nothing read the stored status when an agent's processes started
(`acdc_init` only decides *whether* to start them), so after the 5 s sync
timeout the agent became `ready`. Every restart of the applications node — a
crash, an upgrade, every installer run — put agents who were on break back into
rotation, and the record of the break was lost.

**2. Two nodes: the restarted replica waits in `sync` for as long as the agent
is paused.** In `acdc_agent_fsm:sync/3` a peer answering `ready` lets the new
replica join and `sync` keeps it waiting; any other answer means "delay 15 s and
ask again". That is right for a call in progress and wrong for `paused`, which
is a steady state. Effects: different agent states on the two nodes, `sync` in
dashboards, and the strict maintenance snapshot (used by the main promotion's
idle gate) refusing.

## Fix

`acdc_agent_util:restorable_pause/2` finds the most recent status; when it is
`paused` it returns the pause still owed: the recorded `pause_time` minus the
time since `timestamp`, `infinity` for an open-ended pause, and nothing when the
break already ended while the node was down (`pause_left/3`).

`acdc_agent_fsm` holds that value aside when the agent's processes start and
decides with its peers:

| Peers answer | Result |
| --- | --- |
| nobody (single node, or every node restarted) | the restored pause is applied |
| `paused` | paused, with the time left found at start, or open-ended when the pause had not reached the datastore |
| `ready` | the restored pause is dropped: a live peer outranks a stored status that may predate a resume |
| a call in progress | unchanged: wait and ask again |

The pause is queued as the oldest update, so a `resume` received since the start
still wins. The first version (`ba80c61`) applied the stored pause
unconditionally and was wrong with two nodes: an agent resumed while one node was
down came back `paused` on that node and `ready` on the other. Corrected in
`93b6a3a`.

Known limit: status records reach the datastore on the statistics archive cycle
and on a graceful shutdown. After a hard kill of a *single* node, a pause made
within the last archive period may not be there to restore. With two nodes the
surviving peer supplies it.

## Offline

`make -C applications/acdc test.acdc_agent_fsm_tests` (38 tests): the restored
pause alone, after a newer update, with a paused peer with and without a stored
value, and the remaining-time arithmetic including an expired break.
`bash scripts/test-acdc-unit.sh` 76 and `bash scripts/test-acdc-agent-recovery.sh`
27 pass.

## Native

See the register entry in `PROJECT_TASKS.md`.
