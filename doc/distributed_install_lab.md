# Separated-role installer acceptance lab

Status: CouchDB, RabbitMQ, HAProxy, FreeSWITCH, eCallMgr, Kamailio and Kazoo apps
isolated normal installation/service checks passed. Apps attempt6 passed after
diagnostic lab bootstrap; untouched cold bootstrap is not proven by that retry.
The full separated-role/boot/rollback matrix is not complete.
This is an explicitly owned lab on development host10.1.0.44, not a production
installer option and not evidence of independent-machine HA.

Entry point: `bash scripts/prepare-distributed-install-lab.sh --prepare`, then
`--create ROLE`, `--install ROLE`, `--sync-source ROLE`, `--verify-role ROLE`,
`--reboot-role ROLE` or `--status`. Source and fixed roles are in
`scripts/test-fixtures/distributed-lab/lab.cjs`; the small Containerfile builds
a systemd PID1 image using a verified upstream Rocky9 repository digest.
Normal Kazoo installation must subsequently use `scripts/install-kazoo5.sh`.
For bounded detached builds use `--begin-install ROLE`, followed by
`--collect-install ROLE` before retry/source synchronization. The retained unit
uses `User=root` (required login environment) and `RemainAfterExit=yes` (preserved
terminal evidence). Compilation or a booted container is not an installer pass.

Install/admit data roles first, then HAProxy, apps and FreeSWITCH, then eCallMgr
and Kamailio. Remote JWT/config services must be ready before the SBC's full
integration verification. Dependency failures remain failures, not skipped gates.

The lab refuses other hosts, tracked dirty sources, an existing state/name or
overlapping host route. Root0700 state is at `/var/lib/kazoo5-install-lab`.
It records image/source identity and partial ownership before further changes.
Failed/partial attempts are retained for inspection, never automatically deleted
or replaced. Do not rerun preparation over them.

Containers have their own network namespaces, data filesystems and PID1 systemd.
There are no host-data bind mounts, public published ports, host networking or
privileged containers. NET_ADMIN permits blackhole routes to production/private
10.1.0.0/16 and the two development public addresses inside each container.
The isolated bridge is172.30.253.0/24. Each role must receive newly generated
lab-only credentials; never reuse or copy the existing development configuration
or imported customer data. Container limits are not a claim of physical HA.

Creation reserves Pivot ports34512-34513 with the namespaced Podman `--sysctl`
option. Older retained containers use a pinned network-namespace descriptor and
the normal additive reservation helper before apps/eCallMgr installation. The
host namespace is explicitly refused and host reservations checked unchanged.
No procfs unmasking or privileged-container workaround is used. Confined socket
inspection runs as the service UID when root cannot inspect another UID's file
descriptors; the normal installer still requires exact Kamailio process ownership.

Podman's documented systemd mode supplies the required runtime mounts; scoped
container SELinux labeling is disabled for this lab without changing global
SELinux policy. See the primary [Podman run reference](https://docs.podman.io/en/latest/markdown/podman-run.1.html).

`node scripts/test-fixtures/distributed-lab/lab.test.cjs` checks subnet boundaries,
role uniqueness and static isolation guards without creating lab state.
Only backend roles currently have installation dispatch. Provider-enabled bridge
and separate UI provisioning must not be inferred from the role-name inventory.
`--sync-source` requires clean tracked files and fast-forward-only advancement;
it changes source identity, not deployed-service acceptance. `--reboot-role` is
restricted to data roles before any dependent application/media role is created,
then executes the normal installer verifier. It tests guest systemd boot, not
physical host/kernel failure. A booted container alone reports `installed:false`.

## Native results

- Base Rocky image digest:
  `sha256:d644d203142cd5b54ad2a83a203e1dee68af2229f8fe32f52a30c6e1d3c3a9e0`.
- Initial image preparation failed on curl/curl-minimal conflict; normal
  installer had the same unconditional dependency.90ba5ef preserves the minimal
  provider; three actual helper paths pass. Corrected image preparation passed.
- Initial CouchDB preflight rejected a lab name containing spaces. Corrected
  the fixture input, not production validation. Next install exposed absent
  `cmp`;9147650 adds the required diffutils package to the normal installer.
- `kz5-distributed-couchdb-diffutils-20260909.service` exit0 (fc13ec), role
  source9147650, native authenticated health and enabled/active service pass.
  Private role log `/var/lib/kazoo5-install-lab/couchdb-install-3.log`.
- Separate RabbitMQ normal installer passed3.13.7/Erlang26.2.5, exact AMQP
  listener, vhost permissions, authentication and consistent-hash plugin.
  Private log `/var/lib/kazoo5-install-lab/rabbitmq-install-1.log`.
- No production/dev stack data or provider credentials were mounted/copied.
  New random lab secrets are only in protected state/input files. Do not print
  `lab.json`, role env files or raw logs. The status command omits secrets.

Additional native evidence under `/var/lib/kazoo5-install-lab`:

| Role | Verified result | Boundary |
| --- | --- | --- |
| CouchDB | install3, repeat4, guest boot | one physical host |
| RabbitMQ | install1, repeat2, guest boot, lab-only read monitor | not a broker cluster |
| HAProxy | install1, repeat2, verify after manually restored guest | automated guest reboot failed in Podman/conmon; not marked passed |
| FreeSWITCH | repeat4 normal installer and enabled service | pinned Kazoo module and EI; no physical boot claim |
| eCallMgr | install4, source `e780af1`, enabled service, separate FS connection/framing/intercept inventory | read-only native media admission, no cross-node supervision call |
| Kamailio | install4, source `6eddc28`, enabled service, exact broker socket and JWT verification | passed after isolated apps became available |
| Kazoo apps | install6, source `8966bd7`, normal validation/admin authentication/APIs/installed prompt maps | normal retry after diagnostic lab master creation, not untouched cold bootstrap |

Fresh-role findings and source fixes: pinned Erlang/EI and stale out-of-tree
configure invalidation for FreeSWITCH; explicit login environment for rebar
bootstrap; namespaced Pivot reservation; exact Kamailio socket inspection as
service UID without added capabilities; eCallMgr application readiness before
node registration and cookie-safe registration diagnostics. Apps first master
bootstrap failed; after startup a protected diagnostic succeeded. This was not
retroactively marked a normal first-install pass. Its schema readiness barrier
was strengthened. Attempt5 then exposed the private `kapps_config:get_category/2`
call in Crossbar module registration. Required source/transition patches now use
the exported uncached datastore API. Normal attempt6 passed and its terminal
receipt was collected (`kazoo-apps-install-6.log`). Lab master and transport-probe
child are synthetic lab-only resources retained for inspection. These interventions
and original failures remain recorded rather than relabeled as a cold-install pass.

The remaining role/boot matrix, physical-machine failures, cluster-wide drain/
upgrade and rollback are not certified by these container results.

For the fully installed original lab, `--drained-reboot-role ROLE` is a separate
explicit gate: all seven backend containers must match retained ownership,
network identity and installed status, and the owned FreeSWITCH must report zero
channels. It then uses the same stop/start, isolation-route and normal service
verification checks. It does not weaken `--reboot-role`'s earlier dependency
restriction or authorize host/main-stack restart. A failed stop/start is retained
as a failure, never treated as verified merely because a container later runs.

September9 HAProxy drained guest reboot passed (`haproxy-boot-1788966152367.log`).
Kamailio guest reboot passed (`kamailio-boot-1788966720687.log`). FreeSWITCH's
stop command lost its Podman monitor (exit125, missing exit receipt); the exact
stopped guest was started again, and normal FreeSWITCH/eCallMgr verification
passed (`freeswitch-verify-1788966601223.log`, `ecallmgr-verify-1788966645818.log`).
That restoration is not relabeled a clean automated guest reboot.
The retained eCallMgr guest then failed automatic admission: its old Podman
creation command lacks the namespaced reserved-port setting and the reservation
service cannot write the container's read-only sysctl mount after a reboot.
Current creation code includes the setting. The explicit original-lab-only
`--repair-legacy-pivot ecallmgr` helper requires zero owned media channels, pins
the non-host network namespace, reserves the ports without changing the host,
restarts the exact prerequisite and starts/verifies the role. It records a
restoration, **not** an automatic boot pass. Do not weaken production readiness
or change host/container-wide privilege to make this legacy fixture pass.
Future apps/eCallMgr guest reboot admission now checks the recorded persistent
creation flag before stopping the working role. The fresh cold three-role
scenario also permits `--cold-bootstrap --drained-reboot-role kazoo-apps` after
successful normal installation; it has no media role or calls. This tests the
current creation path instead of pretending a temporary repair was persistent.

## Fresh bootstrap campaign

Use the same entry point with `--cold-bootstrap` before the operation, starting
with `--cold-bootstrap --prepare`. This fixed scenario creates only fresh
CouchDB, RabbitMQ and apps roles on a different network (`172.30.252.0/24`),
with separate root-only state `/var/lib/kazoo5-cold-bootstrap-lab`, container
names, role labels, generated credentials and realm `cold-installer-stage.invalid`.
It reuses the verified immutable Rocky base image, not a provisioned container.
Apps connects directly to its new remote CouchDB/RabbitMQ. Immediately before
apps attempt1, an authenticated database inventory must contain only CouchDB
system databases (or be empty); the inventory/time/source receipt is retained.
No manual account creation is part of this scenario. An installer retry must
never be relabeled a first-attempt success. Existing labs/data are not deleted.

Cold CouchDB and RabbitMQ attempt1 both passed. Apps attempt1 refused the missing
lab management-monitor credentials before compilation/account bootstrap. This
failed preflight is retained, not called a successful first installation. The lab
now creates/authenticates its own read-only monitor before copying app inputs.
Every pre-success apps admission requires an empty Kazoo database inventory;
original and subsequent admission receipts are retained. No diagnostic account
creation is allowed. Native cold account bootstrap result is pending.

The original cold run subsequently exposed the SUP packaging defect documented
in `sup_archive_bootstrap.md`. Its account was created successfully, but the CLI
could not discover it. After fixing/rebuilding, use `--cold-bootstrap-final`
instead of `--cold-bootstrap` for one more genuinely empty end-to-end run. This
fixed additional profile has separate state `/var/lib/kazoo5-cold-bootstrap-final`,
network `172.30.251.0/24`, names `kz5-final-*`, fresh random secrets and realm
`cold-final-stage.invalid`; all admission, ownership and no-takeover gates apply.
It does not delete or reuse either earlier lab's data. First-install result is
pending until its normal apps attempt1 and terminal service validation pass.
