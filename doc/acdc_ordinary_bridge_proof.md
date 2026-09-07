# Normal queue calls: native bridge proof

## Incident and scope

Live dashboard acceptance43165 connected one internal caller to one agent,
verified12 stable FreeSWITCH bridge samples and one CHANNEL_BRIDGE event, yet
51valid dashboard snapshots remained waiting. Evidence is privately retained
in `/var/log/kazoo-strategy-acceptance-BMBtU4`. Scoped test cleanup succeeded.
This is a normal queued call, not a callback or historical-reporting change.

The queue listener subscribes to the caller leg. Native intercept emits its
bridge event on the initiating agent leg. The ordinary queue FSM previously
required a caller-side bridge event plus selected-agent acceptance before
publishing `acdc_stats:call_handled/4`; acceptance alone therefore stranded its
live state even when the media bridge existed.

## Canonical correction

Implementation is in `applications/acdc/src/acdc_queue_fsm.erl`, directly tracked
in kz5. Validated acceptance from the current selected agent/process starts
an asynchronous `acdc_callback_recovery_io:observe_channels/2` observation,
scoped to the account and exact caller. That existing I/O helper performs
correlation, responder and account checks and follows the reciprocal leg.

The FSM additionally requires complete evidence with exactly one caller and
selected agent observation, both active and answered, mutually linked and on
the same nonempty switch node. Only then does it finish the queue member and
publish handled. Acceptance or a WebSocket hint alone never proves a bridge.
The existing caller-side-event path remains supported in either arrival order.

Only one probe is in flight per attempt. Unknown observations may retry after
250ms within one fixed15-second deadline, which duplicate accepts do not extend.
References and caller/current-selection checks reject stale results. Clearing
the member, terminating the FSM, or reaching the deadline stops the worker and
retry timer. A hard-killed parent cannot run termination cleanup; the worker's
own watchdog still limits it to the original deadline, not a new15-second span.

Because the caller may already be physically connected after selected-agent
acceptance, ringing/connection timeouts and late retry messages are fenced.
At an unresolved proof deadline, the FSM explicitly reports
`bridge_proof=unresolved` through its status reply and retains the caller without
inventing handled, hanging up its partner, or originating a duplicate call.
This conservative uncertain-state retention is a liveness limitation, not a
claim that lost events or failed channel observations are fully recovered.
A later genuine caller-side bridge event and matching selected acceptance can
still complete the existing event path; the fixed deadline bounds snapshot
probing, not the lifetime of authoritative call events.

## Verification and remaining gates

`bash scripts/test-acdc-ordinary-bridge-proof.sh --baseline` rebuilds the old
FSM from local `d7dde11`; root54667 reproduced all five expected failures with
stable source pins. Root59099 passed the corresponding five candidate groups.
Both broader strategy shards passed (root53337:16; root60105:15). A sixth focused
test was then added for unknown → retry → success, requiring the unchanged
original deadline, no overlapping worker and one handled transition. Root86399
passed all six focused groups against unchanged production source; evidence
`/tmp/kazoo-ordinary-bridge-proof.7q504M`. Root26126 also passed all16 existing
channel-observation/recovery-I/O tests, including correlation, account/responder
checks and rejection of one-way bridges.
It compiles three production modules without TEST, then uses a separate
TEST-export FSM for handler tests with the channel-observation boundary
substituted. This is not a live broker or call proof.

## Deployed correction and actual live result

Root2519 compiled a fresh production build of74 ACDC and30 Blackhole modules in
`/usr/local/src/kazoo5-installer/live-dashboard-backend.0KplKA`. Root29023 deployed
only the matching `acdc_queue_fsm.beam`; its previous artifact is retained at
`/tmp/kazoo-live-rollout.OYdOqh/acdc_queue_fsm.before-native-proof.beam`.

Root79231 passed the actual isolated `--dashboard-live` call. Private receipts:
`/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-evidence.json` and
`/var/log/kazoo-strategy-acceptance-ZYctqU/dashboard-natural-call-evidence.json`.
All15 HTTP snapshots were valid, with three native invalidations and zero
timeouts. Waiting → handled → gone each had a fresh hint followed by a GET;
the call had one offer, one bridge and12 stable FreeSWITCH samples. Exact
subscribe/unsubscribe ACKs and cleanup passed: all three original agent states
were restored, owned resources/contacts removed, no recovery ledger remained,
FreeSWITCH had zero calls and all eight services were active.

This closes the reproduced P0-15 normal-call transition for this isolated run.
The earlier43165 failure remains valid baseline evidence, superseded by this
pass, not reclassified. Hints contain no causal call nonce. Browser call-transition
rendering, restricted-user authorization, cross-node failures and load/soak
remain unproven; the conservative unresolved-proof liveness limit still applies.
