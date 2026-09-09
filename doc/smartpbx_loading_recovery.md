# SmartPBX loading recovery — September 9, 2026

## Reported failure and source fix

A controlled browser GET stall reproduced the reported behavior on kz5-dev:
the global request counter stayed at1, the blue progress indicator stayed active,
all nine SmartPBX categories remained locked, and no Retry control appeared.
This was not a service outage or a failed login. Baseline log on main44:
`/root/kz5-acceptance/smartpbx-before-20260909.log` (unit exited1).

Source fix `e7dfa14` is tracked in kz5, not only in the deployed web directory:

- `scripts/patches/monster-ui-bounded-sdk-reads.patch` gives SDK GET requests a
  15-second deadline. jQuery's native error completion releases the global
  request indicator. Mutation requests are unchanged; no write replay is added.
- `scripts/patches/monster-ui-smartpbx-loading-recovery.patch` makes all dashboard
  read branches propagate failures, complete once, and avoid formatting partial
  failures as empty successful data. The view shows an explicit error and Retry,
  releases category loading on failure, and retries only through user action.
- Render ownership and account checks reject dashboard results after navigation
  or account changes. Initial service-plan reads also propagate failure and
  display Retry instead of preventing the dashboard from ever rendering.
- Opening the dashboard no longer invokes an unused voicemail get-or-create
  operation. Voicemail creation remains in the existing setup flow; dashboard
  loading and Retry perform reads only.

The installer applies both required patches to fresh pinned checkouts, fingerprints
them for build-cache invalidation, and applies the SmartPBX patch only when the
`voip` app is selected. A future normal `bash scripts/install-kazoo5.sh monster-ui`
therefore includes the fix. Do not patch only minified `main.js` or commit changes
inside the pinned upstream repositories.

## Focused verification

`node scripts/test-smartpbx-loading-recovery.cjs <pinned-monster-ui-checkout>`
passes original-bug reproduction, forward/reverse patch checks, GET deadline and
unchanged mutation settings, all nine read failure paths, duplicate completion,
successful reads, absent directory, read-only dashboard behavior, service-plan
error/success/no-reseller paths, and installer wiring.

Normal main44 installer unit `kz5-smartpbx-ui-deploy-20260909.service` exited0
in1m10.207s. Its log is
`/root/kz5-acceptance/smartpbx-ui-deploy-20260909.log`; it reports served bundle,
API proxy, all ten app registrations, and nginx validation passing.

The deployed-browser acceptance command is:

```sh
bash scripts/run-dev44-company-browser.sh --smartpbx-recovery
```

It uses the protected development master login, real successful backend reads,
and injected failures in browser GETs only. All account writes are blocked. It
checks a stalled dashboard read, explicit Retry, delayed delivery, HTTP503,
successful retry, and a late successful dashboard response after Devices
navigation. It does not place calls, log agents into queues or modify companies.

Final unit `kz5-smartpbx-after-20260909.service` exited0 in25.242s. All six
browser checks passed against the deployed build. Retained logs on main44:

- Before: `/root/kz5-acceptance/smartpbx-before-20260909.log`, SHA256
  `0155f640afdb474299f1cb33b8a7ab00aae3bf80f036267f7482005100f3cc97`.
- After: `/root/kz5-acceptance/smartpbx-after-20260909.log`, SHA256
  `99609e953724489c92584f1850b75cd8377f165bd8cf81de1146670deb43bbc2`.

These checks address the reported SmartPBX initial/dashboard loading bug, not
every unrelated SmartPBX edit workflow or the separate never-settling AMD loader
release gap.
