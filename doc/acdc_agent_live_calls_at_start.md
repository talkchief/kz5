# An agent whose processes start while it is on a call is not available

## How it was found

The live callback campaign gained a boundary that restarts `kazoo-apps` while the
returned callback is bridged to the agent
(`test-acdc-callback-retry.sh --apps-restart-during-bridge`, main development
host, September 18, 2026). The callback side passed: the media bridge lived on,
the ticket stayed `completed` with the same legs and attempt count, and recovery
originated no duplicate. Its samples of the agent's state told another story:

```
sync/2 ready/2 ready/2 ready/2 ready/2 ready/2      (agent state / live channels)
```

With one applications node there is no peer replica to answer `answered` during
the start-up sync, so after any node restart or crash an agent who was talking
came back `ready` and could be offered another call mid-conversation.

## Fix, in three native attempts

The agent FSM already has the right state: `outbound`, for a call that did not
come from this queue process, tracked by call id and left for `ready` when those
channels end. What was missing is finding the agent's live calls at start.

| Commit | Approach | Native result on main |
| --- | --- | --- |
| `d5c9bf0` | Ask the media controllers (the user-channel query Crossbar uses) for channels on the usernames of the agent's **built endpoints**. | FAIL, unit `...-bridge-0918b`: still `ready`. Built endpoints need a registration lookup and can be empty when the agent's processes start. |
| `e091a2b` | Usernames from the agent's own **device documents**, asked when the processes start, up to three times. | FAIL, unit `...-bridge-0918c`: still `ready`. With the node fully up the same code worked (agent logged in while its leg was live: `agent has 1 live call(s) at start`, `outbound`, and `ready` again when the leg ended). Right after a node start the query is answered empty because no media controller is known yet. |
| `c357900` | The helper waits until a media controller is known before asking, and the agent **stays in `sync`**, for at most five extra periods, until the search has answered. | **PASS**, unit `...-bridge-0918d`, `/var/log/kazoo-acceptance/20260918T185637Z`: `sync/2 outbound/2 outbound/2 outbound/2 outbound/2 outbound/2`, notice `agent has 1 live call(s) at start` at 18:58:42, `ready` again after the call, ticket unchanged, no channel left. |

The campaign itself now fails when any sample shows the agent `ready` while its
callback's channels are up, and hangs up its own two legs when that boundary
fails (twice the aborted run had left them bridged on the media server).

## Offline

`make -C applications/acdc test.acdc_agent_fsm_tests` (43 tests): usernames from
device documents (duplicates, missing SIP settings, no devices), call ids merged
from several controllers' answers. `test-acdc-unit.sh` 80 and
`test-acdc-agent-recovery.sh` 27 pass.
