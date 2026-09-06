# Supplemental built-in callback WAVs

45 Gemini/Sulafat recordings generated September 6, 2026: three callback
auxiliary messages in EN/HE/AR/FR/ES and telephone digits 0–9 in EN/FR/ES.
These supplement the existing fixed and completion packs; they do not replace
customer recordings or global prompt aliases.

`manifest.json` contains exact transcripts, locale, voice/model, request hashes,
audio hashes and measured WAV properties. There are 24 kHz PCM16 mono masters
and 8 kHz PCM16 mono telephony deliveries. Conversion is resampling only.

Generation completed in 47 requests. French zero and two each required one
explicit retry after an incomplete provider response. Their first-attempt
records remain in `previous_attempts`; valid clips were not regenerated.
Every effective asset passed format, duration, clipping, volume and hash checks.
Those checks are not native-speaker, listening or live-call certification.

Install and runtime use the checked-in WAVs. No Gemini key, online synthesis,
generation during calls or per-account regeneration is permitted. The authoring
generator is not an installer/runtime step. Future accounts reuse shared media.

This pack does not complete prerecorded queue-position numbers. Do not claim
full language readiness from these files alone. See
`doc/acdc_builtin_queue_voices.md` and VOICE-07 through VOICE-09 in the project
task register for the remaining release requirements.
