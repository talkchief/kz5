# Prerecorded queue cardinal numbers: finite-catalog design

Status: design and isolated EN/ES/FR source building block, **not runtime readiness**.
The release requirement remains EN/HE/FR/ES/AR, each covering every integer
0..999999999 using one built-in female Gemini voice and recordings authored in
this release. No native SAY, digit-spelling substitute for cardinals, runtime TTS,
account-creation synthesis, installer synthesis, or silent language fallback.

The completed 45-clip supplemental callback pack supplies telephone digits and
auxiliary prompts, not the full cardinal range. Telephone readback remains a
separate digit-by-digit operation. Existing manifests/assets must not be rewritten.

## Source contract and next action

`scripts/acdc-cardinal-catalog.cjs` is a pure versioned authoring-time building
block. Version `acdc-cardinal-v1` contains 31 EN, 53 ES and 161 FR logical recordings.
`compose(number, locale)` returns `{catalog_version, locale, number, token_ids}`;
`tokens`, `transcript` and `plan` expose playback IDs, review text and the catalog.
The module has no imports, I/O, provider, playback or account integration.
Only exact `en-us`, `es-es` and `fr-fr` currently compose. Required but
unimplemented `he-il`, `ar-sa` fail explicitly. This is not a reduced release scope.

IDs are `acdc-cardinal-v1-<role>` with locale forming part of the media identity.
They are distinct from historical `acdc-number-*` IDs; do not overwrite the
existing telephone recordings. A new immutable authoring manifest will pin
transcripts, context, request/response provenance and exact audio bytes. Existing
digits may be reused only after their precise form and cadence are qualified;
counts below do not silently assume reuse.

Next: finish AR/HE transcript gates below, implement the remaining pure grammars,
freeze the reachable token catalog, author/verify every required WAV now, then
integrate the catalog into canonical ACDC and the system-media importer. All
existing/future accounts and subaccounts use these same shared recordings. The
installer imports/verifies files; it never invokes generation. Built-in language
selection must not erase customer recordings, nor fall back through them to a
different voice/language. Resolve and verify the whole playlist before playback.

Current canonical `applications/acdc/src/acdc_language.erl:number_prompts/2`
still uses native SAY for EN/FR/ES and complete scalar/scaled clips for AR/HE.
Its universal `lists:join('and', Groups)` is not a five-language grammar. Merely
importing new WAVs does not repair this source integration gap.

## Exact practical EN inventory: 31

| Roles | Transcripts | Count |
| --- | --- | ---: |
| `number-0` through `number-19` | zero, one, two, three, four, five, six, seven, eight, nine, ten, eleven, twelve, thirteen, fourteen, fifteen, sixteen, seventeen, eighteen, nineteen | 20 |
| `number-20`, `-30`, ... `-90` | twenty, thirty, forty, fifty, sixty, seventy, eighty, ninety | 8 |
| `hundred`, `thousand`, `million` | hundred, thousand, million | 3 |

American number-label style: no conjunction “and.” For each nonzero three-digit
group, emit unit + hundred when needed, then the remainder. Emit million,
thousand and final-unit groups in descending order, omitting zero groups. Zero
has one token only when the entire value is zero. Scale words are invariant.

Examples: 101 = “one hundred one”; 1001 = “one thousand one”; 1001001 = “one
million one thousand one.” Maximum999999999 uses14 tokens. This is a selected
American style, not a claim that other English cardinal styles are incorrect.
The installed FreeSWITCH `mod_say_en.c:play_group` also uses this no-and style;
the new compositor does not invoke that native implementation.

## Exact practical ES inventory: 53

| Roles | Transcripts | Count |
| --- | --- | ---: |
| `number-0` through `number-29` | cero through veintinueve, whole words including dieciséis, veintidós, veintitrés, veintiséis | 30 |
| `number-30`, `-40`, ... `-90` | treinta, cuarenta, cincuenta, sesenta, setenta, ochenta, noventa | 7 |
| `number-100`, `-200`, ... `-900` | cien, doscientos, trescientos, cuatrocientos, quinientos, seiscientos, setecientos, ochocientos, novecientos | 9 |
| `hundred-continuation` | ciento | 1 |
| `before-scale-1`, `before-scale-21` | un, veintiún | 2 |
| `and`, `thousand`, `million`, `millions` | y, mil, millón, millones | 4 |

This is masculine abstract number-label grammar, not feminine counted-noun or
ordinal grammar. Use cien for exact100, ciento before a nonzero remainder; y
only joins a decade30..90 to a unit. Terminal1/21 use uno/veintiuno, while scale
coefficients use un/veintiún (including treinta y un). Thousand coefficient1
is omitted: mil, never un mil. Million uses un millón for coefficient1 and
millones otherwise. No y joins hundreds or scale groups.

Examples: 101 = “ciento uno”; 21000 = “veintiún mil”; 101000 = “ciento un mil”;
101000000 = “ciento un millones”; 1001001 = “un millón mil uno.”
The complete source plan contains the exact spelled transcript of all53 roles.
Rules and irregular forms: [RAE, cardinales](https://www.rae.es/dpd/cardinales).

## Implemented pure FR catalog: 161 logical recordings, no WAVs generated

France French, not septante/nonante variants. Prefer whole short phrases to
unreliable phoneme fragments from isolated-word TTS:

| Roles | Contents | Count |
| --- | --- | ---: |
| `terminal-N`, N=0..99 | Complete cardinal phrases, including21..29,71,80..99 | 100 |
| `hundreds-H`, H=1..9 | Complete100,200,...900 phrases | 9 |
| `hundred-one-H`, H=1..9 | Complete101,201,...901 phrases | 9 |
| `scaled-tail-S-N` | Whole N + mille / millions for each N in the set below | 40 |
| `thousand`, `million`, `millions` | mille, million, millions | 3 |

Contextual tail set: **6,8,10,18,26,28,36,38,46,48,56,58,66,68,70,78,86,88,90,98**.
These end in spoken six, huit or dix whose final consonant can differ before
the consonant of mille/millions. Record “vingt-six mille” as a whole phrase,
not an isolated six expected to transform itself at playback. Whole0..99 also
handles the pronounced t in21..29 without incorrectly adding it in81/92.

For group100H+R: exact hundreds use their whole token; R=1 uses the whole
hundred-one token; otherwise prepend the hundred token to the remainder. A
scaled remainder in the set above uses its whole scaled-tail phrase; other
remainders use the terminal phrase plus scale. Thousand coefficient1 is just
mille; million coefficient1 is un million. Hundred-one phrases deliberately
avoid depending on an unverified cent/un audio join. Orthographic cent/vingt
plural context still belongs in the full transcript, even where audio is equal.

The pure source implements these exact161 roles. A `scaled-tail` entry has numeric
`value` (the tail coefficient) and `scale` (1000 or1000000). It closes the current
group as `(preceding hundreds + value) * scale`; the compositor must not append a
second scale token. Whole H01 entries carry their complete numeric value. The
immutable catalog stores normal standalone recording transcripts. Full
`transcript()` output separately removes the silent plural s in cent(s) or
quatre-vingt(s) when another numeral, including mille, follows; it retains the
plural before the noun millions. This spelling operation never alters audio or
replaces a contextual sound with an isolated digit. Existing EN/ES transcripts,
IDs, forms and14-token maximum remain unchanged; French needs at most8 tokens.

Examples: 71 = “soixante et onze”; 81 = “quatre-vingt-un”; 108 = “cent huit”;
111 = “cent onze”; 201 = “deux cent un”; 26000 uses the whole “vingt-six mille”
tail; 106000 = [cent, six mille]; 200000 = “deux cent mille” but200000000 =
“deux cents millions”; 280000 = “deux cent quatre-vingt mille” but280000000 =
“deux cent quatre-vingts millions.” No et is inserted between hundreds or scale
groups; 1001 uses “mille un,” not the indefinite-quantity expression “mille et un.”
The selected full-text spelling is traditional cardinal spelling, not a general
ordinal, feminine counted-noun or currency API. Native listening still needs to
qualify pronunciation and coarticulation; a correct transcript is not audio proof.

Primary references checked during implementation on2026-09-06:
[OQLF six/dix](https://vitrinelinguistique.oqlf.gouv.qc.ca/23137/la-prononciation/prononciation-des-nombres/prononciation-de-six-et-dix),
[huit](https://vitrinelinguistique.oqlf.gouv.qc.ca/23149/la-prononciation/prononciation-des-nombres/prononciation-de-huit),
[vingt](https://vitrinelinguistique.oqlf.gouv.qc.ca/23141/la-prononciation/prononciation-des-nombres/prononciation-de-vingt),
[cent/vingt/mille plurals](https://vitrinelinguistique.oqlf.gouv.qc.ca/21532/la-grammaire/les-determinants/determinants-numeraux/pluriel-de-vingt-de-cent-et-de-mille),
[et in compound numbers](https://vitrinelinguistique.oqlf.gouv.qc.ca/24631/la-prononciation/prononciation-des-nombres/prononciation-de-et-dans-les-nombres-composes),
[traditional number spelling](https://vitrinelinguistique.oqlf.gouv.qc.ca/index.php?id=23494).
This161-role bank needs authoring review before payment and listening review after
generation; it is a practical bounded bank, not a proven minimum or artifact pack.

## HE draft: 133 roles, explicit unresolved transcript gates

Provisional role accounting (not an approved generation manifest):

- Masculine0..19:20; decades20..90:8; complete hundreds100..900:9;
  complete1000..10000 in thousand steps:10; million/two-million:2. Base49.
- Attached-conjunction versions of masculine1..19:19, decades:8, hundreds:9,
  and those ten whole-thousand phrases:10. Additional46.
- Terminal feminine1..19 and their attached-conjunction versions:38.

Total49+46+38=133. Reuse the one-thousand elef form as the scale after larger
coefficients. Number labels are feminine; masculine scale coefficients, construct
3..10thousand and the special2000 form must not be confused with terminal digits.
Examples requiring goldens: 1000 אלף; 2000 אלפיים; 3000 שלושת אלפים;
11000 אחד עשר אלף; terminal21 עשרים ואחת, versus a masculine scale coefficient.

Remaining gates: freeze the complete vocalized table, correct attached vav
pronunciation, and the final-conjunction syntax across nested groups. Do not
reuse one generic ve clip or the existing synthetic phoneme helper as linguistic
approval. Check the existing queue introduction against the selected abstract
number-label meaning before any additional intro recording is proposed.
[Hebrew Academy number-label guidance](https://hebrew-academy.org.il/meeting/%D7%A6%D7%91/)
and [Unicode Hebrew rule source](https://raw.githubusercontent.com/unicode-org/cldr/main/common/rbnf/he.xml)
provide references, not an automatic transcript/audio approval.

## AR draft: 103 roles, explicit unresolved transcript gates

Provisional role accounting (not an approved generation manifest):

- Masculine/nominative number-label0..19:20; decades20..90:8;
  nine free hundreds and nine construct-before-scale hundreds:18;
  five scale forms for each of thousand/million:10. Base56.
- Attached-wa variants:1..19:19; decades:8; free/construct hundreds:18;
  one/two-thousand:2. Additional47. Draft total103.

The five scale roles distinguish one, dual nominative,3..10 plural,11..99
singular accusative and exact-hundred genitive. Examples to freeze include
ألف، ألفان، ثلاثة آلاف، أحد عشر ألفًا، مئة ألف; the analogous million forms
include مليون، مليونان، ثلاثة ملايين. Units precede decades; compound11/12,
hundreds, dual construct endings and conjunctions require actual contextual text.

The103 count is **not established as sufficient**. In particular,101/102-scale
composition and construct/pausal endings must be settled with exact grammatical
and spoken goldens; those may require additional roles. Do not silently select a
dialect, misuse accusative duals in a nominative frame, or certify a draft library
merely because a third-party number converter emits it. Freeze the introduction's
number-label context too. [Arabic number agreement and scale cases](https://learning.aljazeera.net/ar/node/21410).

## Tests and acceptance boundaries

The isolated EN/ES test checks all1000 group values at unit/thousand/million
scales, numeric meaning of token streams, apocope and cien/ciento context, explicit
full transcripts, cross-products of22 group boundaries, mixed full-range values,
and maximum999999999. Both implemented grammars have a14-token maximum. Invalid
inputs/locales fail; imports work with no filesystem/network/provider globals.
The French extension preserves these29,344 EN/ES composition checks and adds
all3000 French group/scale cases, a separately written literal0..99 table, full
transcript goldens, every contextual-tail selection and all161-role reachability.
It also checks22-by22-by22 French group-boundary combinations plus1000 mixed
values, including plural spelling across groups and the8-token maximum. Receipt
counts report actual checks; a prepared fixture is not a claimed test pass.
This is source grammar evidence only, not audio generation or native acceptance.

Guarded run90582 exited0 on September6: six groups passed with29,344 compositions
(48 explicit transcript goldens,6,000 group/context cases,21,296 boundary
cross-products and2,000 mixed values). Catalog SHA-256:
`9c229f8ff15ca8eb808a26f43182a4187e5add13e117ef51a65158418ad11fc4`;
test SHA-256:
`25414e714ef8340cebd3ac9072a0e0a6c07b9882770eee59537f6b89064384f7`.
These input hashes remained stable. No clips were generated or reused by this
run; no runtime media paths changed.

French extension run19058 exited0 on September6 under the256-MiB/768-MiB-reserve,
60-second offline guard. All nine groups passed with44,040 semantic composition
checks, retaining the prior EN/ES coverage and adding48 French goldens, the
literal100 short forms, exhaustive groups/scales, all161-role reachability and
the eight-token maximum. Catalog SHA-256:
`ab64c000ca343e7f0f3289016754555ba24a8b247c0763868346b8e63355e459`;
test SHA-256:
`246884834f2c88514ceaadf302c1aa7ba385c74601bd73848eb25e41f3fbe595`.
Both remained stable. This is a tested pure EN/ES/FR compositor, not a WAV pack
or a deployed runtime. Hebrew/Arabic and listening acceptance remain open.

Reproduce from a prepared host with Node18 or later:

```bash
bash /opt/kz5/scripts/run-kazoo-validation.sh \
  --memory-mib 256 --reserve-mib 768 --runtime-sec 60 -- \
  /usr/bin/unshare --net /usr/bin/node \
  /opt/kz5/scripts/test-acdc-cardinal-catalog.cjs
```

For the remaining locales, enumerate all group values in every gender/scale/join
context, then freeze all reachable roles. Verify full playlists contain only exact
same-locale catalog IDs; preflight missing audio without partial speech or fallback.
Listening must cover consonant joins, stress, conjunctions, cadence and complete
long numbers. Native owned playback cancellation, completion and bridge safety
remain separate open release gates. No source-level test closes those gates.
