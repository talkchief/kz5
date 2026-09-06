# ACDC/backend and UI upgrade readiness — 2026-09-06

The current source and freshly tested Monster bundle are not yet a deployed,
coherent release. Read-only probe `29950` confirmed unchanged service identities
and 27 source/BEAM/helper identities. It performed metadata RPC only: no load,
purge, state conversion, account mutation, restart or deployment.

The new `cb_acdc_agent_queue` is absent from the installed runtime. The installed
`acdc_callback_recovery_io` lacks `observe_channels/2` and was not loaded.
The agent FSM still uses its preceding 25-element state tuple; current source
uses 28 elements. The editor is also an older installed revision. Existing old
code slots for the editor and Gemini mapper must not be force-purged.

The coherent candidate boundary is ten production modules:

- `cb_acdc_agent_queue`, `cb_agents`, `cb_acdc_queue_editor`;
- `acdc_agent_handler`, `acdc_agent_listener`, `kapi_acdc_agent`;
- `acdc_agent_fsm`, `acdc_callback_recovery_io`, `acdc_queue_listener`,
  `kapi_acdc_queue`.

This list is not complete all-node dependency verification. Compile production
BEAMs without `TEST`, independently of fixture BEAMs. Verify all participating
nodes and their supervisor, queue-manager, callback-store and adapter interfaces.

Current-source offline checks passed separately: runtime login 12 and editor 41
in `90416`, production-auth controls nine in `5127`, and agent-recovery 22 in
`60004`. The combined `90416` invocation itself timed out after the editor suite;
it is not an all-suite pass. The recovery fixture compiles with `TEST`, and its
upgrade case calls `code_change` on synthetic state. These checks are not an OTP
suspend/migrate/resume rehearsal, a downgrade test or live broker/node failure.

Loading code does not convert existing FSM state. The preceding conversion
accepted an old ringing offer without a matching Connect-ID, so its replies
could be ignored. The source now rejects legacy conversion unless the agent is
ready/paused with no member call object, member/queue/agent IDs, call start,
outbound calls or monitoring ownership. Unknown state names and record layouts
are also rejected. Accepted conversion preserves the full old record prefix and
adds the recovery timer only after validation; repeating a current-layout change
does not replace the timer or an active recovery probe.

Direct regression session `45037` reproduced unsafe state/layout acceptance
(two failed, 23 passed). After the fix, `99730` passed all 25 recovery tests under
the same 384-MiB, zero-network, 120-second guard. An earlier fixture compile
failure `70165` was a test syntax error, not a behavior result. These direct tests
do not supply an admission fence or prove a live rolling upgrade.
Production compile `68050` then passed all 63 ACDC modules with `-Werror`, no
`TEST` options/test exports and unchanged source/header hashes. Compilation used
private temporary output under the 384-MiB, zero-network guard; no running BEAM
was loaded or replaced.
Broader source regression `66281` passed all 48 agent, queue FSM, manager and
member tests against the same source, also isolated from live services.

The repository now includes a real OTP lifecycle fixture:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 120 -- /usr/bin/unshare --net -- \
  bash scripts/test-acdc-agent-otp-upgrade.sh
```

Session `17426` passed all 27 cases using the actual production FSM compiled
without `TEST`, real `gen_statem` and `sys:suspend/change_code/resume`. The fixture
injects explicit initial state through a local `proc_lib` bootstrap, bypassing
production initialization. It proves old-prefix and finite/infinite pause
preservation, exact timer destination, repeated-conversion idempotence, and
unchanged suspended state with no timer allocation on rejected conversions.
After a rejection, an explicitly test-only replacement with valid current state
precedes resume; malformed/old state is never dispatched into new handlers.

The portable runner checks production/test module paths, loaded OTP/provider
BEAM identities, source/header/compiler hashes and completion/signal status.
Evidence is retained at `/tmp/kazoo-acdc-otp-upgrade-run.pwSAjQ`. The same fixture
first passed privately in `95322`, retained at
`/tmp/kazoo-acdc-otp-upgrade-run.S82T4S`.

This closes the isolated OTP callback-lifecycle test gap, **not** installed-code
replacement, listener upgrades, startup, downgrade, admission control or a
coordinated multi-module live deployment. Those remain release gates.

The old FSM does not implement the reverse conversion. Listener record layouts are unchanged,
but their actual OTP callback is `gen_listener`, whose code-change callback does
not delegate to the client module.

Before activation, use an explicit admission/quiescence mechanism and a complete
work gate: zero FreeSWITCH/eCallMgr channels and pending originates, agents only
ready/paused with no call, queue FSMs ready with no call, zero manager queue sizes,
and a complete durable callback inventory with no nonterminal or unresolved work.
`current_call = undefined` alone is unsafe: outbound agents can return that value.
Neither an empty/partial AMQP report nor a one-time zero-channel snapshot prevents
new work from arriving between inspection and activation.

A drained restart must explicitly preserve runtime queue membership and pause
state; saved rosters and supervisor startup arguments can be stale. A suspended
state-preserving migration needs actual OTP migration and rollback rehearsal,
including queued messages and recovery timers. No generic tested ten-module
migration/admission executor currently exists. Never restore pre-upgrade state
snapshots after processing has resumed, and never load the old FSM over the new
tuple as an assumed rollback.

Only after matching backend acceptance should a new UI ownership/adoption plan
be made. Preserve config, capabilities, unselected apps, `/apis`, catalog revisions
and attachments. The historical UI adoption plan and two-module English loader
are not valid for this release. Passing a mocked browser test does not authorize
or prove live calls, authentication, native callback audio or cluster recovery.

Protected metadata receipt:
`/tmp/kazoo-acdc-coherent-readiness.oRiyXN/readonly-probe.json`, SHA-256
`c8cfc75b4944f48a0d7b77f1cc798f833704836cc46f7e6f0c47e4e5b369da4b`.
See also [agent recovery](acdc_agent_recovery.md) and
[installer regression acceptance](installer_regression_acceptance_20260906.md).
