# ACDC/backend and UI upgrade readiness

## Current maintenance gap — 2026-09-09

The September6 installed-code observations below are historical, not the
current deployment state. Normal deployments since then superseded that old
runtime/UI hold. See `FOCUSED_CLOSEOUT_2026-09-09.md` for collected receipts.
Admission fencing, complete cluster drain, runtime-state preservation and
coordinated restart/rollback acceptance remain open.

### Latest native results

The subsequent main media installation and30-call/1800s soak also **PASS**,
with zero failures/errors/new cores, unchanged media process and empty final
native inventories. Current-media actual supervision passes all four modes,
including independent RTP privacy analysis and clean supervisor-only stop:
`/var/log/kazoo-monitor-acceptance-cwWdKC`. See `main_media_soak.md` and
`channel_monitor_acceptance.md`. Full cluster coordination remains open.

Main44 applications/controller promotion subsequently **PASS** onSeptember10:
normal installer source `4cd9953`, loaded/disk identity verification and actual
four-mode supervision with independent RTP privacy/cleanup evidence
`/var/log/kazoo-monitor-acceptance-WTrjrC`. See `main_dev_runtime_promotion.md`.
The old main44 promotion statements below are historical. Complete cluster
producer/broker drain and coordinated upgrade/rollback remain open.

September10 current checkpoint: cold restoration of both applications VMs now
passes, including finite/infinite pauses, empty membership and paired queue
inventories (`cold-agent-state-tbT2Rt/receipt.json` under the private lab root).
Two subsequent actual queue calls passed audio, but the independent strict
agent-drain check exposed retained terminal-leg placeholders on apps20.
The correction is source `8343d47`; normal private installers
`kz5-stage-install-kazoo-apps-16` and `kz5-stage-install-apps-peer-12` passed and
were collected. The strengthened healthy and apps-broker-partition actual-call
campaigns both passed with strict all-six-replica drain and independent audio/
cleanup verification (`...-5ZZRCj`, `...-e3Y5w1` on dev44).
See `acdc_listener_terminal_cleanup.md`. Main44 runtime promotion is not claimed.
Fresh four-mode supervision independently passed on this new installation:
`/var/log/kazoo-monitor-acceptance-CXndtt`, including post-call strict drain.
The earlier `...-bev21u` run remains evidence for the preceding runtime only.
Full cluster producer/broker drain and coordinated rollback
remain open. Earlier "current" build references below are historical receipts.

September10: initializer normal installs15/11 on `494ee28` and combined version2
inventory passed (two nodes/six replicas), receipt
`queue-inventory-1789002002127-97f89a97.json` under the private lab root. Durable
media normal install6 on `935d544`, all four real supervision/audio modes while
fenced, and two native media process restarts with marker restoration also pass.
See `maintenance_media_fence.md` for exact receipts and remaining scope. These
component passes do not close full cluster producer/broker drain or coordinated
rollback. Cold whole-VM agent restoration subsequently passed as recorded above.

Initializer source/installer/collector integration has18 production-process/status
tests and26 JavaScript guard/merger tests passing; see
`acdc_initialization_readiness.md`. Earlier combined native version1 snapshot
passed on `25be59c`: `queue-inventory-1788999277496-9ba05000.json`, two queues/
six replicas. It does not satisfy the newly enforced startup prerequisite.

Persistent local ingress fencing now has installer/startup integration and
actual systemd plus real-packet acceptance PASS. See
`maintenance_ingress_fence.md`. This is not the full cluster fence/drain.

Normal builds13/9 on `25be59c` are now terminal successful and collected:
`kazoo-apps-install-13.log`, `apps-peer-install-9.log` under the private lab root.
Native queue inventory on that installed revision also passed on both nodes:
`queue-inventory-1788998060332-c90cb0ed.json`. No build job remains active.
Actual paired paused-agent/queue correlation and full cold restore remain due.

Preceding deployment checkpoints (historical):

Both normal `e405aab` builds12/8 passed and were collected. The pinned installed
native queue collector passed for both nodes: one queue and three workers each,
receipt `/var/lib/kazoo5-install-lab/queue-inventory-1788996716962-6fdd7ae9.json`.
Collector SHA-256: `ca59f3858f5d6be9836b49720a4769a517cab2daa1a08cce4d7720479272d8a0`.
That run used the archived matching helper at
`/var/tmp/kz5-queue-observer-e405aab.fkrZvE/scripts/test-acdc-native-maintenance.cjs`.
It proves the idle queue observation on `e405aab`, not the newer paused-member
correlation, cluster admission fence or cold restart/rollback.

**Current normal builds13/9** target
`25be59c1c67a13b4a1df15b5b5e20d7a3b2a48d4`, including the busy/paused correction:
`kz5-stage-install-kazoo-apps-13` and `kz5-stage-install-apps-peer-9`.
Start log: `paused-drain-deploy-25be59c-1788996821818.log` in the private lab.
Fresh admission confirmed zero media/callback work and all6 owned replicas
ready. Collect these exact jobs before native combined queue/agent snapshots.
Main44 `/opt/kz5` is synced; this does not deploy its main runtime. Do not change
either private compiling checkout or start duplicate installers.

Complete native agent-cohort merging passed in
`/var/lib/kazoo5-install-lab/agent-inventory-merged-1788994874158.json`:
all6 replicas across both expected nodes, agreeing epochs, effective states,
memberships and document revisions. It explicitly reports no admission fence
or complete cluster drain.

### Queue drain observations — source tested; native acceptance pending

**Latest correction:** paused agents also publish the manager's busy flag.
Rejecting every busy flag incorrectly blocks maintenance of intentionally paused
queues. The focused test fails against retained production
`/tmp/kazoo-acdc-maintenance.fLiIkJ/acdc_queue_manager.beam` and passes with the
correction. All138 production observation/restore tests now pass in
`/tmp/kazoo-acdc-maintenance.TvPQ6U`;16 journal/merger cases pass.

The manager now returns `busy_agents` as unresolved identities, never an active
call or safe-pause assertion. `mergeQueueSnapshots` correlates the complete
same-epoch queue and agent inventories: each busy member must have observed
paused replicas with unexpired finite or infinite pause and actual membership
in that queue. Missing/ready/expired/nonmember agents are refused. Queue document
revisions and busy membership must agree across replicas; malformed, stale,
incomplete and false-fence snapshots refuse. This still does not prove broker,
durable callback, producer/media drain or admission closure. Builds12/8 target
the earlier `e405aab`; do not change their compiling inputs to this correction.

Internal `maintenance_state/2` covers the queue FSM, private listener, shared
listener and manager. Ready FSMs must have no call/winner, outstanding timer,
pending options, callback context, attempted agents or bridge proof. Private
and shared listeners must hold no call/delivery ownership. Managers must have
no current members, announcements, cancellation ownership or ringing flags;
busy flags require the independent actual-agent correlation described above.
Missing identities/processes are refused. These operations never clear state,
acknowledge work, publish events or expose call payloads. A regression proves
that ready/current_call=undefined alone does not certify drain.

All134 guarded production maintenance cases pass, including54 new queue cases,
retained at `/tmp/kazoo-acdc-maintenance.fLiIkJ`. FSM checks run real OTP
processes; listener/manager/shared checks exercise production callbacks with
no external effects. Source hashes remained unchanged throughout.

`escript scripts/kazoo-maintenance-queues.escript --snapshot LOCAL_BIND_IPV4`
collects all current queue supervisors/workers with strict paired identities,
drained observations, consuming listeners, broker queue names and document
revisions. It refuses incomplete/restarting children instead of filtering them
out, requires no announcement children, and rechecks supervisor inventories
and node epochs. Aggregate collection is bounded to120seconds and5000 workers.
It uses the protected local cookie; output belongs in private journal storage.
Invalid arguments compile and refuse without establishing distribution.

The repeatable private-lab native check is
`node scripts/test-acdc-native-maintenance.cjs --queue-inventory`. It uses the
same owned-guest, shared acceptance lock and collected installed-source checks
as the finite-pause test, without making calls or restarting services. Each
attempt retains private success/failure receipts and logs. Run only after both
normal builds are collected. Native acceptance is pending. Neither collector
proves broker ready/unacked counts, durable callback completion, asynchronous
startup/producer completion or future admission closure; these and coordinated
cold restore/rollback are still required.

### Completed finite-pause native checkpoint

**Current queue-observer native deployment:** private normal installs on
`e405aab535baa8250d9325171b78fd25705eb6aa` are running as
`kz5-stage-install-kazoo-apps-12` and `kz5-stage-install-apps-peer-8`.
Both native systemd jobs were verified active/running with nonzero MainPID.
Start log: `queue-drain-deploy-e405aab-1788995943320.log` in the private lab.
Collect the exact jobs; source synchronization is not deployment and current
`Result=success` while running is not terminal success. Only after collection
run the new native queue inventory check. No production/imported-company
mutation or main44 runtime deployment occurred.

Both normal `4fac43d` installations passed and were collected:
`kazoo-apps-install-11.log` and `apps-peer-install-7.log`. The unchanged guarded
native finite-pause restore regression now **PASSES** on both nodes, receipt
`/var/lib/kazoo5-install-lab/agent-restore-1788994643840-7170b3ed.json`.
Both replicas were paused before supervisor restart, both restored the original
absolute deadline without extension and retained runtime queue membership;
the two final states were `paused`. Restart/restore elapsed5094ms, native exit0,
and independent cleanup verified both agents ready with original membership,
active consumers and no reported call legs. Executed fixture SHA-256:
`afb3445aa210b8bcaf03d3d2fc7d0b78d50335b43584fb759b467dea107915ac`.
The two earlier failed restore receipts and unassisted pause-loss baseline remain
failed. This passes the native finite-pause restore primitive, not whole-VM
restart, infinite-pause/empty-membership native acceptance or the full coordinator.

The complete-current-agent read-only collector also passed on both installed
nodes: `/var/lib/kazoo5-install-lab/agent-inventory-1788994694953.json`.
It observed all3 current workers per node (6 replicas), matching FSM/listener
identities, runtime membership/bindings and document revisions. All were ready.
The receipt explicitly does not claim complete cluster drain or admission fencing.

**Collected native jobs:** source `4fac43d` (absolute deadline correction included)
was installed normally in the two private apps guests as
`kz5-stage-install-kazoo-apps-11` and `kz5-stage-install-apps-peer-7`.
Both were started after zero private media and ready test replicas
were checked, then collected successfully before the passing
`node scripts/test-acdc-native-maintenance.cjs --live` attempt. Earlier builds10/6
passed, but their two restore attempts failed as documented below. Do not confuse
source synchronization or passing offline tests with a native restore pass.

The local-node read-only collector is
`escript scripts/kazoo-maintenance-snapshot.escript --snapshot LOCAL_BIND_IPV4`.
It uses the local protected cookie and installer-standard short node name,
requires a local bind address, and observes every current agent supervisor
(maximum5000,120-second aggregate collection deadline). Each entry requires
matching drained FSM/listener identity, active consumption, exact runtime queue
bindings and a readable saved user-document revision. Stable worker inventory
and process/creation node epoch are rechecked at the end. Output contains only
checkpoint fields and document revisions, not user documents, call records or
credentials; retain it in private coordinator storage.

This collector does not claim that asynchronous startup tasks have completed,
that all queues/callbacks/media are drained, or that future admission is closed.
Those are separate coordinator prerequisites. It explicitly returns
`complete_cluster_drain_proven:false` and `admission_fence_proven:false`.
Source-host invalid-argument compilation/refusal and installed native inventory
collection both pass; the latest receipt is recorded above.

The journal now records `fencing` intent before any fence action and provides
an explicit pre-activation abort path that requires `verified_abort` before
reopening. Its snapshot merger requires every planned apps node, matching node
epochs, fresh collection (no more than30seconds old or2seconds in the future),
complete document revisions and agreement between replicas' effective states,
memberships and document revisions. Expired pauses are compared as ready but
their original deadlines remain in the checkpoint. It never promotes an agent
inventory into full-drain/fence evidence. All12 journal/merger tests pass.
This remains coordinator support code, not an integrated maintenance executor.

### Restore primitives implemented; native coordinated acceptance still open

The production FSM now exposes the internal `maintenance_restore/3` operation.
It accepts only an identity-matched ready checkpoint or a paused checkpoint
with an absolute Unix-millisecond expiry (or explicit `infinity`). It refuses
active/residual work and malformed checkpoints without changing state or timers.
Expired pauses restore ready; repeated restoration cannot extend the original
deadline. A notification failure retains the local restored pause and reports
`notifications_queued:false`; this is not permission to reopen admission.

The listener's internal `maintenance_restore/3` accepts identity-matched runtime
queue membership. It checks the paired, drained FSM and derives availability
from its actual state. It restores empty membership without the ordinary
last-queue logout, reasserts retained bindings, and avoids fabricated workforce
login/logout events. Bindings are asynchronous: `bindings_queued:true` is not
broker acknowledgement. A partial binding/publication failure explicitly returns
`membership_restore_uncertain`; retain the fence and recover from the protected
checkpoint, never assume rollback or blindly retry/un-fence.

Source-host guarded production compilation and all79 observation/restore cases
passed, evidence `/tmp/kazoo-acdc-maintenance.lpGiPi`. This includes43 observation
cases,26 real FSM/timer restore cases and10 production listener callback cases
(external FSM/broker interactions mocked). Earlier FSM-only69-case evidence is
`/tmp/kazoo-acdc-maintenance.cJLp7K`. These are not native restart results.

Required coordinator ordering remains: close all admission, prove complete drain,
durably capture actual per-node agent inventory/membership and absolute pauses,
activate the matching release, restore FSM then listener, verify bindings and
availability across replicas, and only then reopen admission. Generation/replay
protection, full cold restart and rollback acceptance remain unfinished. These
primitives have no public HTTP route and do not themselves supply that fence.

Candidate `ed4d7be` is pushed to master and synced to dev44 `/opt/kz5`.
Its27 existing recovery regressions also pass. Normal isolated installations
are running as `kz5-stage-install-kazoo-apps-10` and
`kz5-stage-install-apps-peer-6`; do not treat an in-progress build as deployed.
The private media inventory was empty and the two baseline agent replicas were
ready with their original queue membership and consuming listeners at admission.
Collect these exact jobs before any further restart test.

The retained baseline fixture now accepts `--live --restore` to test the new
native primitives after those normal builds finish. It captures actual paired
FSM/listener checkpoints, restarts only the fixed agent on both lab nodes,
restores the original absolute pause expiry and runtime membership, then checks
the native consumer/binding registry and unchanged deadline. The original
`--live` mode remains the unassisted baseline; its failed receipt is unchanged.
This finite-pause regression uses memory-only checkpoints and is not the durable
maintenance coordinator. Run it under the host acceptance lock with independent
zero-media/zero-callback admission; do not execute it against an active build.

The repeatable host wrapper is `node scripts/test-acdc-native-maintenance.cjs
--live`. It only admits dev44's owned private guests, verifies both builds have
been collected successfully, holds the existing shared acceptance lock throughout,
requires zero private media/callback tickets and ready fixture agent replicas,
and keeps its native output and result in private `agent-restore-*` receipts.
It does not mutate production or the imported company, nor claim a full fence.
Source-host invalid arguments refuse before any remote work. The inherited-file-
descriptor lock was tested against an independent competing lock acquisition.

`scripts/kazoo-maintenance-journal.cjs` supplies the coordinator's durable phase
journal. It stores exclusive, fsynced, owner-only append-only revisions in a
private generation directory, validates the manifest and actual-agent checkpoint
shape, and verifies the previous-record hash chain on read. Incomplete writes,
revision gaps, unsafe file permissions/links, stale revision requests and invalid
phase transitions refuse; an interrupted write is not deleted or silently
replaced. Finite absolute deadlines and infinite pauses survive serialization.
Restoration is allowed by this journal only in `restoring` or
`restoring_rollback`, never after verification/reopening/completion. Rollback
requires its own verification phase. Eight isolated filesystem/state-machine
tests pass via `node --test scripts/test-kazoo-maintenance-journal.cjs`.

This journal is a library, not yet wired into the installer. Receipt hashes
identify external evidence; they do not prove that admission is closed. The
coordinator must hold its external lock throughout each action, validate current
node epochs and the real fence before restoring, and retain the full drain/action
receipts. Do not treat an accepted JSON document or a green journal test as native
cluster upgrade/rollback acceptance.

Both normal `ed4d7be` builds have now passed and were collected:
`kazoo-apps-install-10.log` and `apps-peer-install-6.log` in the protected lab
directory. The first actual restore regression **FAILED**, receipt
`/var/lib/kazoo5-install-lab/agent-restore-1788993197384-eb7e2734.json`:
both replicas were paused, the primary restore/deadline/membership check passed,
but no second restore verification was recorded. Native exit1; independent
cleanup checks confirm both fixture replicas ready with original membership,
consuming listeners and no reported call legs. Executed fixture hash
`9d796bc0fdd014c57422717a1540501d8ae2d6e4e3298fc201773788907f6369`.
Safe fixed-step diagnostics have been added to identify the failing peer phase;
no raw call data or RPC results are printed. The failed receipt remains unchanged.

The diagnostic repeat also **FAILED**, receipt
`agent-restore-1788993306307-5648da06.json`, at the primary `deadline_check`;
both replicas again passed independent cleanup. A new500-iteration production
FSM regression reproduces a saved deadline being extended by the relative-timer
implementation: the full suite reports79 passes/1 failure, and the isolated
`deadline_sampling` case fails independently against the retained old production
BEAM in `/tmp/kazoo-acdc-maintenance.eIdqXk`.

The source fix maps the saved Unix deadline to absolute monotonic time using the
native-precision time offset, rounds down only after conversion, and uses an
absolute timer. This avoids adding the time spent between calculating a relative
delay and starting it. See the official
[Erlang absolute timer contract](https://www.erlang.org/docs/27/apps/erts/erlang.html#start_timer/4).
The unchanged native deadline check must still pass after normal deployment;
the offline reproduction alone does not close the native restart gate.
After the absolute-timer correction, all80 production observation/restore cases
pass, including the new500-iteration regression. Evidence:
`/tmp/kazoo-acdc-maintenance.ivmQWs`. No running BEAM was hot-loaded or state
force-edited during these tests; the private installed runtimes still require
normal redeployment of this correction.
All27 existing agent-recovery regressions also pass with the correction.

Native run admission now distinguishes checkout source from successfully
installed source. The role/peer collectors record `installedSource` only after
the actual installer exits successfully and the service is active/enabled.
The restore runner requires that installed revision to match both current guest
source pins. A source sync alone cannot be counted as deployment. Three guard
tests and the existing peer scope/reboot regressions pass. Older lab state without
that field must complete a normal install/collection; do not fabricate the field.

### Native restart baseline: pause loss reproduced

Both isolated apps installations on `b6d1a04` passed: primary
`kz5-stage-install-kazoo-apps-9` and peer `kz5-stage-install-apps-peer-5`.
The latter's retained log is
`/var/lib/kazoo5-install-lab/apps-peer-install-5.log`.

The explicit finite-pause baseline then **FAILED** on both actual nodes:
both replicas of the single owned synthetic agent were paused for45seconds;
`acdc_agents_sup:restart_agent/2` recreated their supervisors and both returned
ready. The complete native log finished5597ms after host admission, well before
that pause could legitimately expire. This is a real pause-loss reproduction,
not a missing status response. Main44 services/customer accounts were untouched;
the host acceptance lock was held, private media was empty, and the sole fixture
queue had zero callback tickets before mutation.

Evidence on dev44:

- `/var/lib/kazoo5-install-lab/agent-restart-baseline-1788990948224.json` and `.log`;
- executed fixture SHA-256
  `5009d24047500897a3f4f7349d1d7fac6898d099e7c9b8719e3a41abd95f48bf`;
- independent after-check
  `/var/lib/kazoo5-install-lab/agent-restart-baseline-cleanup-1788991109162.json`:
  all6 replicas ready, consumers active, no reported call legs and original
  queue membership intact. This confirms after-state, not pause preservation.

The original baseline's strict cleanup observation was refused; it is retained
as such. Source inspection and a separate before-failing regression exposed a
consumed `sync_response_timeout` reference retained in the ready FSM. That
reference is now cleared when its timeout is handled.27 recovery cases and43
production maintenance observation cases pass after the one-line behavior fix;
retained latter evidence `/tmp/kazoo-acdc-maintenance.dGTCcC`. This source change
is not yet deployed and does **not** fix pause loss by itself.

The baseline source is
`scripts/test-fixtures/distributed-lab/agent-restart-baseline.escript`; its next
run also records bounded elapsed time explicitly and fails on unverified cleanup.
It is an opt-in fixed-agent reproduction, not a generic restart/upgrade executor.
Run only under the host acceptance lock after independent media/callback
admission and ownership checks. It uses finite pauses, refuses unrelated/active
states, and never re-logs agents or kills calls to manufacture a pass.

Next implementation must capture runtime membership and finite/infinite pauses
under a complete cluster admission fence, keep admission closed across restart,
restore the checkpoint before reopening, and validate rollback in that same
window. Do not inject a reusable pause into supervisor startup arguments: a later
automatic child restart could reapply stale state after an operator resumed the
agent. Do not restore a checkpoint after new work or operator changes are admitted.

Native `acdc_agent_fsm:maintenance_state(Pid, Timeout)` now returns either an
error or an allowlisted observation containing account/agent/listener identity,
ready/paused state and the remaining pause in milliseconds. Finite pauses also
include `pause_until_unix_ms`; expired timers refuse observation until the FSM
processes their transition. Infinite pauses remain explicit `infinity`.
Active states, residual call/offer IDs, outbound calls, monitoring ownership,
pending state updates/recovery probes and sync/wrapup timers refuse readiness.
No call metadata, endpoints or private record contents are returned.

`acdc_agent_listener:maintenance_state(Pid, Timeout)` independently observes
the current runtime queue membership and matching FSM identity. It refuses
residual listener calls/originates, pending synchronization and malformed or
duplicate memberships. Saved user rosters and supervisor startup arguments are
not substituted for runtime membership. Empty membership is preserved as empty.

These are read-only native primitives, **not an admission fence, public HTTP
API, durable checkpoint, restore operation or restart authorization**. They do
not claim the pause has survived a cold restart. A caller must establish the
whole-cluster fence, match both observations to the same live supervisor/FSM/
listener, prove the complete work inventory is drained, and keep admission
closed through preservation, activation and post-checks. Capture timestamps
require verified host clocks; a future restore must subtract elapsed time and
must not restart a full finite pause from its original remaining duration.
Never reuse a snapshot after work has resumed. Existing recurring call-check
timers are housekeeping, not work; an in-flight recovery probe is work.

Guarded production compilation without `TEST` and43 isolated checks passed:
27 real `gen_statem` observations (exact state/timer-reference preservation),
plus16 production listener callback checks (exact returned state unchanged).
Evidence: `/tmp/kazoo-acdc-maintenance.iUgeHD` on the source host. This is not
native broker/startup or cluster restart acceptance.

Source `b6d1a04` was pushed and synced to dev44 `/opt/kz5`. Normal primary
installation passed as `kz5-stage-install-kazoo-apps-9`, protected log
`/var/lib/kazoo5-install-lab/kazoo-apps-install-9.log`. Installed-code read-only
observations then passed for all3 actual fixture agents: matching FSM/listener
identities, ready state, zero pause and exact runtime membership. Receipt:
`/var/lib/kazoo5-install-lab/agent-maintenance-primary-1788990470794.json`.
This did not test pause restoration. Peer `kz5-stage-install-apps-peer-5` has
since passed too; the subsequent explicit pause-restart baseline failed above.
Private media was verified at zero channels before these jobs. Main44 services
are unchanged; its separate Blackhole soak has completed successfully.

The read-only native adapter for the next installed-code observation is
`scripts/test-fixtures/distributed-lab/agent-maintenance-rpc.escript`. Copy it
outside a compiling checkout to `/var/lib/kazoo-stage/` in the exact owned apps
guests. It only admits those two guest hostname/IP pairs, the fixed synthetic
company and an enabled regular user inside it. It matches supervisor/FSM/
listener identities and consumer readiness, and emits only allowlisted JSON.
It has no restart/pause/restore operation and explicitly reports
`admission_fence_proven:false`. Source-host invalid-argument execution compiles
and refuses without connecting. Native primary observation passed as above;
fenced restart/restore acceptance remains due. The pause-loss baseline above
must pass after an actual restoration implementation before closing this gate.

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 120 -- /usr/bin/unshare --net -- \
  /usr/bin/bash /opt/kz5/scripts/test-acdc-agent-maintenance.sh
```

## Historical pre-deployment investigation — 2026-09-06

The current source and freshly tested Monster bundle are not yet a deployed,
coherent release. Read-only probe `29950` confirmed unchanged service identities
and 27 source/BEAM/helper identities. It performed metadata RPC only: no load,
purge, state conversion, account mutation, restart or deployment.

The new `cb_acdc_agent_queue` is absent from the installed runtime. The installed
`acdc_callback_recovery_io` lacks `observe_channels/2` and was not loaded.
The agent FSM still uses its preceding 25-element state tuple; current source
uses 28 elements. The editor is also an older installed revision. Existing old
code slots for the editor and Gemini mapper must not be force-purged.

The coherent candidate boundary now includes eleven production modules:

- `cb_acdc_agent_queue`, `cb_agents`, `cb_acdc_queue_editor`;
- `acdc_agent_handler`, `acdc_agent_listener`, `kapi_acdc_agent`;
- `acdc_agent_fsm`, `acdc_callback_recovery_io`, `acdc_queue_listener`,
  `kapi_acdc_queue`;
- `cf_acdc_member`, including the subsequently reproduced and fixed
  [callback feedback Request-field crash](callback_feedback_request_crash.md).

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

This closes the isolated OTP callback-lifecycle test gap, **not** live installed-code
replacement, listener upgrades, startup, downgrade, admission control or a
coordinated multi-module live deployment. Those remain release gates.

## Isolated actual two-version replacement

Private session `66980` additionally passed four fresh-VM cases using actual
legacy and current production BEAMs, compiled without `TEST`. The exact legacy
source came from local Git commit
`83194e7252f84ce72ce07c72f03c3956acdeb9d4` (FSM SHA-256
`2424cf2f392edbde02bbdd3bceeccf436630f98ed1ded129813ba7125fdebf30`);
that run's current source came from `6639f367f5ad13284f3997e085d89dfb7827a2a2`
(FSM SHA-256 `6fbe5f6e000d93ef6324c432592ec1bf667cbe380e7ee88b8453d5b9cbecb23c`).
Evidence remains at `/tmp/kazoo-acdc-two-version-run.bDglRT`: terminal exit zero,
explicit completion, four case results and unchanged source/dependency inputs.

Each VM runs a real legacy ready/paused status callback, suspends the process,
replaces the actual module using non-purging `code:atomic_load/1`, and verifies
both version paths/MD5s. The old-code slot must be absent before replacement;
there is no third load or purge. Loading alone must leave the legacy tuple
unchanged. Successful `sys:change_code` preserves the complete old prefix and
pause timer, creates the new timer in the correct process, and remains
idempotent before actual current-code resume/status checks. Residual-work and
wrong-tag cases are refused with unchanged suspended state and no new timer;
they are never resumed or reverse-loaded, only cleaned up as private fixtures.

The same four-case proof is now available through a repository-relative retaining
runner:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 180 -- /usr/bin/unshare --net -- \
  bash scripts/test-acdc-agent-two-version-upgrade.sh
```

The historical Git objects must already be available locally; a shallow checkout
or source export without them fails closed. The runner never fetches them.
Prepared local Erlang/Lager libraries and generated ACDC includes are required,
but an installed/live FSM BEAM is not. If an installed BEAM exists, it is only a
preservation input. Each run snapshots and pins the **current working-tree** FSM
and header; its recorded HEAD is context, not a substitute for source hashes.
Both versions use the current pinned compiler/common dependencies, so this is
not a recreation of the historical production build environment. The only
fixture portability change from the accepted private version is an informational
current-version tag; the four assertions and loading sequence are unchanged.
The promoted runner's separate guarded session `41876` passed all four cases,
with terminal exit zero, explicit completion and unchanged inputs. Evidence is
retained at `/tmp/kazoo-acdc-two-version-run.uf5Yzq`. Its final source SHA-256 is
`0671f0715751cd547ded4d309532f9cdfcf66637f67b1f32fbe4c2c02bb20994`;
the fixture SHA-256 is
`3a3f99574dfa953c75823a06eaf438a69b7a3f77987c60c8db88747998c37f4b`.
Both the initial current-source snapshot and aggregate input hashes are checked
on exit, preventing a change between those captures from being accepted.

This closes the isolated actual old-to-new module replacement gap. The bootstrap
still injects explicit state instead of running production initialization. It
does **not** establish live installed-code replacement, listener upgrades,
admission fencing, active-call migration, multi-node/coherent-module rollout, or
a production rollback procedure.

## Remaining activation gates

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
including queued messages and recovery timers. No generic tested multi-module
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
