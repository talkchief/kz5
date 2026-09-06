# Combined installer regression checkpoint — 2026-09-06

All five serialized offline phases passed before recovery merge `8548b98`:
24 suite invocations, with parent HEAD `860ce46` and the pending installer
changes whose exact hashes are recorded below. This verifies
the installer bytes identified below, not later edits, a completed production deployment or a
clean-server installation. ACDC remains ordinary tracked source in kz5.

| Phase | Terminal session | Suites | Retained evidence directory |
| --- | --- | --- | --- |
| Installer and ownership fixtures | 60318 | 16 | `/tmp/kazoo-installer-regressions.Wnzi24` |
| Runtime-root and readiness BEAM fixtures | 23339 | 2 | `/tmp/kazoo-installer-regressions.04mD1w` |
| Crossbar catalog replay and tests | 43605 | 1 | `/tmp/kazoo-installer-regressions.ZqSGB3` |
| Dependency graph, production fixtures, minifier and template order | 73461 | 4 | `/tmp/kazoo-installer-regressions.fHBS0g` |
| Retained production artifact readback | 97654 | 1 | `/tmp/kazoo-installer-regressions.olI5QJ` |

Every phase exited zero with all 129 reviewed input hashes unchanged before
and after execution. Each used the existing validation guard: 384 MiB memory,
zero swap, 50% CPU, 128 tasks and 768 MiB host reserve. Runtime limits were
120 seconds, except the final readback's 60 seconds. No phase ran concurrently.

The frozen proposal and detailed suite coverage are retained under
`/tmp/kazoo-installer-regression-plan.s68t5J/`. Root independently verified both
hash manifests after completion. These host-local receipts are not repository
assets; repeat the repository tests on a new deployment rather than assuming
these paths exist there.

```text
647668951c442f182e8ddcd7106cf4a28acbd6e7228c569d78c6cb128ea667f7  RESULT.md
f3402a038a3fa14698999f304e3573c45f548858c8a95cf1befdaadedbc549ea  evidence-logs.sha256
26b4e918c90acb74ce191aa8ac3c3572d7e7df452bd13aab136039605f76ecc2  reviewed-inputs.sha256
307aa944e7a03e466a3cbcb1c9e19fa7798e90af992d6a75a28a014d5b4e32ca  run-offline-regressions.sh
33c5f80abd846a604be49a17c976b364a6ede77ca137073f0b8fe43ca6854950  scripts/install-kazoo5.sh
5ec8f080b30054404c2fe181f46ea6bfa5ccb98ec9f4cec49b73ef0ff32b05a3  scripts/patches/crossbar-kazoo5-integration.patch
```

Significant checks include 24 owned-file deployment groups; preservation of
operator config, unrelated apps and runtime capabilities; exact served-byte
proof; SUP aliases and unloaded-module inspection; current-invocation eCallMgr
build proof; Pivot port reservation; actual unit runtime roots; and negative
readiness cases. The catalog patch replayed from pinned Crossbar source,
compiled with warnings treated as errors, passed production export/import checks
and all nine isolated tests. The prepared dependency graph had 1,130 nodes and
zero required-edge errors; this is not a peer-compatibility or security audit.

Artifact readback verified 1,931 files, 19 app directories, 16 canonical
preloads, 465 templates and two ACDC state renders. Its tree hash remains
`6cb494731de21b2d49b08856a7187825b3ce9a5330a01e765e011edd4c0de4cf`;
source hash remains
`60ee8cdc98d16928ad22928cb46ea45655d74fa5356d6809d8339131d6dda7fc`.
Build and isolated-browser scope are recorded separately in
[UI preservation](monster_ui_preserving_install.md).
The subsequent recovery merge changed ACDC source and replay tests, so the
129-input manifest is historical evidence of those five phases, not a claim
that every input still matches after the merge. The installer and catalog patch
hashes above identify that checkpoint; subsequent endpoint/RabbitMQ validation
changes need their own regression evidence. Combined recovery evidence is recorded in
[agent recovery](acdc_agent_recovery.md).

Coverage correction from the subsequent standalone-role audit: the 24-suite
plan did **not** include `scripts/test-install-kazoo5.sh`. That entrypoint's
ALL dry-run expectation used an obsolete Monster UI log string and was repaired
and passed separately (session `29889`). The earlier phases must not be cited as a
pass of that omitted script or of every installer test in the repository.
The queue editor source also changed in `8c11030`; its 15 source-only browser
cases passed, but the older compiled artifact above does not include that fix.

## Standalone-role verification follow-up

The verifier now checks RabbitMQ access to the configured vhost, not just the
user's password. It requires the installer-granted configure/write/read
permissions and an AMQP listener on the exact configured interface and port.
Both new inspections are read-only and bounded to 30 seconds plus a 5-second
termination grace; they are not independently byte-bounded. The installed
RabbitMQ 3.13.7 CLI's BEAM code was inspected offline (session `7497`) to establish
its real JSON envelope before constructing the test doubles.

Session `4354` passed 65 runtime-verification scenarios and all 32 existing
password-handling scenarios under a network namespace and the same resource
limits. The Rabbit verifier function and four focused test/fixture hashes were
identical before/after; concurrent endpoint edits elsewhere mean there is no
whole-installer unchanged claim for that run. Retained evidence:
`/tmp/kazoo-rabbitmq-verification-proof.rIg8PF/receipt.json`, SHA-256
`484c1fb58bc4f42bad34b25ee7602d2635710139c1c24608ff25fb4b68860c19`.
This is not a live broker permissions or connection test.

API/WebSocket settings now reject embedded credentials, queries, fragments,
invalid ports, invalid numeric IPv4 hosts and dot path segments before endpoint
logging or package/source effects. An external public API must return one
Crossbar-style JSON document, rather than arbitrary JSON or multiple documents.
Dry runs explicitly state that they did not install services or run live checks.

The first network-isolated combined attempt (`74102`) passed its 61 endpoint
cases, then stopped with exit 2 in the main smoke script. Inspection confirmed
that route discovery failed under `errexit/pipefail` before the intended
loopback fallback on a node with no external route. Correcting that code made
the same combined run pass (`8028`). Dedicated successful-route/no-route
fixtures were then added so this behavior is tested even on a host with a route.
These tests do not establish fresh-server package/dependency installation.

Final focused run `45471` exited zero: 71 endpoint/route/external-response
cases, followed by the main installer smoke suite including ALL. It also
covers browser-numeric host interpretation and uses a sanitized child
environment. Both ran under `unshare --net`, 120 seconds, 384 MiB and 768 MiB
reserve. The full-entrypoint portion targets Rocky Linux 9 explicitly.
Run the committed fixtures with:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 --runtime-sec 120 -- \
  /usr/bin/unshare --net -- /usr/bin/bash -e -c '
    /usr/bin/node /opt/kz5/scripts/test-monster-endpoint-preflight.cjs
    /usr/bin/bash /opt/kz5/scripts/test-install-kazoo5.sh'
```

Separate session `17657` exited zero for the read-only installer checks,
modular endpoint/service-gate suite, runtime configuration tests and all 12
Monster installer wiring/patch groups. It used the same isolated limits and
the locally retained pinned framework source. This is focused regression
coverage, not a rerun of the historical five-phase artifact checkpoint.

The later Blackhole pin/patch and protocol-documentation integration was checked
in session `29798` under the same 120-second/384-MiB/reserve-768-MiB network
isolation. The main installer smoke, `test-ecallmgr-current-build.cjs` and
read-only installer suite all exited zero. The build-reuse fixture now supplies
the additional Blackhole revision variable in its explicitly isolated shell
environment. The installer at this checkpoint has SHA-256
`da4e4c70ddc75f5d484082b74d8623f49deabb8267b6ef5212d81b1fe453732a`.
These are mocked/offline installer paths, not a Blackhole listener restart or
fresh multi-server installation. Protocol documentation's actual private
installer copy and browser checks are recorded in `api_developer_portal.md`.

The initial fast phase (36132) exited 127 because the private runner's PATH
omitted `/usr/sbin/ip`; its evidence remains at
`/tmp/kazoo-installer-regressions.suBkGL`. Restoring the guard's standard PATH
changed only the runner pin, not installer behavior or assertions. The failed
attempt is retained in the 44-file evidence manifest.

A later, separate full-script `shellcheck -S error` invocation (session 1228)
did not complete. Its validation unit
`kazoo-validation-0662ab15-6789-431f-b864-fb0a36c278e8.service` was cgroup-OOM
killed at 12:08:16 UTC, after approximately 13 seconds at the 384 MiB cap. The
retained journal identifies ShellCheck PID 303941 and `Result=oom-kill`; the
garbage-collected unit's later default properties are not a success receipt.
A lower internal GHC heap proposal was refused before linting because this
binary disables most RTS options. Neither attempt is a lint pass or an
installer assertion failure. Separate error-severity lint of
`test-acdc-strategies.sh` and `test-monster-catalog.sh` passed (exit zero).
Full installer lint remains unverified; shell syntax and the executable
installer regression phases above passed without raising the resource cap.

No live catalog write, agent action, call, restart, hotload, sysctl change,
shared BEAM output, actual source cleanup or deployment occurred in these
phases. Fresh-server dependencies, each standalone/distributed module,
reinstallation/reboot, legacy UI ownership adoption, authenticated browser
behavior, coupled callback native/eCallMgr integration and the external team's
P0 recovery fixes remain release gates. Passing these fixtures does not make
the currently combined ACDC runtime safe to deploy on its own.

## Fresh queue-recovery production bundle — 15:55–16:04 UTC

The current ACDC UI source, including `8c11030`, was freshly exported with the
pinned framework/apps into `monster-owned-build.xRMiDU/source`. This supersedes
the older artifact for source coverage, not for live deployment. Installer SHA
`84a140d6553c501b7d5b96f0b37b4382c6b0d6f8237e3f83710b1a67f333a20d`
and prospective build fingerprint
`bfea054efe952a71cf7c344088f61c40e72628cd239891b93547740b8a34c867`
were frozen before compilation and remained unchanged.

The preceding fresh attempt `14583` in `monster-owned-build.PH938c` was killed
by the cgroup memory limit during `buildRequire` at 15:31:17 UTC. Its unfinished
`running` receipt and partial outputs are retained and are not a build pass.
An earlier preflight there also exposed that host-mounted `/sys/class/net` can
show host interfaces after `unshare --net`; the corrected private runner checks
the actual namespace through netlink and separately compares namespace identity.

The new runner separates dependency inventory/copy/graph validation and native
Sass/RE2 smoke into a process that exits before compilation. Subsequent full
dependency inventories also run in disposable processes, keeping their large
objects out of the compiling parent. No memory limit was raised and no failed
build output was reused. Dependency verification `95907`, actual build `72306`
and readback `15995` all exited zero. Compilation retained the normal production
prepare, per-file minification/AMD verification, and finalize phases. Build
peak reached 384 MiB with zero OOM events/kills. Existing legacy build-tool
warnings remain; this is not a warning-free build claim.

Readback verified 1,931 files, 465 compiled templates, 16 canonical preloads,
10 selected-app metadata documents and unchanged runtime configuration. It
reported actual artifact SHA-256
`5910add4beff42042b9ffb8f412676dec0b82d4110df5dbc182b8e2515c5117a`.
Protected receipts in `/usr/local/src/kazoo5-installer/monster-owned-build.xRMiDU/`:

- `dependencies-receipt.json`: `d6303cfddaad1b52baa7ae02f19ca8b5cafafeb521b98ac55521a0dc39c3117b`.
- `build-receipt.json`: `9b812eae9584b869fc6d26179cdc210c8a9a68f2638de67671145323dc6780b5`.
- `readback-receipt.json`: `6bfc7b8598a63d612db901703abf553ed8b1893c1c50506419c4ef16d92e0fc0`.

The actual-artifact browser harness now includes five editor recovery cases:
pending recovery blocks duplicate writes while retaining edits, failed GET
preserves the draft/pending request and requires explicit retry, and late GET
responses are ignored after view replacement, account change or detachment.
It uses the real bundled application, compiled templates, handlers and Chosen
widget; only the fixed in-memory API responses are substituted. No token,
successful authentication or live endpoint is used.

Before-fix run `17814` booted the historical `pfUGAT` bundle and failed the
expected pending-recovery assertion after its GET/update/deferred-GET sequence.
It did not reach all later recovery cases. The first proposal failed earlier
because its Node executable had two hard links; that retained preflight failure
is not a UI regression. The corrected run used the already accepted single-link
copy with identical executable bytes.

Current-bundle run `63918` passed. After promoting the byte-identical harness to
the repository, run `88551` also passed actual unauthenticated boot, queue-specific
login and all five recovery cases, with zero page/console/route/request errors.
The API mock was restored and artifact, application methods, templates and input
hashes remained unchanged. Repository harness receipt:
`/tmp/kazoo-monster-repo-output.tbhz2o/monster-artifact-browser.CiY2Nx/receipt.json`,
SHA-256 `a2e5514c416a01725de86940efdda46a83d5dfddbb726db708a23f1c1995d1cf`.

No UI files were published. The read-only runtime probe confirms that the
matching backend is not yet deployed. See
[coherent upgrade readiness](acdc_coherent_upgrade_readiness.md) for the required
ACDC state migration/work gate. Clean-server dependency installation, all-node
activation, authenticated browser behavior and live calls remain unverified.
