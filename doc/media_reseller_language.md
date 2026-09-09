# Native reseller prompt-language fallback

September 9, 2026 — VOICE-01. DEPLOYED / scoped native verification PASS.

The native account-language resolver previously read only the account document
and its media configuration. A child without either setting used the system
default even when its direct reseller had selected another language.

The root-owned `scripts/patches/kazoo-media-reseller-language.patch` changes
`core/kazoo_media/src/kz_media_util.erl` through the normal installer. Precedence:

1. Account `media.default_language` (the account's `configs_media` document).
2. Account document `language`.
3. Direct reseller's `media.default_language`.
4. Direct reseller account document `language`.
5. The existing caller/system fallback.

The native resolver is used by call initialization and Callflow language setup,
not only ACDC. Explicit endpoint/call language and queue overrides keep their
existing precedence. Existing admitted ACDC calls retain their pinned language.
When `media.support_account_overrides=false`, account/reseller settings remain
ignored. No reseller-chain recursion is introduced. Missing/self reseller IDs,
missing reseller documents and failed optional lookups retain the old fallback.
Explicit account settings avoid reseller reads altogether. Native cached lookup
functions are reused; no new cache, schema, document write or migration is added.

All five built-in female voice packs are still shared immutable repository
artifacts. This change does not invoke Gemini, generate files, clone media for
tenants, or change recording overrides. It changes the spoken default of accounts
that previously had no setting when their reseller has one; it is not a claim
that Kazoo4 and5 can safely share writable production databases.

## Evidence

- Public production resolver tests (not a TEST-exported replacement):
  `bash scripts/test-media-language-inheritance.sh [--baseline]`.
- Baseline observer43934/f6b473:4 failures,10 passes in25.618s. All four failures
  return English instead of a configured reseller locale.
- First candidate21519/354f7c:14 passes,2 failures. The added error cases caught
  Erlang `try ... of` leaving exceptions in the optional lookup body unprotected.
  The whole optional lookup is now inside the protected expression.
- Final88114/f9bb3f:16 passes in30.708s, including optional fetch/config failures,
  explicit precedence, accountless/default resolution and disabled overrides.
  Evidence directory `/tmp/kazoo-media-language.0PM8xsbW`. The same runner proves
  exact patch replay from pinned core5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72,
  including a second idempotent application via the actual installer helper.
- Tests control document/config reads. They do not prove native tenant creation,
  cache invalidation across multiple nodes, live call audio or pronunciation.

## Focused native acceptance

`scripts/test-media-language-live.cjs --prepare` is main-dev-only and authenticates
using protected local installer settings. It creates a unique empty reseller
and child, both disabled, with no users, devices, callflows or queues. It records
their identities and pre-deployment language in the root-only receipt:
`/root/kz5-acceptance/media-language-fixture-20260909.json`.

After normal `kazoo-apps` deployment, `--verify` updates only that owned reseller
through the native HTTPS API, checks all five inherited locales using SUP,
and resolves three shared fixed prompts per locale for the child. An explicit
child-language check follows. The two accounts remain disabled for inspection;
normal ancestor descendant-count metadata changes from creating accounts are
expected. Existing company language settings are not changed. No calls, audio
generation, production writes or full-stack reruns are involved.

Do not blindly repeat a failed phase: inspect the protected receipt and exact
owned account IDs first. A completed verification is terminal. Further live call
and cross-node cache/inheritance acceptance remains a separate gate.

Preparation unit `kz5-media-language-prepare-main44-20260909b` completed
successfully (9781/cfbe01,6.429s). Native fea520 confirms:

- Reseller: `6973ed5f3a10447bf8c4513ed38ef0c0`, language `he-il`.
- Child: `3575eada00b4f501100ef1d17d47b191`, no stored language, native result
  `en-us` before deployment. Its native reseller ID matches the owned parent.
- Both accounts disabled; no users, devices, callflows or queues; zero calls.

The initial prepare unit3000/fb4822 stopped after creating only the reseller:
native account creation initializes pvt_enabled independently of public
enabled:false. Readback f6f0d3 confirmed it was enabled, with no users/devices.
The harness now disables each owned account using the supported PATCH and checks
native `kzd_accounts:is_enabled`. An identity-checked `--resume-preparation`
completed the same receipt; no duplicate reseller. Verification marks its phase
before mutations, so an incomplete verify cannot silently start over.

Source11030da was deployed by normal CLI unit
`kz5-media-language-install-main44-20260909` (87990/7dd90b): exit0 in11m46.774s,
382.2MiB peak. The protected verify phase then ran as
`kz5-media-language-verify-main44-20260909` (43356/3d60a1): exit0 in21.772s.

- All five reseller account-language updates propagated to the child, which
  had no stored language override during those checks.
- For each locale, the child's native default resolver selected the exact
  immutable IDs for position prefix, callback offer6 and callback success:
  fifteen shared prompt resolutions, without generating or copying any voices.
- Setting the child's language to Spanish preserved Spanish when its reseller
  changed back to Hebrew. Both remain disabled and empty, retained for inspection.
- This is native account API/resolver/media-document evidence, not live call
  audio, native pronunciation, broker-failure or multi-node cache acceptance.
  The media.default_language configuration branches have unit coverage, not
  a separate native configuration-write case in this fixture.

The apps-only installer correctly restarted its selected service but eCallMgr
still held the previous shared module (`code:module_status` reported modified,
5c3149). With zero calls, scoped unit
`kz5-media-language-ecallmgr-main44-20260909` initialized installer preflight,
restarted eCallMgr, ran its existing verifier and refreshed the existing owned
media mappings. It also published `/apis`; exit0 in59.720s (2382/7b2519).
No build guard was bypassed and no second compilation was performed. For shared
core changes, include every affected local Kazoo role in deployment planning;
installing one modular role must not implicitly restart unrelated services.

Final79407f proves both `kazoo_apps` and `ecallmgr` use the compiled production
`/opt/kz5/core/kazoo_media/ebin/kz_media_util.beam`, with running/disk MD5
`a3a2e5921dbed0ed2a973e3362d93de4`. Source patch reverse-check passes; nginx,
apps/eCallMgr are active and FreeSWITCH reports zero calls. Certificate-verified
HTTPS `/apis/openapi.json` matches installed bytes and documents the precedence
and overrides-disabled behavior. All jobs are terminal; reuse this evidence.

| Main-server evidence | SHA256 |
| --- | --- |
| `/root/kz5-acceptance/media-language-fixture-20260909.json` | `c9a96c7f458fa2da0f3723baa94054266a5e1f787772680cc69a609c430e40e5` |
| `/root/kz5-acceptance/media-language-install-main44-20260909.log` | `ecc3e8e8bab1c0c5d679d30ca224e96a8e7edaf9e9d7fc9748b97c929fa860fd` |
| `/root/kz5-acceptance/media-language-verify-main44-20260909.log` | `0b3ec497db2c210ecfa9717d2d0a532af2c1472edb0d0f9a8560c3f37e4d907a` |
| `/root/kz5-acceptance/media-language-ecallmgr-main44-20260909.log` | `9a0f708f4b5cfc8ba2399479930263a626a5e60f38f23ecf577db53220756dc0` |
| Served OpenAPI document | `59d0aeb75906b7cd9def804fe5dcd8eb67cc1655246ed42cb6a880d9722fb46d` |
