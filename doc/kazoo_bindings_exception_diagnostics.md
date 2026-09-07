# Binding exception diagnostics (P0-16)

September 7, 2026: focused regressions, actual Lager-transformed runtime checks
and controlled deployment completed. Both application and ecallmgr nodes loaded
the verified module, followed by a successful isolated natural-call check.
This is not a whole-log audit or a production/platform stability claim.

## Defect and change

`kazoo_bindings` assumed a stack frame's argument field was always a list.
Valid integer arities instead raised `bad_generator` or `badarg` inside exception
logging, allowing a second exception to escape the responder catch path.
Other diagnostics formatted argument values, frame metadata and exception
reasons that can contain request credentials.

The patch emits one bounded diagnostic containing the exception category,
responder identity and at most eight module/function/arity frames. Argument
lists are counted without formatting their values, with a 255-argument bound;
integer arities are accepted. Unknown shapes are summarized rather than dumped.
Logger exceptions are caught, so logging cannot replace the subscriber exception.
The original returned exception terms and fold continuation are preserved.
This does not repair the existing returned-error fold badmatch or audit every
binding-registration/server debug log; those are outside this narrow change.

## Reproducible installation

Core is a pinned dependency checkout, unlike directly tracked ACDC. Do not commit
to its nested Git repository. The canonical kz5 artifact is
`scripts/patches/kazoo-bindings-exception-diagnostics.patch`, SHA256
`32577d89289c51831e7ca90d329a60eb1ce54fedc4d8398bfe5c5d3388ab2c8a`.
`scripts/install-kazoo5.sh` applies it in `ensure_kazoo_sources` after the existing
stacktrace-redaction patch. Unmatched source fails closed; repeat installation
recognizes the already-applied patch. Pinned baseline core revision:
`5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72`.

## Verification and limits

Run `bash scripts/test-kazoo-bindings-exceptions.sh --baseline`, then without
arguments, under the serialized 192MiB/512MiB-reserve guard and isolated network
namespace. The baseline intentionally exits nonzero.

- Current `063784`: all 12 tests passed, evidence
  `/tmp/kazoo-bindings-exceptions.QoJX0W` (`eunit.log`: eight sink tests;
  `lager-runtime-eunit.log`: four transformed runtime tests).
- Baseline `20b15f`: all 12 tests failed as expected, evidence
  `/tmp/kazoo-bindings-exceptions.yErKox`. Both suites ran despite failure.
- Exact patch replay, current-source byte equality, reverse application and the
  actual extracted installer helper verify application, idempotence,
  unmatched-source rejection and installer registration.
- Three production modules (`kazoo_bindings`, `kazoo_bindings_rt`, `kz_log`)
  compiled with `-Werror`, the real Lager transform and no `TEST`/`export_all`.
  The eight sink tests separately use untransformed source and substituted
  logging sinks while executing real registry and map/pmap/fold dispatch.
- The four additional tests execute the production-transformed module with real
  pinned prebuilt Lager, its formatter and a bounded private in-memory
  `gen_event` backend, without meck in that VM. They verify nonempty expected
  diagnostic counts/categories/responder identity, redaction and preserved
  responder exception behavior. Loaded module paths, compile options and
  artifact MD5 are checked. This is not a full Lager application/file-handler
  test; other OTP/`ERL_LIBS` dependencies remain prebuilt, unrebuilt and unpinned.

### Historical offline evidence

These earlier eight-test runs remain useful historical evidence, but do not
establish the later actual transformed logger runtime coverage:

- Current `599852`: all eight groups passed, evidence
  `/tmp/kazoo-bindings-exceptions.Lk6iaV`.
- Baseline `35d013`: all eight failed, including the actual logger `bad_generator,1`
  and `length(2)` crashes, evidence `/tmp/kazoo-bindings-exceptions.KeJpBf`.
- Those runs compiled two production modules with the real transform, but their
  runtime logger assertions used untransformed source and substituted sinks.

Earlier runs exposed packaging/test defects: a missing final patch context line,
an invalid fixture format argument list, a missing one-argument logger sink and
an expected stack longer than OTP's backtrace limit. These were corrected before
the final baseline/current runs; earlier failures are not regression evidence.

## Controlled deployment and post-deployment check

Deployment retry `be1cb5` installed the canonical
`core/kazoo_bindings/ebin/kazoo_bindings.beam`, SHA256
`3f25b067e2a7755fdf4672d2be3190b21d27aa22f537e75863895fb927897d8f`.
Controlled application/ecallmgr restarts loaded MD5
`3878349fd51aef5da317aeae54c56636` on both nodes. The retained backup is
`/tmp/kazoo-bindings-deployment.xJ8CQB/kazoo_bindings.before.beam`.

The initial deployment verifier `99329b` could not read the root-private
temporary artifact and rolled back. The corrected verifier reads the installed
target; the retry passed. Do not count that first verifier failure as a module
regression or a successful deployment.

Actual post-deployment natural-call run `befb40`, evidence directory
`/var/log/kazoo-strategy-acceptance-3KSFIT/`, passed with 13 valid HTTP snapshots,
three natural invalidations, one offer/bridge and 12 stable native samples.
Cleanup passed, and the exact MASTER snapshot remained unchanged. This confirms
that isolated call/dashboard flow after deployment, not live execution of every
exception/redaction branch.

A limited post-deployment check found no new errors since the 04:49:37 restart. It was
not a whole-log audit, sustained-load test or proof that all logging paths are
credential-safe. The scoped transformed-runtime fixture remains the evidence
for this patch's diagnostic/redaction behavior.
