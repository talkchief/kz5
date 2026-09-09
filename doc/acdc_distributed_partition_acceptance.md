# Queued-call applications-node broker partition

Status: native test exposed replica selection/synchronization defects; source
fix and108 Erlang regression tests pass. Normal rebuild/native after-test pending.
This closes no release gate until the retained native receipt passes.

Native run1 failed its direct-call-based ownership observation before fault
injection, despite a bridged queued call. Evidence
`/var/log/kazoo-monitor-acceptance-KKW3kf`. Cleanup completed. ACDC explicitly
exports the caller's Authorizing-ID onto its outbound leg; the queue-only gate
now also requires exact Agent-ID, Member-Call-ID, device URI, private contact and
mutual bridge, followed by both native FSM call correlations. Direct monitoring
authorization gates are unchanged. This failed attempt is not a recovery pass.
Run2 passed the exact queue-leg bridge gate, then timed out waiting for both FSMs
to report answered; scoped cleanup completed. Evidence
`/var/log/kazoo-monitor-acceptance-kqJbJ4`. The next runner retains the actual
replica states on that failure, rather than treating a media bridge as FSM proof.

Run3 retained `/var/log/kazoo-monitor-acceptance-yVv098`: primary FSM answered,
peer FSM ready, same synthetic agent/call. Both native listeners were consuming,
enrolled in the same queue and had broker connect-win/shared-event bindings.
Protected log analysis showed both nodes originated for the same agent. The
queue advertised all responding replica process IDs as originators; the loser
could return ready while its peer remained answered. Source now selects one
originating process per agent and retains its exact process/server/offer identity
for callback and ordinary acceptance. Other replicas take the monitoring path.

The correlated CHANNEL_BRIDGE can also arrive before originate_resp. Previously
that first event transitioned locally without broadcasting the winning leg;
the later response was ignored in answered state. Publication now happens at
the owner transition itself; monitoring replicas do not issue duplicate queue
acceptance or connection statistics.

Before-fix tests reproduce both defects: actual original queue FSM retains3
process winners for2 users; bridge-first publication count0 instead of1.
After fix:34 strategy tests,26 agent recovery tests and48 broader ACDC tests pass, including the real
queue-selection path, exact shared correlation, monitor-only behavior, callbacks,
ordinary bridge proof, ring-all losers and no broadcast-loopback dependency.
This is not yet a native after-pass or a completed partition gate.

Source `2e91984` is pushed to master and synced to main dev44 `/opt/kz5` and both
private apps guests. Normal installer rebuilds were started and verified still
running at this checkpoint: primary `kz5-stage-install-kazoo-apps-8` (PID225405),
peer `kz5-stage-install-apps-peer-4` (PID86326). Both reached actual make/Erlang
compilation. Re-poll the existing jobs; do not start duplicate installations.

```sh
bash scripts/prepare-distributed-install-lab.sh --collect-install kazoo-apps
bash scripts/prepare-distributed-install-lab.sh --apps-peer collect
```

Only after both return installed success, rerun the guarded native queued-call
partition command. The main dev44 applications service has not received this
new replica fix yet; its root source checkout does not imply running-code deployment.

Explicit command on the admitted private dev44 lab:

```sh
node scripts/test-channel-monitor-live.cjs --distributed --queue-partition --live
```

Only the original synthetic company, queue2000 and its three provisioned agents
are admitted. Other two agents are paused for300seconds, with exact saved recovery
identities and automatic expiry. No queue membership is changed. Both applications
nodes host an agent FSM replica by design; the test pins and verifies both.

The first real queue call must bridge1001 to1002 and carry two-way synthetic RTP
audio. Apps14 alone loses its lab broker route, while apps20 remains connected.
An independent3-minute watchdog restores that exact route if interrupted. The
owned call ends while disconnected; the inaccessible replica must remain
conservatively busy for at least35seconds, spanning its reconciliation interval.
After route restoration, both unchanged FSMs must recover ready without restart
or agent login. A second real queue call with the existing SIP contacts must
bridge and carry audio. Only test-owned calls, registrations, temporary web users
and alternate-agent pauses are cleaned up. No production route or account changes.

Recovery uses the same admitted harness with `--distributed --cleanup`; unknown
or changed agent states refuse automatic resume. Raw evidence stays root-only in
`/var/log/kazoo-monitor-acceptance-*` on dev44. Do not publish credential files or
unredacted server logs. Failure evidence remains failure evidence.

Offline checks:

```sh
node scripts/test-fixtures/distributed-lab/queue-partition.test.cjs
node scripts/test-fixtures/distributed-lab/controller-partition.test.cjs
node scripts/test-channel-monitor-fixture.cjs
node scripts/test-fixtures/monitor-audio.test.cjs
```
