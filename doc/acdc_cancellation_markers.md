# Queue cancellation markers and delivery settlement

## Status — September 17, 2026

**Deployed to the private apps pair and natively accepted on September 17 (see
`PROJECT_TASKS.md`); not yet promoted to main44.** Originally source-only. Repairs the second half of the September 10
rollout refusal recorded in `maintenance_listener_dispatch.md` (three retained
cancellation markers on each of apps14 and apps20).

## Defect

`cf_acdc_member` publishes `member_call_cancel` when a waiting caller hangs up,
times out or exits by DTMF. Every queue manager on every node stores a marker
for `{Account, Queue, Call-ID}` so that a `member_call` still queued at the
broker is suppressed when some worker finally consumes it.

A marker was erased only by `should_ignore_member_call`, i.e. only on the one
node whose worker later consumed that delivery, and only if a delivery was still
queued. When the worker already owned the delivery (the normal case: it receives
`member_hungup` from its own call-event binding and settles the delivery itself)
nobody asked, so **every manager kept the marker forever**. Effects:

- unbounded growth of `ignored_member_calls`, one entry per abandoned call per
  node, for the lifetime of the VM;
- `acdc_queue_manager:maintenance_snapshot/1` requires zero markers, so the
  maintenance/rollout gate refuses permanently after the first abandoned call.

## Correction

A marker may be released only on proof that the broker delivery is gone. The
only party that can prove this is the worker that owned the delivery, after its
acknowledgement. `queue.member_remove` gains one optional header:

| Header | Type | Meaning |
| --- | --- | --- |
| `Settled-Call-ID` | non-empty binary | Physical call id whose delivery the publishing worker has **acknowledged**. Absent when the delivery was nacked/requeued or the publisher is not the delivery owner. |

`acdc_queue_listener` publishes it after `ack` in `ignore_member_call`,
`handle_call_failure` and the acknowledged branch of `cancel_member_call`. The
nacked branch still publishes a plain removal: a requeued delivery must stay
suppressed. `member_call_success` is already published by the owner after its
acknowledgement and is treated as settlement for its call id.

`acdc_queue_manager` on `member_delivery_settled` erases the marker and records
the settlement for five minutes (bounded at 2000 entries) because the settlement
can overtake the cancellation it answers. A later cancellation skips the marker
only if a fresh settlement exists **and** this manager does not list the call as
a waiting member; a call enqueued again after settlement keeps full protection,
and one settlement answers one cancellation. Anything unproven is retained, as
before. Old nodes ignore the optional header, so mixed versions degrade to the
previous (leaking but safe) behavior.

The manager state record gains `settled_member_calls`. Deploy with the normal
cold VM restart; do not hot-load `acdc_queue_manager` into a running VM.

## Verification

```sh
bash scripts/test-acdc-cancel-markers.sh            # 7 pass
bash scripts/test-acdc-cancel-markers.sh --baseline # d14880e: 5 fail, 1 control passes
```

The runner compiles production `acdc_queue_manager`, `acdc_queue_listener`,
`kapi_acdc_queue` and `acdc_queue_member` with `-Werror` into a private
directory. It covers: settlement releases the marker and reopens the maintenance
gate; plain removal, foreign and malformed settlements retain it; settlement
before cancellation for listed/unlisted calls; expiry and the size bound; AMQP
handler forwarding; header schema; listener ack-then-announce versus nack. The
baseline control that passes on both sources is the retention safety property.
All four changed modules also compile with the full production flags
(`+warn_missing_spec -Werror`).

Follow-up the same day: `member.call_success` also carries `Settled-Call-ID`.
A returned callback leg has a physical id that differs from its logical id and
markers are keyed by the physical one, so a cancellation racing a handled
callback could previously strand a marker. Older workers omit the header and the
logical id is used as before. The suite now has eight groups; six fail on
`d14880e`.

Not proven: broker behavior, multi-node ordering under load, a worker dying
between acknowledgement and announcement (the marker is then retained, which is
the safe direction), and any installed runtime.
