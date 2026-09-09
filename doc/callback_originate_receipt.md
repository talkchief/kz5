# P0-06: durable callback originate success evidence

September 9, 2026. Source correction committed/pushed as `769fdb2` to master.
Native deployment and the scoped positive callback acceptance passed.
This does **not** close the retained historical ticket or the broader HA gate.

## Reported failure and current evidence

A callback can remain `cancelling` after its worker loses the successful
originate response and the native registry no longer retains that result.
An empty call list does not prove that an outstanding originate has settled.

Read-only native query `6f4786` on the original source server returned
`unknown / not_observed_in_current_module_epochs` from `ecallmgr@kz5-testing`
for the exact retained attempt. Its historical identity is:

- Account: `7807ad61761269a1ccec833dde63f621`
- Queue: `ab1bcb924fb4f42fb77a2c53e8c76728`
- Ticket: `acdc-callback-a5d33b5532ef24bd645a4eb60e51707e0a39c134e3abe87dd9388671d7527435`
- Last inspected revision: `8-74bdf9d88b9a98a1d2ae98219f1ef9ff`
- Native originate UUID: `44295d15120852c01eaee441aacf174e`
- Native request ID: `a36eadd23dbea78bc5588731`
- Caller leg: `7faf93c1ef66f35737456aa0e3038484`

The document has not been rewritten, deleted or forcibly settled. It predates
the new receipt and remains open; the missing historical proof cannot be
reconstructed from the receipt feature.

## Source behavior

`applications/acdc/src/acdc_callback_caller.erl` starts one unlinked receipt
writer on the first correlated SUCCESS. It records proof only after execute
and without a previously detected conflicting READY response. Slow database
I/O does not block the confirmation prompt. Duplicate SUCCESS messages do not
spawn additional writers. The writer can finish after the caller worker exits.

`acdc_callback_store:advance/6` gains internal action `originate_succeeded`.
The existing account-scoped revision CAS requires the exact current lease
token, caller UUID, native originate UUID and native request ID. It can record
evidence after cancellation or lease expiry, but cannot claim, complete,
confirm, bridge or retry a call. The private `pvt_originate_success` contains
version, observation time, account, queue, ticket, attempt and originate/caller
identities. Duplicate writes are idempotent. It survives adoption of the same
attempt, is removed when an attempt ends, and cannot authorize another attempt.
Registration input cannot set it and the public callback API does not expose it.

`acdc_callback_recovery_io` still queries native status. Only a complete,
correlated collection reporting no surviving native record may use the exact
durable receipt as originate-success evidence. Pending operations, timeouts,
empty collections, malformed/correlation failures and conflicting native
results do not get overridden. Cancellation requests never use this fallback.
The coordinator still needs independent fresh all-node channel-down evidence
and its existing ownership/revision checks before settling or retrying.

No schemas, design documents, account migrations, runtime TTS or extra service
are introduced. All source is tracked directly in kz5 and compiled by the
existing `scripts/install-kazoo5.sh kazoo-apps` option.

## Validation and next action

Run only the relevant isolated suites:

```sh
bash scripts/test-acdc-callback-store.sh
bash scripts/test-acdc-callback-recovery-io.sh
bash scripts/test-acdc-callback-caller.sh
node scripts/test-callback-fixture-cleanup.cjs
node scripts/test-callback-retry-language.cjs
```

Candidate results: 27 store tests (7b6417), 18 recovery-I/O tests (ece43c),
9 caller tests including an independent writer surviving handler exit while
blocked (c7c8c1). That last run also passes 13 cleanup groups, 12 retry
locale/configuration groups and shell syntax checks. These are isolated unit
and harness checks, not native acceptance. Initial new-test setup failures
(missing mock configuration/logger assumptions) were corrected; their failed
runs are not claimed as passes.

The existing positive native retry harness now requires an independently
computed, secret-free `originate_success_recorded:true` on the exact completed
attempt. The projection checks every saved identity against the durable
document, not just receipt presence. It retains existing single-key6, full
prompt, unanswered-first-attempt, backoff, second confirmation, reciprocal
bridge, agent-ready and teardown gates. Old evidence is not retroactively
declared to pass this new requirement.

Deploy through the normal apps installer on `10.1.0.44:/opt/kz5`, verify loaded
module identity, then run one positive callback retry case on the canonical
isolated account. Do not mutate the imported Talkchief account or rerun the
unrelated voice generation/load campaigns.

Deployment completed through normal `kazoo-apps` CLI in unit
`kz5-callback-receipt-install-main44-20260909`: successful deactivation at
03:03:02 UTC (13bf59/553c04), approximately10m52s wall time,377MiB peak memory.
Its final result reports all selected components passed validation, including
administrator login, ACDC and entitlement/storage APIs and installed media.
Protected log: `/root/kz5-acceptance/callback-receipt-install-main44-20260909.log`.
SHA256: `117c930b7f54b983a3c56953bf3d79d02006d0690465491ad18c2b04dd3ce96d`.
Main repository was clean and fast-forwarded to769fdb2; native entry inventory
was zero calls. Native loaded/disk MD5 matches (c5591d):

- `acdc_callback_store`: `5745bac222d4365d2b9b100220dccfcd`
- `acdc_callback_caller`: `523a419461779c4acc3f00b0cc45e444`
- `acdc_callback_recovery_io`: `b51f4d167aca9033f40fae4076c8f7db`

Live unit `kz5-callback-receipt-case-main44-20260909` completed exit0 (9b2067),
4m2.886s wall time and101.8MiB peak memory. The waiting SSH/tool session58191
is terminal; do not relaunch the passed case without a relevant change.
Log: `/root/kz5-acceptance/callback-receipt-case-main44-20260909.log`.
The existing positive retry CLI used the main isolated account, internal1001,
entry-only6, explicit EN and short confirmation window, with no installed
master test-phone helper. Run: `/var/log/kazoo-acceptance/20260909T030420Z`.

Native results (d07fa9/31a6ad/7680cf/12427c):

- The caller sent only6,4.986s after answer. The entire5.491s registration
  confirmation recording arrived before server BYE; no missing phrase samples.
- The first returned attempt was unanswered. Durable retry_wait retained the
  configured15s backoff; the second INVITE arrived1.0846s after the durable due time.
- The second returned caller heard the full4.331s confirmation with strict RTP
  continuity and correlation0.999995. Digit1 arrived1.1459s after completion,
  within the configured3s response window, followed by one agent INVITE and
  reciprocal bridge with bidirectional audio.
- Exact ticket `acdc-callback-1981138f7edfe548ec2e6a60452a50c22140c225ac9825490bc933b4a687f661`
  is completed at attempt2 with `originate_success_recorded:true` and no
  reconciliation flag. This field checks all receipt/document identities.
- Agent returned ready. Caller2/0 and agent2/0 successful/failed, fresh journal
  and file error counts0/0, new cores0. Native post-run inventory is zero calls;
  apps, eCallMgr, FreeSWITCH, Kamailio and bridge are active. Services used by
  the case did not restart during it. The exact queue timeout restored15->3->15.

Evidence SHA256:

- `retry-bridge-evidence.json`: `50455cd8e917c943152c87816eafd77339d438b9c0e66fea07b0c117d97d032e`
- `retry-packet-evidence.json`: `83633af836407fd9672f06fa3b6079e3db53dc7a62889d693338420e75afb7bf`
- `callback-confirmation-deadline-edit.json`: `d802605d2519e3c4f16a76d107b1a351c66f06f9d6e185eabe865c94c6f40c2c`
- Protected native case log: `a72fba4f9230f58a20add60154aa7198a2b7887c782ba350caa4f1bb58145ebe`

This verifies actual receipt creation and no regression of the reported callback
flow. Worker-loss/registry-expiry fallback has isolated regression coverage;
controlled native failure/recovery remains unverified. The historical ticket
is still retained and P0-06 remains open for that unresolved evidence gap.

Limits: a database conflict/failure or node crash before receipt commit still
requires native evidence and can remain ambiguous after registry expiry. A
fixed warning identifies an unsuccessful write; it does not turn that failure
into proof. This is not an exactly-once guarantee, a broker-partition test,
a native-registry restart test, or authority to clear the old ticket.

## Native queue restart during saved retry backoff

`scripts/test-acdc-callback-retry.sh --queue-restart-during-backoff` adds an
explicit native failure boundary to the existing positive retry case. It is
allowed only with the canonical main isolated account/queue, EN, internal1001
and entry-only6. It cannot combine with language edits, a short response window
or confirmation-expiry mode. No service or FreeSWITCH restart is performed.

After the unanswered first attempt settles into durable retry_wait, it requires
zero native channels, no recorded legs and more than eight seconds before the
saved due time. It writes an attempt marker, invokes the existing
`acdc_maintenance:queue_restart/2` exactly once for that queue and verifies a
different queue supervisor PID. Timeout/error/unchanged PID fails the case;
the marker prevents blind re-execution. Normal callback evidence must then
prove the same ticket/order/backoff, second confirmation, receipt and bridge,
without a third attempt or a Kazoo service restart.

Guard results: 17 actual-shell boundary cases and13 CLI/reference groups pass
(e1d377/065885), plus shell syntax and diff checks.
First native unit `kz5-callback-queue-restart-main44-20260909` failed before
issuing a restart (763319), run20260909T032217Z. There is no restart-attempt
marker. SUP prints an external PID such as `<10623.1778.0>`, not a local
`<0.N.S>` PID; the old guard rejected it. The corrected guard accepts the remote
form but compares only the target-local ID/serial, not the ephemeral SUP VM's
node index. Updated17 boundary cases pass25c932, including a changed client
node index with unchanged target PID being rejected. Native rerun failed below;
the original failed run is not relabeled as a pass.
This tests losing a worker while a callback is waiting, **not** losing an
active returned leg, registry expiry, broker failover or the historical ticket.

### Confirmed failure: last-consumer auto-delete

Second unit `kz5-callback-queue-restart-main44-20260909b` failed (081b66),
run `/var/log/kazoo-acceptance/20260909T032633Z`. The queue supervisor changed
from local PID1778.0 to32710.0 at03:27:55–03:27:57 UTC. The exact callback
`acdc-callback-bfbd63a243e828bdc9983afc01bc10d047a437f79cca10832682f3cfce869fe4`
was durably retry_wait/attempt1, due03:28:09, with no live channels. No second
attempt occurred within the existing75-second deadline. Cleanup then cancelled
that ticket; the final uncached document still has attempts1 (61ca8d). No
unrelated or historical callback document was modified.

Broker read55e55d: shared queue
`acdc.queue.8310dc3170a18de37f205d0da172df65.67c5f3fb115bdd1dd574d6a604a7d29f`
has auto_delete=true, durable=false. `acdc_queue_shared` omits auto_delete;
`kz_amqp_util:new_queue/2` defaults it to true. Stopping every worker deletes
the shared queue and its unacked delivery. The document survives in CouchDB,
but recovery depends on redelivery. Candidate explicitly sets auto_delete=false
without changing names, acknowledgement, prefetch, priority, TTL or length.
`scripts/test-acdc-queue-shared-options.sh` exercises the production start_link
declaration with mocked I/O; the old declaration fails its retention assertion
(ae95c5). Candidate regression passes345c85; syntax/diff checks pass.
Main44 pre-upgrade read69d84a: two shared member queues, both empty; only the
isolated acceptance account has consumers. Exact account query2ae370 returns15
callback tickets, all terminal. FreeSWITCH row_count=0. Deployment completed
below; subsequent native outcomes are recorded separately. Preflight is not
itself a recovery pass.

Source72591d5 was committed/pushed to master and fast-forwarded on main44.
Normal `scripts/install-kazoo5.sh kazoo-apps` unit
`kz5-callback-retention-install-main44-20260909` exited0 (2b2a10), runtime
10m51.570s, peak379.9MiB. Log:
`/root/kz5-acceptance/callback-retention-install-main44-20260909.log`, SHA256
`d6f02d4fc2f94021a7d089240441e86f7c81882d0c7534f7113c29e1f1ed3461`.
Loaded and disk `acdc_queue_shared` MD5 both
`0bd48a1aca96386718c85bcf95ed052f` (c97bcb/0fcccd).
Post-restart broker read96e138 confirms both isolated member queues have
auto_delete=false, messages0 and their1/30 consumers restored; no explicit
broker deletion was performed. Login/ACDC/entitlements/storage readiness passed.
The existing voice gate still reports no full-position/native release readiness;
this callback change does not override that separate limitation.
Native unit `kz5-callback-retention-case-main44-20260909` FAILED (e7991e),
runtime3m4.276s, run `/var/log/kazoo-acceptance/20260909T035026Z`.
It restarted the queue but the ticket still remained at attempt1. Final
uncached read99439b: ticket
`acdc-callback-634575cfdb423c2751ce5f9b9479c721e7db95f5d729c7789420e5173c3df65b`
is cancelled by test cleanup, attempts1, no runtime legs or reconciliation
flag. Broker has messages0 and30 consumers. Queue retention alone is not a
recovery pass.

### Second defect: NACK helper acknowledges unfinished work

`acdc_queue_shared:terminate/2` calls `kz_amqp_util:basic_nack/1` for its unacked
deliveries. The helper's basic.deliver clause incorrectly emits basic.ack.
This drops the recovery delivery even when auto-delete is disabled. Correct
the helper to delegate to basic_nack(Tag, true), keeping explicit /2 and /3
requeue/multiple policies and actual basic_ack unchanged. The fix is maintained
in the root-owned `scripts/patches/kazoo-amqp-basic-nack.patch`, applied by
`scripts/install-kazoo5.sh` to the pinned core tree; no nested core commit.

The focused `scripts/test-acdc-queue-shared-options.sh` now compiles both real
modules into a temporary directory and tests production listener shutdown with
only the channel command mocked. Baseline7ae3cb produces ACK101/ACK100 instead
of NACK101/NACK100 with requeue=true (1fail/2pass). Candidate72f938 passes all3:
shutdown requeues unfinished deliveries only, explicit ACK/NACK policies stay
unchanged, and the shared queue remains non-auto-delete. Reverse patch check,
shell syntax and diff checks pass7b47c8.

Source `f853f47` is pushed to master and present on main44. Normal installer unit
`kz5-callback-nack-install-main44-20260909` exited0 (06d171),10m48.264s,
peak368MiB. It applied the required patch through the normal source-preparation
hook (839009). Log `/root/kz5-acceptance/callback-nack-install-main44-20260909.log`,
SHA256 `dc2d61f7fef89d78aaaae9d5fc969e838aa802cf5d4952ef074d02bb0182b6a2`.
The apps node's loaded `kz_amqp_util` and rebuilt disk module both have MD5
`e7505645109485727b0aff35a39887fe` (b57ad5/5e5646). This was an apps-role
deployment, not an all-role or production rollout. No active calls before the
next test (8b7bff).

### Final scoped native PASS with both fixes

`kz5-callback-requeue-case-main44-20260909` exited 0 (764dcf), runtime4m1.060s.
Run directory `/var/log/kazoo-acceptance/20260909T041030Z`; no service restart
was performed during the case. Exactly one queue maintenance restart changed
local supervisor PID1778.0 to10346.0 at04:11:55–04:11:56 UTC (f8b163).
The callback stayed on the same ticket and enqueue identity, preserved its
15-second backoff, and placed attempt2 1.412752 seconds after the saved due time.

Packet and native evidence prove one digit6 at4.984537 seconds after answer,
the complete5.491-second installed registration phrase before server BYE
(PCM correlation0.999993, zero missing phrase samples), first returned call
unanswered for14.976 seconds, then a confirmed second return. Exactly one agent
INVITE followed confirmation digit1 by943ms; reciprocal native bridge and
bidirectional PCMU were recorded. The two-second wait is after the proof was
collected; measured busy-call release was5.273636 seconds after phrase completion.
This is waveform/packet proof, not a human pronunciation-quality review.

Exact ticket
`acdc-callback-4334ae4ddf2744114893998ef82e8e28d6ff3e0486b335dea9548a97c81a4b0d`
is still completed at attempt2 with persisted originate-success receipt and
no reconciliation flag (6e0559 / e91f2f). Agent-ready and unchanged-service
gates passed; summary reports caller2/0, agent2/0, fresh errors0/0, cores0.
Fresh FreeSWITCH inventory is zero calls (257cbd); correctly named apps,
ecallmgr, FreeSWITCH, Kamailio and HAProxy units are active (bd9051).
The fixture remains intentionally installed (`full_cleanup_acceptance=false`).
This closes only retry_wait recovery after a single queue supervisor restart,
not active-leg loss, broker failover, cross-node recovery, the old retained
ticket, full fixture cleanup, five-language release readiness or production
acceptance. No unchanged replay of this passed case is needed.

SHA256 evidence:

- `retry-bridge-evidence.json`: `2e0a37a064d43ace6771160773bc7b91522f3665a4f4fc48073c06d74eba275e`
- `retry-packet-evidence.json`: `a7e1da0fa3672297da84582b13034f3e29b7b017ad49050a1c0c7ea604280d81`
- `callback-queue-restart.json`: `f3da49e29a739a98c7909abf802c5e2a0873b6771fc17e823e52de191feffcce`
- `/root/kz5-acceptance/callback-requeue-case-main44-20260909.log`: `a044c63605b5d4160c8a7277478a01c165cc885afeeead3e6f852b64e34af3a9`

Upgrade constraint: RabbitMQ declaration properties are immutable. A legacy
auto-delete queue cannot be redeclared with the new property while it exists.
Drain affected queues/callbacks, prevent new ingress, and stop **all** legacy
consumers together so the empty old queues auto-delete before starting the new
release. Never delete a queue containing work or force-cancel tickets as an
upgrade shortcut. In a split/multi-node deployment, restarting only one apps
node is insufficient. Fresh installations use the new declaration directly.
Retained empty queues after business-queue deletion require explicit operator
cleanup; this patch does not automatically delete broker resources. Queues
remain non-durable and messages retain their existing one-day TTL: broker
restart/failover and prolonged outage recovery are NOT covered by this fix.
Rollback to a release that declares auto_delete=true also needs a coordinated
drain: retained queues do not disappear when the last new consumer stops.
Only after verifying no pending tickets, ready/unacked messages or consumers
may an operator remove the exact empty queues for the old release to recreate.
Neither the installer nor this acceptance case performs that deletion. A
mixed-version rolling upgrade/rollback is not validated by this single-node
development deployment.
This also applies to v4/v5 coexistence: legacy v4 consumers declaring the same
account/queue name with auto_delete=true cannot share that broker queue with
the corrected declaration. Keep the development broker/vhost isolated; do not
attach this release to production's shared ACDC work queues without a planned
drained migration. This change is not evidence of v4/v5 broker compatibility.
