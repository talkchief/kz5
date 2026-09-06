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
  limit and a 21-second outer bound, further limited by the remaining menu time.
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

Earlier agent run30693 had64 passing tests and16 failures from a legacy mock
arity mismatch; it lacked the external resource guard. The fixture was corrected
before53629. Keep that failed checkpoint distinct from the successful rerun.
Expected supervisor reports in the private suite come from deliberately killed
temporary workers, not live service crashes.

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

See [engineering handoff](../PROJECT_HANDOFF.md),
[task register](../PROJECT_TASKS.md),
[coherent upgrade requirements](acdc_coherent_upgrade_readiness.md), and
[immutable voice contract](acdc_builtin_queue_voices.md).
