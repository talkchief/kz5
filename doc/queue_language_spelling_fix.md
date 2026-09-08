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

Deployment through the normal `monster-ui` installer and served-artifact
verification are pending. Account/reseller default resolution and new-account
inheritance remain separate; this correction only aligns existing locale
spellings between the editor and backend. No database migration is performed.
