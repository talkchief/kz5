# Cardinal authoring readiness — September 7, 2026

Source-only audit. No tests, provider requests, credential reads, imports,
services, builds or calls were executed. The user has authorized one-time missing
audio authoring for this release. Approval records below describe a finite
source-backed engineering review, not an assumed requirement to wait for an
external reviewer. Native-speaker listening and actual playback remain separate,
unverified facts. Existing 210 assets must not be regenerated.

## Existing assets and exact gaps

| Effective source | Assets selected by the current importer |
| --- | ---: |
| `acdc-gemini-fixed-20260905` | 144 successful entries |
| `acdc-gemini-completion-20260905` | 21: recovered HE `acdc-queue-about_30_minutes`, plus 20 HE/AR digits |
| `acdc-gemini-supplemental-20260906` | 45: three auxiliary prompts in all five locales and 30 EN/FR/ES digits |
| Combined | 210 assets, 420 tracked WAVs, 32 fixed/auxiliary + 10 digits per locale |

The historical fixed manifest intentionally still says INCOMPLETE; its one
failure is satisfied by the completion pack. Do not rewrite that history.
Supplemental generation completed in 47 requests. The installed media receipt
currently records 0 created / 210 preserved / 210 verified and runtime_ready
false. That is retained byte-verification evidence, not a new live test.
The manifest SHA-256 pins are respectively:

```text
4269cfe5495cbffd23b14aad8711e2925f46dc14e2bced2cca12d21a18c49f90
c46a546d41836a4e27f359299f1d8664cdd3d27a11dbcf570db354000ff22208
dc041f104ab060cdd956ee237aaf004dea2edef1db070e654473a85c13f5b50b
```

Historical pre-authoring checkpoint (superseded for English by the September7
31-recording batch and approval files listed in `PROJECT_HANDOFF.md`):
no cardinal recordings or authoring approval artifact were packaged under
`scripts/assets`. The missing catalog is exactly EN31 + ES53 + FR161 + HE131 +
AR208 = 584 role recordings / 1,168 master-and-telephony WAVs, before any newly
versioned introductions. Telephone digits are not presumed reusable cardinal
recordings. The catalog still covers every integer 0..999999999.

`acdc_gemini_prompts:callback_defaults/5` already selects recorded digits and all
callback/auxiliary/returned-confirmation assets in the chosen locale. Its
callback inventory is exactly 42 per locale and must remain separate from the
cardinal map. By contrast, `acdc_announcements:position_prompts/3` still invokes
`acdc_language:number_prompts/2`: EN/FR/ES select SAY; AR/HE select scalar/scaled
`acdc-number-N` and `acdc-number-and` IDs not provided by this 210-asset pack.
Import alone therefore cannot finish position speech. The JS compositor has no
Erlang runtime integration yet.

## Finite source review and introductions

Review all exported role transcripts, then the complete boundary examples in
`acdc_prerecorded_cardinal_design.md`. Retain the existing catalog unless a
specific review finding requires a versioned correction before the first paid
request. These are the exact decisions, not an open-ended approval queue:

| Locale | Review and proposed introduction treatment |
| --- | --- |
| EN | Keep American no-and cardinal style; existing `Your current position is.` introduces the current numeric position. Check 101, 1001, scale joins and maximum. |
| ES | Keep masculine number-label forms, cien/ciento and pre-scale un/veintiún; existing `Su posición actual es.` is interpreted as the current position's numeric label, not a count of feminine positions. Review 21, 101, 21000, 101000000 and maximum. |
| FR | Keep France-French number labels; existing `Votre position actuelle est.` introduces the numeric label. Review all 20 contextual tails before each scale, H01 phrases, 71/80/81 and maximum. |
| HE | Retain feminine abstract labels and masculine scale coefficients. Prefer a new explicit-number introduction below; check all pointed joined forms, 120/121, 12000/21000, compound final-scale conjunctions and maximum. |
| AR | Retain masculine nominative abstract numbers and whole pausal chunks. Prefer a new explicit-number introduction below; check 11/12, singular/dual/plural scales, 101/102/201/202 before both scales, attached-wa forms and maximum. |

Proposed new canonical identity, distinguished by locale:
`acdc-cardinal-intro-v1-current-position-number`.

- HE: `מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.`
- AR: `رَقْمُ مَوْقِعِكَ الْحَالِي فِي طَابُورِ الِانْتِظَارِ هُوَ.`

Both mean the number of the caller's **current position in the queue**, not a
ticket number, an ordinal recording scheme or the number of callers ahead.
These are proposed release text, not existing WAVs. They add two initial
recordings if selected; preserve all old introductions. No new introduction is
needed merely to authorize EN/ES/FR authoring first; all five locales remain
required for release.

Primary sources re-read September 7:
[RAE cardinales](https://www.rae.es/dpd/cardinales) supports masculine numerical
labels, the selected apocope and number-label usage after feminine nouns.
[OQLF six/dix](https://vitrinelinguistique.oqlf.gouv.qc.ca/23137/la-prononciation/prononciation-des-nombres/prononciation-de-six-et-dix)
supports contextual final-consonant treatment.
[CET's original language-team lesson](https://www.lib.cet.ac.il/PAGES/item.asp?item=13674)
supports feminine abstract labels when “number” is explicit or insertable,
hundreds/thousands agreement and the vav vowel classes. The proposed HE wording
applies that rule; the source does not quote this queue sentence.
[Al Jazeera's grammar answer](https://learning.aljazeera.net/ar/node/590) and
its linked lesson support scale-complement agreement.
[The Virtual Academy's own decision](https://almajma3.blogspot.com/2018/04/blog-post_20.html)
supports large-to-small composition and repeated-scale addition. Extending its
additive construction to 101/102 scale groups is an explicit engineering
inference, not a quoted Academy example or native-speaker approval. The AR intro
uses a nominative numeric predicate; pausal chunk delivery must be preserved.

## Exact approval artifact and next authoring step

The protected JSON file accepted by `readApprovals` has exactly
`schema_version:1`, `catalog_sha256:pack.CATALOG_HASH`, `approvals:[five records]`
and `approvals_sha256:pack.digest(approvals)`. Each record comes from
`pack.pendingApproval(locale)` and binds locale catalog/context hashes. Set
transcript, delivery and intro to APPROVED only after recording the decisions
above in a review artifact and binding its evidence hash. The evidence may
honestly say source-backed engineering review; do not label it native listening.
The separate listening object remains
`{status:"PENDING",evidence_sha256:null,asset_set_sha256:null}` before listening.

Intro approval also requires `canonical_id`, exact `transcript`, its SHA-256 and
`wav_sha256`. Use the selected telephony WAV's hash, not a placeholder or a
master hash. The verifier currently validates this declaration but does not open
the introduction artifact: `intro_audio_verified:false` remains intentional.
For existing introductions, select the actual successful fixed/completion entry
and verify its bytes through the existing source tools. For the two proposed
new intros, the smallest follow-up is a separate two-identity authoring ledger
using the existing protected request/WAV conventions and the exact cardinal SoX
recipe; freeze those texts, generate/verify once, then bind their real hashes.
Do not expand the 584-role cardinal inventory or rewrite historical manifests.

The existing cardinal generator can then author selected approved locales with
explicit request limits and one/two workers, reserve every attempt before
transport, preserve QA successes, and resume only unfinished work. It requires
an explicit retry budget for FAILED attempts; REQUESTING remains indeterminate.
This is sufficient provider plumbing already; no runtime TTS service is needed.

Pure review commands for the root-controlled window (not executed in this audit):

```bash
node scripts/generate-acdc-gemini-cardinal-pack.cjs --plan
node scripts/generate-acdc-gemini-cardinal-pack.cjs --plan --locales he-il,ar-sa
```

The actual generation CLI and strict approval-file example are in the cardinal
design. Supply the independently reviewed approval-set hash; do not substitute
a synthetic test approval or a key in process arguments.

## Narrow source correction — root regression verified

Root September7 `f3037b/83a87f` passes all12 groups/177 checks with11 mock
requests,zero real provider calls/keys and actual SoX resampling. Evidence:
`/tmp/acdc-cardinal-generator-proof.bf2n5X`. Running the historical generator
through a private process module cache fails the new no-output assertion
(`6b22f7`, `/tmp/acdc-cardinal-generator-proof.ThBYPt`), without modifying source
or making provider requests. This verifies the narrow authoring fix only.

`generate()` previously created its fresh output directory before validating
approval. A rejected approval left no manifest; a fresh retry rejected the
directory and resume could not read a manifest. The candidate moves only fresh
approval/key-path checks before directory creation. Existing-pack resume still
validates under its lock; request budgeting, durable reservations, immutable
bytes, provider loading and approval requirements are unchanged.

`scripts/test-acdc-gemini-cardinal-pack.cjs` now asserts pending/wrong-hash/
wrong-context/key-location rejections leave no output and successfully reuses
that same untouched path after correction. Its prior 12-group/173-check proof
does not cover these new assertions; reproduce the current candidate with:

```bash
bash scripts/run-kazoo-validation.sh \
  --memory-mib 128 --reserve-mib 768 --runtime-sec 60 -- \
  /usr/bin/unshare --net /usr/bin/node \
  /opt/kz5/scripts/test-acdc-gemini-cardinal-pack.cjs
```

After authoring: technical verification, honest listening results, a separate
create-only cardinal importer/map and Erlang compositor/whole-playlist preflight
remain necessary. `install_acdc_language_packs` currently imports exactly 210;
keep that contract while adding a separately verified cardinal inventory.
For distributed playback, either use the existing verified shared system-media
route on every media node or add explicitly authorized immutable local-root
provisioning. Do not equate the experimental private resource classifier's
limitations with ordinary FreeSWITCH WAV support. Current native cancellation,
offer/confirmation playback, bridge safety and coherent deployment require the
actual normal-transport acceptance in `callback_native_vertical_slice.md`.
