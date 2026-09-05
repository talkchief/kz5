# Gemini Sulafat fixed-voice completion

This directory supplements `../acdc-gemini-fixed-20260905`; neither is a claim of live playback or native-speaker approval.

The combined release has 145 fixed EN/HE/AR/FR/ES queue/callback clips and 20 AR/HE telephone digits, all with Google Gemini `gemini-2.5-pro-preview-tts`, female Sulafat provenance. Five matching success clips were reused by SHA-256. Generation consumed 162 new requests: 140 initial fixed requests, 20 digit requests and two retries. Two unsuccessful fixed-prompt responses are retained in the ledgers as `AUDIO_GENERATION_NOT_COMPLETE`. Generation is frozen; the remaining budget is not an instruction to spend.

Every effective entry has an exact-transcript hash, request/instruction provenance, a 24kHz mono PCM16 master and an 8kHz mono PCM16 telephone WAV. Conversion is SoX resampling only: no speedup, trimming, gain or normalization. Container, duration, silence, clipping and SHA-256 checks passed. Success messages are at most 10 seconds; other fixed clips at most 20 seconds; digits at most 5 seconds. These technical checks do not establish native pronunciation, semantic completeness by listening, routing or live call success.

## Offline verification and mapping

```sh
node scripts/generate-acdc-gemini-completion-pack.cjs --verify-only \
  --fixed-pack /opt/kz5/scripts/assets/acdc-gemini-fixed-20260905 \
  --output /opt/kz5/scripts/assets/acdc-gemini-completion-20260905
node scripts/plan-acdc-gemini-voices.cjs
node scripts/test-acdc-gemini-voice-import.cjs
node scripts/test-acdc-gemini-voice-plan.cjs
```

The planner emits a separate source-only voice map, **not** `language-capabilities.json`. It cannot enable a language. `--queue-json /absolute/queue.json --locale en-us` adds a read-only English baseline proposal for six callback media fields and four announcement fields. It preserves every explicit override, never enables callbacks, never changes announcement timers/alternate-number policy/routing, and will not suggest English clips for a non-English queue. Apply only after checking the current queue revision and verifying installed audio. Re-read the queue instead of applying a stale proposal.

## Reviewed create-only media import

The following operation is for the deployment owner, using the existing protected `KAZOO_COUCHDB_*` environment; it does not require a Gemini key:

```sh
node scripts/import-acdc-gemini-voices.cjs --import --locale en-us \
  --fixed-pack /opt/kz5/scripts/assets/acdc-gemini-fixed-20260905 \
  --completion-pack /opt/kz5/scripts/assets/acdc-gemini-completion-20260905
```

Replace `--locale en-us` with `--all-locales` for all 165 assets, then repeat with `--verify-only`. It creates only immutable IDs `<locale>/<canonical>-gemini-sulafat-<sha256-prefix>` and one equally versioned attachment each. Existing canonical, custom and foreign-owned documents are never overwritten. Existing owned versioned documents must match exact provenance and attachment hashes. A conflict is re-read and verified, never overwritten. Final verification re-downloads every attachment. Queue/account configuration remains unchanged.

Different IDs and attachment names also avoid serving an older recording from the media cache, whose key does not include the CouchDB revision. No old recordings need deletion, and rollback means selecting the previous queue media references rather than deleting shared documents.

## Installer and runtime gates

For a Gemini-selected deployment, the installer must verify and import these checked-in sources with this importer. It must not call a speech provider, re-render eSpeak replacements, reuse the eSpeak provenance validator, overwrite canonical/custom media, or declare an entire language ready from these assets. Official upstream non-ACDC prompts remain a separate installation responsibility. Retain the import receipt and verify it during reruns; do not silently switch back to robotic prompts after an import error.

English baseline callback/menu playback can use the six explicit `callback.media` fields, including `returned_confirmation`, after importer verification. The four configurable announcement media fields can use their versioned IDs. Eight wait-time bucket references are hardcoded in the current worker and require a reviewed runtime lookup before these eight voices can be activated. EN/FR/ES numeric playback is a separate native-say runtime dependency, not generated or certified by this pack.

AR/HE have **only digits 0–9 for callback number readback**. A dedicated versioned digit mapping must be implemented and verified before advertising callback readiness. Do not install these ten digits as a supposed 2,999-prompt numeric language pack or mark full queue-position capability. No complete AR/HE position numbers were generated. A future limited position range must have an explicit maximum and suppress unsupported positions, never fall back silently to robotic/English audio. Generating positions 10–100 would require 91 additional clips per locale and separate budget authorization.
