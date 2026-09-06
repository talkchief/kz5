# Combined installer regression checkpoint — 2026-09-06

All five serialized offline phases passed before recovery merge `8548b98`:
24 suite invocations, with parent HEAD `860ce46` and the pending installer
changes whose exact hashes are recorded below. This verifies
the current installer changes, not a completed production deployment or a
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
hashes above remain unchanged. Combined recovery evidence is recorded in
[agent recovery](acdc_agent_recovery.md).

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
