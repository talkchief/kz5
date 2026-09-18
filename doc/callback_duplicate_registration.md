# A duplicate callback registration must produce one ticket

## Why it can happen

A caller's "call me back" request travels from the callflow process to the queue
process over AMQP and is written by a spawned job (`acdc_queue_fsm:callback_register/2`).
A retransmitted request, a redelivered message after a broker or node fault, or the
same member call owned by two applications nodes for a moment can all ask for the
same registration more than once, at the same time, from different nodes.

## How it is prevented

- The ticket id is `sha256({QueueId, OriginalCallId})` (`acdc_callback_store:callback_id/2`),
  so every request for one caller in one queue addresses one document.
- `create_doc/4` saves without a revision. The datastore accepts exactly one writer;
  every other writer gets `conflict`, reads the stored ticket and compares the
  identity and authority keys (`same_registration/2`): identical means the stored
  ticket is returned as the acknowledgement, different means `registration_conflict`.
- Creating never activates. `bind_registration/6` ties the ticket to the request id,
  and only the owning queue process activates it.
- Inside one queue process a second request while the first is in flight is ignored
  and acknowledged by the first write's result (`registration_ref`).

## Offline

`scripts/erlang-tests/acdc_callback_store_tests.erl`: `idempotent_registration_test`
(identical, then a different number, one stored document), the concurrent-claim and
`bind_registration` conflict cases. These use a mock store, so they cannot show what
the real datastore does under concurrent writers.

## Native injection (private lab, September 18, 2026)

`node scripts/test-acdc-callback-duplicate-live.cjs` copies
`scripts/test-fixtures/distributed-lab/callback-duplicate-rpc.escript` into every
running lab applications guest. The escript refuses any host, address, cookie file
or company other than the lab's synthetic one, then calls the product's own
`acdc_callback_store:create/5` on the live node. All nodes fire at the same moment
with one caller identity and one enqueue time.

| Check | Result |
| --- | --- |
| 2 nodes x 32 concurrent identical registrations | all 64 acknowledged `{ok, Ticket}` |
| ticket named by the acknowledgements | one id, one `pvt_created` |
| stored document afterwards | revision `1-…`: nothing overwrote the first write; status `registering`: no duplicate activated it |
| same caller, another number | `{error,registration_conflict}`, document unchanged |
| clean-up | `cancel/3` -> `cancelled`, document deleted, also when a check fails |

Receipt: `/root/kz5-callback-duplicate-20260918/run-2-nodes-32.log` (9 PASS). Earlier
runs the same evening: one node x 16 and two nodes x 16, both PASS. No call is placed:
the ticket is never activated and its authority id is not a real device.

Message-level duplicates with real calls are covered by the recovery campaigns
(`--apps-restart-during-backoff`, `--apps-restart-during-bridge`, queue-restart and
worker-loss), each of which fails on a duplicate callback.
