# Installer build identity — September 6, 2026

The installer explicitly recompiles Erlang source instead of trusting artifact
timestamps. It also rejects source or artifact drift before reusing a successful
build for ecallmgr within the same invocation.

## Implementation

- `KAZOO_FORCE_RECOMPILE=1` forces the existing per-project full-source compile
  recipe. Its order-only beam dependency prevents parallel per-beam recipes
  racing the batch compiler. Normal developer incremental builds are unchanged.
- The number and MIME generator targets are explicitly phony for their targeted
  installer invocation. No global `make -B` or dependency-download forcing is
  introduced.
- After production-BEAM validation, a content snapshot covers selected source,
  headers, build scripts, generator data, dependencies, BEAM/application files,
  version inputs and compiler environment. Before ecallmgr activation/reuse,
  mismatch or missing proof is fatal. The proof is not persisted across runs.
- Linked source directories are rejected; selected linked files are hashed by
  content and dangling links fail. Git and build-tool cache trees are excluded.

## Evidence

`test-kazoo-force-recompile.cjs` passed 12 commands with real private Make/erlc
and BEAM readback, including future timestamps, normal incremental behavior,
forced current-source compilation and compiler failure. Receipt:
`/tmp/kazoo-force-recompile.8X2lwo/receipt.json`.

`test-kazoo-generated-rebuild.cjs` passed seven groups / 17 commands, using the
actual number/MIME Makefile recipes with tiny private inputs and real Erlang
compilation. It reproduced stale generated output with older input mtimes,
verified targeted regeneration, and rejected malformed JSON/MIME data. No
download rule ran. Receipt: `/tmp/kazoo-generated-rebuild.a46KIZ/receipt.json`.

The content snapshot fixture, ecallmgr build-reuse fixture and complete installer
dry-run smoke suite passed together in session 46576. This included all module
options and ALL, drift refusal before activation, invalid proof, failed BEAM
verification, and dry-run behavior. These tests ran network-isolated with a
256 MiB cap, 768 MiB reserve and 120-second deadline. The real generator fixture
used the same limits with a 60-second deadline. An earlier 320 MiB attempt was
refused before execution because available memory did not meet cap plus reserve.

## Remaining limits

These are focused regression tests, not fresh distributed installation or live
deployment certification. The post-build snapshot detects later drift; it does
not prove inputs were immutable throughout compilation or provide an atomic
service activation barrier. Native components need their separate identity and
integration checks. No running service, shared BEAM or live call was changed by
these tests. Canonical Gemini-source/runtime parity must be reconciled before a
full rebuilt deployment, otherwise existing live prompt selection could regress.
