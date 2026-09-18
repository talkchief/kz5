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

## Native evidence (private lab, September 18, 2026)

| Run | Result |
| --- | --- |
| eCallMgr guest, install 6 (`9d0f7df`) | **FAIL** `The previous Erlang port mapper did not release port 4369`. A guest's `ss -p` shows no socket owners, so nothing was stopped. Guest unchanged. Fixed in `8ded71d`: mappers are found by process, excluding only a proven foreign network namespace (host: 1 of 7 visible mappers; guests: their own). |
| eCallMgr guest, install 7 (`8ded71d`) | **PASS** `epmd.service owns port 4369, no wildcard listener, every running Erlang role is registered`; mapper pid 2477 as user `epmd`, listeners `127.0.0.1:4369` and `172.30.253.16:4369`. |
| `systemctl restart kazoo-ecallmgr` in that guest | Mapper pid 2477 before and after, no second mapper, `freeswitch@kz5-stage-freeswitch` found again in about 18 s. This is the failed promotion's sequence. |
| FreeSWITCH guest, install 7 (`8ded71d`) | **FAIL** `epmd.service: Failed to execute /usr/bin/epmd: Resource temporarily unavailable`; the guest was left without a mapper. The packaged `LimitNPROC=1` is counted per numeric uid across the user namespace, which rootful guests share with the host and each other; two guests already ran a mapper as uid 997. Fixed in `555a2a2`: drop-in `LimitNPROC=infinity` (epmd never forks), and the migration requires the service to answer before FreeSWITCH is restarted. |
| FreeSWITCH guest, install 8 (`555a2a2`) | **PASS**, guest repaired: `fs_epmd` replaced, idle FreeSWITCH restarted once, `freeswitch` registered, eCallMgr relinked. |
| Cold boot of the FreeSWITCH guest | Socket listening at 8586.73 s, FreeSWITCH started at 8587.11 s (monotonic); one mapper, in `epmd.service`; `freeswitch` registered unaided; eCallMgr relinked in about 40 s. |

Receipts: `/var/lib/kazoo5-install-lab/ecallmgr-install-7.log`,
`/var/lib/kazoo5-install-lab/freeswitch-install-8.log`.

Not yet proven: FreeSWITCH and eCallMgr sharing one host exists only on main.
The register records that result when main is promoted.
