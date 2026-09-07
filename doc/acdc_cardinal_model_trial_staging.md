# Mixed-model cardinal candidate staging

`scripts/import-acdc-gemini-cardinals.cjs` can stage a complete selected locale
using original QA-passed Gemini 2.5 recordings, explicitly verified Gemini 3.1
trial candidates, and reviewed ES4/ES9 whole-word aliases. This is candidate
staging only: it neither approves listening nor enables runtime composition,
queue configuration, installer maps, or five-language release readiness.

## Explicit index contract

Both new options are required together:

```
--model-trial-index /absolute/path/index.json
--model-trial-index-sha256 <independently-reviewed-exact-index-byte-sha256>
```

The programmatic option names are `modelTrialIndex` and
`modelTrialIndexSha256`. Existing cardinal directory, selected locale, exact
intro and independent approval pins remain mandatory. ES whole-word aliases
still require their separate all-or-none pinned alias options.

The exact index schema is:

```json
{
  "schema_version": 1,
  "owner": "kazoo5-acdc-cardinal-model-trial-index",
  "source_manifest_sha256": "<original cardinal manifest SHA256>",
  "catalog_sha256": "<cardinal catalog SHA256>",
  "approvals_sha256": "<independently approved approval-set SHA256>",
  "trials": [
    {"directory": "format-compatible", "sha256": "<exact trial.json SHA256>"}
  ],
  "runtime_ready": false,
  "native_listening_approved": false
}
```

The index is bounded to 32 KiB and 1–64 distinct trial directories/ledger
hashes. Directory paths resolve beneath the index parent: only nonempty safe
path components are accepted, never absolute paths, `.`/`..`, aliases through
symlinks, or duplicate directories/hashes. Index fields are exact; unrecognized
fields or readiness claims reject. The existing read-only trial verifier
independently checks every listed terminal ledger, source history/body pins,
model/voice/format, actual WAV metrics and deterministic SoX replay. Include
failed receipts to preserve complete known trial request accounting; a caller's
index does not establish that no unlisted historical request ever occurred.

## Resolution and immutable provenance

For each selected catalog role, precedence is original QA-passed audio, then a
verified 3.1 successful candidate, then an explicitly reviewed whole-word alias.
No unresolved role may reach database access. Nothing edits the original
manifest, failed attempts, trial receipts, audio, or fixed210 importer. Omitting
trial options preserves the generated-only and alias-only contracts.

Every trial-backed media document persists its real
`source_voice.model = gemini-3.1-flash-tts-preview`, provider `google-gemini`,
and voice `Sulafat`. Its full verified trial provenance, including the selected
trial ledger/entry, original source entry/attempts, request body, catalog/context,
audio hashes and recipe pins, is retained in `source_cardinal_resolution`.
Optional narrow diagnostic provenance supplied by the verifier is retained as
well; the importer itself grants no model-generation exception.

The whole original manifest and whole index byte hashes are operation/audit
pins, not added to immutable per-role resolution or its resolved asset-set
digest. Selected trial ledger and entry hashes remain immutable. Expanding an
index with unrelated HE/AR results therefore requires a fresh plan but preserves
the unchanged selected ES asset-set and zero-write reinstall. Selected lineage
or audio drift is not backfilled and conflicting content-addressed documents
are never overwritten or revision-retried.

On every real database read, conflict readback and final readback, the importer
first checks full exact resolution metadata and the actual expected 3.1
model/voice/provider. Only then does it pass a private copy with the legacy
model field normalized to the unchanged shared attachment verifier. This local
compatibility view is neither persisted nor applied to the actual database
response; it cannot admit a document falsely labeled as 2.5.

The summary distinguishes original generated, reused and model-trial counts,
and reports additional trial requests separately from original request history.
The historical generated asset-set hash remains null when that original locale
contains failed entries. The resolved asset-set is a candidate review target,
not a listening approval. Runtime, native listening and full-release readiness
remain false; an emitted map is not runtime activation.

## Validation boundary

Focused importer tests use copied committed ES13/HE30 trial recordings with
explicitly repinned synthetic source/index fixtures and the real read-only
trial/WAV verifier. They cover all-or-none index options, safe paths and pins,
complete mixed resolution, truthful stored model metadata, model/provenance
tampering and 409 refusal, idempotence, and unrelated-index-growth stability.
Serialized offline importer validation passes23 groups/8,016 checks with636
actual SoX operations (`0e8e14/session51915/d9c298`). Source hashes remain
unchanged; no provider or real database requests occur. Receipt:
`/tmp/acdc-cardinal-import-proof.r3ESe8/receipt.json`. Actual complete-locale
read-only plans are checked separately; fixture success is not deployment.

Actual complete-locale plan validation `cd6452/session49491/f2a5bf` passes:

- ES53:25 original,26 model-trial,2 reviewed aliases,0 unresolved; resolved
  asset-set `999e2763e2dd5b5a17b3440b9327ae1cf105b08960d8d1e349ae604da4157055`.
- FR161:160 original,1 model-trial,0 aliases,0 unresolved; resolved asset-set
  `ab2a919fa0a21e33f29f78eb42cf18f3453f063e7b46300e526f010d4424c04a`.

Both use model-trial index SHA256
`fbd37afd26c9211ae05b5a9c1b65d29e10874693c327f99ad0e58dbf4523ca33`.
All source/trial/audio pins and native SoX proofs passed. Provider and database
requests were zero; staged-candidate/runtime/listening flags remain unchanged.
These hashes are candidate listening-review targets, not approval records.
