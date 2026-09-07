# Hebrew cardinal release text review — 2026-09-07

Decision: retain all 131 Hebrew cardinal role transcripts and the compositor's
selected feminine abstract-number-label grammar. Select the new explicit-number
introduction below for this release. This bounded source-backed engineering
review found no specific transcript correction requiring a new catalog version.
It accepts the written catalog, semantic frame and intended natural prerecorded
chunk delivery for authoring; it is **not native-speaker listening, pronunciation
acceptance, audio verification or runtime readiness**.

The review read the four pinned inputs below, enumerated every exported Hebrew
role and evaluated the pure compositor on short forms, hundreds, scales and the
documented full-number boundaries. No provider request, credential access, audio
generation, audio playback, import, service operation, deployment or commit was
performed. No approval JSON or existing asset was changed. Historical regression
receipts in the design were read, not rerun or represented as new evidence.

## Frozen inputs

SHA-256 of complete file bytes at review time:

| Input | SHA-256 |
| --- | --- |
| `doc/acdc_cardinal_authoring_readiness.md` | `15645573cb39d33216b847335b31b57b3a1369760e55de8bc984be67d520e491` |
| `doc/acdc_prerecorded_cardinal_design.md` | `cb747de5d0932a8d1b1df2d2b921bca0118757f6be81c5dbda2c1d796b6379f7` |
| `scripts/acdc-cardinal-catalog.cjs` | `402be11bfb4da7d2113c06940d41a362cd89b159436fefe092c13f4b56c2f855` |
| `scripts/acdc-cardinal-pack.cjs` | `a53f1ff78c55ab941a5bf3a7ba9a5525161a580e03573e42cde18287ffe20328` |

These are distinct from the canonical JSON hashes computed by `pack.digest`:

| Value | SHA-256 |
| --- | --- |
| `pack.CATALOG_HASH` (all five locales) | `5703e649a1f5a2bcd0c00e9e19bf4424e024c85648452dba0d190bcf73088134` |
| `pack.LOCALE_HASHES['he-il']` (enriched records) | `b254435a21152a804eb1ffa114adf9e26c6e46afe83289ddec5fdccac27ee661` |
| `pack.digest(catalog.plan('he-il'))` | `5053238e28b0a9a5992279c48ce698d4a9774cb97caa1515a4e224f6f16344d7` |
| `pack.digest(pack.contexts['he-il'])` | `afe1b6d0956d260a12387ce935b4f893eac3197ecd6bbd6ccee74d3b12c92f18` |

The context is `current-queue-position-number-label`, grammar
`abstract-number-label-feminine`, delivery `natural-prerecorded-chunks`, with
introduction approval required. All ACDC work and this review remain in `kz5`.

## Inventory and complete transcript review

Every identity is locale `he-il` plus `acdc-cardinal-v1-<role>`. There are 131
roles: 66 plain and 65 joined, requiring 131 new recordings / 262 master and
telephony WAVs. The selected introduction adds one separate recording / two WAVs;
it does not expand the 131-role or 584-role catalog. No fixed210 telephone digit
or introduction recording is presumed reusable or replaceable.

The following tables enumerate the complete reviewed text. A dash means the
plain masculine role does not exist; it is not a missing recording.

| N | `masculine-N` | `joined-masculine-N` | `feminine-N` | `joined-feminine-N` |
| --- | --- | --- | --- | --- |
| 1 | — | וְאֶחָד | אַחַת | וְאַחַת |
| 2 | — | וּשְׁנַיִם | שְׁתַּיִם | וּשְׁתַּיִם |
| 3 | שְׁלוֹשָׁה | וּשְׁלוֹשָׁה | שָׁלוֹשׁ | וְשָׁלוֹשׁ |
| 4 | אַרְבָּעָה | וְאַרְבָּעָה | אַרְבַּע | וְאַרְבַּע |
| 5 | חֲמִשָּׁה | וַחֲמִשָּׁה | חָמֵשׁ | וְחָמֵשׁ |
| 6 | שִׁשָּׁה | וְשִׁשָּׁה | שֵׁשׁ | וְשֵׁשׁ |
| 7 | שִׁבְעָה | וְשִׁבְעָה | שֶׁבַע | וְשֶׁבַע |
| 8 | שְׁמוֹנָה | וּשְׁמוֹנָה | שְׁמוֹנֶה | וּשְׁמוֹנֶה |
| 9 | תִּשְׁעָה | וְתִשְׁעָה | תֵּשַׁע | וְתֵשַׁע |
| 10 | עֲשָׂרָה | וַעֲשָׂרָה | עֶשֶׂר | וְעֶשֶׂר |
| 11 | אַחַד עָשָׂר | וְאַחַד עָשָׂר | אַחַת עֶשְׂרֵה | וְאַחַת עֶשְׂרֵה |
| 12 | שְׁנֵים עָשָׂר | וּשְׁנֵים עָשָׂר | שְׁתֵּים עֶשְׂרֵה | וּשְׁתֵּים עֶשְׂרֵה |
| 13 | שְׁלוֹשָׁה עָשָׂר | וּשְׁלוֹשָׁה עָשָׂר | שְׁלוֹשׁ עֶשְׂרֵה | וּשְׁלוֹשׁ עֶשְׂרֵה |
| 14 | אַרְבָּעָה עָשָׂר | וְאַרְבָּעָה עָשָׂר | אַרְבַּע עֶשְׂרֵה | וְאַרְבַּע עֶשְׂרֵה |
| 15 | חֲמִשָּׁה עָשָׂר | וַחֲמִשָּׁה עָשָׂר | חֲמֵשׁ עֶשְׂרֵה | וַחֲמֵשׁ עֶשְׂרֵה |
| 16 | שִׁשָּׁה עָשָׂר | וְשִׁשָּׁה עָשָׂר | שֵׁשׁ עֶשְׂרֵה | וְשֵׁשׁ עֶשְׂרֵה |
| 17 | שִׁבְעָה עָשָׂר | וְשִׁבְעָה עָשָׂר | שְׁבַע עֶשְׂרֵה | וּשְׁבַע עֶשְׂרֵה |
| 18 | שְׁמוֹנָה עָשָׂר | וּשְׁמוֹנָה עָשָׂר | שְׁמוֹנֶה עֶשְׂרֵה | וּשְׁמוֹנֶה עֶשְׂרֵה |
| 19 | תִּשְׁעָה עָשָׂר | וְתִשְׁעָה עָשָׂר | תְּשַׁע עֶשְׂרֵה | וּתְשַׁע עֶשְׂרֵה |

| Role | Plain transcript | `joined-` transcript |
| --- | --- | --- |
| `tens-20` | עֶשְׂרִים | וְעֶשְׂרִים |
| `tens-30` | שְׁלוֹשִׁים | וּשְׁלוֹשִׁים |
| `tens-40` | אַרְבָּעִים | וְאַרְבָּעִים |
| `tens-50` | חֲמִשִּׁים | וַחֲמִשִּׁים |
| `tens-60` | שִׁשִּׁים | וְשִׁשִּׁים |
| `tens-70` | שִׁבְעִים | וְשִׁבְעִים |
| `tens-80` | שְׁמוֹנִים | וּשְׁמוֹנִים |
| `tens-90` | תִּשְׁעִים | וְתִשְׁעִים |
| `hundreds-100` | מֵאָה | וּמֵאָה |
| `hundreds-200` | מָאתַיִם | וּמָאתַיִם |
| `hundreds-300` | שְׁלוֹשׁ מֵאוֹת | וּשְׁלוֹשׁ מֵאוֹת |
| `hundreds-400` | אַרְבַּע מֵאוֹת | וְאַרְבַּע מֵאוֹת |
| `hundreds-500` | חֲמֵשׁ מֵאוֹת | וַחֲמֵשׁ מֵאוֹת |
| `hundreds-600` | שֵׁשׁ מֵאוֹת | וְשֵׁשׁ מֵאוֹת |
| `hundreds-700` | שְׁבַע מֵאוֹת | וּשְׁבַע מֵאוֹת |
| `hundreds-800` | שְׁמוֹנֶה מֵאוֹת | וּשְׁמוֹנֶה מֵאוֹת |
| `hundreds-900` | תְּשַׁע מֵאוֹת | וּתְשַׁע מֵאוֹת |
| `thousands-1` | אֶלֶף | וְאֶלֶף |
| `thousands-2` | אַלְפַּיִם | וְאַלְפַּיִם |
| `thousands-3` | שְׁלוֹשֶׁת אֲלָפִים | וּשְׁלוֹשֶׁת אֲלָפִים |
| `thousands-4` | אַרְבַּעַת אֲלָפִים | וְאַרְבַּעַת אֲלָפִים |
| `thousands-5` | חֲמֵשֶׁת אֲלָפִים | וַחֲמֵשֶׁת אֲלָפִים |
| `thousands-6` | שֵׁשֶׁת אֲלָפִים | וְשֵׁשֶׁת אֲלָפִים |
| `thousands-7` | שִׁבְעַת אֲלָפִים | וְשִׁבְעַת אֲלָפִים |
| `thousands-8` | שְׁמוֹנַת אֲלָפִים | וּשְׁמוֹנַת אֲלָפִים |
| `thousands-9` | תִּשְׁעַת אֲלָפִים | וְתִשְׁעַת אֲלָפִים |
| `thousands-10` | עֲשֶׂרֶת אֲלָפִים | וַעֲשֶׂרֶת אֲלָפִים |

The remaining three plain-only records are `number-0` = אֶפֶס, `million` =
מִילְיוֹן and `two-million` = שְׁנֵי מִילְיוֹן. Million is the highest supported
scale and cannot be an outer joined group, so joined million records are not
missing. Exact one/two scale groups have whole recordings; compound coefficients
ending one/two use the joined masculine forms. The omitted plain masculine 1/2
are consequently unreachable by construction. Counts reconcile as
1 + 17 + 19 + 38 + 16 + 18 + 20 + 2 = 131.

The fully retrieved [CET language-team usage lesson](https://www.lib.cet.ac.il/PAGES/item.asp?item=13674)
supports feminine numerical labels, feminine hundreds, masculine thousands and
vav's sheva/shuruk/hataf vowel classes. Applying those rules to these authored
words supports the joined inventory, including the different treatment of
feminine five versus masculine five, and plain nine versus construct nineteen.
The [CET number-tables lesson's retrieved prose](https://www.lib.cet.ac.il/PAGES/item.asp?item=13671)
also supports mixed hundreds/tens/units and scale agreement; its table images
were not consulted. The [Academy's mathematics terminology](https://terms.hebrew-academy.org.il/Millonim/ShowMillon?KodMillon=110)
supplies the vocalized million form. These sources provide rules and examples,
not a quotation or certification of this entire authored table.

The pointed joined forms consistently remove initial begadkefat dagesh from
tav after vav, while preserving internal dagesh: compare תֵּשַׁע / וְתֵשַׁע,
תִּשְׁעָה / וְתִשְׁעָה and תְּשַׁע / וּתְשַׁע. Internal tav in וּשְׁתַּיִם
is retained. The hundreds use construct forms, including חֲמֵשׁ, שְׁבַע and
תְּשַׁע. No correction to these written forms was identified.

## Boundary decisions

These are actual pure `transcript(number, 'he-il')` outputs inspected in this
review. Spaces are token joins only where a role ends; multiword hundred and
small-thousand roles remain single recordings.

| Number | Full vocalized output |
| --- | --- |
| 0 | אֶפֶס |
| 11 | אַחַת עֶשְׂרֵה |
| 12 | שְׁתֵּים עֶשְׂרֵה |
| 21 | עֶשְׂרִים וְאַחַת |
| 101 | מֵאָה וְאַחַת |
| 102 | מֵאָה וּשְׁתַּיִם |
| 119 | מֵאָה וּתְשַׁע עֶשְׂרֵה |
| 120 | מֵאָה וְעֶשְׂרִים |
| 121 | מֵאָה עֶשְׂרִים וְאַחַת |
| 2500 | אַלְפַּיִם וַחֲמֵשׁ מֵאוֹת |
| 12000 | שְׁנֵים עָשָׂר אֶלֶף |
| 21000 | עֶשְׂרִים וְאֶחָד אֶלֶף |
| 101000 | מֵאָה וְאֶחָד אֶלֶף |
| 200356 | מָאתַיִם אֶלֶף שְׁלוֹשׁ מֵאוֹת חֲמִשִּׁים וְשֵׁשׁ |
| 1001000 | מִילְיוֹן וְאֶלֶף |
| 1001001 | מִילְיוֹן אֶלֶף וְאַחַת |
| 1021000 | מִילְיוֹן וְעֶשְׂרִים וְאֶחָד אֶלֶף |
| 1101001 | מִילְיוֹן מֵאָה וְאֶחָד אֶלֶף וְאַחַת |
| 121121121 | מֵאָה עֶשְׂרִים וְאֶחָד מִילְיוֹן מֵאָה עֶשְׂרִים וְאֶחָד אֶלֶף מֵאָה עֶשְׂרִים וְאַחַת |
| 999999999 | תְּשַׁע מֵאוֹת תִּשְׁעִים וְתִשְׁעָה מִילְיוֹן תְּשַׁע מֵאוֹת תִּשְׁעִים וְתִשְׁעָה אֶלֶף תְּשַׁע מֵאוֹת תִּשְׁעִים וְתֵשַׁע |

Accept the existing last-additive-term conjunction rule. The coefficient of a
scale is itself an expression: 1021000 has both an outer join on twenty and an
inner join on one. These denote 1000000 + (20 + 1) × 1000. In 1101001, the
internal hundred-and-one coefficient and outer final one also each retain their
join. This follows the selected compositional style and preserves numeric
meaning; it is an engineering application, not a claim that a primary source
quotes those exact large numbers or that their recorded cadence was heard.

The [Academy-authored Ministry slideshow](https://meyda.education.gov.il/files/Pop/0files/ivrit_habaah_lashon/pedagogia/shem-mispar.pdf)
is search-index retrievable for the final-term conjunction and joined exact
decades; direct retrieval failed in this review. The design's earlier-join
allowance and its 200356 example therefore retain their stated source limitation.
Likewise, [Academy number decisions](https://hebrew-academy.org.il/category/יידוע/)
are search-index retrievable for singular million after a coefficient and
construct hundreds/small thousands, but the direct category fetch failed.
No inaccessible PDF page is claimed as newly read. These bounded retrieval
limits do not identify a concrete correction to the existing selected style.

At maximum, the roles are `hundreds-900`, `tens-90`, `joined-masculine-9`,
`million`, `hundreds-900`, `tens-90`, `joined-masculine-9`, `thousands-1`,
`hundreds-900`, `tens-90`, `joined-feminine-9`: exactly 11, with no extra scale
coefficient and no digit spelling. The structural upper bound is four tokens
for each scaled group plus three for the final group. When a final thousand
group gains an outer join, only its first existing role changes. The full
0..999999999 range remains required; source review does not prove live support.

## Introduction and delivery decision

Select locale `he-il`, canonical identity
`acdc-cardinal-intro-v1-current-position-number`, exact UTF-8 transcript including
the final ASCII period and no trailing newline:

`מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.`

Transcript SHA-256:
`3546259e51a69a94ea84d3c3ba28d8b9105397ae0830599cc2b7301a0fb7a2d1`.

Its meaning is the number of the caller's current place in the queue. The
explicit number frame licenses the following feminine label under the retrieved
CET rule. The pronoun הוּא agrees with masculine מִסְפַּר, while the numeral
names the numerical label; it need not become a masculine count of people.
This is a new authored queue sentence inferred from the usage rule. It is not
an ordinal, ticket number or callers-ahead announcement. Preserve the historical
`מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.` recording and all fixed210 provenance.

Use the same one female prerecorded HE voice for intro and all 131 roles. The
reviewed pack pins `Sulafat`, requests native Israeli Hebrew and an adult female
call-center delivery, and has no runtime TTS path. A pinned voice name and prompt
are authoring constraints, not perceptual proof of voice consistency. Record
the attached-vav phrases whole and deliver joined coefficient/scale playlists
at a natural number-reading pace. The SoX recipe only resamples; it establishes
neither acceptable boundary silence nor natural speech continuity.

No introduction WAV hash is supplied by this text review. Bind the actual new
telephony WAV hash after its creation and byte verification; never fill the
approval schema with a placeholder, a master hash or the old intro's hash.
`intro_audio_verified:false` in the cardinal verifier correctly remains separate.
Native listening must still establish the spoken text, initial-vav vowels,
gender contrasts, stress, short and maximum playlists, intro-to-number joining,
cadence and one-voice continuity on actual assets. The listening declaration
remains `{status:"PENDING",evidence_sha256:null,asset_set_sha256:null}` until
that work occurs. No listening approval is implied by this review's authoring
decision or by a successful technical WAV check.
