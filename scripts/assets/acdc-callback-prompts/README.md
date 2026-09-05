# English ACDC prompt provenance

The 17 WAVs in `en-us/` are synthetic speech generated from the fixed text in
`scripts/generate-acdc-callback-prompts.sh`; they are not production recordings,
copied customer audio, cloned voices, or neural-model output.

The original assets were rendered locally with eSpeak NG 1.50's `en-us` formant
voice at 150 words per minute and amplitude 120, followed by the script's SoX
filter/normalization pipeline. Output is mono 8-kHz signed 16-bit PCM WAV.
The exact text, including offers for each key 0–9 and the complete queue-position
prefix, remains in that generator. Engine upgrades can change output bytes.

[eSpeak NG](https://github.com/espeak-ng/espeak-ng) is GPL-3.0-or-later software.
No MBROLA or separately licensed external voice model was used. These generated
project assets are intended for the deployment's ACDC prompts; their provenance
does not apply to separately downloaded upstream Kazoo/FreeSWITCH sound packs.

The installer imports missing attachments only and preserves existing custom
recordings. The newer multilingual generator and its separate, pinned-engine
manifests are documented in `doc/acdc_language_packs.md`; generating those
manifests alone does not certify runtime language readiness or native review.
