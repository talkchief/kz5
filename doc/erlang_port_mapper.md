# Erlang port mapper ownership

## The failure

Main development promotion `kz5-promo-0918b` (source `b809eec`, run directory
`/root/kz5-main-promotion-20260918.rw1khk1v`, receipt `status: FAIL`) built and
restarted `kazoo-apps` and `kazoo-ecallmgr` correctly and then failed its last
check on September 18, 2026 at 10:03:33 UTC:

```
[kazoo5] ERROR: eCallMgr and FreeSWITCH node freeswitch@dev-testing did not negotiate four-byte event-stream framing
```

The promotion script left SIP ingress closed, as designed. It stayed closed from
09:50:20 to about 10:09 UTC.

## Root cause

Nothing on the host owned the Erlang port mapper (`epmd`). The first Erlang VM
to start spawns `epmd -daemon`, and that daemon stays in the **starting
service's cgroup**. Both Kazoo units use `KillMode=control-group`, so restarting
the owning service kills the mapper for the whole host:

| Observation | Value |
| --- | --- |
| Host `epmd` after the promotion | pid 386407, cgroup `/system.slice/kazoo-ecallmgr.service`, started 10:00:15 |
| `kazoo-freeswitch` started | 08:16:07, registered with the previous mapper |
| `epmd -names` after the promotion | `ecallmgr`, `kazoo_apps`, `couchdb`, `rabbit` — no `freeswitch` |
| eCallMgr | `failed to get mod_kazoo version from freeswitch@dev-testing: timeout`, `net_adm:ping` → `pang` |
| FreeSWITCH | `Erlang communication fault with node ecallmgr@dev-testing … socket closed` at 10:00:14 |
| Listener | `0.0.0.0:4369` and `[::]:4369`, so also on the public address |

Erlang nodes register again by themselves (`kz_epmd` for the Kazoo nodes, OTP for
RabbitMQ and CouchDB). FreeSWITCH's `mod_kazoo` is a C node and registers only
when the module loads, so once the mapper is replaced no new eCallMgr VM can
resolve it. An established link survives, which is why this shows up only at the
next restart or reconnect. The same sequence applies to any all-in-one host,
including production, and to a reboot in which FreeSWITCH wins the start race
and a later Kazoo restart replaces the mapper.

The installer already moved the mapper to the packaged socket-activated
`epmd.service`, but only for a full all-loopback install with `couchdb` and
`rabbitmq` both selected. It never applied to main or to any partial install.

## Recovery performed on main

Zero channels and no installer running were confirmed, then
`systemctl restart kazoo-freeswitch`. `freeswitch` reappeared in `epmd -names`
and in `ecallmgr_maintenance list_fs_nodes`. `install-kazoo5.sh --verify-only
kazoo-apps ecallmgr` then passed every check including the framing check that
failed the promotion, and `kazoo-kamailio` was started. `kazoo5-stack-health.sh`
reported `failures=0`.

The failed receipt is retained. The runtime on main is source `b809eec`; the
promotion is recorded as failed-then-recovered by hand, not as passed.

## Fix

`configure_stable_epmd` / `verify_stable_epmd` in `scripts/install-kazoo5.sh`
replace the loopback-only functions and run whenever an Erlang role
(`couchdb`, `rabbitmq`, `kazoo-apps`, `ecallmgr`, `freeswitch`) is selected and
the packaged `epmd.socket` exists:

- `epmd.socket` is enabled and bound to `127.0.0.1:4369` plus the Erlang
  interface only (`FreeBind=true`, because `sockets.target` precedes network
  configuration after a reboot). No wildcard listener remains.
- Each Erlang role unit gets `Wants=`/`After=epmd.socket`, so a VM's own
  `epmd -daemon` always finds the port taken and exits.
- Migration from a service-owned mapper refuses **before any change** when
  FreeSWITCH has live or unknown channels. Otherwise it stops the old mapper,
  starts the socket, restarts idle FreeSWITCH once and waits until every running
  role is registered, naming the unit to restart if one is not.
- Verification (install and `--verify-only`) requires the socket enabled, the
  listener owned by `epmd.service`, no wildcard listener and every running role
  registered. On main before deployment it refuses with `epmd.socket is not
  enabled; a reboot would hand the port mapper to the first Erlang service again`.
- `kazoo5-stack-health.sh` checks every two minutes that each installed role is
  registered and that the mapper is not owned by another service.

A host without the packaged unit (a CouchDB-only guest) runs a single Erlang
role whose mapper restarts with it, and is left alone. A FreeSWITCH-only host
otherwise uses `fs_epmd` inside its own unit, which has the same property.

Native basis for relying on re-registration: in lab guest `kz5-stage-rabbitmq`
the service-owned mapper was killed and `epmd.socket` started; `rabbit`
registered again after about 4 s, the new mapper ran in `epmd.service` as user
`epmd`, listeners were `127.0.0.1:4369` and `172.30.253.12:4369`, and
`rabbitmqctl status` worked. On main, `couchdb` and `rabbit` registered with the
10:00:15 mapper unaided.

## Offline regression

`bash scripts/test-install-kazoo5-stable-epmd.sh` (6 groups) reproduces the
September 18 host with controlled commands: migration steps and order, refusal
on live or unknown channels before any change, undisturbed repeat / loopback /
unit-less / non-Erlang installs, a named remedy for a role that does not
register, five rejected unsafe states in verification, and the wiring.
`bash scripts/test-install-kazoo5-stack-health.sh` (4 groups, twelve failure
classes) covers the two health conditions.

## Native evidence

See the register entry in `PROJECT_TASKS.md` for the lab and main results.
