# Calls right after a media server restart

## Finding

Private lab, September 18, 2026, unit `kz5-stage-queue-fault-freeswitch-restart-1`
(FAIL, retained): after `systemctl restart kazoo-freeswitch` the next queued call got
`486 Unable to Comply` five seconds after its INVITE.

| Time | Event |
| --- | --- |
| 15:46:57.3 | restart issued |
| 15:46:58.8 | both eCallMgr nodes: `received node down notice` |
| 15:47:09.8 | first reconnect attempt: `unable to connect` |
| 15:47:12.4 | caller INVITE reaches FreeSWITCH |
| 15:47:17.4 | `486 Unable to Comply` (FreeSWITCH's route request went unanswered) |
| 15:47:17.9 | eCallMgr connected again |

Kamailio probes a media server every 10 s and needs three failures to stop
routing to it, so a restart of a few seconds is invisible to it. The window is
therefore governed only by how fast an eCallMgr reconnects.

## Cause

Measured, not assumed. FreeSWITCH's Erlang listener answers before its SIP
listener is up, so a prompt reconnect leaves no window at all. eCallMgr's
reconnect path was slow by construction:

- about 3 s to stop the lost node's listeners;
- a fixed `timer:sleep(3 s)` before the first attempt (`ecallmgr_fs_nodes`);
- the attempt itself is `mod_kazoo:version/2` with a fixed 5 s timeout, lost in
  full when FreeSWITCH's listener is up but `mod_kazoo` is not answering yet;
- the pinger's first check 3 s later, then 2 s, 3 s, ... between retries;
- 1 s after the successful ping, and the same fixed 3 s sleep again on node-up.

## Change

`scripts/patches/ecallmgr-media-reconnect-delay.patch`: the connect wait is
`ecallmgr.fs_node_connect_delay_ms` (default 1000), the pinger's first check and
first retry are 1 s, and the back-off for a node that stays away is kept.

The two files belong to `ecallmgr-kazoo5-integration.patch`. The new patch is
applied after it and stays clear of its hunks, so the integration patch's own
`git apply --reverse --check` still recognises it on a repeat install.
`bash scripts/test-ecallmgr-media-reconnect.sh` proves exactly that on private
copies, and both private eCallMgr guests were repeat-installed with it
(`ecallmgr-install-9`, `ecallmgr-peer-install-5`, PASS).

## Result

| Run | Node down to connected again |
| --- | --- |
| before | about 19 s |
| `kz5-stage-queue-fault-freeswitch-restart-4`, run without the harness's media wait | 7 s; next call placed 13 s after the restart: 200 OK, campaign PASS |
| manual restart, first attempt landed in the not-answering phase | 16 s |

The remaining 5 s `version` timeout sits inside the integration patch's own hunks, so
it was not changed. Instead `scripts/patches/ecallmgr-media-reconnect-ready.patch`
(`1e1511d`) asks `mod_kazoo:version/2` with a 1 s timeout, up to
`ecallmgr.fs_node_answer_tries` (6) times 500 ms apart, **before** that attempt, so the
attempt is only made against a node that answers.

| Run (private lab, both controllers patched) | Result |
| --- | --- |
| `kz5-stage-queue-fault-freeswitch-restart-5`, diagnostic mode | landed in the not-answering phase (`failed to get mod_kazoo version … timeout` after 1 s); linked 9.2 s after node-down instead of 16 s. Campaign **FAIL** for another reason, below |
| `kz5-stage-queue-fault-freeswitch-restart-6`, normal mode | same phase, linked 9.0 s after node-down; campaign **PASS** (`/var/log/kazoo-monitor-acceptance-hvlHg5`) |

## Linked is not callable: the whole window, measured

Run 5 placed its next call 13.7 s after the restart and got `486 Unable to Comply`
three seconds *after* both controllers had logged `successfully connected`.
FreeSWITCH's log for that second: `bgexec: load(mod_sofia)` at 19:58:04.74,
`The system cannot create any sessions at this time` at 19:58:06.26, `Adding
Endpoint 'sofia'` at 19:58:06.46. In Kazoo FreeSWITCH has no SIP stack until a
controller tells it to load one; while `mod_sofia` loads, its profile already
receives packets but the endpoint is not registered yet (about 1.5 s).

Run 6, second by second (restart ordered at 20:04:11.6):

| Phase | Ends | Cost |
| --- | --- | --- |
| FreeSWITCH stops and starts | 20:04:16.9 | 5.3 s |
| `mod_kazoo` answers; brief probes, no lost 5 s attempt | 20:04:18.5 | 1.6 s |
| controller attaches: `node.info`, event streams, fetch handlers | 20:04:22.1 | 3.6 s |
| `fs_cmds_wait_ms`, then `load mod_sofia` and its configuration | 20:04:26.0 | 3.9 s |
| **SIP callable** | | **14.4 s** |

`fs_cmds_wait_ms` (stock default 5000, counted from the node listener's start) is
deliberately **not** lowered. It is the only thing guaranteeing that the
configuration fetch handlers are bound before `mod_sofia` asks for its profiles;
the handlers bind asynchronously about 3 s after the node listener starts, and a
`mod_sofia` that loads first comes up with no profile and stays that way (the
second controller's `load` is answered `Module mod_sofia Already Loaded!`). That
would trade 2 s of a restart for a standing outage.

Restarting the only media server is therefore a SIP outage of about 15 s, of which
about a third is FreeSWITCH itself. It recovers without an operator, agents return
to `ready` without logging in again, and the next call is bridged with audio in both
directions (run 6). A deployment that must not reject calls during a media restart
needs a second media server behind Kamailio's dispatcher.

What changed because of run 5: "linked" is no longer accepted as "callable".

- The campaign waits for `sofia status` to show a running profile before it calls again.
- `kazoo5-stack-health.sh` reads the live link from `ecallmgr_fs_nodes connected`
  (`list_fs_nodes` keeps listing a node it has lost) and fails with `FreeSWITCH has
  no running SIP profile` when the media server is active and linked but cannot
  take calls. `bash scripts/test-install-kazoo5-stack-health.sh`: 16 failure classes.

The campaign itself waits on `ecallmgr_fs_nodes:connected/0`.
`ecallmgr_maintenance list_fs_nodes` keeps listing a node it has lost and must
not be used as a link check.
