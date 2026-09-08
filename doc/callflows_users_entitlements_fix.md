# UI-03 — Callflows → Users entitlement failure

September8,2026. Fixed and deployed on **10.1.0.44:/opt/kz5**.

## Cause and source fix

The account entitlement handler existed but `cb_entitlements` was absent from
both effective Crossbar startup configuration and running bindings. Before the
fix, an authenticated master-account GET reproduced HTTP404. Registering the
module restored the imported Talkchief account's response, but exposed a second
fault: the master account's empty ancestor list reached `erlang:tl/1`, causing
HTTP500. The runtime diagnostic identified
`kz_entitlements:entitlements/1 → cb_entitlements:get_account_entitlements/1`.

`scripts/install-kazoo5.sh` now registers the module, verifies exact startup and
runtime membership, and probes the real master entitlement response during
authenticated installation verification. The root-repository patch
`scripts/patches/kazoo-entitlements-master-ancestry.patch` fixes all four account,
overlay and user ancestry paths. Empty ancestry is accepted; descendants still
skip only the master layer and retain reseller ordering. Authorization and
capability/enrollment calculations are not bypassed or replaced with fake data.
Normal source preparation applies this patch to the pinned Kazoo core checkout.
ACDC remains directly tracked in kz5; no nested repository was committed/pushed.

## Verification and deployment

- Focused ancestry EUnit:3 tests pass locally and on main; candidate production
  module compiles with `-Werror`, without TEST exports. Patch replay matches
  the actual core source. Main build evidence: `/tmp/kazoo-entitlements.R9V8Tgdy`.
- Installer wiring and8 exact registration cases pass. Missing startup/runtime,
  misleading module suffixes and malformed responses are refused.
- Main module hot-loaded successfully, with matching file/runtime MD5
  `b858c81c9b758a0eb6f4987e1df483ae`. Previous BEAM retained in
  `/root/kz5-acceptance/entitlements-deploy.gaX5SE8b/`; no service restart.
- Real authenticated master and copied-company requests return successful
  capability/enrollment objects. Unauthenticated request remains HTTP401.
- Actual browser **Users clicks PASS** for master (1 visible user) and copied
  Talkchief (15 visible users), with HTTP200 entitlements, no captured page/HTTP/
  insecure-request failures, request counter0 and inactive blue top indicator.
  Unit `kz5-callflows-users-controls-main44-20260908`, source b2d014c,
  terminal exit0 in17.682s; observer51327/211278.

Replay the directly relevant checks from main:

```sh
cd /opt/kz5
node scripts/test-entitlements-installer.cjs
bash scripts/test-entitlements-master.sh
bash scripts/run-dev44-company-browser.sh --callflows-users
```

The browser uses certificate-verified HTTPS over the private route. It does not
establish public-IP reachability. No company user, entitlement or call settings
were edited. Broader restricted-principal/enrollment-write matrices remain open;
this closes the reported Users lookup/load failure, not every entitlement feature.

Initial full legacy EUnit invocation passed the3 ancestry cases but cancelled
older entitlement-calculation generators because their datastore prerequisites
were absent. That invocation is not a full-suite pass. Initial browser assertions
incorrectly required a zero-height floating layout wrapper to be visible;
diagnostics showed its user row existed and no browser errors. The final test
checks visible controls and the exact visible row count instead, without changing
application CSS or weakening HTTP/error checks.
