# Exact-word reuse in cardinal staging

The separate `scripts/import-acdc-gemini-cardinals.cjs` importer accepts an
explicit, all-or-none set of options in addition to its existing single-locale
source and authoring-approval pins:

```
--supplemental-pack /absolute/supplemental-directory
--alias-file /absolute/alias-manifest.json
--alias-sha256 <independently-reviewed-sha256-of-exact-alias-file-bytes>
```

The `openPlan` equivalents are `supplementalDirectory`, `aliasFile`, and
`aliasSha256`. Supplying no alias options preserves the generated-only plan,
asset-set hash, maps, documents, and create-only behavior. Missing, malformed,
duplicate, or unpinned alias options fail closed. There is no automatic fallback
from failed generation to supplemental audio.

The opted-in path uses `acdc-cardinal-reuse.cjs` unchanged. Its reviewed ES4/ES9
whole-word source and failed-history pins remain mandatory. Every role of the
selected locale must resolve before any database access; completeness of other
locales is not required. Generated roles still require real QA-passed attempts.
Reused roles use the exact pinned 24 kHz supplemental master and the existing
deterministic 8 kHz resampling recipe, never an invented successful attempt or
an unverified old telephone file. All input ledgers and audio files remain
read-only. The fixed210 importer and its intro ownership remain unchanged.

## Immutable resolution records

Opted-in cardinal documents retain their existing content-addressed media IDs
and exact attachment checks. A new `source_cardinal_resolution` field records
the source kind, selected entry or failed-history digest, alias/review/source
pins where applicable, transcript/context/catalog pins, model and voice,
master/telephony/PCM hashes, duration, resampling recipe, and resolved asset-set
digest. It explicitly records listening, provider authentication, and runtime
readiness as unverified/false. Reused `source_voice.source_file` identifies the
actual source master; resolution hashes distinguish that master from the
derived telephony attachment.

The versioned `cardinal-resolved-assets-v1` asset-set digest is `pack.digest` of
`{schema_version:1, kind:'cardinal-resolved-assets-v1', locale, intro, prompts}`,
where `intro` is the selected release-pinned intro definition and `prompts` is
the ID-sorted list of `{id, resolution}` records exposed by the plan. Resolution
does not contain the asset-set digest itself. The persisted document adds
`resolved_asset_set_sha256` afterward, avoiding a circular hash definition.

Whole cardinal manifest bytes are pinned for each plan/install operation and
remain in the audit summary, but are excluded from immutable per-role lineage
and the resolved asset-set digest. Thus legitimate unrelated-locale progress
requires opening a fresh plan but does not change selected ES media identities
or prevent a zero-write reinstall. Selected entry/failed history, alias,
supplemental source, content, context, or recipe drift remains detectable.

Every existing/create/conflict/final-readback document must match the full
expected resolution metadata as well as the original media/attachment checks.
Missing provenance is not backfilled and a conflicting document is never
overwritten or revision-retried. In particular, selecting alias mode over an
older generated-only installation with the same media IDs fails closed when
those documents lack this provenance; this path does not migrate old records.

## Gates that remain closed

The historical `pack.assetSetHash` is still null for a locale with failed
authoring entries. The opted-in summary reports it separately as
`historical_generated_asset_set_sha256`; its `selected_asset_set_sha256` and
`resolved_asset_set_sha256` describe resolved assets, explicitly labeled by
`asset_set_kind`. It reports selected generated/reused/unresolved counts without
changing historical requests or `artifact_complete`.

Existing independent transcript, delivery/context, and intro authoring
approvals remain required. Resolution is not native listening approval, and
the importer does not accept a resolved hash as a generated-ledger listening
approval. `resolved_listening_approval_declared` remains false. Any future
listening gate must explicitly bind the resolved asset-set digest and review
the actual generated and reused playback; no listening approval mechanism is
added here. Staging or emitting an Erlang map does not enable runtime role
mapping/composition or claim full-language/five-language readiness.

Regression additions cover complete ES51+2 staging, unchanged failed histories,
all-or-none CLI pins, unresolved roles, forbidden listening claims, source
mutation, exact provenance/readback/409 refusal, zero-write idempotence, and
unrelated-locale progress versus selected-lineage drift. Serialized network-isolated
validation passed 19 groups / 5,962 checks with 306 actual SoX operations and
unchanged source hashes (`2a22ae/session39592/4ae12e`). Receipt directory:
`/tmp/acdc-cardinal-import-proof.5sW1Ti`. No provider or real database was contacted.
The installer adapter also passed its 13 cases and five-locale ordering/barrier
checks (`348d67`). Actual artifact resolution remains 412 generated + 2 reused
roles, with 170 unresolved: this is not a complete ES or five-language deployment.
