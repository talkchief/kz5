# Offline five-locale installer adapter

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
no operator-supplied pack, map, intro or locale paths. Without `--all-locales`,
the original EN31 mode, source path, header bytes and final `VERIFY_ONLY` receipt
remain unchanged. `install-kazoo5.sh` still invokes that original EN command and
checks count/verified31; this tranche does not alter its caller or activate the
all-locale branch.

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

The four new fragments are **required future reviewed release artifacts**. This
task does not create them or fabricate complete maps from incomplete recordings.
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
ledger hash. The ledger must declare artifact completeness after the underlying
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
