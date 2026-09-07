# Foreground app preservation during background loading (P0-18)

## Cause and source ownership

The default-entry queue summary was visible, fresh and subscribed, but
`monster.apps.getActiveApp()` returned MyAccount. The framework's public
`apps.load` changed both `lastLoadedApp` and keyboard shortcuts whenever any
load finished. Core starts its background plugins in parallel, so late plugin
completion could overwrite the foreground app without changing the visible UI.

The canonical fix is
`scripts/patches/monster-ui-background-app-load.patch`, applied and fingerprinted
by `scripts/install-kazoo5.sh`. It changes pinned framework
`src/js/lib/monster.apps.js` and `src/apps/core/app.js`; do not commit a separate
framework repository or edit only the generated bundle.

Only explicit `{ background: true }` skips activation and shortcut replacement.
Core passes it for both ordinary logged-in plugins and the Common readiness
wrapper. Foreground loads still activate normally. Resource options, callbacks,
errors and Common readiness retain their existing behavior. The fix does not
save and later restore a potentially obsolete foreground value.

## Reproducible regression test

Run serially through the repository resource guard, using the existing pinned
framework cache and dependencies:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 90 -- /usr/bin/unshare --net /usr/bin/node /opt/kz5/scripts/test-monster-background-app-load.cjs --baseline
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 90 -- /usr/bin/unshare --net /usr/bin/node /opt/kz5/scripts/test-monster-background-app-load.cjs
```

The baseline command must fail with MyAccount replacing ACDC. The candidate
must pass all 12 groups. The runner evaluates actual pinned AMD implementations
with controlled deferred resource completion and UI sinks. It also checks
cached loads, later foreground navigation, callback/error identity, literal-true
selection, both Core branches, native default routing, and exact installer
forward/idempotent/reverse/conflict handling. It does not mutate the source
cache or access an API.

September 7 evidence: baseline `ef9a77` failed as expected, retained at
`/tmp/monster-background-app-proof.gFLwnE`; candidate `f43e08` passed all 12,
retained at `/tmp/monster-background-app-proof.PVeswA`. Both directories contain
input hashes, source lineage and receipts.

## Deployment acceptance

Fresh production build `e175b8` and deployment `e8e212` passed; stage/backup are
under `/usr/local/src/kazoo5-installer/monster-owned-build.OxxzgK/`. Only
main/templates changed, with 1,942 files preserved and zero removals. All four
same-account/company-switch summary/detail reconnect browser checks passed;
exact receipts and operational restoration caveats are in the reconnect guide.
The test harness also now waits for native startup routing and avoids reopening
an already-active default ACDC page; this separates startup navigation from
the reconnect controller-preservation assertion. Keep the deployed browser's
active-app assertion: do not replace it with a mounted-DOM-only check or fake
the framework marker. Re-run same-account and normal company-switch summary
and detail reconnect checks against exact deployed hashes. See
[the reconnect guide](monster_live_reconnect_acceptance.md).

Historical reporting and ClickHouse are postponed. This bounded fix and its
tests do not establish restricted-user isolation, TLS, cross-node failover,
load capacity or whole-platform production readiness.
