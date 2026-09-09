# Native reseller prompt-language fallback

September 9, 2026 — VOICE-01. Source verified; deployment/native fixture pending.

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

## Focused native acceptance, pending

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
