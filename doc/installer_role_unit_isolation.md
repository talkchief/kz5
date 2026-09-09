# Standalone apps/eCallMgr service-unit isolation

## Defect and fix

`install_kazoo_systemd_units` previously wrote both service definitions on every
call. Consequently `install-kazoo5.sh ecallmgr` could overwrite the unselected
apps unit, and an apps-only install could overwrite eCallMgr's. It also created
both log directories and recursively changed ownership under the shared log
parent. This violated the intended standalone-role boundary.

The normal installer now passes an explicit `kazoo-apps` or `ecallmgr` argument
to its unit generator. Only that service definition and role-specific log
directory are handled. Missing, unknown or multiple arguments are rejected
before any host mutation. The internal explicit `all` argument remains available
for combined generation; normal combined installation calls each role once.

Existing unselected units are **not deleted, disabled, restarted or rewritten**.
For example, on an all-in-one development host, an eCallMgr update leaves the
apps unit in place. On a new standalone eCallMgr host, it no longer creates an
unused apps unit. Unit contents, the apps alias `kazoo-applications.service`,
configured runtime root, production-BEAM check and Pivot dependency are unchanged.

Shared runtime ownership/cookie, source build, core configuration, SUP and the
Pivot reservation helper remain shared by design. This change does not promise
independent per-role data/config roots or crash-atomic concurrent deployment.
Do not infer that an arbitrary live combined-node reconfiguration is safe merely
because unselected service files are preserved.

## Focused evidence — September9

- Before correction: the actual generator regression failed both standalone
  selections, and the entry-point wiring assertion failed (a04a85, three failures).
- After correction: seven tests pass (b359be) in
  `scripts/test-kazoo-unit-runtime-root.py`. They execute the actual generator,
  check selected unit/log scope, reject invalid role/naming inputs before writes,
  and exercise generated BEAM guards using separate temporary runtime/source trees.
- Nine Pivot reservation tests pass (50a4f5). The fixture now supplies the actual
  preflight value `-sname`; its old `sname` value failed the existing naming guard
  before reaching its intended test. That fixture correction does not weaken the
  installer or establish a newly discovered runtime naming failure.
- `scripts/test-kazoo-unit-selection.sh` exercises the normal CLI in dry-run mode:
  apps only, eCallMgr only and combined all pass (ca722f). Each selected service
  is written exactly once and each unselected service zero times. These are
  non-mutating CLI checks, not new live installation/reboot evidence.
- Shell syntax and diff whitespace checks pass.

Main44 baseline (d8c4ed): apps PID1333645, eCallMgr PID1019194, both active with
zero automatic restarts. Existing unit SHA256 values:

| Unit | SHA256 |
| --- | --- |
| kazoo-apps.service | `87f52ad4f9daf279a4fa954af8a0b9338660d76e6d623d40db925c78de5bc47f` |
| kazoo-ecallmgr.service | `3492127098e7ed45f1a254b8c44f126764b8319b6e1f961818b854b7d6d62d80` |

The source fix belongs in main44 `/opt/kz5`; no runtime rebuild or restart is
needed to activate a future installer branch decision. Full separate-role
installation/upgrade/failure-recovery acceptance remains tracked in INST-07/13.
