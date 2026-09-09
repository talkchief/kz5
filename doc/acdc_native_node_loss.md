# Native ACDC missed-hangup / eCallMgr-loss acceptance

The test is `scripts/test-acdc-node-loss.sh`. It is restricted to development
host10.1.0.44 and canonical isolated account8310dc3170a18de37f205d0da172df65.
It uses the existing protected fixture lock and requires zero native channels
before admission. It never uses the imported company, PSTN or master account.

1. Register the owned SIP endpoints, log one agent into the queue and bridge
   a real queued call. Confirm both native channels belong to the fixture.
2. Arm an independent systemd restoration timer, then stop eCallMgr only.
   The real endpoints hang up while no eCallMgr is available to publish the
   hangup events. Require both SIP transactions to finish successfully.
3. Keep eCallMgr down for a complete30s reconciliation interval plus margin.
   The same agent FSM must remain answered/busy: missing evidence is not proof
   of termination. No synthetic state replacement or event injection is used.
4. Restore eCallMgr. Require the same FSM and unchanged applications service
   process to recover to ready without another agent login or queue restart.
5. Wait for an active media destination in Kamailio's actual primary/secondary
   INVITE groups, then call again. Require SIP success, RTP and final readiness.
   The normal-call phase retains its fresh error-log and coredump checks.

The wrapper restores eCallMgr on failure; its separate timer survives a killed
test/SSH process. It stops only its own timer after the service is restored.

## Initial native result and installer defect

Run20260909T110454Z is **failed**, not relabeled as a pass. Both first-call SIP
endpoints succeeded, no channels remained, and the same agent FSM recovered
after the outage. The next INVITE received `480 All servers busy` from Kamailio
before entering ACDC. The script had equated recovered agent state with media
admission. Unit `kz5-acdc-node-loss-20260909.service` exited1 in3m49.333s (13eaa2).
All services were restored; the watchdog was stopped (da7858).

Inspection also found a real installer false-positive: `verify_kamailio`
accepted any `DEST` entry, including inactive, trying or disabled destinations.
Native dispatcher.c defines availability as flag prefix `A`; `P` versus `X`
describes probing, not whether calls may be routed. `b3a67ec` adds
`kamailio-dispatcher-ready.py`, reads the effective INVITE group IDs, checks
complete structured RPC output and rejects unavailable/unrelated groups.
Both local combined eCallMgr and Kamailio verification use the bounded wait.

Nine offline test groups passed locally and on main44, including reproduction
of the previous inactive-entry false positive. The real RPC helper then reported
one selected/active destination in groups1/2 (17e34d). A tenth regression now
executes the actual installer's wait function with successful and unavailable
adapters, proving failure does not print a PASS (14db69).

The corrected native rerun is `kz5-acdc-node-loss-admission-20260909.service`;
its protected log is `/root/kz5-acceptance/acdc-node-loss-admission-20260909.log`.
It exited1 (ca69b3). The next caller entered ACDC and was answered, but the agent
received no INVITE. Three rapid offers failed with SUBSCRIBER_ABSENT and led to
automatic unavailability. Same FSM45476.0 had recovered correctly before those
offers. Evidence: `/var/log/kazoo-acceptance/node-loss/20260909T111622Z`.

The location fetch handler returned not-found on an empty eCallMgr ETS cache,
although Kamailio retains the registration across eCallMgr restarts. The required
installer patch `ecallmgr-location-cache-recovery.patch` consults the existing
native token-scoped Kamailio search API on cache miss/missing proxy. It retains
warm-cache behavior, uses a bounded2s validated response, and rejects incomplete
AOR replies. Public production-entry tests reproduce the cache-miss failure and
cover warm cache, missing proxy, timeout, malformed response and WebRTC flags.
Native after-deployment acceptance **passed**: normal installer unit
`kz5-location-recovery-deploy-20260909.service` exited0, compiled/deployed the
required source overlay and passed eCallMgr validation. The unchanged native
scenario then passed in `kz5-node-loss-location-after-20260909.service`, exit0
(1bd8da). Evidence directory20260909T113605Z under the node-loss root includes
same-FSM identity, dispatcher admission and the second call's SIP/RTP proof.
The agent was not logged in again and its phone was not re-registered. No calls
remained afterward. Source `c3f11bb` is on master and main44.

## Broker-outage variant

Source `ecc2e63` adds the explicit `--live --fault broker` variant. Only the two
fixed service identities are accepted; arbitrary service names and extra CLI
arguments are rejected. Nine actual parser boundaries pass without writes.
The variant retains the same fixture ownership, complete unknown-evidence busy
interval, independent restoration watchdog, same-FSM/apps PID and subsequent
native call gates. It does not alter the previously passed eCallMgr scenario.

Native `kz5-acdc-broker-loss-20260909.service` completed exit0 (fc13ec), evidence
`/var/log/kazoo-acceptance/node-loss/20260909T125202Z`. RabbitMQ stopped after the
first real bridge; endpoints hung up, agent remained busy for35s with broker
unavailable, then recovered after broker restoration. The same agent accepted
the next native SIP/RTP call without logout/login or re-registration. The log
records both phases; all original service-restoration guards remain in place.

These one-agent scenarios do not establish multi-node broker partitions, all
ring strategies,30-call fault-load behavior or long soak. Those remain separate
parts of point1.
