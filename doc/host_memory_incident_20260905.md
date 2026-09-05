# Host memory / AMQP incident — 2026-09-05

Production acceptance remains **incomplete**. This incident supersedes any
unqualified claim that the running platform has clean logs. Earlier passing
call/browser tests describe only their recorded observation windows.

## Evidence and recovery

At 23:27:02 UTC the kernel recorded a global out-of-memory event on this
3,559 MiB, no-swap host. It killed a Codex process (PID 2014386), reporting
869,560 KiB anonymous resident memory. It did not kill or restart the observed
RabbitMQ, Kazoo applications, eCallMgr or FreeSWITCH main processes.

Both Kazoo nodes nevertheless recorded AMQP heartbeat/socket timeouts and
closed-writer failures. RabbitMQ also reported temporary exclusive-consumer
conflicts during reconnection. Broker connection warnings predate the final
OOM event; memory pressure is strong evidence of resource contention, not proof
that every earlier disconnect had this single cause.

RabbitMQ cleared its system-memory alarm at 23:28:04. At approximately 23:35,
bounded read-only diagnostics returned no local alarms and five connections
in `running` state. FreeSWITCH reported zero calls. Applications and eCallMgr
crash logs had not grown beyond their last 23:27 entries (161,047 and 11,111
bytes respectively). These checks establish recovery observations, not
successful post-incident call handling, no lost messages, or failover readiness.

At 23:37 the existing authenticated read-only member/device acceptance passed
its schema, account/catalog preservation, pagination, malformed-cursor rejection
and registry-comparison gates. Crucially, it reported **0 online / 31 offline**,
compared with 30 online before the incident. That is not a healthy-registration
acceptance result. Registration recovery remains under investigation. The
API correctly exposing an offline state is separate from repairing that state.

Heavy builds, browser runs and live acceptance work were paused. One exact
owned private EUnit runner was terminated with TERM; its incomplete rerun is
not a test pass. No platform service restart, queue-roster change, broad call
hangup, cache flush or log truncation was used for recovery.

## Required follow-up

- Serialize resource-intensive validation/build commands; use hard memory,
  CPU, process-count and runtime limits plus a host-memory reserve. A per-job
  cap alone does not reserve memory against unrelated host processes.
- Keep source review parallel, but do not run several private Erlang/browser
  builds alongside live call acceptance on this host.
- Repeat the bounded platform health and isolated callback/browser gates after
  the deployment artifacts are finalized. Retain this failed observation window.
- Establish production resource isolation, monitoring and capacity with actual
  workload evidence. Neither adding swap nor raising heartbeat timeouts alone
  constitutes a production-readiness fix.

Primary local evidence: kernel journal around 23:27, broker log
`/var/log/rabbitmq/rabbit@kz5-testing.log`, and the two per-node Kazoo crash logs.
Do not commit raw runtime logs containing account/call or credential material.
