# Queue language spelling consistency

September 8, 2026 — VOICE-01 focused UI correction.

The backend canonicalizes supported locales (for example `HE_IL` to `he-il`).
The editor previously compared stored values literally, selected English for
`HE_IL`/`HE-IL`, and adopted English on Save when its pack was ready. Thus an
unrelated edit could change the spoken language of a legacy/imported queue.

`monster-ui/acdc/app.js` now normalizes case and underscores before choosing
among the existing five options. No sixth/custom option, language alias to a
different region, new account default or runtime TTS is introduced. If the pack
is unavailable, selection remains disabled and unrelated edits retain the exact
original stored value. Ready packs save the canonical spelling of the same
spoken language. Existing built-in adoption behavior is otherwise unchanged.

Evidence:

- Baseline `a9f2bc`: expected `he-il`, actual `en-us` for `HE-IL`.
- New regressions cover three spellings for each of five locales, serialization
  of ready selections, and preservation when readiness is unavailable.
- Full source contract `4ac811`: PASS. Its old native-SAY source expectation
  was updated to require the current prerecorded cardinal playlist. The initial
  full run `44dce2` failed that stale expectation; it is not a language-fix failure.
- Initial invocation `805831` lacked the documented build-directory Lodash
  dependency; it made no deployment or API changes.

Run from a normal installer-prepared Monster build directory with Lodash:

```sh
node /opt/kz5/monster-ui/acdc/tests/contract.test.cjs
```

## Deployment on the main development server

Source `d4eb7ad` was pushed to master and synced to `10.1.0.44:/opt/kz5`.
Normal `monster-ui` installer unit `kz5-queue-locale-spelling-main44-20260908`
completed successfully (`21645/6f16cc`, exit0,79.083s). Its retained log is
`/root/kz5-acceptance/queue-locale-spelling-main44-20260908.log`, SHA256
`b65913b5aee3a0d96f4e44904e13da0a9273a488f3103af39e42242cfc997900`.
Prepared build: `/usr/local/src/kazoo5-installer/monster-owned-build.elU8wE/source`.

Read-only served-artifact check `ef38b2` fetched certificate-verified HTTPS
`/js/main.js` through the private main-server address, matched installed bytes,
parsed the actual `apps/acdc/app` AMD definition and exercised its selection
functions. All15 spelling variants and disabled/unready preservation passed;
the five choices remain unchanged. No account writes or provider calls.

- Served bundle SHA256:
  `1236056403e75c0036380ecf4afdb4d1b0781db4099de5b85bad83deff788b79`.
- Extracted AMD definition SHA256:
  `1ea9dbf95b2a8acfa42180c03bdd95a0d6d18cd7c6ee631b5fa14bf36ff452b6`.

The first artifact check `2bec00` assumed a standalone `apps/acdc/app.js` file
and failed before evaluation. This release bundles the app into `js/main.js`;
the corrected check used the installed bundle rather than an HTML fallback.
This is served-code verification, not a new browser DOM/Save or live-call test.
Account/reseller default resolution and new-account inheritance remain separate;
this correction only aligns existing locale spellings between editor and backend.
No database migration is performed.
