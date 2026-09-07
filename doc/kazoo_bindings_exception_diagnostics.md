# Binding exception diagnostics (P0-16)

September 7, 2026: source and focused offline regressions verified; deployment
and live logging acceptance remain open. This is not a platform stability claim.

## Defect and change

`kazoo_bindings` assumed a stack frame's argument field was always a list.
Valid integer arities instead raised `bad_generator` or `badarg` inside exception
logging, allowing a second exception to escape the responder catch path.
Other diagnostics formatted argument values, frame metadata and exception
reasons that can contain request credentials.

The patch emits one bounded diagnostic containing the exception category,
responder identity and at most eight module/function/arity frames. Argument
lists are counted without formatting their values, with a255-argument bound;
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
arguments, under the serialized192MiB/512MiB-reserve guard and isolated network
namespace. The baseline intentionally exits nonzero.

- Current599852: all8 groups passed, evidence
  `/tmp/kazoo-bindings-exceptions.Lk6iaV`.
- Baseline35d013: all8 failed, including the actual logger `bad_generator,1`
  and `length(2)` crashes, evidence `/tmp/kazoo-bindings-exceptions.KeJpBf`.
- Both runs verified exact patch replay, current-source byte equality, reverse
  application and actual extracted installer helper application, idempotence,
  unmatched-source rejection and exact installer registration.
- Two production modules compiled with `-Werror`, the real Lager transform and
  no `TEST`/`export_all`. Runtime logger-argument assertions use the same source
  without the transform and substituted logger sinks, executing real registry,
  map/pmap/fold dispatch. Other dependency beams were not rebuilt or pinned by
  this focused test. No broker, API or production logger behavior is claimed.

Earlier runs exposed packaging/test defects: a missing final patch context line,
an invalid fixture format argument list, a missing one-argument logger sink and
an expected stack longer than OTP's backtrace limit. These were corrected before
the final baseline/current runs; earlier failures are not regression evidence.

No module deployment or service restart accompanied this fix. Deploy via a
reviewed build and verify real transformed logger behavior before closing P0-16.
