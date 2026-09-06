# Canonical callback media integration — September 6, 2026

This is source-level acceptance evidence, not live callback certification.
ACDC remains directly tracked under `applications/acdc` in the kz5 repository.
The tested modules are compiled from current files, without reversing historical
patches or replacing running application BEAMs.

## Implemented behavior

- `acdc_gemini_prompts` preflights the exact 42 immutable assets for the selected
  locale: 32 fixed recordings and ten telephone digits. Supported locales are
  EN, HE, FR, ES and AR. Missing or mismatched imported metadata prevents an
  incomplete built-in callback menu from being advertised.
- Built-in callback playlists use exact versioned `/system_media/<locale>/<id>`
  paths. Recorded telephone digits preserve leading zeroes; they do not use
  native SAY. The separately identified legacy custom-media path is retained;
  it is not proof of built-in voice readiness.
- `cf_acdc_member` uses localized auxiliary recordings for unavailable action,
  invalid input and alternate-number entry. Feedback has a 20-second playback
  limit and a 21-second feedback deadline, further limited by remaining menu time.
  **Review found that synchronous metadata lookup before the receive could exceed
  that deadline in the preceding committed implementation.** The P0-12 fix
  moves auxiliary paths into the preflight contract; its validation checkpoint
  is recorded separately below. This is not a bound on arbitrary custom AMQP
  publishing functions or native playback execution.
  Completion is correlated; stale/foreign events cannot complete feedback.
  Failed feedback resumes the original queue instead of claiming registration.
- `acdc_callback_caller` resolves built-in returned-call confirmation using the
  queue language before the call's inherited language. Explicit legacy media
  remains a separate path; malformed explicit values fail closed.
- `acdc_announcements` resolves callback media once before the loop, retaining
  the initial monotonic deadline and installing the manager monitor before
  preflight. Slow metadata reads do not add another initial announcement delay.
  Existing bounded event-drain and expired-deadline handling are preserved.

## Test evidence

All runs below used a 256-MiB memory cap, 768-MiB reserve and a private network
namespace. Production and TEST modules were compiled separately. The harness
checks private loaded paths, production test-hook absence and input hashes.

| Run | Result and limits |
| --- | --- |
| `53629`, exit 0 | All81 current-source tests passed: helper13, five-language contract6, feedback20, menu integration7, returned caller6, announcements12, accepted callback17. Input SHA-256 `e7966aee54ec8f957f403e847ff9b057aca0870ed32d70dfe50c0381748b1733`. This predates the fixed-projection count correction below. |
| `78039`, exit 1 | New editor-projection regression failed as expected: complete32-recording inventory was rejected by the stale29-recording requirement. Other19 focused tests passed. |
| `15466`, exit 0 | All20 focused helper/contract tests passed after sharing one32-fixed-asset constant across callback, capabilities and editor completeness checks. Covers all five locales, every missing fixed entry, old29-entry lists, tampered hash and unsupported locale. Input SHA-256 `e201d08269876816d97c762465dcf8c6bc4456ee6c4ef5809ef96caf3cd85e30`. This is a focused rerun, not a second all-suite result. |
| `90582`, exit 0 | All63 current production ACDC modules compiled with-Werror, noTEST options and unchanged bundled inputs after the count fix. No application BEAM was loaded or installed. |
| `28251`, exit 0 | All21 focused tests passed after adding the editor's complete42-entry callback projection. Tests cover all five locales, reject fixed-only proof, and reject every individually missing entry. Input SHA-256 `6133495ec01d8a9d76214524acba1cf7a1651fcb7d235d10acbd8b98b250461c`. |
| `62912`, exit 0 | Current63-module production compilation passed again after complete42-entry projection integration; generated OpenAPI/schema/deterministic rebuild tests passed in the same guarded run. |

Earlier agent run30693 had64 passing tests and16 failures from a legacy mock
arity mismatch; it lacked the external resource guard. The fixture was corrected
before53629. Keep that failed checkpoint distinct from the successful rerun.
Expected supervisor reports in the private suite come from deliberately killed
temporary workers, not live service crashes.

## P0-12: remove metadata IO from timed feedback

The built-in callback preflight already verified42 assets but discarded the
three auxiliary paths. The fix retains them under `auxiliary` in the
callback contract. Legacy fully explicit custom menus preflight only the three
optional auxiliary assets before queue entry; missing assets do not disable the
legacy menu or trigger a global English fallback.

Unavailable-action feedback, invalid-entry feedback and alternate-number entry
now use only the cached map. A missing/malformed cache fails quietly through the
existing resume/media-failed handling. No timed branch lazily resolves metadata.
This avoids CouchDB/cache wait and retry time consuming the remaining callback
menu budget while delaying hangup or ownership events.

Focused run `6821` exited0 with all22 helper/canonical contract tests passing,
plus current production/TEST compilation and stable input pins. Digest:
`5bcd7e76678f42988001ad768c391fd272401d2ec8b6d4b48eab975a73759ea8`.
It verifies exactly42 built-in reads including the retained auxiliary map,
exactly three optional legacy preflight reads per supported locale, and missing
legacy auxiliary behavior. It does not execute the full timer/lifecycle suites.

Full guarded run `75590` exited0: **all87 tests passed across all seven suites**,
with production/TEST compilation and stable source pins. Its input digest is
the same as6821 above. It used256MiB,768MiB reserve, a600-second outer deadline
and a private network namespace. The added tests poison both the helper resolver and datastore reads, exercise
30-ms remaining budgets for built-in and legacy cached contracts, and cover
missing maps without false registration or ownership changes. Existing
20-second playback/21-second feedback and correlated completion/terminal-event
tests remain and passed, including the actual21-second receive deadline. The
large suite wall time includes repeated meck compilation under a half-core CPU
cap, not a measured live-call latency. This closes the scoped source-level
metadata-IO regression, not native audio, arbitrary synchronous command publishing
or real callback acceptance. No source from this checkpoint has been deployed.

Root integration run `7787` then exited0: all63 production ACDC modules compiled
with `-Werror`, no `TEST` build options or agent test exports, and unchanged
bundled source/header inputs. It used the256-MiB/768-MiB-reserve offline guard
with a180-second deadline. No application BEAM was loaded or installed.

## Reproduce

From a prepared `/opt/kz5` checkout with its local Erlang dependencies:

```bash
bash scripts/run-kazoo-validation.sh \
  --memory-mib 256 --reserve-mib 768 --runtime-sec 600 -- \
  /usr/bin/unshare --net /usr/bin/bash \
  /opt/kz5/scripts/test-acdc-gemini-canonical-callback.sh
```

For only the helper and five-language media contract suites, append
`--media-only` and use a120-second deadline. This still compiles the canonical
production/TEST module set but does not run lifecycle/timer suites. No option
installs media, calls a provider or modifies live services.

## Deployment and remaining gates

Installer import session19674 exited0, verifying210 assets with0 new documents
and210 preserved. Receipt:
`/usr/local/share/kazoo5-installer/acdc-gemini-media.json`. This proves the
installer's byte verification checkpoint, not runtime mapping activation.

The canonical source is not deployed by these tests. Full queue-position
prerecorded composition, native immediate audio/ownership, five-language
listening, key6 registration/confirmation,30-second offer, returned-call retries,
multi-node recovery and clean/distributed installation remain required.
Do not enable whole-language readiness from these results alone.

UI adoption must remove obsolete queue prompt references without deleting media
documents. Normal editor/Crossbar PATCH uses null deletion markers on the wire;
the persisted returned-prompt field must be absent, not explicitly null. Tests
for that UI/editor change are a separate acceptance boundary.

The editor must project the same42 immutable callback entries used at runtime,
not only the32 fixed recordings. Otherwise missing telephone digits can leave
the editor claiming a selectable built-in language while callback configuration
fails closed. The complete callback projection helpers are
`callback_media_ids/1`, `verified_callback_media/2` and `callback_media_complete/2`;
the original fixed-only helpers retain their narrower32-recording contract.
The legacy English editor adds15 official position/auxiliary prerequisites,
giving57 bounded entries. This transitional readiness is not all-Gemini queue
position speech or a five-language listening certificate.

UI30215 passed the contract and20 queue-login groups, including rejection when
any telephone digit is missing. Editor71128 passed all42 in-memory pipeline and
manifest tests, including every missing prerequisite and persistence of deletion
markers as absent fields with unchanged recording documents. Evidence:
`/tmp/kazoo-queue-editor-test.xE5ClX/`. Earlier47-entry runs are narrower historical
evidence, not substitutes for this57-entry rerun. No real browser/queue was changed.

See [engineering handoff](../PROJECT_HANDOFF.md),
[task register](../PROJECT_TASKS.md),
[coherent upgrade requirements](acdc_coherent_upgrade_readiness.md), and
[immutable voice contract](acdc_builtin_queue_voices.md).
