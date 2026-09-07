# Offline five-locale installer adapter

Current integration supersedes the original EN-only caller described below:
`install-kazoo5.sh` now selects all five locales using a fixed source index and
Spanish reuse pins. All584 source roles and five maps must pass before
`ensure_system_media_database` or fixed210 imports. Cardinal receipts stay
separate, include final intro revisions, and receive independent byte readback.
Runtime cache activation/check is a separate scoped584+2 operation; no provider
key, account changes or synthesis is used. Shell ordering/negative receipt
fixtures pass `debd38/b50cb1`; complete source/runtime validation is recorded
in the latest task register. Older sections retain their historical scope.

Root validation `d5431a/session11085/822a82` passed the retained13 EN cases
and all new five-locale adapter barriers/order/read-only verification cases in
an isolated network namespace. These use adapter doubles, not complete release
recordings, real CouchDB writes or live playback.

`scripts/install-acdc-cardinal-pack.cjs` now has an explicit all-locale mode:

```bash
node scripts/install-acdc-cardinal-pack.cjs --plan --all-locales
node scripts/install-acdc-cardinal-pack.cjs --import --all-locales
node scripts/install-acdc-cardinal-pack.cjs --verify-only --all-locales
```

These are prepared interfaces, not commands executed by this task. They accept
no operator-supplied original cardinal pack, map, intro or locale paths. The
explicit mixed-model extension below accepts pinned trial/alias inputs only.
Without `--all-locales`,
the original EN31 mode, source path, header bytes and final `VERIFY_ONLY` receipt
remain supported. The original adapter tranche did not alter the main-shell
caller; the current integration above replaces that EN-only dispatch.

## Fixed release inputs

Every locale uses the versioned checked-in ledger directory
`scripts/assets/acdc-gemini-cardinals-20260907` and the independently frozen
approval-set SHA-256
`452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5`.
EN/FR/ES intros remain in the fixed20260905 pack; HE/AR intros come from the
separately authored `acdc-gemini-cardinal-intros-20260907` pack. Identity,
transcript and telephony WAV hashes must match the committed importer pins.

| Locale | Required roles | Required reviewed map |
| --- | ---: | --- |
| en-us | 31 | `applications/acdc/src/acdc_cardinal_map.hrl` |
| he-il | 131 | `applications/acdc/src/cardinal_maps/acdc_cardinal_he-il.hrl` |
| fr-fr | 161 | `applications/acdc/src/cardinal_maps/acdc_cardinal_fr-fr.hrl` |
| es-es | 53 | `applications/acdc/src/cardinal_maps/acdc_cardinal_es-es.hrl` |
| ar-sa | 208 | `applications/acdc/src/cardinal_maps/acdc_cardinal_ar-sa.hrl` |

The four new fragments are required reviewed release artifacts. They are emitted
only from complete verified recordings, never fabricated from incomplete audio.
Each file must exactly equal its locale importer's `renderMap()` bytes. NonEN
fragments include the explicit intro asset tuple; EN keeps its original map and
the independently verified fixed intro. Secure map reads reject symlinks,
hardlinks, writable files/directories and observed changes. The EN limit remains
64KiB; nonEN files permit 256KiB, sufficient for the complete AR208 fragment.

## All-locale prerequisite and ordering

`installAll(mode, entries, client)` and `releasePlans()` provide dependency
injection for offline adapter tests. Production builds the five entries only
from the fixed paths above. Before constructing the database client, it requires
all five complete source plans, exact role sets, reviewed map bytes, intro pins,
locale/catalog/context hashes, the fixed approval pin and one shared original
ledger hash. In the original generated-only all-locale mode, the ledger must
declare artifact completeness after the underlying
full validator has checked every original attempt and recording. It cannot mix
locale snapshots from different ledgers, omit an unavailable locale or accept
technical/listening/runtime readiness substitutions.

All-locale `--plan` performs no database operation. For `--import`, every source
prerequisite passes before the first create. Source/map snapshots are rechecked
at each locale boundary, and all map files are rechecked immediately before
each PUT. Each lower importer retains its full source/WAV pinning, complete
locale inventory and create-only byte-verification contract. Existing EN/FR/ES
intros must already be installed by the fixed210 importer; new HE/AR intros may
be created by their scoped locale importers.

After the last locale's import, the adapter performs a separate fresh
verify-only pass over **all five** locales, then checks all source/map snapshots
again. The final-pass client rejects writes. Any incomplete count, changed
ledger/map/asset-set hash, wrong intro or false readiness claim in a verification
receipt fails the aggregate result. The aggregate count is584; its per-locale
receipts retain the individual intro verification facts. `--import` returns
`IMPORT_AND_VERIFY`; `--verify-only` returns `VERIFY_ONLY`. Both require584
verified roles. Plan output reports `database_verified:false`.

This is create-only staging, not an atomic database transaction. A later database
failure can leave earlier immutable creations installed; an explicit rerun
verifies and preserves those documents. The adapter never rolls them back,
overwrites them, retries an ambiguous write or continues to a missing language.
Source completeness before writes does not promise that every existing database
document or fixed-intro prerequisite will be acceptable. That is established by
the scoped database operations and final verification.

All output keeps runtime/full-position/five-language-release readiness and
listening verification false. Source authoring approval and correct stored WAV
bytes do not establish native listening or actual distributed playback. The
required range remains0..999999999 in every locale, one female prerecorded voice
per locale, with no runtime TTS, native SAY, digit substitute or language fallback.

## Explicit mixed-model candidate extension

The adapter additionally accepts this all-locale-only option group, with no
current trial-index hash compiled into code:

```text
--model-trial-index /absolute/trial-index.json
--model-trial-index-sha256 <independently-reviewed-index-byte-sha256>
```

The pair is mandatory together. If Spanish needs the reviewed ES4/ES9 sources,
also provide the existing importer's separate complete alias option group:

```text
--supplemental-pack /absolute/supplemental-pack
--alias-file /absolute/reviewed-aliases.json
--alias-sha256 <independently-reviewed-alias-byte-sha256>
```

The adapter rejects incomplete groups, unknown/duplicate options, malformed
hashes, noncanonical paths and resolution options without `--all-locales`.
Alias options require the trial-index opt-in in this adapter; they are never
an automatic language fallback. The importer validates the exact versioned
index schema, descendant-only ledger paths, every pinned trial receipt, source
history, true model/voice, WAV hashes and resampling. See
`doc/acdc_cardinal_model_trial_staging.md` for that unchanged contract.

Compatibility is deliberate: EN31 stays on its original generated-only
importer path, with no trial or alias options. This preserves the existing
content-addressed EN document identities and provenance and avoids prohibited
metadata backfill. HE/FR/ES/AR receive the same explicit trial-index pair; only
ES receives alias options. Original source, intro and reviewed map paths remain
fixed. `releasePlans(open, readHeader, resolution)` exposes this option routing
for offline tests, without adding arbitrary original-source or map overrides.

Mixed preflight still requires all five complete selected inventories and all
five exact reviewed map files before database construction or any create. EN
must supply all 31 generated identities with its original generated asset-set
hash. Each other locale must supply its exact complete resolved identity set,
matching transcript/catalog/context/recipe and true per-role model/voice, exact
resolved asset-set digest, source-kind counts, zero unresolved roles and false
listening/runtime claims. All five share one original manifest hash and the
same historical completion fact. The four indexed plans must share one exact
index hash and complete trial audit. NonSpanish aliases are refused.

The historical ledger may remain `artifact_complete:false`; no failed attempt
is promoted to a successful 2.5 generation. Here `source_complete:true` means
the complete selected 584-role staging resolution, not original generation
completion. Aggregate output explicitly adds `resolution_complete:true`,
`resolution_mode:indexed-model-trials-v1`, the original historical completion
fact, current index pin, generated/trial/reused counts and the additional trial
request count. That last count is taken once from the shared audit, not summed
four times. It remains separate from original request history.

The same before-write barriers, immutable/create-only per-locale imports and
final write-disabled five-locale readback apply. In mixed mode every original
source-summary field, including complete per-role provenance, must match the
final verification receipt, including EN's unchanged generated proof. Any
observed index/source/map drift stops subsequent work. Adding unrelated trial
results requires a fresh pinned invocation; the importer keeps the whole index
hash out of immutable selected per-role lineage, so an unchanged selected asset
set does not require metadata backfill or a new content-addressed document.

This extension does not create missing maps, approve native listening, change
main-shell dispatch or activate mixed-model runtime playback. In particular,
the existing runtime verifier's fixed-model admission is a separate unresolved
contract; successful mixed staging is not permission to broaden it globally.

## Verification status and next integration

The existing13 EN adapter cases remain. Prepared all-locale cases cover fixed
path selection, strict CLI parsing, complete584 ordering, fifth-locale failure
before writes, wrong/missing maps, incomplete/duplicate roles, context/approval/
intro/ledger mismatch, source drift before and between writes, per-PUT map drift,
ambiguous failure without continuation, false final receipts and read-only final
verification. Retained private file-reader specimens test map-size limits and
file alias/writability rejection. These are adapter doubles and reader specimens,
not actual release media/maps or native acceptance evidence.

The delegated source task ran no tests, providers, credentials, imports or
deployment. Root subsequently ran the offline validation recorded above.
Actual complete recordings, reviewed nonEN fragments, complete
runtime map/intro integration and coordinated main-shell/dispatcher admission
remain release work; the existing default EN path is intentionally retained
until those artifacts are available. All changes remain in `kz5`.

The subsequent mixed-model extension adds focused adapter doubles for explicit
index/alias parsing, ES-only alias routing, unchanged EN provenance on repeated
complete imports, full 584-role mixed ordering, unresolved/missing/incorrect
fifth-locale proof, index/audit/count/model/context drift, and exact final
provenance receipts. These are not real database idempotence or listening
evidence; the separate importer suite owns byte-level document tests. The
extension has not run tests in its delegated source task. Root's serialized
validation command is `node scripts/test-install-acdc-cardinal-pack.cjs`, with
`node scripts/test-acdc-cardinal-import.cjs` as the relevant lower-layer
regression suite. Actual all-five planning additionally requires complete
recordings and reviewed maps; a currently complete ES locale alone is not
sufficient.
