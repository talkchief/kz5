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

Production build `c56a9e`/`a1f197` passed artifact validation at
`/usr/local/src/kazoo5-installer/monster-owned-build.MwsDYg/source`.
Both temporarily paused services were restored and verified active. Owned
deployment `ec9a75`/`9f9af6` changed only main.js and preserved1,943 files;
served index/main/configuration readback passed. Main SHA-256:
`a75c1b18ec02365047dda3704dac2c2daaa5835313d23eb2a8d3b4b6e77415c4`.
Templates retain
`fd6d1c690383e1d1dc30c73435bdfa165728434e897db2d76fc391bf7418f0bd`.
Rollback: `/usr/local/src/kazoo5-installer/monster-owned-plan.Jha2kk/rollback`.

Fresh actual-browser check `3ff064`/`eefb87` passed initial dashboard rendering,
current plain labels, the deployed singleflight method, real selected-queue
confirmation GET and the agent Login dialog, with no page errors and no login
mutation. Subsequent production-shell/account-switch/reconnect checks are
recorded below. No source test alone closes P0-25.

The standard actual-deployed production smoke also passed seven checks
(`e5b91d`/`2241b2`, `/tmp/kazoo-monster-live-deployed.5gI81P/receipt.json`):
normal login, current overview, selected-queue detail, native subscription ACK
and refetch, controller disposal, acknowledged unsubscribe, and exact served
asset hashes. It recorded zero page/console/HTTP/scope errors, three subscribe
and three unsubscribe ACKs, and no injected events or calls. Ecallmgr was
temporarily paused for browser memory admission and restored/verified active.

Normal account-switch smoke passed ten checks (`45576a`/`e20ac1`,
`/tmp/kazoo-monster-live-deployed.3FFBzz/receipt.json`), including acknowledged
home disposal, selected account scope, and restoration of the home account.
It also recorded zero page/console/HTTP/scope errors. This used an administrator
switching accounts; it is not fresh restricted-principal authorization proof.

Reconnect checks against the same deployed bundle:

| View/scope | Evidence | Checks |
| --- | --- | --- |
| Summary, home account | `43b917`/`9f0cb4`, hltOHJ receipt | 7 passed |
| Detail, home account | `1ff77a`/`74873d`, jDrUgY receipt | 9 passed |
| Summary, switched account | `5c93b8`/`3d186b`, hcjYc6 receipt | 10 passed |
| Detail, switched account | `2b28d4`/`6dafbe`, 2rApWe receipt | 12 passed |

Receipts reside under `/tmp/kazoo-monster-live-deployed.<suffix>/receipt.json`.
These tests close only their own browser socket, verify visible stale state,
new-connection subscription acknowledgements and subsequent no-store readback,
then verify navigation disposal. Periodic reconciliation was not excluded as
an additional refresh cause; this is not a proof that reconnect alone caused
every refresh. No calls/events were injected. Both ecallmgr and simulated test
phones were temporarily paused for memory and restored by the wrapper; apps,
Blackhole and the broker stayed running. An earlier summary attempt
`ded5b8`/`889360` was refused before browser execution by the memory guard.

All four reconnect receipts report zero console/page/HTTP/scope errors and
successful return/navigation cleanup. Controlled HTTP stalls/late replies and
never-settling loader delivery remain acceptance gaps; these successful idle
browser tests do not establish load, active-call or cluster-failure reliability.

Final snapshot `1a05df`/`d94553` and comparison `fecef6` prove the original queue
roster and all31 reported statuses/memberships unchanged after the build and
browser jobs. No restoration writes were performed. The same final check found
all nine scoped services active and zero FreeSWITCH calls. Source commits are
`9f695ed` (editor/read/wording/content-type fixes) and `b02f7fe` (loader fix).
They are local kz5 commits, not a master push or production-readiness claim.
