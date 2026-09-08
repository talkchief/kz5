# UI-01: optional storage lookup

## Diagnosis and source correction

The current ACDC create/edit form does not request `/storage`. Its real Add
queue and Save checks passed separately; the historical storage404 is not
evidence that it caused the independent queue-editor400.

SmartPBX user call-recording settings (`usersGetStoragePlan`) and Common's
`storagePlanManagerGetStorage` already handle a missing optional plan. Common's
storage selector did not: its GET had no error callback, so the completion
chain never settled on404 or other failures. A successful empty/null response
also caused its formatter to access properties of undefined/null.

Installer-owned source patch:
`scripts/patches/monster-ui-storage-selector-errors.patch`, commitf85bb21.
The installer fingerprints and requires it for fresh Monster source builds.

- HTTP 404 settles the selector's error callback, displays an unavailable warning,
  and does not open an empty picker or invoke selection success.
- HTTP 401/403/500 and transport failures still invoke the genuine global error
  handler and complete the selector error path.
- Empty successful storage data displays no available options, not a phantom
  plan. A real configured attachment still displays and selects normally.
- Caller-provided storage data still avoids the HTTP lookup.

No storage plan, account document, API response, or `cb_storage` registration
was created/modified to suppress the error. Main's module was absent at the
earlier diagnostic; a native missing account plan can also yield404. A404
alone cannot distinguish those causes. The backend404 remains visible in the
network console and must not be reported as eliminated by this UI correction.
Configuring actual external storage and capability-based request gating remain
separate work; this patch only fixes the broken selector error interaction.

## Native API installer correction

Follow-up f0eb1c confirms the main dev server still lacks `cb_storage` in both
effective autoload and running bindings. Source `configure_kazoo_api_modules`
now calls `configure_kazoo_storage_module`. It starts the native module only
when needed, checks exact startup/runtime membership, and confirms that all
previous modules remain. Malformed reads, failed start, missing persistence,
node-override mismatch and lost existing entries fail visibly. It does not
overwrite node overrides or fabricate storage plans. Already-registered and
dry-run paths do not mutate configuration.

`verify_acdc_interfaces` now includes read-only storage module verification
and a genuine administrator `/v2/storage/plans` collection read. It does not
require every account to have a custom storage document. Native module
authorization and provider configuration remain unchanged; no provider
credentials or imported company documents are edited.

Focused test `node scripts/test-storage-installer.cjs`: baseline ad354e fails
the missing installer wiring; candidate0e35e6 passes14 registration/preservation
cases. The adjacent entitlement verifier also passes8 cases. Final source/wiring
check a4c28f passes the same14+8 cases after adding the collection read.

Source10455c5 is pushed/synced and deployed on main through the exact installer
functions `configure_kazoo_storage_module` and `verify_kazoo_storage_module`.
Unit `kz5-storage-api-main44-20260908`, observer6730/132512, exits0 in5.854s.
Readback verifies effective startup/runtime membership and preserves previously
visible modules. There is no telephony restart or account/provider-plan write.

Native certificate-validated HTTPS check6c006e:

- Master login201 (an initial ad-hoc probe05ecdd failed at its login gate;
  it had required200 rather than allowing native201).
- Administrator `GET /v2/storage/plans`:200, successful empty collection.
- Anonymous same request:401, error envelope.
- Master `GET /v2/accounts/adecbb84fbe9e06902a76731914d1943/storage`:404,
  genuine absent optional plan. No plan was created to suppress this response.

The focused actual-Common-subscriber browser check was repeated because its
backend module changed: unit `kz5-storage-api-browser-main44-20260908b`,
observer83719/7e1624, exits0 in8.983s. Native404 completes the error callback,
shows a visible unavailable message and leaves the global indicator inactive,
with zero account writes. This remains a subscriber/HTTP test, not a manual
user-click test. Initial unit `kz5-storage-api-browser-main44-20260908` exited127
before launching the browser because a relative script path was resolved from
systemd's working directory; the successful unit uses the absolute script path.
All of these jobs are terminal. FullALL and external-provider write workflows
were not rerun and are not established by this scoped correction.

## Focused verification

Offline actual AMD-source check:

```sh
node /opt/kz5/scripts/test-monster-storage-selector.cjs PATH/TO/storageSelector.js
```

Run from a Monster build source directory with its installed lodash dependency.
Original source fails4 of7 groups; patched source passes7 of7 (`bddc23`).
Patch application check passes (`ac0622`); shell and JavaScript syntax pass.
An initial test double incorrectly treated jQuery's deep-extend flag as its
target; corrected before recording the baseline/candidate comparison.

Main deployment PASS through the normal `monster-ui` installer:
`kz5-storage-selector-install-main44-20260908`,22488/383cf4, exit0 in79.417s.
Three web files changed,1941 were preserved, none removed; the installed
ACDC language-capability file was preserved. Owned output, served bytes,
HTTPS, same-origin API and catalog checks passed. nginx was restarted;
telephony services were not requested for restart. Private log:
`/root/kz5-acceptance/storage-selector-install-main44-20260908.log`, SHA256
`db4012ee21e2f7cbe0c727637a76e2f08a0c6cff56de4e70950f117df174ef36`.
Retained deployment plan/rollback:
`/usr/local/src/kazoo5-installer/monster-owned-plan.cjzVLM/`.
Seven focused groups also pass against the actual installer-prepared source
`/usr/local/src/kazoo5-installer/monster-owned-build.BtHq0t/source` (`109341`).

The focused browser mode is read-only:

```sh
bash scripts/run-dev44-company-browser.sh --storage-selector-check
```

It invokes the actual public Common subscriber, accepts only the exact native
master-account storage404, requires its error callback and visible warning,
checks the loading indicator has settled, and blocks account writes. It does
not simulate successful HTTP data or claim a user-click workflow. Deployed
acceptance PASS in `kz5-storage-selector-browser-main44-20260908`,33704/37350c,
exit0 in9.931s: native404, settled error callback, visible unavailable warning,
inactive global indicator and zero account writes. This is not a configured
storage-provider write test or elimination of the native404. Both jobs are
terminal; reuse this evidence unless the related code or behavior changes.
