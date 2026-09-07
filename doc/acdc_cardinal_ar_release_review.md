# Arabic cardinal release text review — 2026-09-07

Decision: retain all 208 Arabic `acdc-cardinal-v1` role transcripts and the
`msa-masculine-nominative-number-label` / `pausal-chunks` contract. Select the new
explicit-number introduction below. This is a finite, source-backed engineering
review of the exported text and compositor; no specific catalog correction was
identified. It supports recording the transcript, intended-delivery and intro-text
decisions as reviewed. It is **not native-speaker listening approval**, a claim of
natural recorded cadence, an intro-WAV verification, or release/runtime readiness.

Scope was `/opt/kz5` only. No audio was generated or listened to; no credentials,
provider requests, audio conversion, media import, deployment or commits were
performed. The existing fixed210 recordings and historical manifests remain
immutable. This review does not qualify their digits for cardinal reuse. Only
this review document was written; catalog and approval files were not edited.

## Exact reviewed inputs

The four files were read and the exported Arabic plan was inspected in full.
File hashes are SHA-256 over exact bytes. Catalog/context hashes below use the
pack's canonical JSON digest and are deliberately distinct from source hashes.

| Input | SHA-256 |
| --- | --- |
| `doc/acdc_cardinal_authoring_readiness.md` | `15645573cb39d33216b847335b31b57b3a1369760e55de8bc984be67d520e491` |
| `doc/acdc_prerecorded_cardinal_design.md` | `cb747de5d0932a8d1b1df2d2b921bca0118757f6be81c5dbda2c1d796b6379f7` |
| `scripts/acdc-cardinal-catalog.cjs` | `402be11bfb4da7d2113c06940d41a362cd89b159436fefe092c13f4b56c2f855` |
| `scripts/acdc-cardinal-pack.cjs` | `a53f1ff78c55ab941a5bf3a7ba9a5525161a580e03573e42cde18287ffe20328` |
| `pack.CATALOG_HASH` (all five locales) | `5703e649a1f5a2bcd0c00e9e19bf4424e024c85648452dba0d190bcf73088134` |
| `pack.LOCALE_HASHES['ar-sa']` | `ab8f4b5d5e7d92ec1006b03042158fba5ccc8d6349876257dce8025d59fb6151` |
| `pack.digest(pack.contexts['ar-sa'])` | `71eb75bcd3e3e0f0511bd693cc8052357af4e6f7523aaf9b911c5d3766b86b16` |

These decisions bind those inputs, not future changed transcripts. The catalog's
existing `authoring_status: provisional-needs-language-review` metadata was
preserved; this separate evidence records the review without silently changing
the already pinned global catalog.

## Inventory and transcript findings

All identities below have locale `ar-sa` and prefix `acdc-cardinal-v1-`.

| Exact role family | Plain | Joined | Total |
| --- | ---: | ---: | ---: |
| `number-N`, N=0..19,20,30,40,50,60,70,80,90,100,200,300,400,500,600,700,800,900; joined excludes zero | 37 | 36 | 73 |
| `scale-S-small-N`, S=1000/1000000, N=1..19 | 38 | 38 | 76 |
| `scale-S-decade-N`, S=1000/1000000, N=20,30,40,50,60,70,80,90 | 16 | 16 | 32 |
| `scale-S-hundred-N`, S=1000/1000000, N=100,200,300,400,500,600,700,800,900; joined only for S=1000 | 18 | 9 | 27 |
| Total | 109 | 99 | 208 |

The 20 small-number transcripts are:
`صِفْر، وَاحِد، اِثْنَان، ثَلَاثَة، أَرْبَعَة، خَمْسَة، سِتَّة، سَبْعَة، ثَمَانِيَة، تِسْعَة، عَشَرَة، أَحَدَ عَشَر، اِثْنَا عَشَر، ثَلَاثَةَ عَشَر، أَرْبَعَةَ عَشَر، خَمْسَةَ عَشَر، سِتَّةَ عَشَر، سَبْعَةَ عَشَر، ثَمَانِيَةَ عَشَر، تِسْعَةَ عَشَر`.
The eight decades are
`عِشْرُون، ثَلَاثُون، أَرْبَعُون، خَمْسُون، سِتُّون، سَبْعُون، ثَمَانُون، تِسْعُون`.
The nine standalone hundreds are
`مِئَة، مِئَتَان، ثَلَاثُمِئَة، أَرْبَعُمِئَة، خَمْسُمِئَة، سِتُّمِئَة، سَبْعُمِئَة، ثَمَانِمِئَة، تِسْعُمِئَة`.

The scale families consistently use `أَلْف / أَلْفَان / آلَاف / أَلْفًا` and
`مِلْيُون / مِلْيُونَان / مَلَايِين / مِلْيُونًا`. Coefficients 3..10 have their
internal nominative ending before the plural, e.g. `ثَلَاثَةُ آلَاف` and
`ثَمَانِيَةُ مَلَايِين`. Whole 11..19 phrases retain the internal teen ending,
e.g. `أَحَدَ عَشَرَ أَلْفًا` and `اِثْنَا عَشَرَ مِلْيُونًا`. The first part of 12
is nominative `اثنا`; changing it to `اثني` would contradict the selected frame.
Decades have their internal ending before the singular accusative scale, e.g.
`عِشْرُونَ أَلْفًا`. These complement choices follow the primary
[Al Jazeera number lesson](https://learning.aljazeera.net/tr/languageofmedia/جائزة-الشيخ-حمد-للترجمة-1).

Hundred-scale prefixes are exactly
`مِئَةُ، مِئَتَا، ثَلَاثُمِئَةِ، أَرْبَعُمِئَةِ، خَمْسُمِئَةِ، سِتُّمِئَةِ، سَبْعُمِئَةِ، ثَمَانِمِئَةِ، تِسْعُمِئَةِ`.
Each is recorded with its singular scale in one phrase. This preserves construct
`مِئَتَا أَلْف` and the internal genitive in `ثَلَاثُمِئَةِ أَلْف`; a standalone
`مِئَتَان` must never be spliced before a scale. The final scale word is pausal,
so its omitted final case vowel is deliberate. The genitive-complement principle
is also stated in [Al Jazeera's grammar answer](https://learning.aljazeera.net/ar/node/590).

All 99 joined transcripts were inspected. They attach `وَ` to the whole phrase;
initial `اِ` becomes `ا` in the joined spelling, giving `وَاثْنَان` and
`وَاثْنَا عَشَرَ أَلْفًا`. Initial hamzat al-qat remains, as in `وَأَلْف`.
`وَوَاحِد` correctly has two waw letters: conjunction plus the word's initial
consonant. No joined zero or joined million-hundred is required. Million-hundred
can only be the first component within 0..999999999. A joined million-small or
million-decade is reachable after the same group's hundred phrase.

## Composition and boundary findings

The compositor emits descending million/thousand/unit groups. Within each group
it emits an already scaled hundred phrase, then the remainder. Units precede
decades. Every component after the first selects an attached-wa recording.
For 124000, the interpretation is `100000 + (4 + 20) * 1000`; the final scale
does not multiply the already completed 100000 component a second time.

The Virtual Academy's own
[2018 adopted decision](https://almajma3.blogspot.com/2018/04/blog-post_20.html)
supports descending large-number order and discusses a repeated-scale 124000
example. Its quoted historical example is not an endorsement of an audio
segmentation scheme. Applying that additive construction to 101/102 and 201/202
scale coefficients is this review's explicit engineering inference: each phrase
is a complete correctly inflected quantity and conjunction adds those quantities.
The source does not directly quote all eight cases below. No Cairo Academy or
native-speaker endorsement is claimed.

The separator ` / ` below marks actual recording boundaries, not spoken text.

| Value | Exact selected recording transcripts |
| --- | --- |
| 11 | أَحَدَ عَشَر |
| 12 | اِثْنَا عَشَر |
| 21 | وَاحِد / وَعِشْرُون |
| 101 | مِئَة / وَوَاحِد |
| 102 | مِئَة / وَاثْنَان |
| 201 | مِئَتَان / وَوَاحِد |
| 202 | مِئَتَان / وَاثْنَان |
| 2000 | أَلْفَان |
| 3000 | ثَلَاثَةُ آلَاف |
| 11000 | أَحَدَ عَشَرَ أَلْفًا |
| 12000 | اِثْنَا عَشَرَ أَلْفًا |
| 21000 | وَاحِد / وَعِشْرُونَ أَلْفًا |
| 101000 | مِئَةُ أَلْف / وَأَلْف |
| 102000 | مِئَةُ أَلْف / وَأَلْفَان |
| 103000 | مِئَةُ أَلْف / وَثَلَاثَةُ آلَاف |
| 124000 | مِئَةُ أَلْف / وَأَرْبَعَة / وَعِشْرُونَ أَلْفًا |
| 201000 | مِئَتَا أَلْف / وَأَلْف |
| 202000 | مِئَتَا أَلْف / وَأَلْفَان |
| 2000000 | مِلْيُونَان |
| 3000000 | ثَلَاثَةُ مَلَايِين |
| 11000000 | أَحَدَ عَشَرَ مِلْيُونًا |
| 12000000 | اِثْنَا عَشَرَ مِلْيُونًا |
| 101000000 | مِئَةُ مِلْيُون / وَمِلْيُون |
| 102000000 | مِئَةُ مِلْيُون / وَمِلْيُونَان |
| 201000000 | مِئَتَا مِلْيُون / وَمِلْيُون |
| 202000000 | مِئَتَا مِلْيُون / وَمِلْيُونَان |
| 1001001 | مِلْيُون / وَأَلْف / وَوَاحِد |

Maximum 999999999 selects nine recordings:

`تِسْعُمِئَةِ مِلْيُون / وَتِسْعَة / وَتِسْعُونَ مِلْيُونًا / وَتِسْعُمِئَةِ أَلْف / وَتِسْعَة / وَتِسْعُونَ أَلْفًا / وَتِسْعُمِئَة / وَتِسْعَة / وَتِسْعُون`.

A bounded read-only Node inspection performed 15,648 pure compositions: every
0..999 group at each of three scales; the unit/thousand groups also following
100000000; and the 22³ cross-product of groups
`[0,1,2,3,9,10,11,12,19,20,21,22,29,99,100,101,102,199,200,201,202,999]`.
All 208 identities were reachable; no catalog invariant error occurred; the
largest playlist had nine tokens. This was an inventory/boundary inspection,
not a new independent semantic-decoder regression or audio test. The historical
79,465-check regression described by the design document was not rerun here.

## Introduction and delivery decision

Select this exact new identity and text for `ar-sa`:

`acdc-cardinal-intro-v1-current-position-number`

`رَقْمُ مَوْقِعِكَ الْحَالِي فِي طَابُورِ الِانْتِظَارِ هُوَ.`

Exact UTF-8 transcript SHA-256, including the final period and no newline:
`a90d20b338dcafa924d45f03364399aca462df3fce7de1924397097ee0e2166f`.

The sentence introduces the number of the caller's current position in the
waiting queue. `رَقْمُ` provides the explicit numeric frame; `هُوَ` introduces
the nominative predicate. `الْحَالِي` agrees with the current position in the
construct phrase. The masculine singular address follows the proposed existing
addressing convention. The sentence is this release's authored wording, not a
quoted reference sentence. Preserve the historical introductions under their
historical identities. This choice adds one Arabic intro recording outside the
208 cardinal-role bank; it does not add an ordinal or a callers-ahead count.

Approve the intended delivery specification as whole pausal chunks: retain brief
natural recording boundaries, internal inflection within every scale phrase,
pausal final consonants, and the pausal long final vowel of `أَلْفًا` /
`مِلْيُونًا`. A pause after the unit in 21/21000 or between joined hundreds and
remainders is an intentional reading style whose actual naturalness must be
heard. Do not interpret this text review as permission to remove all silence
and claim continuous inflected speech. No textual alteration is required by
this review; if recorded delivery fails, preserve successful immutable bytes
and handle replacement through the explicit versioned authoring workflow.

Use the one pinned female voice `Sulafat` for Arabic cardinal and new intro
authoring. `pack.requestBody` pins that voice and requests Modern Standard Arabic
whole pausal chunks. This is a source/request contract; actual voice consistency,
pronunciation, comfortable pauses, completeness and intelligibility remain
unverified. Runtime remains prerecorded playback with no TTS.

The intro has no WAV hash in this review. Bind a real verified 8-kHz telephony
WAV hash after authoring; do not substitute its master hash, a placeholder, or
this transcript hash. Leave listening evidence and asset-set hashes pending
until actual listening occurs. `pack.verifyPack` explicitly reports
`intro_audio_verified: false`; declaration validation cannot prove intro bytes.
The finite text review is complete, while recording, technical QA, listening,
whole-playlist verification and ACDC runtime acceptance are separate work.
