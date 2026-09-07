# Isolated Gemini 3.1 cardinal authoring trial

This is a release-authoring experiment, not an installer or runtime dependency.
The 210 deployed prerecorded Gemini prompts are unchanged. The main expanded
cardinal ledger remains 412/584 technical QA, 697 historical requests, 113
retries, with SHA256
`9c97120495c327a66644330d222ae7d4705402c40b1f97b6696a486e4a5d0398`.
Trial requests are additional and are recorded separately, never erased from
history or represented as Gemini 2.5 recordings.

## Why a separate trial

Repeated bounded requests using the approved text and existing Gemini 2.5 Pro
TTS model sometimes return OTHER with no audio. The diagnostics do not establish
the provider's reason. Google's [Gemini 3.1 Flash TTS model page](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-tts-preview)
identifies a newer text-to-speech model. Trying it with the same Sulafat female
voice and exact concise-v2 transcript tests a different model, without changing
the approved wording or claiming voice equivalence before listening review.

`scripts/trial-acdc-gemini-31-cardinals.cjs` selects 1–3 FAILED HE/AR/ES roles
from a byte-pinned, fully verified source pack. It refuses successful, pending,
in-flight and six-attempt-capped roles. Plan mode is read-only and never reads
credentials. Explicit generation requires a fresh private output directory,
reserves each request durably before sending, uses header-only authentication
to one fixed HTTPS endpoint, permits no redirect/automatic retry, and stops on
the first failure. Each response is bounded to 90 seconds and 2 MiB.

Each separate `trial.json` records true model, source attempt hashes/counts,
approved transcript/body hashes, safe diagnostics and successful WAV hashes.
The original source manifest, attempts and audio are read-only. Trial outputs
are never importable, listening-approved, runtime-ready or deployed by this tool.
Any future promotion must explicitly preserve mixed-model provenance and review
actual playback; do not relabel a trial output as a successful 2.5 attempt.

## First real trial

Guard `764144/session59880/70e2d9` stopped after one request. HE tens30 returned
the exact requested 3.1 model, STOP and one inline audio part, but the reused
2.5-specific MIME validator rejected `UNSUPPORTED_AUDIO_FORMAT`. No audio was
accepted or installed. The selected Arabic4 and Spanish13 roles were not sent.
Protected receipt:
`/usr/local/src/kazoo5-installer/acdc-cardinal-31-trial-20260907-1833/trial.json`.
Receipt SHA256:
`8b2fa867de24a6e389a5f26465e7105452be3988a7b9c483c0cc34930dd08936`.

The first offline suite passed 285 checks (`c5124b/session84029/bdff1f`),
including source preservation, reservations, transport bounds, failure stopping,
model mismatch and secret redaction. Follow-up format/CLI validation is tracked
below; a technical pass alone is never listening approval.

## Format compatibility fix

The trial-only adapter now accepts explicit `audio/L16;rate=24000;channels=1`
with optional `codec=pcm`, alongside the existing codec/24k spelling. It rejects
stereo, other rates/codecs, duplicate, malformed or unknown parameters. No sample
rate or byte order is inferred from the audio. Google's [speech-generation guide](https://ai.google.dev/gemini-api/docs/speech-generation)
uses decoded PCM directly as mono 24 kHz 16-bit WAV in its 3.1 example.
The old shared parser is unchanged; only a validated copy of the MIME metadata
is adapted before the original STOP/base64/PCM checks. Audio bytes are untouched.
Allowlisted format/model/finish diagnostics are saved before extraction, without
persisting raw provider strings or credentials.

Validation `8be8d2/session72620/e31576` passes 526 offline checks, including real
CLI subprocess execution, no-op CLI prevention, format rejection, unchanged
legacy behavior, response immutability and actual WAV/SoX validation. No provider
or original source writes occur in those tests.

## Real format-compatible result

`8cb350/session45900/0e2d15` passed all three selected requests: HE tens30,
AR number4 and ES number13. Each returned exact model 3.1, STOP and
`audio/l16`, rate24000, channels1, no codec parameter. These are observed safe
format components, not a retrospective claim about the first rejected response.
All three master/telephony WAV pairs passed technical QA, exact SoX resampling
and hash readback. The source 2.5 ledger is unchanged.

Protected receipt directory:
`/usr/local/src/kazoo5-installer/acdc-cardinal-31-trial-20260907-1840`.
Receipt SHA256:
`4b0cb5b5e097d2a829d19945664cca70d912e9400b8a2ee357e9ad3f899e06b9`.
Both failed and successful receipts, plus the six successful WAVs, are preserved
under `scripts/assets/acdc-gemini-cardinal-model-trials-20260907/` in
`format-rejected/` and `format-compatible/`. There were four additional real
requests across both trials, not three: the first rejected-format request remains
part of the evidence. These three clips are separate candidates, not additions
to the original 412/584 count or deployed/runtime-ready media.

Next: review the saved audio, then explicitly support mixed-model provenance
and bounded failed-only authoring recovery without regenerating these successes.
The experiment demonstrates a working alternative for three roles, not proof
that every remaining role, language or context will succeed.

Independent saved-artifact check `a38719` reverified transcript hashes, all six
WAV hashes, technical QA and actual SoX replay. Both original private/repository
manifest hashes remain exactly pinned and unchanged after the trials.

## Failed-only Spanish follow-up

Each follow-up uses the same original source pin, approved transcript, model,
voice, bounded three-request limit and stop-on-failure behavior. Previously
requested identities and the two reviewed ES4/ES9 reuse candidates are excluded.
Successful WAVs and exact receipts are saved in the model-trial asset directory.

| Artifact directory | Spanish numbers | Result | Execution evidence |
| --- | --- | --- | --- |
| `es-batch1` | 14, 16, 17 | Three QA-passed clips / six WAVs | `b94427/session92905/63521e` |
| `es-batch2` | 18, 19, 20 | Three QA-passed clips / six WAVs | `9bd5c6/session39386/9dddd7` |
| `es-batch3` | 21, 23, 24 | Three QA-passed clips / six WAVs | `4f1a5c/session96228/0d86f1` |
| `es-batch4` | 25, 26, 27 | Three QA-passed clips / six WAVs | `e73d09/session35145/3a4f88` |
| `es-batch5` | 28, 29, 40 | Three QA-passed clips / six WAVs | `1b1c76/session82730/65d87b` |
| `es-batch6` | 50, 60, 80 | Three QA-passed clips / six WAVs | `d8dbdb/session19325/cf10f6` |
| `es-batch7` | 200, 300, 400 | Three QA-passed clips / six WAVs | `99e567/session55379/9cbd05` |
| `es-batch8` | 700, 800, 900 | Three QA-passed clips / six WAVs | `207d64/session52518/3f4a43` |
| `es-final-he-start` | before-scale21; plus HE joined-masculine3/7 | Three QA-passed clips / six WAVs | `2b7949/session94415/455cc2` |

At this checkpoint there are 30 successful separate 3.1 candidate clips and
31 total additional model-trial requests, including the original format failure.
The original 2.5 ledger remains 412/584. Neither count establishes runtime or
listening readiness; preserve every failed receipt as well as successful audio.

Spanish source inventory is now complete: 25 original QA clips, 26 separate
3.1 QA candidates and the two reviewed exact-word ES4/ES9 aliases cover all53
roles. This is artifact completeness, not an imported or listening-approved
Spanish runtime release. The checked-in index names all11 known terminal trial
receipts: `scripts/assets/acdc-gemini-cardinal-model-trials-20260907/index.json`,
SHA256 `9a77a94df3948b2ffadc5248f3bbe52dd489df2a8e6178e65a26227629507866`.
Mixed-model staging and full five-language runtime gates remain open.

Subsequent FR89 one-shot request passed; see `acdc_cardinal_fr89_one_shot.md`.
Current index now contains12 terminal receipts,31 QA candidates and32 additional
trial requests; index SHA256
`fbd37afd26c9211ae05b5a9c1b65d29e10874693c327f99ad0e58dbf4523ca33`.
The earlier11-receipt hash above is historical. EN/ES/FR technical artifact
coverage is complete; HE95/131 and AR105/208 remain incomplete.
