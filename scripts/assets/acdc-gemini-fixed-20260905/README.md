# ACDC female fixed voice pack — Gemini Sulafat

This is the fixed queue/callback inventory for American English (`en-us`),
Israeli Hebrew (`he-il`), Modern Standard Arabic (`ar-sa`), French (`fr-fr`) and
Spanish (`es-es`). The target is **29 fixed prompts per locale, 145 total**.
Consult `manifest.json` for the current generation result; a directory containing
some WAV files is not proof that generation or verification completed.

Provider: Google Gemini API, model `gemini-2.5-pro-preview-tts`, preset voice
`Sulafat`. These are AI-generated female voices, not human voice-actor recordings.
Fixed text comes from `scripts/acdc-language-catalog.cjs`; Hebrew uses its natural
text, never the separate eSpeak phoneme transcription. No caller text, telephone
numbers, account information or credentials are submitted for these recordings.

Each prompt has a 24 kHz mono PCM16 master and an 8 kHz mono PCM16 telephone WAV.
Conversion uses SoX resampling only: no speedup, shortening, gain or normalization.
Technical checks reject clipping, near-silence, malformed audio and excess
duration (10 seconds for callback success, 20 seconds for other fixed prompts).
The manifest retains transcript/instruction hashes, raw PCM and WAV hashes,
provider/model/voice identity and the original preview source where applicable.

The five already-generated matching success previews are reused by hash. The
generator permits at most **140 new requests**, at most two concurrently, with
no automatic paid retries. It persists request reservations before transport.
An interrupted or failed request remains charged against that budget; completed
recordings are verified and preserved on resume. A surviving `.generation.lock`
after a killed process requires operator confirmation that no generation process
is running before removing that exact lock file.

```sh
node scripts/test-acdc-gemini-fixed-pack.cjs
node scripts/generate-acdc-gemini-fixed-pack.cjs --plan
node scripts/generate-acdc-gemini-fixed-pack.cjs --verify-only \
  --output /opt/kz5/scripts/assets/acdc-gemini-fixed-20260905
```

Generation into a new dedicated output directory requires explicit `--generate`,
an owner-only `--key-file`, and `--output`; `--resume` preserves and verifies an
existing owned pack. The key is read from its protected file and sent only as an
HTTPS request header. It is not placed in URLs, command arguments or manifests.

Generation and testing deployment were requested by the operator. Nevertheless,
technical QA does not establish transcript accuracy, perceived naturalness or
native pronunciation: `audio_listening_review` and `native_speaker_review` remain
false. Generation does not import media, change queues, publish language
capabilities or claim the running system uses these voices.

## Deliberately incomplete numeric scope

This fixed-only pack contains **no numeric prompts**. Under the current numeric
playback contract, Arabic and Hebrew each require another 2,999 numeric/conjunction
recordings for the full queue-position range. Callback telephone-number readback
alone uses the smaller subset of digits 0–9 in each language, but even those
20 additional recordings are outside this generation budget. Do not advertise
the full Arabic/Hebrew language packs as ready based on these fixed files.

## Safe deployment requirements

The existing eSpeak language importer intentionally requires its own full-pack
provenance and preserves installed recordings. Do not disguise this Gemini pack
as eSpeak or pass it through that importer. Do not overwrite the existing
preview manifest to suggest it was approved or deployed.

A reviewed importer/installer integration should:

1. Verify the entire fixed pack and source hashes before any database write.
   Select these checked-in files explicitly; never regenerate eSpeak over them
   and never require a speech API key during deployment.
2. Restrict targets to `system_media/<locale>/<fixed-prompt-id>`. Preserve account
   overrides, unrelated prompts and unrecognized existing custom recordings.
   For replacement, require an exact reviewed old document revision/audio hash
   and keep a protected backup with the old attachment bytes.
3. Replace a document and its single audio attachment together using CouchDB
   revision checking. Use a versioned attachment name containing the new audio
   hash; an unchanged attachment name can leave cached old audio playing.
   Abort on a concurrent change rather than overwrite another administrator.
4. Verify the new downloaded attachment hash and a resolved media URL, then
   invalidate only affected document/media metadata caches as needed. Retain a
   receipt and an MVCC-checked rollback path; do not restart call services solely
   to change audio.
5. Keep numeric and runtime-language readiness gates separate. Test live offer,
   current/alternate number menus, registration confirmation, retry and returned
   callback prompts before reporting deployment complete.

The fixed manifest and WAVs belong in Git. Existing live database backups,
credentials and account data do not.
