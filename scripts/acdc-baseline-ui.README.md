# Temporary ACDC baseline UI deployment layer

This is a narrow compatibility release based on commit
`57560824fc7457c0e506c3bbd416c64ec9be4562`. It does **not** replace or roll back the
staged aggregate-editor implementation in `monster-ui/acdc`, and does not claim
aggregate API deployment, voice activation, native listening approval, or
complete multilingual prompt packs.

The overlay removes four queue-announcement and six callback recording
selectors. There are no hidden required replacements. New queues omit these
media fields and use backend defaults; PATCH omits them and preserves existing
custom/immutable recordings and the legacy returned-confirmation field. Hold
music and pre-connect media selectors remain available. Original prompt state
is retained privately in form data, not submitted as a stale replacement.

Independent callback-offer controls use the already deployed backend contract:
`callback.announcement.enabled`, `initial_delay` (1–3600 seconds), and `interval`
(15–3600 seconds). Defaults are true/30/60. Inactive timing inputs are disabled
and omitted from PATCH so they cannot prevent saving or erase the stored
schedule. Disabling the offer does not disable callback registration.

EN, AR, HE, ES and FR retain the baseline capability checks. No readiness file
is generated or installed. Incomplete packs remain unavailable; retained
legacy language selections are not new readiness claims.

## Build and offline verification

Use existing local Monster UI build dependencies; no dependency download is
performed. Source inputs and the three overlay anchors are pinned/hashed.

```sh
node scripts/build-acdc-baseline-ui.cjs
/tmp/kazoo-ui-browser.eXdEqS/node_modules/node/bin/node scripts/test-acdc-baseline-ui.cjs /usr/local/src/kazoo5-installer/monster-acdc-baseline-XXXXXX
```

The builder prints its newly created mode-0700 private directory, containing
`src/apps/acdc`, `dist/apps/acdc`, and `baseline-build.json` with source and
compiled hashes. Tests use real offline Chromium, block every network request,
exercise native HTML form validity and serialization, and verify every unrelated
baseline app method/request remains unchanged. The build does not touch the
live webroot, aggregate source, services, capabilities or database.
The build uses the existing Node 18/native Sass environment; the browser test
uses the existing private Node 20+ runtime required by the installed Playwright.
Other hosts may provide their own compatible runtime and
`KAZOO_PLAYWRIGHT_MODULE` path without changing the overlay.

## Root-reviewed deployment only

First run the existing read-only browser preview against the private stage with
`KAZOO_TEST_ACDC_PROFILE=baseline` and aggregate-editor testing **disabled**.
This explicit profile verifies the pinned manifest, absent editor endpoints,
omitted prompt controls, and preserved overrides; default staged/aggregate
assertions remain unchanged. Root may run it with the existing protected login:

```sh
KAZOO_TEST_ACDC_PROFILE=baseline \
KAZOO_TEST_ACDC_STAGE=/usr/local/src/kazoo5-installer/monster-acdc-baseline-XXXXXX \
KAZOO_TEST_INITIAL_DELAY=true KAZOO_TEST_CALLBACK_ANNOUNCEMENT=true \
KAZOO_PLAYWRIGHT_MODULE=/tmp/kazoo-ui-browser.eXdEqS/node_modules/playwright \
/tmp/kazoo-ui-browser.eXdEqS/node_modules/node/bin/node scripts/test-monster-acdc-readonly.cjs
```

Authentication is the only write allowed by that preview harness. The offline
test above does not authenticate or contact a service. Keep the deployed language capability
file authoritative. Deployment should replace only the reviewed compiled ACDC
app and its localization/static files, preserving readiness and every other app.
If ACDC is preloaded as a named AMD module in the web shell, use the existing
exact-AST removal/cache configuration procedure to replace that one definition;
do not rebuild or replace the full shell. Back up exact old bytes and verify
hashes before any replacement. Root owns deployment, rollback and live tests.

This layer resolves the mandatory blank prompt selection blocker without
requiring an aggregate backend rollout. It is not a claim that all queue,
callback, installation or production acceptance testing is finished.
