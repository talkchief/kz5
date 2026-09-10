# ACDC initializer completion prerequisite

## Why this is required

The earlier `acdc_init:start_link/0` returned `ignore` after spawning work.
Agent restoration and datastore retries spawned more untracked processes.
Consequently a stable current supervisor inventory could be observed while
additional agents or queues were still scheduled to start. Some query/start
failures also ended the initializer without proving the intended work finished.
That cannot support a maintenance checkpoint or a successful startup assertion.

## Source correction

`applications/acdc/src/acdc_init.erl` is now a registered, supervised gen_server.
It owns linked, monitored initialization jobs, including nested agent jobs and
delayed retries. Child work is registered before its parent can finish. Public
initialization entry points keep their synchronous return behavior for their
own work; their asynchronous descendants remain accounted for. The owner stays
alive after completion instead of returning `ignore`.

Normal owner termination stops its jobs; abnormal owner death also propagates
to the linked jobs. Failed jobs are retained as failed readiness, not discarded
as an empty inventory. Missing views or rejected supervisor starts therefore
cannot turn into a ready assertion. Account-discovery errors retry under the
same ownership; first database creation is followed by another discovery read.

Initialization also uses the new strict agent-status lookup. The legacy lookup
converts current/previous datastore errors to `unknown`, which would silently
skip an agent and falsely count the startup job as successful. The strict path
retains those errors and rejects malformed status values. Verified empty
history or an absent previous month still means genuinely unknown. Existing
non-initializer callers retain their prior API behavior; their compatibility is
covered explicitly by the strict/legacy regression comparisons.

The internal Erlang interfaces are:

- `acdc_init:maintenance_state(Timeout)` returns an initializer identity,
  generation and revision only when all owned jobs finished successfully.
  Otherwise it returns initialization_pending or initialization_failed.
- `acdc_init:startup_status()` returns ready, pending, failed or unavailable.
  The normal installer now checks this native status after application/broker/
  stats readiness. Failed jobs refuse installation success immediately;
  pending/unavailable is bounded by KAZOO_START_TIMEOUT. No loading or repair
  is performed by the verifier.

These are internal node-maintenance calls, not new Crossbar HTTP endpoints.
After a failed job, fixing the underlying cause alone does not erase failure
evidence in the current owner. Re-initialization/restart must be coordinated
with the maintenance fence and reconciled inventory; never treat a source sync
or a cleared process list as recovery proof.

## Snapshot integration

Both read-only collectors now emit schema_version2. They require a ready,
unchanged initializer token before and after their observations. The token is
a SHA256 of the initializer identity/generation/revision, with no user payload.
The combined merger requires matching queue/agent tokens for each node and
retains them in its output for later revalidation. Missing tokens, version1
inputs and changes between the two observations are refused. The queue
collector also requires the manager's asynchronously declared secondary queue
to appear in its broker inventory; primary consumption alone is insufficient.

This proves only initializer completion plus the collectors' existing checks.
It does not prove that all external broker requests, callback workers, media
origination or other producers are drained or fenced. The coordinator still
must establish those independent conditions and revalidate tokens before acting.

## Evidence and rollout

- **Native rollout and version2 acceptance PASS:** corrected jobs15/11 on
  `494ee28` exited0 and passed collection/service checks. Their logs are
  `kazoo-apps-install-15.log` / `apps-peer-install-11.log`. The new combined
  inventory passed both nodes/six agent replicas with schema_version2 startup
  tokens: `queue-inventory-1789002002127-97f89a97.json` under
  `/var/lib/kazoo5-install-lab`. This supersedes the pending rollout statements
  below. It is not proof of the separate full cluster fence/drain/restore gate.

- Corrected source `494ee28` is now in normal private deployment, exact units
  `kz5-stage-install-kazoo-apps-15` / `kz5-stage-install-apps-peer-11`.
  Actual active/running MainPID506156/363012 observed after guarded admission.
  Protected start log `init-readiness-deploy-494ee28-1789001079511.log` is under
  `/var/lib/kazoo5-install-lab`. Collect these jobs before version2 acceptance;
  do not edit/sync compiling inputs or relabel their launch as a pass.

- Normal builds14/10 on `c6e0c36` failed before deployment (exit2). The production
  compiler's warn_missing_spec rejects all six new gen_server callbacks without
  specifications. The focused runner originally lacked that flag; it now uses
  the production warning flags when compiling production modules and reproduces
  this exact failure. Callback specifications are added in source. Failed logs
  are retained on dev44 under `/var/lib/kazoo5-install-lab` as
  `kazoo-apps-install-14.log` and `apps-peer-install-10.log`. Corrected production
  compilation and all18 tests PASS (`/tmp/kazoo-acdc-init.3egwot`, input hashes
  unchanged). Normal deployment must pass before claiming runtime readiness.

- 18 production initializer/status tests PASS in
  `/tmp/kazoo-acdc-init.SpfhvZ`: delayed agent work/retries, discovery failure,
  fresh database re-read, rejected startup/missing view, revision change and
  normal/abnormal owner shutdown, strict datastore-error handling and legacy
  status API compatibility. Dependencies are controlled test doubles;
  these results are not presented as live broker/call acceptance.
- Four actual installer-function tests, five native-runner guard tests and17
  journal/merger tests PASS, including per-node startup-token mismatch rejection.
  Main/modular installer regression suites and both collectors' compilation/
  invalid-argument rejection also pass in a network-isolated validation guard.
- Earlier native combined inventory on installed `25be59c` PASS:
  `/var/lib/kazoo5-install-lab/queue-inventory-1788999277496-9ba05000.json`,
  two queues/six agent replicas. Its version1 evidence is historical and **does
  not pass the newer initializer-completion gate**.

Normal applications deployment on both private nodes and a version2 native
combined snapshot are still required. Do not use the new collectors against
the old installed runtime and call their expected refusal a deployment pass.
No main44 runtime hot-loading is authorized or needed for this change.

The preceding deployment started on source
`c6e0c36532f5242fb5d9ef6d0b0391baaf9029b2` after zero media/callback work and all6
ready replicas were verified. Exact jobs (now failed and collected):
`kz5-stage-install-kazoo-apps-14` and `kz5-stage-install-apps-peer-10`.
Start log `/var/lib/kazoo5-install-lab/init-readiness-deploy-c6e0c36-1789000314473.log`.
Their start and the earlier focused tests do not turn this failed build into
a pass. Use a new normal deployment of the corrected source for runtime proof.
