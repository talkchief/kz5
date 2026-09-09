# Native broker/WSS fanout soak

Status: corrected native pilot PASS; full soak is running.
This does not close the fanout release gate until the full retained receipt passes.
Pilot receipt `/var/log/kazoo-blackhole-fanout-ab89346f96fd41d9ec09e4f1b2911bd3.json`
on dev44 verifies3 real broker events,12/12 deliveries, zero other-call leaks,
maximum control ping7.2ms, maximum delivery latency11.7ms and all sockets closed.
Full unit `kz5-blackhole-fanout-soak-20260909` is active on runner `7f3df3c`.
First two batches passed120 broker events/3840 deliveries in64.7seconds.
This intermediate checkpoint is not a30-minute PASS. Poll the same unit and
`/var/log/kazoo-blackhole-fanout-soak-20260909.log`; do not repeat admission or
restart services while it is active. The final receipt must pass all60 batches,
duration, isolation, source identity, resource bounds and socket cleanup.
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
