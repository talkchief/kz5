# Blackhole and Crossbar source upgrades

The existing `scripts/install-kazoo5.sh` entry point now upgrades the known
previous integration patches as well as accepting clean and already-current
sources. No extra deployment entry point or nested Git commit is required.
ACDC remains directly tracked in kz5 and is not handled by these transitions.

## September 8: normal-build schema formatting

A real apps/eCallMgr reinstall (`39751/8e209c`) passed voice media verification
but stopped before compilation/restarts because the previous build had formatted
three Crossbar schemas. `make/kz.mk` includes the `json` target in compilation;
that target invokes `scripts/format-json.py`. The resulting byte changes were
not functional schema changes, but invalidated the raw aggregate reverse check.

`crossbar-build-json-format.patch` records the complete raw and formatted bytes
of `channel_monitoring.json`, `queues.json`, and `queue_update.json`. The same
raw schema sections occur in the current, pre-icon and before-frame aggregates.
The helper recognizes only those exact complete representations, privately
reverses known formatting where needed, then rehearses the ordinary source
upgrade and proves the complete current aggregate. Actual normalization occurs
only after the existing source metadata/byte and patch-input rechecks.

No generic JSON equality or reserialization is used to accept caller input.
Duplicate keys, semantic/property edits, partial formatting and arbitrary
whitespace changes remain unknown edits and are refused without source writes.
Unrelated files and supported comments outside owned Erlang hunks remain
preserved. A subsequent normal build may format the schemas again; the same
known representation can be recognized on the next installation.

The new regression suite adds real install/formatter/reinstall cycles and raw/
formatted previous-state cases. Consult `PROJECT_TASKS.md` for its latest
executed result; source edits or a prepared test are not acceptance evidence.

Executed26154/15c456:110 source-transition cases, installer smoke checks and12
catalog tests PASS. Evidence `/tmp/kazoo-source-transition-tests.x7UYvz`.
Actual server transition82966/00c47b also PASS, with source preflight retained
at `/tmp/kazoo-integration-preflight.LLkrRB`. Full apps/eCallMgr installation
must still pass separately. A build interrupted between schema formatting steps
can leave a mixed state, intentionally refused for inspected recovery.

### Earlier source-transition checkpoints

`apply_kazoo_integration_patch` accepts `blackhole` or `crossbar`, plus
`mod_kazoo` with an explicit canonical source-directory argument:

| Family | Supported previous integration | Transition to current |
| --- | --- | --- |
| Blackhole | `blackhole-token-redaction.patch` | `blackhole-redaction-to-integration.patch` |
| Crossbar | `crossbar-kazoo5-before-frame.patch` | `crossbar-blackhole-frame-schema.patch` |
| mod_kazoo | `mod-kazoo-before-version.patch` | `mod-kazoo-version-namespace.patch` |

The mod_kazoo extension and its aggregate-versus-individual-series verification
are documented in [the version namespace correction](mod_kazoo_version_namespace.md).
Session `33997` reran all 42 Blackhole/Crossbar cases successfully after that
extension; evidence: `/tmp/kazoo-source-transition-tests.RhuupY`.

The retained Crossbar previous patch is byte-identical to the aggregate at
`63e6bf7` (SHA-256 `5ec8f080b30054404c2fe181f46ea6bfa5ccb98ec9f4cec49b73ef0ff32b05a3`).
Classification checks complete supported patch hunks, not whole-source equality;
unrelated source comments and files are intentionally preserved. Unknown partial
states stop rather than resetting or attempting arbitrary patch repair.

Before writing source, the helper validates the fixed file inventories and
canonical, non-linked paths, copies the relevant files into a protected
`/tmp/kazoo-integration-preflight.*` directory, applies privately and verifies the
complete current patch in reverse. It then rechecks original bytes/metadata and
patch hashes, applies the selected patch, and checks the final bytes and modes.
Preflight copies are retained for inspection and recovery. Inherited `GIT_*`
overrides are removed only inside the helper's subshell. Staging and apply
commands explicitly stop on failure, including when a caller suppresses Bash
`errexit` by testing the function's return status.

Dry-run checks required patch files but allows absent source trees and explicitly
reports that source-state validation has not run. Normal Git ownership semantics
apply. This is not a crash-atomic multi-file transaction or protection against
a malicious concurrent writer after the final preflight check. I/O failure stops
for inspection; it does not trigger an automatic source reset.

## Verification, 2026-09-06

Guarded session `36178` passed all 42 cases in
`scripts/test-kazoo-source-transition.sh`, then `scripts/test-install-kazoo5.sh`.
The runner extracts the actual helper from the main installer, checks both call
sites and pins its inputs before/after; it never sources the full installer.
Fresh private archives use the pinned Blackhole and Crossbar Git objects.
Cases cover both families' clean/current/previous states, exact desired output,
unrelated edits/modes, idempotence, Git redirects, dry-run, missing/partial/unsafe
inputs, wrong transition results, failed staging allocation and failed copying.
Rejected cases require an explicit failure and unchanged target tree.

Evidence: `/tmp/kazoo-source-transition-tests.I8ZBgv`. The run used 384 MiB,
768 MiB reserve, a 180-second deadline and a private network namespace. The
preceding private 42-case candidate run `37511` is retained at
`/tmp/kazoo-source-transition-tests.gTAerv`; earlier 38-case evidence is not
substituted for the hardened result.

No services, live source checkouts or account data were changed by these tests.
Clean-server, separated-host, real upgrade and restart/reboot acceptance remain
open in INST-06/07; this checkpoint does not certify the full installer.

Session `15944` subsequently passed the ten Blackhole public-handler/redaction
tests and thirteen real Cowboy frame/wire groups with the updated installer hook
assertions. Fresh pinned patch replay and private production compilations passed;
evidence is retained at `/tmp/kazoo-blackhole-redaction.wjYFde` and
`/tmp/kazoo-blackhole-frames.nRY608`. These remain fixture-authenticated tests, not
live token-lifetime or tenant-isolation certification. The same bounded run
regenerated the API catalog's source provenance, passed deterministic/tamper and
schema checks, and rendered all 651 operations in isolated Chromium with ten
local requests, zero external requests and zero console errors. Only repository
assets were refreshed; the previously published `/apis` assets are unchanged.
