# French cardinal recordings: source review, September 7, 2026

Decision proposed for root review: approve one-time authoring of the existing
161 FR-FR roles, current-number-label context and natural chunk delivery. Review
found no incorrect recording transcript or required missing role. The checks
below specifically address liaison and contextual endings; this is not a
blanket approval of yet-unheard WAVs or actual queue playback.

## Exact reviewed inputs

| Input | SHA-256 |
| --- | --- |
| `scripts/acdc-cardinal-catalog.cjs` bytes | `402be11bfb4da7d2113c06940d41a362cd89b159436fefe092c13f4b56c2f855` |
| `scripts/acdc-cardinal-pack.cjs` bytes | `a53f1ff78c55ab941a5bf3a7ba9a5525161a580e03573e42cde18287ffe20328` |
| Entire v1 catalog, canonical JSON | `5703e649a1f5a2bcd0c00e9e19bf4424e024c85648452dba0d190bcf73088134` |
| Exact FR plan, including each transcript/record hash | `cc42ea5d1b0cde01955baa4fe6a1d0a7b2cebfd5600ac1c7db5c42022376618a` |
| FR context, canonical JSON | `2fe1233a54f0ffbb21b2319913bece61833d45f979ccac1d7dbe8ebe689a40d8` |

Context: `current-queue-position-number-label`; grammar:
`cardinal-contextual-scale-tails`; delivery: `natural-prerecorded-chunks`;
separate introduction approval required. The dialect is French from France,
using soixante-dix/quatre-vingts/quatre-vingt-dix, not regional alternatives.

## Exact finite role inventory

All identities have prefix `acdc-cardinal-v1-` and locale `fr-fr`.

- 100 `terminal-N` roles, N=0–99: complete conventional French number phrases
  from `frenchSmall()`. Base 0–16 is zéro, un, deux, trois, quatre, cinq, six,
  sept, huit, neuf, dix, onze, douze, treize, quatorze, quinze, seize.
  17–19 are dix-sept/dix-huit/dix-neuf. Tens 20–60 are vingt/trente/quarante/
  cinquante/soixante, with `et un` for unit one, otherwise a hyphenated unit.
  70–79 use soixante plus 10–19, except `soixante et onze`; 80 is
  `quatre-vingts`; 81–99 use `quatre-vingt-` plus 1–19, without added `et`.
- Nine `hundreds-H`, H=1–9: cent, deux cents, trois cents, quatre cents,
  cinq cents, six cents, sept cents, huit cents, neuf cents.
- Nine `hundred-one-H`, H=1–9: cent un, deux cent un, trois cent un,
  quatre cent un, cinq cent un, six cent un, sept cent un, huit cent un,
  neuf cent un. These are whole recordings, not a cent/un audio splice.
- Forty `scaled-tail-S-N`: S is 1000 or 1000000, and N is exactly
  6, 8, 10, 18, 26, 28, 36, 38, 46, 48, 56, 58, 66, 68, 70, 78, 86, 88, 90,
  98. Each whole transcript is the matching terminal phrase followed by
  `mille` for S=1000 or `millions` for S=1000000. The scale is inside that WAV
  and is never appended a second time.
- Three scale roles: `thousand` → mille, `million` → million,
  `millions` → millions.

## Grammar and boundary findings

Whole 0–99 phrases preserve the pronounced final consonant of vingt in 21–29
without introducing it in quatre-vingt compounds. No new vingt stem is needed.
[OQLF, pronunciation of vingt](https://vitrinelinguistique.oqlf.gouv.qc.ca/23141/la-prononciation/prononciation-des-nombres/prononciation-de-vingt).

The terminal six/dix forms and their compounds cannot simply be reused before
consonant-initial scale words: their endings differ. The existing 40 contextual
tails cover the applicable six/dix/huit endings, including 70/90 and 18/78/98.
They let the provider render the complete local context instead of trying to
edit consonants in generated audio. [OQLF, six and dix](https://vitrinelinguistique.oqlf.gouv.qc.ca/23137/la-prononciation/prononciation-des-nombres/prononciation-de-six-et-dix),
[OQLF, huit](https://vitrinelinguistique.oqlf.gouv.qc.ca/23149/la-prononciation/prononciation-des-nombres/prononciation-de-huit).

Two tempting extra-role changes are unnecessary: cent huit and cent onze do
not require a liaison across that boundary. The present hundred-plus-terminal
split is textually compatible. Whole H01 recordings already cover the separate
cent-un boundary. [OQLF, huit](https://vitrinelinguistique.oqlf.gouv.qc.ca/23149/la-prononciation/prononciation-des-nombres/prononciation-de-huit),
[OQLF, onze](https://vitrinelinguistique.oqlf.gouv.qc.ca/23140/la-prononciation/prononciation-des-nombres/prononciation-de-onze-et-de-onzieme).

The catalog correctly retains et in 21/31/41/51/61/71, omits it in 81/91, and
does not insert it after cent or mille. The literary indefinite *mille et un*
must not replace the exact value 1001. [OQLF, et in numbers](https://vitrinelinguistique.oqlf.gouv.qc.ca/24631/la-prononciation/prononciation-des-nombres/prononciation-de-et-dans-les-nombres-composes).

Silent plural spelling is not an omitted speech role. `transcript()` drops s
from cents/vingts before another numeral or mille, but preserves it before the
noun millions. Ordinal-label orthography may also omit those silent s letters;
the present API is expressly cardinal and not an ordinal text formatter. No
required acoustic change follows from that spelling distinction here.
[OQLF, plural of vingt, cent and mille](https://vitrinelinguistique.oqlf.gouv.qc.ca/21532/la-grammaire/les-determinants/determinants-numeraux/pluriel-de-vingt-de-cent-et-de-mille).

Source-traced examples, not newly executed tests:

| Number | Intended composed speech |
| --- | --- |
| 71 / 81 | soixante et onze / quatre-vingt-un |
| 108 / 111 / 201 | cent huit / cent onze / deux cent un |
| 26000 / 106000 | vingt-six mille / cent six mille |
| 200000 / 200000000 | deux cent mille / deux cents millions |
| 280000 / 280000000 | deux cent quatre-vingt mille / deux cent quatre-vingts millions |
| 1001001 | un million mille un |
| 999999999 | neuf cent quatre-vingt-dix-neuf millions neuf cent quatre-vingt-dix-neuf mille neuf cent quatre-vingt-dix-neuf |

The supported range is unchanged, 0–999999999, at most eight recordings.
Zero is a grammar boundary, not a fabricated position or permission to change
queue ordering. No SAY/digit-spelling fallback is part of this approval.

## Existing immutable introduction

Keep `acdc-queue-your-current-position-is`: **Votre position actuelle est.**
The intended completion is the numeric label, not a feminine count of positions
or an ordinal adjective such as première. OQLF treats un naming the number as
a noun, with no liaison to the preceding/following word. This supports the
number-label interpretation and separate intro boundary; applying that rule to
this exact queue sentence is an engineering semantic judgment, not a quoted
official approval of the sentence. [OQLF, pronunciation of un](https://vitrinelinguistique.oqlf.gouv.qc.ca/23131/la-prononciation/prononciation-des-nombres/prononciation-de-un).

All paths below are under `scripts/assets/acdc-gemini-fixed-20260905/`.

| Immutable input | SHA-256 |
| --- | --- |
| Exact UTF-8 intro transcript, no newline | `e5613b3e9cb8b84efc9081c6876fe28815eec069d9b27866d96c25503b09cca0` |
| `fr-fr/acdc-queue-your-current-position-is.master-24000.wav` bytes | `16e25edb162e8950a9da7de0d4a4ac89d81a7aa70e69fff111381a9bacee1501` |
| `fr-fr/acdc-queue-your-current-position-is.telephony-8000.wav` bytes | `7ed7292b5feac6a03881c958532d2f9150d39ea4ca7ecf9d1d11385f10be6b2c` |
| Fixed-pack `manifest.json` bytes | `4269cfe5495cbffd23b14aad8711e2925f46dc14e2bced2cca12d21a18c49f90` |

The manifest records `GENERATED_QA_PASSED`; this review rehashed the files, not
their spoken content or resampling. `intro.wav_sha256` pins the telephony file.
There is no text-based need to regenerate this successful introduction.

## Delivery decision and remaining checks

Approve the existing request instruction: French from France, Sulafat, warm
professional adult female voice, exact transcript only, comfortable pace,
no extra words/music, complete natural chunks of at most ten seconds. Preserve
the deterministic master-to-telephony recipe without trimming, padding, gain
changes or invented silence. Natural recorded edge pauses are measured, not
declared correct by duration alone.

Listening remains `PENDING`: check the actual six/dix/huit endings before both
scales, all H01 chunks, 21/71/81/91, cent huit/onze, plural scale meaning, short
un/mille/million recordings and complete intro/number playlists. Verify no lost
or added word and acceptable joins/prosody. Text review cannot certify those
audio properties. No runtime/full-range acceptance or native-speaker listening
claim is made. No provider request, test or build ran during this review.

The separate proposed `acdc-cardinal-approvals-es-fr-20260907.json` binds this
document's bytes while retaining the attempted EN approval unchanged. Existing
210 assets, their manifests, catalog and all other locales remain untouched.
