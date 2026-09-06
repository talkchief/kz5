# ACDC source in kz5

`applications/acdc/` is ordinary source tracked by the `kz5` repository. It is
not a submodule or a separate checkout. Review and commit its Erlang modules,
tests, views and build files with the rest of kz5. Generated BEAMs, application
files and dependency caches remain ignored.

The imported source began at `kazoo-community/kazoo-acdc` revision
`6f71c85f67ee2228efb0edceb5248b6334ba1998` and includes the local integration
work present at migration. Upstream licensing is retained in
`applications/acdc/LICENSE`. The migration preserves the existing source;
it does not certify or deploy the pending language, callback or atomic-answer
changes. The coordinated integration and live acceptance requirements in
`PROJECT_TASKS.md` still apply.

The installer uses the bundled source without cloning ACDC or applying the old
ACDC patch stack. Dependency fetching excludes ACDC, and deep-clean targets
preserve its source directory. A missing bundled directory must be restored
from kz5 rather than silently replaced with upstream code.

Deep clean removes only ignored ACDC BEAM/application outputs and dependency
stamps, using fixed paths. Tracked files (including `ebin/.placeholder`) and
unrelated untracked notes remain intact; generated symlinks are unlinked without
following their targets. The source-ownership tests exercise both clean targets
only in disposable Git fixtures, never the current working checkout.

`scripts/refresh-kazoo-integration-patches.cjs` manages only the remaining
external checkouts. The existing ACDC patch files remain historical fixtures.
The Gemini compatibility suite reconstructs its historical baseline privately
from bundled source by reversing the language/atomic layers; it no longer
requires ACDC Git metadata. That suite does not establish acceptance of all
current bundled behavior.

Only `src/`, `include/` and `priv/` participate in that historical projection.
Bundled `test/` changes are excluded from patch reversal and the runtime input
receipt because the suite compiles its separate `scripts/erlang-tests/` fixtures.
Those actual compiled fixtures remain fingerprinted; runtime source drift still
fails the historical patch checks.

Run source regressions separately to avoid competing Erlang mock compilation:

```sh
python3 scripts/test-acdc-source-ownership.py
bash scripts/test-acdc-unit.sh
bash scripts/test-acdc-strategies.sh
```

On the resource-capped validation host, run the strategy suite in two sequential
guarded invocations with `--shard 1/2` and `--shard 2/2`. Each prints the full
exported test inventory and its deterministic selection; both are required.
This avoids raising the guard's two-minute deadline or dropping assertions.
Without `--shard`, the script still selects the complete suite.

The outbound-agent regression covers a delayed queue satisfaction event during
multiple direct calls, readiness after the final hangup, preservation of an
existing pause and application of a pending logout. These checks run in
isolated processes and do not deploy or replace live BEAMs.
