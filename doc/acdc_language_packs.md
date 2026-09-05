# ACDC language packs (staged)

Canonical locales are `en-us`, `ar-sa`, `he-il`, `es-es`, and `fr-fr`.
The language dropdown must use the installer-verified capability artifact;
source files or a single media attachment do not establish runtime support.

## Natural female-voice replacement checkpoint — 2026-09-05

Five Gemini/Sulafat callback-confirmation samples, their transcripts and hashes
are saved in [`scripts/assets/acdc-gemini-samples-20260905`](../scripts/assets/acdc-gemini-samples-20260905/README.md).
The larger fixed/completion packs are now present under
`scripts/assets/acdc-gemini-fixed-20260905` and
`scripts/assets/acdc-gemini-completion-20260905`: 145 fixed prompts (29 per
language), plus 20 Arabic/Hebrew telephone digits. All 165 immutable versioned
system-media documents were imported and their downloaded audio hashes verified.
The protected receipt is in `acdc-callback-controls-deploy.V4lihZ` on this host.

Import is **not default activation**. The running queue/callback defaults still
select legacy IDs; the immutable Gemini resolver and installer transition remain
in progress. Existing queue/account custom recordings must not be overwritten.
English, French and Spanish numeric playback is still native FreeSWITCH audio;
Arabic/Hebrew whole-number coverage and native-language listening review remain
incomplete. No full-language or production-readiness claim follows from these
files. No credential belongs in Git.

## Earlier eSpeak draft implementation (not the requested final voice set)

The applications installer now prepares the pinned speech dependencies and
imports the complete media packs, including when CouchDB is on a separate host.
It does **not** yet publish runtime capabilities or activate the new backend
mappings. The supplemental
`scripts/patches/acdc-language-runtime.patch` is deliberately separate from the
installer's main ACDC integration patch until full media verification is done.
Do not apply that supplemental patch to a running release before importing the
complete required assets; it also changes English wait-prompt identifiers.

Each locale contains 29 fixed queue/callback prompts, including a complete
position prefix, every wait-time bracket, offers for digits 0–9, alternate-number
confirmation, and returned-caller confirmation. Custom account media is preserved.

English, Spanish, and French numbers use their native FreeSWITCH say modules and
matching sound trees. Arabic has no native FreeSWITCH say module. Arabic and
Hebrew instead use 2,998 whole numeric chunks plus a conjunction. Base-1000
composition covers 0–999,999,999 without saying a large queue position as
unrelated individual digits. Telephone readback intentionally speaks every
digit, preserving leading zeros. Missing localized callback media fails closed.

## Reproduction and provenance

```sh
bash scripts/prepare-acdc-speech-engine.sh /usr/local/src/kazoo5-installer
node scripts/generate-acdc-language-prompts.cjs --dry-run
node scripts/generate-acdc-language-prompts.cjs \
  --output-dir /usr/local/src/kazoo5-installer/acdc-language-prompts \
  --espeak /usr/local/src/kazoo5-installer/espeak-ng-1.52.0/build/src/espeak-ng \
  --espeak-data /usr/local/src/kazoo5-installer/espeak-ng-1.52.0/build
node scripts/generate-acdc-language-prompts.cjs \
  --output-dir /usr/local/src/kazoo5-installer/acdc-language-prompts --verify-only
bash scripts/test-acdc-languages.sh
node scripts/test-acdc-language-catalog.cjs
node scripts/test-acdc-language-generator.cjs
node scripts/test-acdc-language-import.cjs
```

`--only-fixed` produces a small preview and deliberately leaves Arabic/Hebrew
packs incomplete. Generation never imports media or publishes runtime readiness.
Every WAV is verified as non-silent, unclipped, mono 8-kHz PCM16, with a bounded
duration and SHA-256 digest. Existing unowned output recordings are not replaced.

`scripts/import-acdc-language-packs.cjs --import --pack-dir ABSOLUTE` imports
only missing recordings into `system_media`; `--verify-only` makes no writes.
It inherits `KAZOO_COUCHDB_HOST`, `KAZOO_COUCHDB_PORT`, `KAZOO_COUCHDB_USER`, and
`KAZOO_COUCHDB_PASSWORD` from the installer's protected configuration. Do not put
credentials in command-line arguments. Standalone CouchDB needs no local
FreeSWITCH or web server for this media step.

Metadata and audio are written in one revision-conditional request, using
[CouchDB's document revision and attachment semantics](https://docs.couchdb.org/en/stable/api/document/common.html).
If another writer installs a recording first, it is preserved. Existing deleted,
conflicted, foreign-type, or malformed media fails verification rather than
being replaced. Installed-media proof hashes use the actual attachment digests,
not the generator's WAV hashes, so preserved custom audio is represented.
The media-only receipt is `acdc-language-media.json` in the installer state
directory. It always says `runtime_ready:false`; it is not the UI capability file.

Speech uses the formant synthesizer from [eSpeak NG 1.52.0](https://github.com/espeak-ng/espeak-ng/releases/tag/1.52.0),
pinned to `4870adfa25b1a32b4361592f1be8a40337c58d6c`, licensed GPL-3.0-or-later.
Its optional Sonic dependency is pinned by upstream CMake to
`fbf75c3d6d846bad3bb3d456cbc5d07d9fd8c104`. No neural model, paid service, or
noncommercial voice dataset is used. The build disables MBROLA. Fixed text and
Hebrew phoneme instructions are reviewable project source; output manifests
record the source revision, text, exact synthesis input, phonemes and WAV hashes.

## Hebrew limitation and readiness

The upstream Hebrew voice is labeled `testing`. Its numeric dictionary speaks
80 incorrectly, and some combining-mark sequences are spelled as English
character names. See the [upstream diacritic issue](https://github.com/espeak-ng/espeak-ng/issues/2132).
The staged Hebrew pack bypasses these paths using explicit fixed phonemes,
including distinct 30/80 and singular/dual thousand/million forms. Tests check
these distinctions, full numeric coverage, and absence of language switching.

These are synthetic drafts, **not native-speaker-approved recordings**. Audio
format, exact number decomposition, and phoneme tests do not replace native
listening. Hebrew must not be marked fully reviewed simply because files exist.
All generated manifests set `runtime_ready:false` and
`native_speaker_review:false`; installer/live acceptance and review are separate.

## Runtime capability contract

Only after complete media import/attachment verification, backend activation,
and required native say-module/sound-tree checks may the installer publish
`apps/acdc/language-capabilities.json`. Its `schema_version` is `1` and
`languages` is keyed by the canonical locale. Each entry contains `ready`,
`position`, `wait_time`, `callback`, `numbers` (`prerecorded` or
`native_say`), `number_range`, `required_prompt_ids`,
`numeric_prompt_count`, `source_catalog_sha256`, `installed_media_sha256`,
and `native_speaker_review`. The source and actual installed-media hashes are
separate because imports preserve existing custom recordings.

The 29 user-facing IDs come from `catalog(locale).prompts` entries with
`kind === 'fixed'`. The UI must exclude `acdc-number-*` from editable prompt
lists before applying pagination/size limits, then use the verified capability
artifact for numeric-pack completeness. Missing or invalid artifacts must not
advertise new languages as supported.

## Node-local media cache prerequisite (staged)

Direct CouchDB imports do not send Kazoo document-change events. After importing
media, the staged `acdc_language_maintenance` module provides SUP-callable
`refresh/0`, `refresh/1`, `verify/0` and `verify/1`. With no locale argument it
checks exactly 6,143 catalog documents; with an argument it accepts only an
exact canonical locale (29 documents for EN/ES/FR, 3,028 for AR/HE).

```sh
sup acdc_language_maintenance refresh es-es
sup acdc_language_maintenance verify es-es
# The no-argument forms check all five installed packs.
sup acdc_language_maintenance refresh
sup acdc_language_maintenance verify
bash scripts/test-acdc-language-cache.sh
```

These commands act only on the node addressed by SUP. The deployer must run and
verify them on **every advertised apps/ecallmgr node** before publishing a
cluster capability. The module is still in the supplemental runtime patch;
these commands are not automatically enabled by media import alone.

Refresh validates a complete direct keyed CouchDB inventory, exact media
identity/revision/type/language/prompt, deletion/conflict state, system-only
account fields and nonempty audio attachment metadata/digests. It invalidates
only those exact local document-cache keys and synchronously merges each locale
into the existing system prompt map. It never flushes the whole cache, removes
other locales, changes account mappings, broadcasts asynchronous readiness, or
writes a customer/system document. `verify` makes no cache updates.

The resolved path must equal the requested locale's exact encoded media ID;
English fallback, a missing map or any changed database sequence fails the
operation. A success receipt includes the actual node name, local-only scope,
document count and stable CouchDB update sequence. It deliberately retains
`runtime_ready:false`: attachment metadata and map resolution do not establish
audio intelligibility, native-speaker review, native say-module readiness,
backend activation or cluster-wide verification.
