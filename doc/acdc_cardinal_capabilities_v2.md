# Prerecorded cardinal capability contract v2

Source implementation only. This change publishes no capability artifact,
performs no deployment, and establishes no listening approval. Schema1 and its
explicit all-false `backend_mode: "legacy"` contract remain supported unchanged.
The negative initializer still preserves valid existing artifacts byte-for-byte
and creates only the old all-false fallback when none exists.

## Exact source contract

The root has exactly `schema_version: 2`,
`backend_mode: "prerecorded-cardinal-v1"`, UTC `generated_at`, and `languages`.
The language object has exactly EN/en-us, HE/he-il, FR/fr-fr, ES/es-es and AR/ar-sa.
Every locale entry has the following required fields; unknown fields reject.

| Fields | Meaning |
| --- | --- |
| `numbers` | Exactly `prerecorded-cardinal`; never native SAY or the obsolete2999-chunk model. |
| `number_range` | Exactly `[0, 999999999]`; queue positions themselves must be positive. |
| `numeric_prompt_count` | Required role inventory: EN31, HE131, FR161, ES53, AR208, total584. A count alone proves nothing installed. |
| `callback_prompt_count` | Exactly42 per locale: immutable32 fixed prompts plus ten prerecorded telephone digits. |
| `position_installed_verified` | Complete locale cardinal inventory **and exact approved intro** have byte-verified installed documents. |
| `callback_installed_verified` | All42 immutable fixed/callback-digit documents have byte-verified installed audio. This inventory includes wait-time phrases. |
| `position_runtime_verified`, `callback_runtime_verified`, `wait_time_runtime_verified` | Separate deployed-function evidence, not authoring or importer success. |
| `source_catalog_sha256`, `cardinal_map_sha256`, `fixed_map_sha256` | Exact source catalog, selected locale rendered cardinal map, and immutable fixed210 map pins. Backend compares these against compiled headers, including EN's unchanged generated-only map. |
| `installed_media_sha256` | Nullable SHA256 reference to retained installed-byte verification evidence for this locale and its maps/intros. Required when either installed flag is true. |
| `runtime_evidence_sha256` | Nullable SHA256 reference to retained deployment/runtime evidence. Required when any runtime flag is true. |
| `native_speaker_review`, `native_review_sha256` | Review boolean and nullable real listening-evidence hash. True requires a hash; false requires null. Automated QA, transcripts and generated audio do not supply this evidence. |
| `position`, `callback`, `wait_time` | Derived installed-and-runtime availability booleans. Wait-time uses `callback_installed_verified` because its phrases are part of that fixed inventory. |
| `selection_ready` | Exactly `position && callback && wait_time`. Permits selecting a deployed, verified locale for development voice testing without claiming native review. |
| `ready` | Exactly `selection_ready && native_speaker_review`. Separate fuller language-readiness fact, not inferred from the dropdown being selectable. |

All state fields are strict booleans. All hashes are lowercase64-character
SHA256 strings, except the three evidence references explicitly allowing null.
Evidence hashes may remain after a runtime availability downgrade; they retain
historical evidence identity and do not override the false state.

The new contract permits source-only, installed-only, partially deployed,
runtime-testable and listening-reviewed states. Source/installation alone never
enables selection. Publisher code must not set runtime flags based only on
generated audio, importer receipts or metadata reads. This structural contract
does not authenticate arbitrary evidence hashes: the future protected publisher
must validate the referenced artifacts, their locale/map scope and actual
outcomes before declaring facts.

## Backend and UI behavior

`cb_acdc_queue_editor:verified_cardinal_media/1` selects only locales declaring
at least one runtime-verified function. Source-only/installed-only locales cause
no media database reads. For selected locales it fetches the exact owned IDs
through one `kz_datamgr:open_docs/2` invocation, using Kazoo's existing bounded
bulk-read datapath (`_all_docs` with keys/include_docs and configured chunking).
This is not one synchronous request per recording. Maximum scope is796 distinct
documents:584 cardinal roles +210 fixed/digit recordings +two new HE/AR intros.
The three other intros already belong to fixed210. A single AR locale requires
251 documents; EN requires73.

Every selected cardinal document is checked against its actual compiled seven-
or nine-field row and existing immutable ownership/revision/attachment/model/
source-kind verifier. The exact intro and fixed42 projections are also checked.
Missing or mismatched metadata only downgrades that locale's corresponding
runtime/availability/selection/readiness flags; it never upgrades declared
installation or native-listening facts. Database errors or malformed batch
correlation fail closed. Cardinal chunks are not returned as selectable hold
music: only verified fixed/callback projections are included in `system_media`.

The UI validates the versioned shape, checks every one of the selected locale's
42 fixed projections, rejects missing/duplicate/malformed projections, and uses
`selection_ready` for admission. An unreviewed selectable locale is labeled
**Available for voice testing**, followed by the existing native-review-pending
notice, not **Ready**. The older internal option field `ready` still means
selectability to existing form logic; it is not the manifest's full `ready` fact.
Backend selection validation uses the same v2 selection gate and exact fixed
media projections. V1 admission and labels remain unchanged.

The bulk read is still synchronous, and when all five locales claim deployed
runtime it rechecks all796 documents on each editor request. This slice reduces
neither Kazoo's configured chunk latency nor repeated request work through a new
cache; evidence-bound cache invalidation/TTL is a separate optimization. No
metadata check here hashes audio, interrogates live resolver caches or proves
audible quality. Those remain publisher/runtime acceptance obligations.

## Publication and path boundary

No publisher is included. The intended publisher runs only after separate full
source/import/map verification and actual deployed-function acceptance. It must
retain exact provenance for source maps, immutable document revisions/audio,
running code and media-map checks. Native review stays false/null until genuine
listening evidence exists. Staging receipts and individual media documents keep
their existing false readiness fields; do not backfill EN or relabel3.1 audio.

Existing path policy is intentionally unchanged: explicit
`acdc.queues.editor_language_capabilities_path` wins; otherwise a present legacy
web artifact is protected-read first, even if corrupt/unreadable, and only its
absence permits the service-configured apps path. A publisher must deliberately
configure the desired authoritative path or publish consistent protected web
and apps artifacts. It must not bypass or overwrite an operator artifact merely
because an alternative path looks newer. UI build/deploy must continue to
preserve runtime capability files instead of manufacturing them.

OpenAPI source is `scripts/api-docs-queue-editor.cjs`:
`QueueEditorLanguageCapabilities` now references preservedV1 and explicitV2
schemas. Generated `scripts/assets/api-docs/openapi.json` and live `/apis` are
not regenerated/published by this change. Regenerate and validate those only
against the matching backend; `scripts/test-api-docs.cjs` now expects the union.
Cross-field truth rules and real evidence verification remain application rules,
not an assertion that an OpenAPI-shaped artifact is trustworthy.

## Root-serialized validation

- `node scripts/test-acdc-cardinal-capabilities.cjs`: real Node validator and UI
  source with synthetic evidence and actual fixed210 projections; stage/type/
  count/hash/unknown-field, per-locale partial runtime, missing/duplicate media,
  testable-versus-reviewed labels and legacy fallback checks.
- `bash scripts/test-acdc-queue-editor.sh`: adds focused cardinal capability
  EUnit using actual compiled map rows with synthetic documents/evidence;
  locale-scoped bulk reads, no source-only reads, mixed models, missing intro,
  missing digit/cardinals, independent downgrades and legacy/path regressions.
- `node scripts/test-acdc-language-capability-state.cjs`: initializer remains
  negative-only and preserves existing v1/v2 bytes without mutations.
- Existing UI/editor browser, filesystem and installer portability suites remain
  separate regression gates. No tests were executed by the implementing agent.

All synthetic fixtures under `scripts/test-fixtures` and `scripts/erlang-tests`
are test data, never publishable review/runtime evidence.
