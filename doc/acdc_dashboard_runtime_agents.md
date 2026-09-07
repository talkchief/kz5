# Live queue runtime-agent observation

Status: local source/protocol tests passed; **not deployed, not yet exposed in
the public live snapshot**. Historical reporting and ClickHouse remain deferred.

`applications/acdc/src/acdc_dashboard_agents.erl` reads only explicitly selected
account/queue/agent IDs. The caller must authorize those IDs before requesting
them. At most200 sorted unique agent IDs are accepted, with a one-second local
collection budget and at most50ms per process call. There is no global agent
supervisor scan, database read, AMQP publish, per-agent worker spawn or agent
command in this collector.

Each regular `acdc_agent_sup` registers its own local gproc name during init.
The dashboard obtains that supervisor's two current child PIDs with a bounded
OTP call. The new `acdc_agent_fsm:dashboard_state/2` observation returns only
account, agent, FSM state and listener identity. It is supported in all eight
FSM states and neither reads call details nor changes agent availability.
Listener queue membership and FSM identity/state are checked before and after
the read, then supervisor/child identities are rechecked. The internal instance
digest distinguishes observed process incarnations; it is not a public field.

These sequential reads are **not atomic** and cannot rule out an away-and-back
transition between observations. Missing processes/registration, timeouts,
changed identities or membership, malformed responses and exhausted budgets
produce unknown rows. Missing local registration does not mean logged out.
An observed `ready` state plus selected-queue membership does not verify SIP
endpoint reachability or prove that a call will be routed successfully.

Registration is best effort so observability cannot prevent agent startup.
Existing supervisors acquire the registration on a coordinated restart; loading
only the collector does not retroactively register them. A future cluster merge
must distinguish missing local observations from positive observations on other
nodes and must not sum replicas or turn conflicts into readiness.

## Evidence

Root validation64066 passed17 EUnit cases and compiled all three modified/new
production modules with `-Werror`, without TEST exports or live BEAM replacement.
Retained evidence: `/tmp/kazoo-dashboard-agents.XzPtgX`.

The tests execute actual supervisor init, all eight actual FSM observation
clauses, the collector, gproc registration/cleanup and gen_listener's call
transport. Local child-protocol processes stand in for real running agents;
this is not call-flow, broker, distributed-node or endpoint-reachability proof.
Cases include invalid/duplicate scope, empty/missing observations, all states,
nonmember-ready, identity mismatch, malformed/changing memberships, changing
FSM state, each process timeout, missing children, total budget and nonfatal
registration failure. Production source/dependency and artifact hashes are
checked; production module path/MD5/build options are checked before/after.

Reproduce under the standard guard in an offline network namespace:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 256 --reserve-mib 768 \
  --runtime-sec 120 -- /usr/bin/unshare --net /bin/bash \
  /opt/kz5/scripts/test-acdc-dashboard-agents.sh
```

Retained earlier failed runs: `POb6Sa` stopped at a missing test-runner include
path before assertions; `7kBw9f` hit the128MiB compiler cgroup limit. The include
path was corrected and the passing run used256MiB while preserving768MiB host
reserve. Development apps/ecallmgr were stopped only for test capacity and
restored by an EXIT trap. No database records were changed.

## Remaining integration

Add bounded authorized agent scope to the federated snapshot contract, validate
and merge source observations conservatively, document the public DTO in
OpenAPI, and replace the detail UI's supplemental global-status interpretation.
Coherently deploy/restart and verify real selected-queue login, pause, direct
call, queue call and logout transitions, missing-node behavior and permission
isolation. This source checkpoint does not close DASH-02/03.
