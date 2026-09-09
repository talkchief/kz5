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
At the time of this UI correction, native `kz_media_util:prompt_language/2`
consulted the account document and account media configuration, not reseller
configuration. The later deployed follow-up in `media_reseller_language.md`
adds direct reseller fallback and records fresh-tenant native verification.
Cross-node cache propagation and actual inherited live-call audio remain open.

## Verification and deployment

- Baseline contract d5c05d: fails because `adopt` is true for an existing queue
  with no override.
- Candidate contract6f74ba and final296def: pass, including omitted/empty/unsupported language
  preservation, explicit adoption, the existing fifteen locale-spelling cases
  and new-queue English default.
- Focused browser command: `node scripts/test-monster-acdc-language-only.cjs
  --inheritance-only`, with the existing pinned browser and vendor dependencies.
  It uses the actual source/template/change/submit handlers and real Chromium
  validity checks, with only readiness data controlled. It is not a native API
  write or installed-media readiness test.
- Focused browser unit `kz5-inherited-language-browser-main44-20260909c`:
  observer36479/070f42, exit0 in1.312s. Four scenarios PASS with actual DOM,
  change/submit handlers and native form validation. No network requests or
  account writes. Readiness is controlled; this does not certify media readiness
  or native API acceptance of a legacy invalid empty language value.
- Initial browser unit4eb31e stopped before browser startup on the old full-suite
  fixture's hardcoded29-asset assertion (current map has42). Focused mode now
  bypasses that unrelated count because its readiness catalog is controlled;
  the old full media suite is not claimed to pass. Second unitffbad9 exposed
  jQuery1.9's `val(null)` retaining the first option. The source fix explicitly
  sets `selectedIndex=-1`; the third unit above passes. All three are terminal.
- Source c009191 was pushed to master and synced to `10.1.0.44:/opt/kz5`.
  Normal CLI `bash /opt/kz5/scripts/install-kazoo5.sh monster-ui`, unit
  `kz5-inherited-language-install-main44-20260909`, completed successfully:
  observer66827/5e3115, exit0 in80.184s. No apps/eCallMgr rebuild or restart.
- HTTPS67b094 fetched certificate-validated `/js/main.js`, `/js/templates.js`
  and `/apps/acdc/i18n/en-US.json`, compared them to installed bytes, and
  evaluated the compiled ACDC definition: three legacy/inherited states are
  preserved, new-queue EN and all five supported selections remain correct.
  nginx/apps/eCallMgr are active. No authenticated account writes. The first
  readback fd648c assumed a standalone HTML template and failed on the missing
  file; this release bundles templates into `js/templates.js` instead.

Retained main-server evidence:

| Artifact | SHA256 |
| --- | --- |
| `/root/kz5-acceptance/inherited-language-browser-main44-20260909c.log` | `37540e0338b0b37d4df5dfa1328f54a53fd43ba8b99dd14e5128b38cc9e38d0d` |
| `/root/kz5-acceptance/inherited-language-install-main44-20260909.log` | `8f885d0f4357d183d1514276fdaeb279344162d4e5dccb1117db0ed17b8c3adc` |
| Served `js/main.js` | `1b95b0ee1f437c8591a746f5b8e8e238ea9a8a0faac6d1ca18e551940072ad55` |
| Extracted ACDC definition | `2d7a45f5800f26f909ec501efc5b7c68d6253f880806b58171b01818c479193a` |
| Served `js/templates.js` | `a581c2733e6450dff0cc143309c6c3ebfbb374cfd651bb5ee8bf715b27fa1de1` |
| Served ACDC `i18n/en-US.json` | `81289775a08c870d6806bcc530601b3a0274af4f848e54c98900c1f088f7a323` |

Source: `monster-ui/acdc/app.js`, `views/queue-form.html`, `i18n/en-US.json`;
regressions: `monster-ui/acdc/tests/contract.test.cjs` and the browser script above.
