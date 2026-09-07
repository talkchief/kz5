# Monster app-loader overlap fix

## Symptom and cause

The September 7 deployed browser repeatedly raised a TypeError while evaluating
`app.i18n.active().acdc.dashboard`. Exact hXJTv6 bundle frames were main.js
84:4859,84:4695,83:25753,83:5048. This happened after a successful dashboard GET;
it is not evidence that agent login or queue data failed.

The native loader caches only completed public calls but exposes the shared AMD
app object while construction is still running. A second `_loadApp` resets its
`data`, including translations read by the first render. The source regression
reproduces the missing translation table and original failing render on the
pinned old loader. Actual browser interleaving still needs post-build evidence.

## Code ownership and behavior

`scripts/patches/monster-ui-app-load-singleflight.patch` is applied and
fingerprinted by `scripts/install-kazoo5.sh` after the background-app-load patch.
It wraps `_loadApp`, shared by public and dependency loads, and checks a pending
construction before accepting an already-published app. Identical effective
name/source/API loads share construction. Conflicting sources/APIs fail
explicitly. Limits are 32 simultaneous constructors and 32 waiters per app.

Each public caller retains its own foreground/background completion behavior.
Locale loading, fallback and native auth initialization remain authoritative;
the patch does not assign account IDs or manufacture fallback translations.
Failed attempts remove only their own partial cache and subscriptions. Pending
submodule siblings finish before retry is allowed, preventing late mutations
of the same AMD object. Failed subscription cleanup blocks a new constructor.
One consumer exception is reported asynchronously without stranding other
accepted callbacks.

There is no new timeout that abandons callbacks still capable of mutating the
shared object. A never-settling module delivery remains pending. The separate
ACDC read watchdog does not certify loader or network liveness.

## Evidence and remaining acceptance

Root `fe213e`/`d8fe85` passes all16 actual-loader offline groups, including old
source reproduction, constructor/init counts, dependency/public overlap,
partial-cache gating, foreground/background behavior, source/API conflicts,
module/locale/submodule failure, retry cleanup, account/locale native behavior,
callback isolation and capacity limits. The test executes actual pinned loader,
monsterization, locale and auth init source with controlled delivery/UI sinks.
It also tests forward/idempotent/reverse installer patch application.
Evidence: `/tmp/monster-app-singleflight-proof.V1WiPI`.

Two preceding failures were in the candidate test packet: a missing final
patch context line, then an omitted fixture `parseVersionFile` dependency.
Their evidence remains in olgtjR and V0OYj7; neither is claimed as a passing run.

Production build/deployment and fresh-browser first-open, reopen, account/tab
switch and reconnect checks remain required. No source test alone closes P0-25.
