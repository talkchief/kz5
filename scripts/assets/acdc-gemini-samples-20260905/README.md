# Female ACDC voice previews — 2026-09-05

These are AI-generated **listening samples**, not an approved/installable voice
pack. Each language contains only the callback-registration success message.
No sample has been imported into Kazoo or marked runtime-ready.

Provider: Google Gemini API. Model: `gemini-2.5-pro-preview-tts`.
Preset voice: **Sulafat**, a warm female voice. See Google's
[speech-generation guide](https://ai.google.dev/gemini-api/docs/generate-content/speech-generation)
and [voice list](https://docs.cloud.google.com/text-to-speech/docs/gemini-tts).
This is Gemini TTS, not the separately named Cloud Chirp 3 HD product.

| Language | High-quality master | Telephone WAV | Duration |
| --- | --- | --- | ---: |
| EN | [24 kHz](en-us/acdc-callback-success.master-24000.wav) | [8 kHz](en-us/acdc-callback-success.telephony-8000.wav) | 5.491 s |
| HE | [24 kHz](he-il/acdc-callback-success.master-24000.wav) | [8 kHz](he-il/acdc-callback-success.telephony-8000.wav) | 5.171 s |
| AR | [24 kHz](ar-sa/acdc-callback-success.master-24000.wav) | [8 kHz](ar-sa/acdc-callback-success.telephony-8000.wav) | 6.011 s |
| FR | [24 kHz](fr-fr/acdc-callback-success.master-24000.wav) | [8 kHz](fr-fr/acdc-callback-success.telephony-8000.wav) | 5.971 s |
| ES | [24 kHz](es-es/acdc-callback-success.master-24000.wav) | [8 kHz](es-es/acdc-callback-success.telephony-8000.wav) | 6.291 s |

Both formats are mono signed PCM16 WAV. The raw 24-kHz speech was resampled with
SoX; it was not sped up, shortened, or regenerated during conversion. All five
passed non-silence, clipping, container, duration and checksum checks, and fit the
default ten-second success-announcement timeout. Those checks do **not** prove
transcript accuracy, naturalness or native pronunciation. Listening approval is
still required for each locale.

`manifest.json` records the fixed transcripts, synthesis instructions, provider
and returned model version, raw PCM and WAV hashes, conversion recipe, and
explicit unapproved/undeployed status. Credentials and caller data are not part
of these assets. Keep the WAVs and manifest in Git; future use of these exact
recordings does not require a speech API call or key.

To generate a new, separate preview directory from the repository root:

```sh
node scripts/generate-acdc-gemini-samples.cjs --plan
node scripts/test-acdc-gemini-samples.cjs
node scripts/generate-acdc-gemini-samples.cjs --generate \
  --key-file /protected/gemini-key-file \
  --output /absolute/existing-parent/new-preview-directory
```

The key file must be owner-only and not a symlink. The generator makes at most
five sequential paid requests, never retries automatically, stops on the first
failure, and refuses to overwrite an existing output directory. A successful
sample set deliberately leaves `complete:false`, `approved:false` and
`runtime_ready:false`: the full queue, callback and numeric inventories are a
separate release gate. Installers must not consume this preview directory as a
complete language pack.
