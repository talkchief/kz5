# ACDC language packs (staged)

Canonical locales are `en-us`, `ar-sa`, `he-il`, `es-es`, and `fr-fr`.
The language dropdown must use the installer-verified capability artifact;
source files or a single media attachment do not establish runtime support.

This is staged implementation, not an enabled installer feature. The current
installer does **not** automatically import these new packs, publish their
capabilities, or activate the new backend mappings. The supplemental
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
```

`--only-fixed` produces a small preview and deliberately leaves Arabic/Hebrew
packs incomplete. Generation never imports media or publishes runtime readiness.
Every WAV is verified as non-silent, unclipped, mono 8-kHz PCM16, with a bounded
duration and SHA-256 digest. Existing unowned output recordings are not replaced.

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
