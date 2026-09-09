# P0-06: durable callback originate success evidence

September 9, 2026. Source correction; native deployment/acceptance pending.
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

Limits: a database conflict/failure or node crash before receipt commit still
requires native evidence and can remain ambiguous after registry expiry. A
fixed warning identifies an unsuccessful write; it does not turn that failure
into proof. This is not an exactly-once guarantee, a broker-partition test,
a native-registry restart test, or authority to clear the old ticket.
