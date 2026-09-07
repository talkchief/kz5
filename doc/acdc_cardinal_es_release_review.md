# Spanish cardinal recordings: source review, September 7, 2026

Decision proposed for root review: approve one-time authoring of the existing
53 ES-ES cardinal roles, their current-number-label context and natural chunk
delivery. No incorrect transcript or missing required role was found in this
review. This is source-backed engineering approval, not listening approval,
provider execution, deployment or proof of actual queue playback.

## Exact reviewed inputs

These hashes distinguish source-file bytes from canonical catalog/context JSON.

| Input | SHA-256 |
| --- | --- |
| `scripts/acdc-cardinal-catalog.cjs` bytes | `402be11bfb4da7d2113c06940d41a362cd89b159436fefe092c13f4b56c2f855` |
| `scripts/acdc-cardinal-pack.cjs` bytes | `a53f1ff78c55ab941a5bf3a7ba9a5525161a580e03573e42cde18287ffe20328` |
| Entire v1 catalog, canonical JSON | `5703e649a1f5a2bcd0c00e9e19bf4424e024c85648452dba0d190bcf73088134` |
| Exact ES plan, including each transcript/record hash | `b0eceef36cec5d489da437e98cc274f23fa6d9a6eb8b7b71f671e8f6b2a2d7d4` |
| ES context, canonical JSON | `c23189c1e99b0f5d7c22df55dc2a9cc544779cc3d20ecf276785395c7b324653` |

The context is `current-queue-position-number-label`, grammar
`masculine-number-label-apocope-before-scale`, delivery
`natural-prerecorded-chunks`, with separate introduction approval required.

## Finite transcript and composition review

Identity prefix is `acdc-cardinal-v1-`; locale is always `es-es`.

- `number-0` through `number-29`: cero, uno, dos, tres, cuatro, cinco, seis,
  siete, ocho, nueve, diez, once, doce, trece, catorce, quince, dieciséis,
  diecisiete, dieciocho, diecinueve, veinte, veintiuno, veintidós, veintitrés,
  veinticuatro, veinticinco, veintiséis, veintisiete, veintiocho, veintinueve.
- `number-30/40/50/60/70/80/90`: treinta, cuarenta, cincuenta, sesenta,
  setenta, ochenta, noventa.
- `number-100/200/300/400/500/600/700/800/900`: cien, doscientos, trescientos,
  cuatrocientos, quinientos, seiscientos, setecientos, ochocientos, novecientos.
- `hundred-continuation`: ciento; `before-scale-1`: un;
  `before-scale-21`: veintiún; `and`: y; `thousand`: mil;
  `million`: millón; `millions`: millones.

The RAE distinguishes masculine number names from gender agreement when
counting feminine things. It also permits masculine cardinals as numeric labels
of feminine nouns. That supports the chosen numeric-label reading rather than
counting *posiciones*. The catalog's accents, `cien`/`ciento`, apocope before
`mil`/`millones`, and singular `un millón` agree with the RAE's rules and table.
Its `y` is restricted to a tens-and-units join, not added between hundreds or
scale groups. [RAE, cardinales, sections 1–4, 6 and 8](https://www.rae.es/dpd/cardinales).

Source-traced boundary examples (not newly executed tests):

| Number | Intended composed speech |
| --- | --- |
| 0 / 21 / 31 | cero / veintiuno / treinta y uno |
| 100 / 101 | cien / ciento uno |
| 1000 / 1001 | mil / mil uno |
| 21000 / 101000 | veintiún mil / ciento un mil |
| 1000000 / 1001000 | un millón / un millón mil |
| 101000000 | ciento un millones |
| 999999999 | novecientos noventa y nueve millones novecientos noventa y nueve mil novecientos noventa y nueve |

`spanishGroup()` retains full `uno`/`veintiuno` in the final group, selects
apocopated recordings only before a scale, and `compose()` omits the coefficient
one before `mil`. The range remains 0–999999999, with at most 14 recordings.
Zero is a grammar boundary, not permission to fabricate a queue position.

## Existing immutable introduction

Keep `acdc-queue-your-current-position-is`: **Su posición actual es.**
Interpreting the following cardinal as the value of the current position is an
engineering semantic judgment supported by the number-label rules above. It is
not an ordinal announcement, a ticket identifier or a callers-ahead count.
There is no text-based reason here to replace this successful introduction or
to feminize the number catalog. Compatibility of its recorded end prosody with
the new number clips still requires listening.

All paths below are under `scripts/assets/acdc-gemini-fixed-20260905/`.

| Immutable input | SHA-256 |
| --- | --- |
| Exact UTF-8 intro transcript, no newline | `a3c7ef71bec8c1c0db48b96ebbf59f4733cce242df4c30384b216b8fcf831bd9` |
| `es-es/acdc-queue-your-current-position-is.master-24000.wav` bytes | `a332ccaa986a7025a1cf726b1586b7c3ac74b4c7a71414ab48230dcf00bd7b01` |
| `es-es/acdc-queue-your-current-position-is.telephony-8000.wav` bytes | `4753cdfe28956fa8ea620508984041b30ab7fb781845c9f80b565e2662f216d4` |
| Fixed-pack `manifest.json` bytes | `4269cfe5495cbffd23b14aad8711e2925f46dc14e2bced2cca12d21a18c49f90` |

The existing manifest records `GENERATED_QA_PASSED`; this review rehashed bytes,
not audio content or resampling. The approval field `intro.wav_sha256` pins the
8 kHz file, not its master. Neither file nor the fixed manifest was changed.

## Delivery decision and remaining checks

Approve the existing request instruction: native Spanish from Spain, Sulafat,
warm professional adult female voice, exact transcript only, comfortable pace,
no extra speech/music, each complete chunk at most ten seconds. Preserve masters
and the verifier's deterministic resampling-only recipe; no new trim, padding,
gain, synthetic silence or contextual rewriting policy is introduced.

After generation, listen especially to standalone `y`, `un`, `mil`, accented
teens/twenties, irregular hundreds, scale boundaries and the intro-to-number
join. Confirm the actual words and natural cadence, not merely WAV duration or
energy. Successful technical QA alone cannot approve these properties.
Listening remains `PENDING`; runtime/full-range readiness remains false until
the separate asset integration and real playback gates pass.

The new proposed `acdc-cardinal-approvals-es-fr-20260907.json` binds this file's
bytes as evidence. It must preserve the already-attempted EN record exactly and
does not alter the original EN approval file, existing 210 assets or catalog.
