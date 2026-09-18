# Single installation entry point

Owner target (September 18, 2026): every installation goes through
`scripts/install-kazoo5.sh`, for all components or a single one, with interactive
options.

## Using it

```sh
sudo ./scripts/install-kazoo5.sh                     # on a terminal: menu
sudo ./scripts/install-kazoo5.sh --interactive        # the same, explicitly
sudo ./scripts/install-kazoo5.sh kazoo-apps           # one component
sudo ./scripts/install-kazoo5.sh couchdb rabbitmq     # several
sudo ./scripts/install-kazoo5.sh all                  # everything
sudo ./scripts/install-kazoo5.sh --verify-only all    # read-only
sudo ./scripts/install-kazoo5.sh --dry-run kamailio   # print only
```

The menu lists the nine components with their state on the host
(`installed, active` / `not installed on this host`), takes numbers, names,
aliases or `a` for all, asks for the action (install or upgrade, verify only,
dry run) unless `--verify-only` or `--dry-run` was given, and requires a literal
`yes` before anything that restarts services. `q` quits. It only fills the same
variables the command line fills, so every later step is the same code path.

Without a terminal nothing changed: no component means usage and exit 2, naming
a component never opens the menu, and `--interactive` refuses instead of
waiting. Automation, the lab and the promotion wrapper are unaffected.

## What was beside it, and what happened to it

A read-only audit of `scripts/` found nine tracked scripts that changed a host
without the installer. All nine were removed (they remain in git history):

| Removed | Why |
| --- | --- |
| `setup-dev.sh` | Stock upstream. `rm -rf /var/lib/rabbitmq /var/log/rabbitmq /usr/lib/rabbitmq` with no guard, against `/opt/kazoo`, which is a symlink to this tree on the development host: it would have removed the live broker database. The installer owns the SUP link, the units and the broker. |
| `sync_to_release.bash`, `sync_to_remote.bash` | Stock upstream. Moved arbitrary BEAM files into the release and hot-loaded them into both running nodes: no pin, checksum, idle check or backup. |
| `deploy-revision-safety-fixes.sh` | Superseded by `kazoo-couch-single-delete-result.patch` and `crossbar-soft-delete-revision.patch`, applied and built by the installer. Referenced nowhere. |
| `deploy-scope-management-guard.sh` | Superseded by `crossbar-scope-management-guard.patch`, plus installer registration and verification. |
| `deploy-internal-callback.cjs`, `deploy-single-key-callback.cjs` (+ its test) | One-module hot loads of tracked ACDC source that the installer builds and installs. |
| `deploy-monster-standalone-component.cjs` (+ its test), `patch-monster-myaccount-bundle.cjs` | Wrote the live web root directly, with no guard. Superseded by the installer's owned Monster UI deployment and `monster-ui-myaccount-transition.patch`. |

The evidence documents that describe runs of those helpers keep their record and
carry a removal note.

Not deployment paths, and deliberately left: the development promotion wrapper
(it *calls* the installer and is limited to the development host), the container
lab, post-boot verification and incident recovery (all limited to the
development host), the loopback SIPp fixture phones
(`install-live-test-agents.sh`) and the private browser test tooling. Scripts the
installer itself runs (`deploy-owned-monster.cjs`,
`install-acdc-cardinal-pack.cjs`, the guards, the health check, the maintenance
helpers) are inside the entry point.

## Guard

`bash scripts/test-single-install-entry-point.sh` (4 groups) fails if one of the
nine returns, if a script named like an installation path is neither run by the
installer nor listed as test tooling with a reason, or if any tracked script
loads code into a running node. `python3 scripts/test-install-kazoo5-interactive.py`
(7 groups) drives the menu on a real pseudo-terminal.

## Open

- `migrate-monster-app-api-url.cjs` stays: it is a reviewed, hard-scoped one-time
  migration of ten documents, and the installer deliberately never rewrites an
  existing catalog document. What is missing is detection: installer verification
  does not compare a registered app's `api_url` with the configured API URL, so a
  changed URL would leave apps pointing at the old address unnoticed.
