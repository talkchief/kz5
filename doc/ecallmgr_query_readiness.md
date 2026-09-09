# eCallMgr query readiness after a broker reconnect

An available AMQP connection is not proof that the channel-query consumer has
recovered its queue, bindings and consumer. During distributed supervision
partition run1, native broker registration returned, but the immediate stop
request failed503 with `channel ownership could not be verified`. It failed in
the read-only ownership phase, not after sending a media stop command. Retained
RTP proves Listen audio/privacy survived the actual interruption.

The normal installer's `verify_ecallmgr` now also calls
`verify_ecallmgr_query_listener`. It requires the exact native result `true`
from `gen_listener:is_consuming(ecallmgr_fs_channels)` within
`KAZOO_START_TIMEOUT`. Missing, false, malformed and timed-out status cannot
claim readiness. No service restart, binding change or authorization bypass is
performed by this check. The actual extracted function passes regression cases
in `scripts/test-ecallmgr-query-readiness.cjs`; the modular installer suite also
passes. Main44's native sourced installer check passed on `a7c8b28`.

The opt-in partition acceptance uses the same native consumer condition after
registered broker recovery and before sending one correlated stop request.
It records whether the consumer was already ready at broker recovery. The
test's recovery deadline is45seconds, with bounded status calls; no automatic
POST replay is introduced. The API continues to fail closed while complete
ownership evidence is unavailable. This is maintenance/recovery readiness,
not a claim that API control remains continuously available during partition.

Run2 exposed a test-runner handling gap: its first consumer status RPC failed
instead of waiting for readiness. The route was restored, but first cleanup
could not establish ownership; protected state and three exact synthetic legs
were retained. Read-only follow-up confirmed both listeners consuming and both
controllers available without a restart. The ordinary guarded `--distributed
--cleanup` then removed the owned legs, registrations and temporary web users.
The runner now treats unavailable consumer-status RPCs as not ready, never as
successful recovery. Unit coverage includes delayed consumer recovery and
invalid/failed status. Run1 and run2 remain failures.

Native run3 now **PASSes all four modes**, unit `kz5-stage-monitor-partition-3`
exit0 on runner `5554a11`: `/var/log/kazoo-monitor-acceptance-o7yewF` and
`/var/lib/kazoo5-install-lab/monitor-partition-3.log`. Each mode proves real
audio privacy during the partition, unchanged controller VMs, recovered native
broker and channel-query consumer, supervisor-only stop202, and original bridge
survival. All owned calls, temporary users and registrations were cleaned up;
both exact broker routes are restored and both consumers read back true.
The normal main44 stack's nine services remain active. No production audio or
imported-company records were involved.
Native Join recorded `query_consumer_at_broker_recovery=false` before the
consumer became ready and the single stop succeeded. This directly confirms
why registered-broker readiness alone was insufficient. Each interruption
lasted about14seconds; this is not a prolonged network partition.

See [actual monitoring acceptance](channel_monitor_acceptance.md).
