# Queued-call applications-node broker partition

Status: harness and offline ownership/audio gates pass; native acceptance pending.
This closes no release gate until the retained native receipt passes.

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
