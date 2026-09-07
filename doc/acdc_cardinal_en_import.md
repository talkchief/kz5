# EN31 immutable cardinal staging

Root-verified checkpoint September7: offline importer passed10 groups/605 checks
with real SoX and no network (`0ae241/2ebcc3`). Actual local CouchDB import
`de5fda/eeb8e2` created31 immutable EN documents and verified all31 plus the
existing intro in74 scoped requests, with no queue configuration changes.
The separate generated header is now tracked as a source candidate. This does
not activate announcements or establish audible playback,
listening approval, callback readiness or five-language completion.

`scripts/import-acdc-gemini-cardinals.cjs` accepts exactly `en-us`. The original
584-entry cardinal manifest remains intact, including pending identities and
failed attempts in other locales. The existing210 fixed/callback assets,
importer, source map, receipts and recordings are not changed. Spanish reuse is
a separate verified resolution layer; this EN slice does not consume or rewrite
its aliases or historical requests.

## Local verification and import boundary

- `openPlan({cardinalDirectory, introFile, approvalSha256, locale})` runs the
  actual cardinal verifier against the complete original ledger, including its
  exact versioned SoX resampling replay. It requires all31 EN identities to be
  `QA_PASSED`, and independently pins the declared transcript, context, delivery
  and intro approval set. It does not call the all584 `verifyPack()` gate or
  manufacture an EN-only manifest.
- The intro must be the already-recorded “Your current position is.” Its exact
  transcript SHA is `14dc2fb6f6e5de230d62fed0f66e70626b64b2f23a7a31a052528d4f0ece880d`;
  its8kHz WAV SHA is `1fe37e0db985dab9765745fca6cc2e78d17026a992a6088dc92fa37ac7be2dd6`.
  This preserves the existing intro; it does not resample it again or infer
  native-speaker listening from a hash.
- All local sources are securely reread and pinned before database work. The
  selected master/telephony files, original manifest and intro are rechecked
  after import too. Files must be regular, single-link, non-symlinked and not
  group/world-writable. Returned summaries do not expose mutable audio buffers.
- `install(client, allowWrite)` reuses the existing create-only media writer.
  First it verifies the intro already exists with exact installed metadata and
  downloaded bytes, without writing it. Then it creates/verifies only31
  content-addressed cardinal documents and finally rechecks the intro. It never
  writes `_rev`, retries an ambiguous write, or overwrites a409 winner. Conflicts
  are explicitly requested and rejected. Every call is scoped to these32
  identities; at most128 database requests are admitted.
- Cardinal catalog/context/master/attempt/resampling/approval provenance stays
  in the separate plan/receipt. The reused media-document contract retains the
  canonical ID, transcript hash, WAV hash, model and voice; it does not newly
  store the complete authoring ledger in CouchDB. Import is not an atomic
  database snapshot: a failure can leave valid new immutable documents, which
  a later explicit rerun verifies rather than overwrites. A final readback does
  not prevent a subsequent external database edit.
- No provider key is accepted or accessed. `--plan` and `--emit-map` use no
  network. Import/verification access only the configured CouchDB through the
  existing child-environment credentials, never argv or printed credentials.
  No media file, manifest, account, queue, service or runtime state is written
  by a local plan/map operation. No source WAV is regenerated.

## Reproducible root-reviewed commands

Run the offline fixture in the serialized no-network resource guard (proposed
128MiB cap, unchanged768MiB reserve,90-second deadline):

```sh
node scripts/test-acdc-cardinal-import.cjs
```

It retains a private `/tmp/acdc-cardinal-import-proof.*/receipt.json`, fixture
files and failures. It uses real production validators and local SoX with
synthetic cardinal WAVs, the pinned existing intro, and a controlled CouchDB
double. Ten groups cover the original584 ledger, source/approval/locale
rejection, wrong resampling, missing intro, create/idempotence,409 conflict,
ownership/attachment/replica conflicts, ambiguous failures and final drift.
Actual network is forbidden; none of this is audible/native acceptance.

The current checked-in release can subsequently be planned without database
access using this exact approval pin (it must be reviewed again if changed):

```sh
node scripts/import-acdc-gemini-cardinals.cjs --plan --locale en-us \
  --cardinal-pack /opt/kz5/scripts/assets/acdc-gemini-cardinals-20260907 \
  --intro-file /opt/kz5/scripts/assets/acdc-gemini-fixed-20260905/en-us/acdc-queue-your-current-position-is.telephony-8000.wav \
  --approval-sha256 d5cd6e9713c30745ac06220c76a5996277b4766f6e1bfcc0620887c058e1e71e
```

Replace only `--plan` with `--emit-map` to emit the separate source header to
stdout, after the same real verification. Root can capture it in a protected
private output and promote it after review. No generated header has been
created by this source-only task. Replace the mode with `--import` or
`--verify-only` only in a separately authorized configured-CouchDB operation.
Other locales, `--all-locales`, unknown/duplicate options and missing pins fail
closed; EN success never admits an incomplete five-language release.

## Runtime identity handoff and remaining integration

The emitted `applications/acdc/src/acdc_cardinal_map.hrl` format is:

```erlang
%% Each member of CARDINAL_ASSETS has this seven-field layout:
{Locale, CanonicalId, VersionedPromptId, WavSha256, Md5Digest, ByteLength, TranscriptSha256}
```

The header defines `CARDINAL_ASSETS`, `CARDINAL_MAP_SHA256`,
`CARDINAL_CATALOG_SHA256`, `CARDINAL_EN_CATALOG_SHA256`,
`CARDINAL_EN_CONTEXT_SHA256` and `CARDINAL_EN_INTRO`. The intro macro is exactly
`{CanonicalId, TranscriptSha256, WavSha256}`. Rows are sorted by document ID and
the map hash is SHA256 over `JSON.stringify(rows)`, matching the existing map
convention. The separate header deliberately does not define `GEMINI_ASSETS`.

The independently authored pure `acdc_cardinal_prompts:roles/2` returns the
canonical `acdc-cardinal-v1-number-N`, `-hundred`, `-thousand`, `-million` IDs.
The later runtime resolver must join those exact IDs against this31-row map,
verify installed metadata and emit exact `/system_media/en-us/<versioned-id>`
PLAY paths. The existing210 helper supplies the pinned intro. Missing clips
must not authorize SAY/TTS, digit spelling or another language.

Root's next installer slice must invoke separate EN31 plan/import/final
verification and retain a separate receipt, preserving the existing210 path.
The announcement resolver, custom-media-preserving selection logic, production
build/deployment and actual hold/bridge/callback playback checks are not part
of this importer. All receipts retain `runtime_ready:false`,
`full_position_language_ready:false` and `five_language_release_ready:false`.
