# Native broker/WSS fanout soak

Status: **full native soak PASS**. The defined fanout release gate is closed.
Unit `kz5-blackhole-fanout-soak-20260909` finished inactive/dead with exit0.
Root0600 receipt on dev44:
`/var/log/kazoo-blackhole-fanout-6f4ed2b1f3bd165f0a2c551ddd4d4595.json`.
All60 batches passed:3600 real broker events and115200 exact deliveries across
32 subscribers in1901seconds (31minutes41seconds), zero other-call leaks,
all sockets closed. Maximum control ping580.1ms; maximum measured delivery
latency1035.8ms including the deliberately lagged receivers. Native VM memory
was146658752bytes at baseline and156285952bytes peak; processes3249→3315 peak.
The three retained input hashes matched throughout. All9 main services were
active afterward, main media had zero channels, and apps/eCallMgr error-priority
journal entries were zero over the preceding35-minute window.
This proves the specified32-subscriber workload, not indefinite scalability,
media-node failover, historical persistence or30 calls per second.

## Retained pilot and intermediate evidence

Pilot receipt `/var/log/kazoo-blackhole-fanout-ab89346f96fd41d9ec09e4f1b2911bd3.json`
on dev44 verifies3 real broker events,12/12 deliveries, zero other-call leaks,
maximum control ping7.2ms, maximum delivery latency11.7ms and all sockets closed.
Full unit `kz5-blackhole-fanout-soak-20260909` started on runner `7f3df3c`.
First two batches passed120 broker events/3840 deliveries in64.7seconds.
That intermediate checkpoint was not a30-minute PASS. The completed receipt
above supersedes it and verifies duration, isolation, source identity, resource
bounds and socket cleanup. Preserve the terminal log at
`/var/log/kazoo-blackhole-fanout-soak-20260909.log`; do not rerun this passed
campaign without a relevant source or workload change.
First native pilot correctly rejected the runner changing a connected socket's
authentication token (`638d9d38f451af33e3a26af04275a5ab` receipt, refresh-auth,
zero events published, all client sockets closed). Native policy requires
reconnect to change token and is not relaxed. The corrected harness issues one
45-minute synthetic fixture token and retains the same sockets throughout.
Second pilot (`5af423da05ef9f3bb603cda25881b231`) reached broker publication but
native event validation rejected missing Msg-ID before any publication. The
producer now obtains header seeds from installed `kz_api:default_headers/4`
and explicitly supplies Msg-ID before its pre-publication validation (the normal
publisher would otherwise add it later). Third pilot
`ddc05e6d3b34fff44771cf25b99e25dc` confirmed the seed helper alone does not add
Msg-ID. Both attempts failed before publication; all client sockets closed.
Fourth pilot (`91bfa389685f66386503d941b220dc9e`) published the3 broker events,
then the receiver rejected their native normalized envelope. `bh_events:event/3`
exposes the type as top-level `name`, with lowercase/underscore public data keys;
it does not forward the original internal AMQP shape. The receiver and its
regression fixtures now validate that actual contract. This earlier attempt
remains failed, not a fanout pass; its sockets were closed.

Explicit development44-only commands:

```sh
python3 scripts/test-blackhole-fanout-unit.py
python3 scripts/test-blackhole-fanout.py --pilot
python3 scripts/test-blackhole-fanout.py --live
```

The pilot uses4 subscriptions and3 events. Full acceptance uses32 subscriptions
plus one other-call control connection,60 batches of60 events at2 events/second
(3600 broker events,115200 expected subscriber deliveries). Eight receivers
periodically delay actual network reads; every subscriber must receive every
numbered event exactly once within the bounded drain window. The other-call
subscription must receive none. The control connection pings during publication.
The single45-minute fixture token is never printed. Each batch verifies native
authenticated commands without replacing the token or reconnecting sockets.

Publication uses actual `kapi_call` validation, AMQP worker publication, pooled
call-event handling and native Blackhole subscription fanout over
certificate-verified WSS through nginx. No direct socket message injection or
replacement emitter. Only synthetic CHANNEL_HOLD notifications for a random
nonexistent call in fixed acceptance company8310dc3170a18de37f205d0da172df65 are
permitted. No dial/originate, service restart, database write or real-call action.

Full acceptance must last at least30minutes. Per-batch broker process startup,
authenticated checks and read-lag drain add wall time. Native VM memory and
process counts are sampled with bounded growth assertions, along with responsive
control pings. Runner/transport/producer input hashes are retained and checked
throughout to refuse mixed-version evidence. This is a defined traffic envelope, not indefinite scalability,
media-server failover or30 calls-per-second evidence. Retain failed receipts.

The shared root0600 acceptance lock prevents concurrent call/stream tests.
Receipts stay root0600 at `/var/log/kazoo-blackhole-fanout-*.json`. Client threads
and sockets must close even on error. The helper independently admits root on
development44, the cookie file and the exact synthetic account realm before
publishing; no arbitrary endpoint, tenant, event type or unbounded count option.
