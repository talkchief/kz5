# Separated-role installer acceptance lab

Status: isolated CouchDB and RabbitMQ normal installation/service checks passed;
the full separated-role and recovery matrix is not complete.
This is an explicitly owned lab on development host10.1.0.44, not a production
installer option and not evidence of independent-machine HA.

Entry point: `bash scripts/prepare-distributed-install-lab.sh --prepare`, then
`--create ROLE`, `--install ROLE`, `--sync-source ROLE`, `--verify-role ROLE`,
`--reboot-role ROLE` or `--status`. Source and fixed roles are in
`scripts/test-fixtures/distributed-lab/lab.cjs`; the small Containerfile builds
a systemd PID1 image using a verified upstream Rocky9 repository digest.
Normal Kazoo installation must subsequently use `scripts/install-kazoo5.sh`.

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

Repeat/guest-boot, downstream separated roles, cluster admission/drain and
rollback remain unverified.28 pure/static lab groups and3 actual dependency
selection groups pass; they do not replace native role evidence.
