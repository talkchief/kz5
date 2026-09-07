# Prepared cardinal-only mixed-model admission

This change prepares runtime verification without claiming deployment or
listening approval. The current integration includes all five maps, adds only
HE/AR cardinal introductions outside fixed210, and routes every supported queue
position through this verifier. EN map bytes remain unchanged. Main-shell
dispatch now requires complete all-five preflight; see the adapter document and
latest task register for deployment/validation evidence.

## Explicit rendered-row contract

Only a nonEN cardinal import plan with an explicitly pinned model-trial index
emits `cardinal-resolved-row-v1` rows. Each is an exact nine-tuple:

```text
{Locale, CanonicalId, PromptId, WavSha256, AttachmentMd5, ByteLength,
 TranscriptSha256, ExpectedModel, SourceKind}
```

The first seven fields retain their previous meaning. The locale header adds
`CARDINAL_<LOCALE>_ROW_SCHEMA` with the version string, and its `MAP_SHA256` is
SHA256 of the importer's exact JSON serialization of
`{schema_version:1,row_schema:'cardinal-resolved-row-v1',rows}`. Thus expected
model and source kind, row order and schema version are included in map
identity. The plan exposes the same `map_row_schema`.

EN, fixed210, generated-only and alias-only map bytes/hash definitions stay
unchanged. Introductions remain seven-tuples and keep the original 2.5 model
contract. No resolved asset-set hash is added to these rows and no cross-language
canonical JSON hashing is assumed.

## Narrow verification

`acdc_gemini_prompts:verified_asset/2` retains its seven-tuple, fixed2.5 contract.
The new `verified_cardinal_asset/2` accepts only nine-tuples with a nonempty
`acdc-cardinal-v1-` canonical ID in ES/FR/HE/AR. Its model/source-kind pairs are
explicitly restricted:

| Expected model | Source kind |
| --- | --- |
| `gemini-2.5-pro-preview-tts` | `generated_cardinal` |
| `gemini-2.5-pro-preview-tts` | `reused_supplemental_master` |
| `gemini-3.1-flash-tts-preview` | `separate_model_trial` |

Expected values come from the immutable compiled row, never from the database
or a configuration fallback. The real document's `source_voice` must match the
expected model, Google provider and Sulafat voice. Its version1 importer-owned
`source_cardinal_resolution` must match the same model/provider/voice/source kind,
transcript hash and telephony SHA. Duplicate metadata keys, missing provenance,
or altered immutable false listening/runtime/authentication facts reject.

Reused sources are further restricted to Spanish
`acdc-cardinal-v1-number-4` → `es-es/acdc-number-4` and
`acdc-cardinal-v1-number-9` → `es-es/acdc-number-9`. No other identity, language
or model/source pairing is admitted as an alias.

Both entrypoints share the same private ownership, document identity, revision,
deletion, type, content-length, voice, transcript and attachment metadata checks.
The private helper accepts an already-selected expected model; it is not a new
public global model allowlist. Runtime still checks metadata rather than
downloading/replaying WAV bytes; actual byte/resampling checks remain the
create-only importer's responsibility.

`acdc_cardinal_media:prepare_with/6` dispatches exact nine-tuples to the new
cardinal verifier and exact seven-tuples to the unchanged legacy verifier.
The selected locale must be nonempty and uniformly seven-field or nine-field
before any frame lookup or document read; a single role cannot drop its model
admission fields and fall back to legacy verification. Mixed schemas and other
tuple arities fail. Its independent complete role-set check still rejects
missing, extra and duplicate roles before playback, with no partial number or
language/native-speech fallback. Existing intro verification is untouched.

## Root validation

Serialized network-isolated root run `38195b/session91945/4482a3` passes:
23 importer groups /8,233 checks /648 actual SoX calls with stable source pins;
production and TEST compilation of the four current modules plus17 EUnit tests;
retained13 EN adapter cases and all five-locale/mixed adapter barriers.
Importer receipt: `/tmp/acdc-cardinal-import-proof.3bfOpf/receipt.json`.
Private BEAMs: `/tmp/kazoo-cardinal-media.VfZtdV`.
No provider, real database, deployment or runtime-readiness claim follows.

## Actual source map preparation

Root `f4048a/session79206/42fcd9` opens all three complete HE/FR/ES plans against
index `8be831344f48e8fb8f6ce8c30d890f36a031e7f2027efecb7ea59e5c7fed178e`,
validates all source/trial/WAV/SoX and intro pins, then creates the absent map
fragments with `apply_patch` and compares exact file bytes to fresh rendered maps.
No provider or database operation and no compiled include/activation is involved.

| Fragment under `applications/acdc/src/cardinal_maps/` | Roles | File SHA256 |
| --- | ---: | --- |
| `acdc_cardinal_he-il.hrl` |131| `3b63c24ca5df5f4f9248eed574b43e2b63b305e7989f96330d459697534bc95d` |
| `acdc_cardinal_fr-fr.hrl` |161| `35c5d97c302daf5ff757c949f2258b06a9590df91fcf87fa816e258bc01a76df` |
| `acdc_cardinal_es-es.hrl` |53| `95ddcfec8f911da84378c3a6590a99a89058e770abc507442d59693b725a50ce` |

All345 rows are versioned nine-tuples. HE uses92 original/39 trial recordings,
FR160/1 and ES25/26 plus the two reviewed aliases. Arabic's208-role map remains
absent until complete, so the all-five adapter must still refuse installation.
These source fragments do not make language readiness true by their existence.

Importer regressions check nine-field row correlation, schema/row hash binding,
changed-model hash divergence and unchanged EN/alias-only maps. Focused current
source EUnit tests in `scripts/erlang-tests/acdc_cardinal_media_tests.erl` cover
allowed model/source combinations, exact Spanish reuse identities, missing and
altered provenance, duplicate metadata/roles, unchanged seven-field admission,
and complete synthetic nine-field playlists for all four nonEN locales.

No tests were run by the delegated implementation; root ran these commands:

```text
node scripts/test-acdc-cardinal-import.cjs
bash scripts/test-acdc-cardinal-media.sh
node scripts/test-install-acdc-cardinal-pack.cjs
```

The historical reconstructed Gemini runtime test is not a substitute for the
current-source cardinal media suite. Actual locale maps, native listening,
full release validation and authorized runtime activation remain separate work.
