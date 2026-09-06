# Combined ACDC source validation — 2026-09-06

ACDC remains ordinary tracked kz5 source, not a submodule or nested repository.
The current combined branch contains the team's migration `1634524` and
availability fix `83194e7`. No separate ACDC commit, push, deployment or service
restart was performed during these checks.

## Unit suite

Root validation session `73318` exited **0**, with **all 48 tests passing**.
The isolated compiler and EUnit VM used the current bundled source, including
the three delayed queue-notification/direct-call recovery regressions.

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 --runtime-sec 120 -- /usr/bin/bash /opt/kz5/scripts/test-acdc-unit.sh
```

Earlier sessions `54936` and `64163` failed in mock setup under EUnit's default
five-second wall timeout. They are retained as failed runs, not superseded
success receipts. The runner now uses EUnit's documented `scale_timeouts=4`
option for the CPU-limited host. The outer 120-second deadline, 384 MiB cap,
zero swap and 50% CPU quota remain unchanged. No production timeout or assertion
was relaxed. The queue-manager fixture now mocks only its explicit configuration
readers rather than recompiling and invoking the real configuration module.

Validated input SHA-256:

```text
39719efb64169514a18dced8242cb5d6bcce152c7d3891816d3e975e086785fb  scripts/test-acdc-unit.sh
3fd8ea756734b7a021508a498cc23393328dcad626fedc96d8f9142a4e1dd31f  applications/acdc/test/acdc_queue_manager_tests.erl
```

## Source ownership and historical test projection

Agent validation session `57076` exited **0**. Six Python ownership groups and
the Node runtime-input tests passed, along with syntax and scoped diff checks.
Both real deep-clean recipes ran only in disposable Git fixtures: tracked
source, tracked generated-looking files and unrelated notes survived; ignored
build outputs were removed without following symlink targets.

Historical replay excludes bundled `test/`, which that suite does not compile.
Its actual separate Erlang fixtures remain fingerprinted. Synthetic tests prove
that unrelated bundled test edits do not block replay but runtime source drift
still fails. The separate historical replay-only session `26391` subsequently
exited **0**: the deterministic 165-asset map matched, all four production
modules compiled with `-Werror`, no TEST exports or staged language imports
were present, and the before/after runtime-input fingerprints matched.
This is historical compatibility proof, not acceptance of the current bundled
language/atomic runtime or its coupled eCallMgr/native changes.

Private detailed receipt:
`/tmp/kazoo-acdc-source-maintenance.VXoE73/REVIEW-RECEIPT.md`, SHA-256
`7e711e2c76dc796cc416015e1eb8976875403f0f0fb9000f6d35830439ea9cdc`.

## Remaining release gates

P0-07/08/09 are assigned to the operator's external team and remain open until
their branch is integrated and independently verified. These source checks do
not establish live queue ringing, callback audio/DTMF/retries, multi-node
recovery, a clean-server install, or production readiness. See `PROJECT_TASKS.md`
for the complete scope; no live acceptance requirement is waived.
