# Prerecorded queue cardinal numbers: finite-catalog design

Status: design and isolated EN/ES/FR/HE source building block, **not runtime readiness**.
The release requirement remains EN/HE/FR/ES/AR, each covering every integer
0..999999999 using one built-in female Gemini voice and recordings authored in
this release. No native SAY, digit-spelling substitute for cardinals, runtime TTS,
account-creation synthesis, installer synthesis, or silent language fallback.

The completed 45-clip supplemental callback pack supplies telephone digits and
auxiliary prompts, not the full cardinal range. Telephone readback remains a
separate digit-by-digit operation. Existing manifests/assets must not be rewritten.

## Source contract and next action

`scripts/acdc-cardinal-catalog.cjs` is a pure versioned authoring-time building
block. Version `acdc-cardinal-v1` contains31 EN,53 ES,161 FR and131 HE logical recordings.
`compose(number, locale)` returns `{catalog_version, locale, number, token_ids}`;
`tokens`, `transcript` and `plan` expose playback IDs, review text and the catalog.
The module has no imports, I/O, provider, playback or account integration.
Only exact `en-us`, `es-es`, `fr-fr` and `he-il` currently compose. Required but
unimplemented `ar-sa` fails explicitly. This is not a reduced release scope.

IDs are `acdc-cardinal-v1-<role>` with locale forming part of the media identity.
They are distinct from historical `acdc-number-*` IDs; do not overwrite the
existing telephone recordings. A new immutable authoring manifest will pin
transcripts, context, request/response provenance and exact audio bytes. Existing
digits may be reused only after their precise form and cadence are qualified;
counts below do not silently assume reuse.

Next: finish AR/HE transcript gates below, implement the remaining Arabic grammar,
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

## Implemented pure HE catalog: 131 roles, no WAVs generated

The explicit source context is `abstract-number-label-feminine`, exported as
`HEBREW_CONTEXT` and present on every HE catalog entry. Terminal numbers use
feminine forms; coefficients of thousand/million use masculine forms. Hundreds
are complete feminine construct phrases in either context. This is neither
ordinal grammar nor masculine counting of places, callers or people.

| Roles | Contents | Count |
| --- | --- | ---: |
| `number-0` | אֶפֶס | 1 |
| `masculine-N`, N=3..19 | Complete masculine units/teens for scale coefficients | 17 |
| `joined-masculine-N`, N=1..19 | Complete masculine units/teens with pronounced attached vav | 19 |
| `feminine-N`, `joined-feminine-N`, N=1..19 | Complete terminal units/teens, plain and attached-vav | 38 |
| `tens-N`, `joined-tens-N`, N=20,30,...90 | Eight complete decades in each form | 16 |
| `hundreds-N`, `joined-hundreds-N`, N=100,200,...900 | Nine complete hundred phrases in each form | 18 |
| `thousands-N`, `joined-thousands-N`, N=1..10 | Whole1..10thousand phrases in each form | 20 |
| `million`, `two-million` | מִילְיוֹן; שְׁנֵי מִילְיוֹן | 2 |

Total131:66 unjoined and65 joined. This corrects the earlier133-role draft:
unjoined masculine1/2 are unreachable. One/two thousand and million already have
whole phrases, while larger scale coefficients ending1/2 require their joined
forms. No recordings are silently reused or overwritten. The complete vocalized
transcripts are in `plan('he-il')`; this is an authored review table, not paid
transcript or pronunciation acceptance.

Each three-digit group decomposes into additive terms: hundreds, decade, then
unit, or hundreds plus one whole teen. Attach vav to the last term when there is
more than one. A scaled coefficient is its own additive expression followed by
the scale. The top-level expression contains each entire scaled group and the
unscaled additive terms. Conjoin its final term, not every scale boundary or
every recording. A final compound thousand term may therefore have both an outer
conjunction and its coefficient's internal conjunction; earlier conjunctions
are permitted. Examples below make this selected style explicit.

Exact1..10thousand uses אֶלֶף, אַלְפַּיִם, שְׁלוֹשֶׁת אֲלָפִים through
עֲשֶׂרֶת אֲלָפִים. Larger coefficients precede singular אֶלֶף; million uses the
singular loanword after its coefficient. The `whole-scale` metadata stores
coefficient `value` and `scale`. After a preceding numeric coefficient, only a
singular `value:1` scale record is valid; it closes that coefficient, without
adding another one. Otherwise the complete scale phrase supplies its own value.

Record each conjunction-bearing word/phrase whole. The explicit table includes
וְ, וּ before an initial sheva or labial, and וַ before hataf-patah forms. Examples:
וְחָמֵשׁ versus וַחֲמִשָּׁה; וּשְׁתַּיִם; וּשְׁמוֹנֶה; וּמֵאָה; וַחֲמִשִּׁים.
Begadkefat pointing after vav is included in the authored text. There is no
standalone conjunction clip, phoneme splicing or playback-time vowel rewrite.
`transcript()` joins the exact vocalized recording texts without changing them.

Full-number examples, in ordinary unpointed spelling for readability:

- 21: עשרים ואחת;21000: עשרים ואחד אלף;12000: שנים עשר אלף.
- 120: מאה ועשרים;121: מאה עשרים ואחת;2500: אלפיים וחמש מאות.
- 200356: מאתיים אלף שלוש מאות חמישים ושש.
- 1001000: מיליון ואלף;1001001: מיליון אלף ואחת.
- 1021000: מיליון ועשרים ואחד אלף;1101001: מיליון מאה ואחד אלף ואחת.
- 121121121: מאה עשרים ואחד מיליון מאה עשרים ואחד אלף מאה עשרים ואחת.

The maximum999999999 needs11 tokens. The new tests enumerate every0..999 group
at three scales and additional leading/trailing group contexts, independently
decode numeric meaning, check plain full text and selected exact vocalization,
require all131 roles reachable, and check mixed/full-range boundaries. Prepared
tests do not constitute a claimed pass before the guarded run.

### Hebrew phrase-context and authoring gates

The existing immutable introduction is
`מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.` (“your current place in the queue is”).
Its noun is masculine and it does not explicitly say “number.” This pure catalog
does **not** certify that simply appending a feminine cardinal to that recording
is natural. Runtime integration must preserve **current queue position**, not
change it to a ticket number or a count of callers ahead. Before authoring or
switching playlists, approve either that existing phrase as an implicit numeric
label or a separately identified, NEW versioned introduction explicitly naming
the current position's number. A candidate wording for review is
`מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא` (“the number of your current place
in the queue is”). It is not a catalog entry or an approved replacement. Never
rewrite the historical WAV, transcript or provenance.

Primary evidence checked on2026-09-06:

- [CET language-team original usage lesson](https://www.lib.cet.ac.il/PAGES/item.asp?item=13674):
  retrievable prose explaining feminine abstract labels, the insertable word
  “number,” vav vowel classes and the gender of hundreds/thousands.
- [CET original number tables lesson](https://www.lib.cet.ac.il/PAGES/item.asp?item=13671):
  retrievable prose with mixed-group examples and scale agreement. Its linked
  table images redirect to an inactive-site page; they were **not** read.
- [Academy meeting314, pages263 and267](https://hebrew-academy.ussl.co.il/wp-content/uploads/2024/11/meeting314.pdf):
  retrievable full Academy-authored minutes distinguish technical feminine
  numbers and masculine thousand coefficients. The current canonical-domain
  mirror and meeting309 links returned403 during this audit.
- [Academy-authored Ministry slideshow](https://meyda.education.gov.il/files/Pop/0files/ivrit_habaah_lashon/pedagogia/shem-mispar.pdf):
  search-index text specifies the final additive conjunction and permits
  earlier ones, including the200356 example. Direct retrieval returned404/403;
  **this indexed source remains provisional**, not a fully retrieved transcript
  authority for paid generation.

The vocalized table, constructed join forms, complex-scale cadence and final
introduction require qualified Hebrew review before freezing paid text; listening
then qualifies actual speech. Unicode's Hebrew RBNF source is a useful structural
cross-check, not a normative text oracle: its current conjunction helper omits
vav for120, so it must not replace the explicit tests or Academy rules. These
gates do not reduce the required full range or authorize fallback/native SAY.

## AR historical draft: 103 roles, not approved

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
number-label context too. The previously cited Al Jazeera node21410 resolves to
an oil-barrel lesson, not the intended grammar source; do not use it as evidence.

### Arabic continuation checkpoint — research only, September6

No Arabic catalog/test implementation, generation or runtime edit was made.
The researcher proposed208 whole-context roles to avoid the unresolved joins
in the103-role draft. This is **not a frozen manifest, minimum proof or approved
transcript set**:

- 73 unscaled roles:37 plain (0..19,8 decades,9 whole hundreds) and36 joined
  counterparts excluding zero.
- 76 whole1..19 ×2 scale phrases, plain and joined.
- 32 whole-decade ×2 scale phrases, plain and joined.
- 27 whole-hundred ×scale phrases:18 plain plus9 joined thousand phrases;
  joined million-hundreds would be unreachable under the proposed ordering.

The estimated9-token maximum and reachability have not been implemented or
tested. Proposed101000 = `مئة ألف وألف`,102000 = `مئة ألف وألفان` apply an
additive repeated-scale rule by **inference**, not a directly sourced example.
Whole phrases preserve contextual case/dual/plural forms rather than splicing
isolated ta-marbuta endings. Pausal delivery and conjunction cadence still need
qualified review, as do all vocalized authoring transcripts.

The proposed MSA masculine/nominative numeric-label context must denote the
**current queue position**, not an ordinal, ticket number or callers ahead.
Existing `scripts/acdc-language-catalog.cjs` intro `مَوْقِعُكَ الحالي هُوَ.` and
alternative `أَنْتَ في المَوْقِعِ.` do not explicitly introduce a number.
Compatibility is unresolved; no replacement intro has been selected or recorded.

Research handoff references (retrieved by the language research agent; they do
not approve the proposed recordings):

- [Al Jazeera grammar answer](https://learning.aljazeera.net/ar/node/590), covering
  genitive nouns after hundred/thousand/million and linking the actual
  [number-agreement lesson](https://learning.aljazeera.net/tr/languageofmedia/جائزة-الشيخ-حمد-للترجمة-1).
- [Virtual Academy2018 adopted decision](https://almajma3.blogspot.com/2018/04/blog-post_20.html),
  covering large-to-small ordering and an explicit100K+24K repeated-scale
  example. This is the Virtual Academy, not a Cairo Academy decision.

Next: independently review that evidence/context, implement exact grammar and
goldens, prove full-range coverage and role reachability, review transcripts,
then author missing immutable WAVs once. Do not start paid generation from the
provisional role count alone.

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

Hebrew extension run50243 exited0 on September6: all12 groups passed with61,747
semantic composition checks, including the preceding44,040 EN/ES/FR checks,
25 vocalized and34 full-number Hebrew goldens,6,000 group/scale/join cases,
all131-role reachability and the11-token maximum. Catalog SHA-256:
`1bf013bd7aecfefdf0a01f3541831782b5a1a10000a4a7e8716a22773b476edf`;
test SHA-256:
`2407caf32f361511f4ece6dd8c702261228f59c974e75e069a3891337dca027f`.
The initial256-MiB admission attempt exited69 without running tests because
available memory was insufficient. The successful run used a tighter128-MiB
cap, the same768-MiB reserve,60-second deadline and network isolation, without
removing checks. Source/test pins remained stable. Exact vocalization and the
current-position introduction/context still require review before paid WAV
generation; the existing immutable introduction was not changed. Arabic remains
unimplemented; this does not establish four-language runtime or audio readiness.

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
