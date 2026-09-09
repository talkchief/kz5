# Queued-call applications-node broker partition

Status: native run5 PASS, after source fixes and108 Erlang regression passes.
Both normal lab rebuilds passed on source `2e91984`; runner `0ac6fb9` completed
as `kz5-stage-queue-partition-5`, exit0. Evidence on dev44:
`/var/log/kazoo-monitor-acceptance-aKrXXe`; terminal log
`/var/lib/kazoo5-install-lab/queue-partition-5.log`.

Two actual queued SIP/RTP calls passed directional audio and exact ownership.
Both original agent FSMs agreed on the answered call, retained their identity
through apps14-only broker loss and recovered ready without re-login or SIP
re-registration. The second call connected using those same registrations.
Independent route restoration and scoped call/user/contact/pause cleanup passed.
This covers that bounded apps-node broker partition, not arbitrary media-node
failure or indefinite availability. Main44 runtime deployment is next.

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
private apps guests. Both normal installer rebuilds completed and their collected
receipts report PASS: primary `kz5-stage-install-kazoo-apps-8`, peer
`kz5-stage-install-apps-peer-4`. Logs are `kazoo-apps-install-8.log` and
`apps-peer-install-4.log` under `/var/lib/kazoo5-install-lab` on dev44.

```sh
bash scripts/prepare-distributed-install-lab.sh --collect-install kazoo-apps
bash scripts/prepare-distributed-install-lab.sh --apps-peer collect
```

Native after-test `kz5-stage-queue-partition-4` failed, with evidence retained at
`/var/log/kazoo-monitor-acceptance-g8fTGc`. Its first actual
queued call passed the exact bridge, both answered replica correlations and
two-way audio gates. Apps14 remained conservatively answered during a39-second
broker partition; both original FSMs recovered ready afterward. The second SIPp
receiver answered an OPTIONS health check, exhausted its `-m 1` call budget and
ignored subsequent actual INVITEs. The platform did send three ringing attempts;
the unattended synthetic agent was then logged out. This is not a delivery-loss
diagnosis. A native loopback regression reproduces the old limit rejecting the
INVITE and verifies the corrected bounded receiver accepting it. Customer
origination remains limited to one call; receiver timeout, exact ownership,
audio/bridge checks and scoped cleanup remain unchanged. Calls, registrations,
temporary users and alternate-agent pauses were cleaned up. A new run requires
explicit preparation of that logged-out synthetic agent, not relogin during the
recovery measurement. The main dev44 applications service has not received this
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
