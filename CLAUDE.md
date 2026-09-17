# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a KAZOO 5 (2600hz VoIP platform) deployment repository, not a stock upstream
checkout. Read `PROJECT_HANDOFF.md` (engineering handoff: source map, evidence,
deployed artifacts, gaps) and `PROJECT_TASKS.md` (authoritative task register with
open/failed items) before starting work — `README.md`, `doc/README.md` and
`scripts/README.md` all point there first. Per-topic evidence lives in `doc/<topic>.md`
(e.g. `doc/acdc_broker_upgrade.md`, `doc/maintenance_listener_dispatch.md`), which the
register links by name.

Those two files also carry the standing working rules for this repo: fix reported bugs
and deployment gaps in source, validate the failing path, deploy through the installer,
then record the actual result (with exact hashes/receipt paths) in the register and the
topic doc. Do not re-run campaigns already recorded as passed, and do not delete or
soften recorded failures — failed evidence is retained deliberately.

### What is tracked vs. fetched

`.gitignore` excludes `/core/`, `/deps/` and every `applications/*/` **except**
`applications/acdc/`. So:

- Tracked and editable here: `applications/acdc/` (ordinary source, not a submodule —
  see `doc/acdc_source_ownership.md`), `scripts/`, `doc/`, `monster-ui/acdc/`,
  `services/push-bridge/`, `rel/`, `make/`, `Makefile`.
- Fetched at build time by `erlang.mk` from pinned refs: `core/`, `deps/` and all
  non-ACDC applications. They exist on disk but are not tracked, so **edits there are
  not source changes**.
- Fixes to fetched components live as patches in `scripts/patches/` (127 of them) and
  are applied by the installer via `apply_required_source_patch` (see
  `scripts/install-kazoo5.sh` around the `apply_required_source_patch` calls). Adding a
  core/crossbar/blackhole/ecallmgr fix means adding or updating a patch there plus its
  regression test, never editing `core/` in place.

## Build

Erlang 26.2.5 / rebar 3.23.0 (`.tool-versions`). Everything is GNU make on top of
`erlang.mk`; app makefiles include `make/kz.mk`.

```sh
make                      # prerequisites + deps + core + all apps (fetches core/deps)
make -C applications/acdc  # build just ACDC (from repo root: ROOT is derived)
make clean-kazoo          # deep clean; deliberately PRESERVES applications/acdc source
make build-release        # relx release into _rel/ (also build-dev-release, build-ci-release)
make sup_completion       # regenerate sup.bash (gitignored)
```

Escripts under `scripts/` generally need `ERL_LIBS=deps:core:applications`.

## Tests

Three distinct layers; they are not interchangeable.

**1. EUnit through make** (`applications/acdc/test/*.erl`):

```sh
make -C applications/acdc eunit                          # with cover
make -C applications/acdc test                           # all modules, debug-friendly
make -C applications/acdc test.acdc_queue_fsm_tests      # ONE module (test.% target)
make eunit-apps / make eunit-core / make test            # whole tree
```

**2. Standalone script suites** under `scripts/` (~479 `test-*` scripts: 155 `.sh`,
262 `.cjs`, 49 `.py`). Each is self-contained and run directly; `.cjs` files use
`node:test`. They compile their fixtures (`scripts/erlang-tests/*.erl`) into a temp dir
and never touch live BEAMs:

```sh
python3 scripts/test-acdc-source-ownership.py
bash scripts/test-acdc-unit.sh
bash scripts/test-acdc-strategies.sh            # accepts --shard 1/2 / --shard 2/2
bash scripts/test-acdc-agent-recovery.sh
node scripts/test-acdc-native-maintenance.cjs
```

Run Erlang source regressions sequentially, not in parallel — competing mock
compilation breaks them. Many suites also assert on the *text* of
`scripts/install-kazoo5.sh` (they `grep`/extract shell functions from it), so installer
edits usually require updating the matching `scripts/test-install-*` expectations.

**3. Resource-guarded runs.** On capped hosts wrap a suite in the foreground guard
rather than raising its internal deadlines:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 60 -- /usr/bin/bash /opt/kz5/scripts/test-....sh
```

Native/live acceptance runs execute as transient systemd units (named
`kz5-<case>-<host>-<date>`) and write protected receipts under `/var/log/kazoo-*` or
`/root/kz5-*`; the register cites those paths and unit exit codes as the evidence.

## Checks before committing

```sh
make code_checks          # copyright/license bump, edoc, raw-JSON, loglines, stacktrace, kz_diaspora
make elvis                # style, on CHANGED files (make/elvis.config)
make dialyze-changed      # or dialyze-apps / dialyze-kazoo; needs build-plt
make fmt                  # erlang-formatter on CHANGED files
make ci-codechecks ci-docs ci-dialyze   # the minimal pre-PR set (doc/engineering/commits.md)
```

Most targets operate on `CHANGED` (computed by `scripts/check-changed.bash` against
`.base_branch`), so they are cheap but only cover your diff.

## Deployment

`scripts/install-kazoo5.sh` (Rocky Linux 9, run as root) is the only deployment entry
point. It converges packages, source, patches, config and systemd units, then verifies —
it restarts selected services, so it needs a maintenance window and must never be used
as a status check.

```sh
sudo ./scripts/install-kazoo5.sh --list
sudo ./scripts/install-kazoo5.sh --dry-run kazoo-apps
sudo ./scripts/install-kazoo5.sh --verify-only all
sudo ./scripts/install-kazoo5.sh couchdb rabbitmq
```

Components: `couchdb`, `rabbitmq`, `haproxy`, `kazoo-apps`, `ecallmgr`, `freeswitch`,
`kamailio`, `monster-ui`, `push-bridge`, `all`. Inputs come from environment variables
persisted to `/etc/kazoo/deployment.env` (root-owned 0600; explicit env wins over saved
values) — `--help` lists the full set, including the pinned component refs.

## Architecture

Runtime topology: two Erlang release nodes (`kazoo_apps` and `ecallmgr`, see `rel/`)
over RabbitMQ (all inter-app messaging) and CouchDB (behind HAProxy on 15984/15986),
with FreeSWITCH (media, via `mod_kazoo`) and Kamailio (SIP edge) as native services,
Monster UI as the web frontend, and `services/push-bridge/` as a separate Python
FCM/APNs bridge.

`applications/acdc/` — the call-centre/ACD application and the focus of nearly all work
here (`applications/acdc/doc/architecture.md` has the process trees and FSM diagrams):

- **Agents**: `acdc_agents_sup` → `acdc_agent_sup` → paired `acdc_agent_listener`
  (`gen_listener`, AMQP) + `acdc_agent_fsm` (`gen_statem`:
  init→sync→ready→ringing→answered→wrapup). `acdc_agent_manager`,
  `acdc_agent_handler`, `acdc_agent_stats`.
- **Queues**: `acdc_queues_sup` → `acdc_queue_sup` → `acdc_queue_listener` +
  `acdc_queue_fsm`, plus `acdc_queue_manager` (membership/strategy, own `.hrl`),
  `acdc_queue_strategy`, `acdc_queue_worker_sup`/`acdc_queue_workers_sup`.
- **Callbacks** (queued call-me-back): `acdc_callback_store` (durable),
  `acdc_callback_caller`, `_menu`, `_policy`, `_reconcile`, `_recovery`,
  `_recovery_io`, `_internal`, `_agent_probe`. Recovery correctness and retained
  ticket state are recurring open items — see `doc/callback_originate_receipt.md`.
- **Prompts/languages**: `acdc_language`, `acdc_cardinal_media`/`acdc_cardinal_prompts`
  with per-locale `src/cardinal_maps/*.hrl`, `acdc_gemini_prompts`,
  `acdc_wait_time_media`. Voices are pre-recorded assets (`scripts/assets/`); never
  synthesize at runtime or during deployment.
- **Dashboard**: `acdc_dashboard_*` (collector, projection, snapshot, events, codec) —
  explicitly lower priority / postponed.
- **Integration seams**: `kapi_acdc_*` (AMQP API definitions), `cb_*` (Crossbar REST
  endpoints), `cf_*` (callflow actions), `acdc_maintenance`/`acdc_agent_maintenance`/
  `acdc_language_maintenance` (SUP console commands), `acdc_init` (startup readiness,
  polled by the installer), `priv/couchdb/views/*.json`.

## Conventions

Style is the upstream 2600hz standard (`CONTRIBUTING.md`); the parts most likely to
trip you up: quoted atoms (`'foo'`, never `foo`), leading-comma list/export formatting,
no `if` (use `case` or function-clause pattern matching), a `-spec` for every function
with the narrowest useful types, no chained call sequences, no single-letter variables,
no shared records across modules, small functions (~12 expressions), and matching the
surrounding module's existing style over your own preference.

Commit/PR conventions are in `doc/engineering/commits.md`; commit messages in this
repo's history describe the verified outcome ("Record …", "Verify …", "Track …").

## Gotchas

- `sup.bash`, `TAGS`, `_rel/`, `elvis` and `make/erlang-formatter/` are generated and
  gitignored; don't commit them.
- Untracked-but-not-ignored files exist in the working tree (e.g. `key`,
  `scripts/__pycache__/`). Never `git add -A`; stage explicitly, and keep secrets out.
- Several targets (`clean-kazoo`, `sparkly-clean`) abort if the tree has changes
  (`stop-if-changed`).
- A green offline test says nothing about deployment state; deployment claims require an
  installer run plus native verification, recorded in `PROJECT_TASKS.md`.
