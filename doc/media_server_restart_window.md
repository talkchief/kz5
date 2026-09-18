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

Mitigated, not eliminated. The remaining 5 s is the `version` timeout, which sits
inside the integration patch's own hunks; changing it means evolving that patch
through its old/delta/new mechanism. A deployment with several media servers
should also consider making Kamailio fail over on this reply.

The campaign itself waits on `ecallmgr_fs_nodes:connected/0`.
`ecallmgr_maintenance list_fs_nodes` keeps listing a node it has lost and must
not be used as a link check.
