# Listener dispatch completion during maintenance

## Source status — September 10, 2026

Implemented and tested in private OTP processes; **not deployed or natively
accepted yet**. This addresses one missing prerequisite for point 4, not the
complete producer fence or coordinated upgrade/rollback executor.

The native RabbitMQ inventory can be empty while Kazoo is still executing a
responder. `gen_listener:handle_info/2` acknowledges auto-ack deliveries before
dispatch. `distribute_event/4` launches asynchronous responders, and
`spawn_handle_event=true` introduces an additional detached dispatcher. A
broker-side message count cannot represent the lifetime of those processes.

The required root-kz5 installer patch is
`scripts/patches/kazoo-listener-dispatch-inventory.patch`, applied after the
existing secondary-queue recovery patch. Its target is the pinned external
core source `core/kazoo_amqp/src/gen_listener.erl`. No nested repository commit
is required. Normal applications/controller builds apply it before compilation.
Use a normal cold VM restart; do not hot-load a changed listener record layout.

## Behavior

- Listener-owned asynchronous workers are monitored until termination.
- Detached dispatchers retain their own child-monitor group until every
  responder finishes. They do not synchronously call their owner to register
  children, and they do not inherit the owner's existing monitor map.
- A failed responder, or a killed dispatcher with potentially surviving child
  work, leaves a nonzero failure count. Maintenance must refuse and investigate;
  there is no automatic clear or assertion that the original job succeeded.
- Existing callback routing, broker acknowledgement timing and unrelated DOWN
  delivery remain unchanged. No message body or caller details appear in the
  dispatch observation.

Internal observation on a known local listener PID:

```erlang
gen_server:call(ListenerPid, maintenance_dispatch_state, 2000).
```

This is a `gen_server` control request, not `gen_listener:call/2` (which forwards
to the application callback), and not a public HTTP endpoint. The response has
`pending_dispatches`, `failed_dispatches`, `admission_fence_proven=false` and
`complete_cluster_drain_proven=false`. Pending counts represent top-level work
or detached groups, not a total count of every descendant process.

The normal agent snapshot, queue snapshot and agent-restore helpers now require
zero pending/failed dispatches before and after relevant listener observations.
Missing support, timeouts, unknown shapes and false claims of complete drain
refuse. Old runtime/new helper combinations therefore refuse safely: deploy the
required core patch with the helpers, not a helper-only update to old VMs.

## Verification

Run in a private network namespace:

```sh
unshare --net timeout 90 bash scripts/test-gen-listener-dispatch.sh
unshare --net timeout 60 node scripts/test-maintenance-dispatch-guards.cjs
```

The first runner compiles the actual production `gen_listener` without test
exports and exercises its callbacks in real OTP processes. Only external AMQP
transport is controlled. It checks synchronous and asynchronous delivery,
federation, acknowledgement before a blocked responder completes, multiple
responders, failures, a killed dispatcher, independent groups, unmatched events
and foreign DOWN delivery. All 12 cases fail on the preceding source without
the observation and pass with the patch. Fresh pinned source plus the required
patch sequence reproduces the current target exactly. Evidence:
`/tmp/kazoo-dispatch-maintenance.aRNSq9` on the source host.

The actual three collector predicates compile and pass three valid cases and
36 refusals: `/tmp/kazoo-dispatch-guards-irsRph`. Existing restore validation
passes five valid, 13 invalid checkpoints and five private-file guards:
`/tmp/kazoo-maintenance-restore-tests-8M2AUj`. The prior secondary-queue regression
also passes: `/tmp/kazoo-listener-secondary.mx14UK`.

The first development of the test itself sent its acknowledgement notification
to EUnit's setup process rather than its test process; two cases failed. That
fixture error was corrected before the before/after acceptance. It was not a
runtime acknowledgement defect.

## Remaining acceptance and limits

### First native rollout admission refused — no build started

Source `a12fc2d` was pushed to master and synced to dev44 `/opt/kz5`.
Unit `kz5-dispatch-apps-rollout-20260910` exited 1 during read-only preflight,
before source synchronization into either private apps guest or either installer
launch. Both remain on installed source `8343d47`, with admission open. Private
rollout receipt/log: `/root/kz5-dispatch-rollout.BDPDJNag/receipt.json` and
`run.log`. This attempt is FAIL, not a deployment or an installed-code pass.

Independent native observations found all six agents ready with their original
queue membership and zero private media channels, but queue inventories refuse:

- Apps14 has one queue worker in `connecting`, retaining its member call,
  delivery and winner; its bridge context has `proof_status=unresolved` and no
  active probe/timer. The two other workers are drained.
- Its manager retains one current member and three cancellation markers.
- Apps20's three queue workers are drained, but its manager also retains three
  cancellation markers.
- A fresh `acdc_callback_recovery_io:observe_channels/2` query for the exact
  retained caller returned complete `terminated` evidence from both advertised
  eCallMgrs. No timer or state was changed by this observation.

Read-only, field-name-derived runtime summaries and the fresh proof are retained
in that rollout directory as `queue-state-172.30.253.14.txt`,
`queue-state-172.30.253.20.txt` and `ordinary-proof-observation.txt`.
No fake hangup, state replacement, force-ack, restart or redial was used.

**Next source repair:** reconcile an ordinary queue bridge-proof timeout after
its initial deadline without rerouting a possibly connected caller; only fresh
complete terminal evidence may release owned queue work. Also reconcile manager
cancellation markers against delivery ownership without allowing a delayed
cancelled call to ring. Add before/after regressions and native recovery of this
retained synthetic case, then retry the deployment admission. Do not equate
zero FreeSWITCH sessions alone with complete broker/queue cleanup. This is the
private ordinary-call fixture, not the separate historical callback ticket.

Next: normal deployment to the owned private applications pair, native paired
queue/agent inventory and cold checkpoint restoration, then actual SIP/RTP
follow-up. Controller/main promotion must be explicit; synchronizing `/opt/kz5`
alone does not deploy BEAM code. Existing actual-call results predate this patch.

This observation covers the asynchronous dispatch started by `gen_listener`,
not arbitrary processes spawned by application callbacks, targeted-PID delivery,
scheduled jobs, all node mailboxes or external publishers. It does not stop
future admission. Complete producer coverage, stable runtime/broker/durable
reconciliation under an enforced barrier and tested cohort activation/rollback
remain required. Do not label this component a complete maintenance gate.
