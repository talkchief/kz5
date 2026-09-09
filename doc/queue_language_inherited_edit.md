# Preserve inherited language on unrelated queue edits

September 9, 2026 — VOICE-01 focused regression.

Queue admission uses the caller/account language when `announcements.language`
is omitted. The editor previously defaulted an unrecognized/omitted setting to
English and initialized built-in adoption whenever that pack was ready. Saving
an unrelated field therefore installed an English override and cleared queue
prompt overrides, changing the subsequent calls' spoken language.

The existing-queue form now preserves omitted and unsupported settings until
the operator explicitly selects one of EN, HE, FR, ES or AR. It does not claim
to know the language of a future caller. The dropdown has the same five options
but initially no selected item for these legacy/inherited queues, with a visible
explanation. Unrelated edits still submit; choosing a ready language uses its
built-in voice and clears old prompt references as before. New queues still
default to English. Existing supported spellings and same-language adoption are
unchanged; unavailable packs cannot be activated.

No new API request, schema, migration, account setting or audio is introduced.
All recordings remain checked-in artifacts; Gemini is not called. This fix
preserves existing inheritance, not a new reseller-default implementation.
Native `kz_media_util:prompt_language/2` currently consults the account document
and account media configuration, not reseller configuration; broader reseller
and new-tenant inheritance acceptance remains open.

## Verification and deployment

- Baseline contract d5c05d: fails because `adopt` is true for an existing queue
  with no override.
- Candidate contract6f74ba: passes, including omitted/empty/unsupported language
  preservation, explicit adoption, the existing fifteen locale-spelling cases
  and new-queue English default.
- Focused browser command: `node scripts/test-monster-acdc-language-only.cjs
  --inheritance-only`, with the existing pinned browser and vendor dependencies.
  It uses the actual source/template/change/submit handlers and real Chromium
  validity checks, with only readiness data controlled. It is not a native API
  write or installed-media readiness test.
- Browser execution and normal `monster-ui` installer deployment pending.

Source: `monster-ui/acdc/app.js`, `views/queue-form.html`, `i18n/en-US.json`;
regressions: `monster-ui/acdc/tests/contract.test.cjs` and the browser script above.
