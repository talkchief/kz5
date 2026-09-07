# Built-in queue voices: release contract

Generate audio during release authoring only. The supported release must never
need Gemini again to install, run, create accounts/sub-accounts, edit queues or
make calls. Neither a Gemini credential nor an internet synthesis service is a
deployment dependency. Missing/corrupt assets are an explicit installation or
readiness failure, not a reason to synthesize audio online.

The UI exposes one Queue language choice: EN, HE, FR, ES or AR. Each has one
built-in female voice. That choice governs position/wait announcements, callback
offers, menus, number readback, confirmation, returned-call confirmation and
error responses. There are no separate voice/custom-recording choices for these
standard queue prompts. Existing media documents are not deleted; adopting the
built-in mode clears obsolete queue prompt references rather than retaining
hidden overrides that contradict the selected language.

## Immutable release contents

Ship the WAVs, fixed transcripts, locale/voice/model provenance, cryptographic
hashes, generated lookup table, importer and regression tests in kz5. Masters
are PCM16 mono 24 kHz; telephony files are PCM16 mono 8 kHz. Resampling is done
once during authoring. Installers verify and import the checked-in telephony
bytes into shared system media for all current and future accounts.

The packaged effective inventory contains 145 fixed messages (29 per locale),
20 Hebrew/Arabic telephone digits and the following 45 supplemental assets:

| Code context | ACDC-scoped recording | Count |
| --- | --- | --- |
| Callback unavailable | `acdc-callback-unavailable` | Five locales |
| Invalid input / retry | `acdc-callback-invalid-entry` | Five locales |
| Enter an alternative callback number | `acdc-callback-enter-number` | Five locales |
| Telephone-number readback | `acdc-number-0` through `acdc-number-9` | EN/FR/ES: 30 |

These 45 clips are **already generated and packaged**. Their 47 requests retain
two incomplete first attempts and their successful explicit retries; none is
pending. The combined inventory is 210 effective assets / 420 tracked WAVs,
42 assets per locale. Do not regenerate those valid recordings. Their text lives in
`scripts/acdc-gemini-supplemental-catalog.cjs`. Number-entry text must match the
reducer's pound-to-finish and star-to-remain-queued behavior. Generic global
prompt IDs and customer recordings must not be overwritten.

The September 7 source-only inventory audit and finite next authoring steps are
in [cardinal authoring readiness](acdc_cardinal_authoring_readiness.md). The
separate 584-role cardinal generator is implemented and offline-tested, but its
recordings have not been authored. Source-backed transcript/context review can
authorize that one-time work; it must not claim native-speaker listening or
runtime acceptance that has not occurred.

## Acceptance still required

The supplemental callback inventory does not complete queue-position numbers.
All supported position values need a language-correct prerecorded composition
contract; using native SAY would mix voices and does not satisfy this release.
Audio format/hash/volume checks do not prove natural pronunciation, correct
translation or correct live playback. Listening review and callback/position
call tests must establish those separately.

The canonical source must select the packaged assets, including all auxiliary
and returned-call paths. A live BEAM using an older Gemini patch does not prove
the next build will do the same. Deployment requires coherent source, native
media handling, UI, assets and rollback checks. Do not publish five-language
readiness simply because generation or import succeeded.

Release tests must run installer and runtime paths with provider credentials
absent and Gemini access unavailable. They must establish that no fallback
invokes online TTS and that new accounts reuse the shared installed assets.
