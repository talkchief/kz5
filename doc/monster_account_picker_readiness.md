# Native account-picker readiness

2026-09-07 — focused checks, production build and deployed company-switch acceptance passed.

The deployed account-switch browser flow exposed an initialization race. Core's
`_loadApps` starts Common asynchronously; `monster.apps._loadApp` registers each
Common submodule's Postal callback before `monsterizeApp` installs `getTemplate`
and before native app initialization completes. Core's topbar could publish
`common.accountBrowser.render` during that interval. Actual diagnostic 3554
(`/tmp/kazoo-monster-live-deployed.QKTSG1`) reached accountBrowser.js:42 with
`getTemplate` unavailable. Diagnostic 67194
(`/tmp/kazoo-monster-live-deployed.kSyTvZ`) showed the first five Common modules
pending and the remaining 29 not yet requested. No failed dependency was
established; network idle was not an application-readiness condition.

`scripts/patches/monster-ui-account-picker-readiness.patch` modifies only the
pinned framework's `src/apps/core/app.js`, `src/apps/core/views/app.html` and
`src/apps/core/i18n/en-US.json`. It is applied after the existing branding patch
to Monster commit `7ef735eada6fd0e2b96c06f32c0bb868867f7d18` and participates in
the installer's build fingerprint.

The picker starts disabled, with `aria-disabled`, keyboard exclusion and a
visible loading status. Only the successful native Common-load callback may
enable it, and only for the canonical Common object with template/render/API
and locale helpers plus the initialized current-account ID. Direct calls to
`showAccountToggle` cannot publish while loading or failed. Duplicate callback
completion is ignored; older load generations cannot change current readiness.
Plugin names are deduplicated, preserving their first-occurrence order; repeated
configuration entries no longer start competing initialization tasks. For each
unique plugin, completion and navigation behavior remain unchanged.

Failure leaves a fixed visible instruction to reload the page. There is no
automatic retry into a partly initialized loader and no exception/body output.
A normal reload starts a fresh application instance. No authorization, account
selection, token, callback-context or submodule-registration behavior is changed.

## Validation

Root runs these within the serialized validation window:

```sh
node scripts/test-monster-account-picker-readiness.cjs /usr/local/src/kazoo5-installer/monster-ui
node scripts/test-monster-installer-preservation.cjs
node scripts/test-monster-installer-wiring.cjs /path/to/reviewed-patched-framework
```

The focused fixture privately replays the pinned source and actual installer
fresh/repeat patch hook; exercises actual Core and accountBrowser AMD handlers;
reproduces the old early-click exception; and checks success, failure/reload,
malformed/cached partial success, duplicate tasks/callbacks, stale generations
and unchanged navigation. Native load callbacks and DOM are explicit doubles;
it does not execute the complete AMD loader or a browser. Evidence is retained
under a private `monster-account-picker-proof.*` directory with input hashes.
The wiring suite's source argument must include the new patch because its final
check compares the configured framework bytes exactly.

Root run 98957 passed all 14 focused groups; retained evidence is
`/tmp/monster-account-picker-proof.SS17Sv`. Run 44606 passed all 11 installer
preservation groups. Fresh actual installer preparation 25080 succeeded at
`/usr/local/src/kazoo5-installer/monster-owned-build.nUolDS/source`, preserving
the existing configuration exactly. These are not deployment results.

Initial wiring run 13624 passed 11 groups, then found a socket source mismatch:
the fixture's reconstruction omitted the already-required WebSocket lifecycle
patch. The fixture now includes that patch after the socket-config patch and
reports only filenames, SHA-256 hashes and byte lengths on source mismatches.
This correction is not yet rerun; the production patches/installer remain frozen.

Corrected wiring run95129 passed all12 groups. Production build74495 and artifact
verification passed (19 apps, 466 templates, 1,931 files), with the pinned inputs
unchanged. Root deployment85061 changed only `js/main.js`, `js/templates.js`, and
`apps/core/i18n/en-US.json`; removed zero files and preserved1,941, including
configuration, prompts/capabilities and `/apis`. Recoverable backup:
`/usr/local/src/kazoo5-installer/monster-owned-build.nUolDS/deployment-backup`.
Owned-content/build-marker verification10382 passed. Apps/ecallmgr were restored
after the memory-bounded build window. Browser-scope fixtures3e50c7 passed16 groups.

Actual default browser74850 passed7 checks; switched browser69219 passed10,
including the ready picker, exact home subscription cleanup, target account
readback, summary/detail and normal return home after acknowledged disposal.
Receipts are `/tmp/kazoo-monster-live-deployed.w8N0gc/receipt.json` and
`/tmp/kazoo-monster-live-deployed.tE4KRo/receipt.json`. Both recorded zero console,
page, HTTP and blocked-scope errors. All8 services were active and zero calls
remained. The harness's separate home-admission guard was corrected and tested;
see `monster_deployed_account_switch.md`. This does not prove restricted-principal
isolation, browser rendering during a natural call, cross-node recovery or soak.
