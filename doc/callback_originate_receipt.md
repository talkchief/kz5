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
