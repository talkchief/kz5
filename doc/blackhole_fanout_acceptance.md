# Native broker/WSS fanout soak

Status: offline framing/identity guards pass; native pilot and full soak pending.
This does not close the fanout release gate until the full retained receipt passes.

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
Short-lived fixture tokens are refreshed between batches, never printed.

Publication uses actual `kapi_call` validation, AMQP worker publication, pooled
call-event handling and native Blackhole subscription fanout over
certificate-verified WSS through nginx. No direct socket message injection or
replacement emitter. Only synthetic CHANNEL_HOLD notifications for a random
nonexistent call in fixed acceptance company8310dc3170a18de37f205d0da172df65 are
permitted. No dial/originate, service restart, database write or real-call action.

Full acceptance must last at least30minutes. Per-batch broker process startup,
authentication refresh and read-lag drain add wall time. Native VM memory and
process counts are sampled with bounded growth assertions, along with responsive
control pings. This is a defined traffic envelope, not indefinite scalability,
media-server failover or30 calls-per-second evidence. Retain failed receipts.

The shared root0600 acceptance lock prevents concurrent call/stream tests.
Receipts stay root0600 at `/var/log/kazoo-blackhole-fanout-*.json`. Client threads
and sockets must close even on error. The helper independently admits root on
development44, the cookie file and the exact synthetic account realm before
publishing; no arbitrary endpoint, tenant, event type or unbounded count option.
