# Separated-role installer acceptance lab

Status: bootstrap implemented; no separated-role installation acceptance yet.
This is an explicitly owned lab on development host10.1.0.44, not a production
installer option and not evidence of independent-machine HA.

Entry point: `bash scripts/prepare-distributed-install-lab.sh --prepare`, then
`--create ROLE` or `--status`. Source and fixed roles are in
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
Installation, service enable/start, repeat/reboot, admission/drain and rollback
still need actual evidence. A booted container is explicitly reported as
`installed:false`.
