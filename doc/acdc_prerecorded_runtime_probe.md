# DEV prerecorded runtime-function proof

The new probe is a **source-only, unexecuted implementation** until the root
operator runs the guarded tests and deployed-node probe. It proves function
testability, not audible SIP delivery, listening quality, or production approval.
The separate publisher can produce v2 `selection_ready: true`; `ready`, native
review, and live-SIP verification stay false. No existing capability file is
changed by building, importing, or probing audio.

## Inputs and bounded scope

`scripts/probe-acdc-prerecorded-runtime.cjs` accepts these explicit options:

```
--node kazoo_apps@EXACT_HOST
--account EXPLICIT_EXISTING_32_LOWERCASE_HEX_ACCOUNT
--cardinal-receipt /absolute/all-five-verified.json
--cardinal-receipt-sha256 SHA256
--fixed-receipt /absolute/fixed210-verified.json
--fixed-receipt-sha256 SHA256
--beam-manifest /absolute/production-beams.json
--beam-manifest-sha256 SHA256
--fixed-map /absolute/acdc_gemini_map.hrl
--fixed-map-sha256 SHA256
--fixed-pack /absolute/fixed-pack
--completion-pack /absolute/completion-pack
--supplemental-pack /absolute/supplemental-pack
--model-trial-index /absolute/index.json
--model-trial-index-sha256 SHA256
--alias-file /absolute/reviewed-alias.json
--alias-sha256 SHA256
--output /absolute/new-runtime-receipt.json
```

The mixed-index/alias options retain the existing all-five installer's exact
all-or-none validation; no current index hash is embedded in this helper.
The explicit caller-supplied account must be exactly 32 lowercase hexadecimal
characters, already exist, be active and undeleted;
there is no account discovery, queue creation, or config lookup. Even
`kapps_config:get/4` can save a missing category, so this probe does not use it.
Existing account overrides are respected by runtime preparation; if they replace
the expected built-in PLAY paths, the built-in proof fails without modifying them.
This is default-function testability **under that explicit account**, not a claim
that every account's custom overrides work. There is no tenant allowlist or DEV
account constant in production. Main-SH may pass its configured account after
normal bootstrap; this helper never bootstraps or discovers one.

The protected BEAM manifest has only `schema_version: 1` and `modules`, with each
entry containing exactly `module`, absolute `path`, and `sha256`. Required modules:

```
acdc_announcements acdc_callback_caller acdc_cardinal_media
acdc_cardinal_prompts acdc_gemini_prompts acdc_language acdc_wait_time_media
cb_acdc_queue_editor cf_acdc_member kz_media_map media_map
```

Use the **actual production build outputs** for the proposed deployment, then
pass their exact deployed paths. The helper does not assert that an arbitrary
operator-supplied build is correct. Root must bind this manifest to its reviewed
source/build/installation receipt. Files and all ancestors must be root-owned,
non-writable by group/other, and nonsymlink paths. On-node `code:which/1` must equal
each exact path; file SHA256, `beam_lib:md5/1`, and loaded `module_info(md5)` must
agree. TEST defines are rejected. There is no loading or reloading code.

## Actual checks

The existing source resolvers independently verify all source audio and receipt
lineage before any SUP request. A root-owned, service-group-readable sidecar
contains the resulting bounded input (at most 8 MiB); only its exact path and
SHA256 are inserted into the small Erlang script. No large literal AST, keys,
cookies, endpoints, or audio bytes are placed in the RPC command.
Both sidecar and BEAM reads reject nonregular, linked, non-root-owned or writable
files and unprotected direct parents before opening. The sidecar additionally
requires its exact 0640 file / 0750 parent mode and matching group. File size is
validated before allocation; descriptor `pread` requests at most the approved
size plus one byte (maximum 8 MiB + 1), then descriptor/path/parent identities and
SHA256 are rechecked before JSON decoding or BEAM parsing. Growth, replacement,
truncation and wrong pins fail closed. This reuses the mapping helper's bounded
descriptor pattern, not an unbounded `read_file` followed by a size check.

The production template checks before and after native function execution:

- 796 distinct owned document revisions and exact metadata: 584 cardinal assets,
  210 fixed callback/wait assets, and two additional HE/AR introductions.
- 1,592 exact entries in both `media_map` and `kz_media_map`, with stable registered
  PIDs and ETS owners. Direct ETS reads never invoke a lazy mapping repair.
- All eleven loaded production modules and the explicit active account document.

Media metadata uses two bulk `open_docs` passes, rather than 796 individual
network requests. Existing runtime prepare functions perform their normal cached
metadata/account checks once per preparation. This deployment probe is not run
on each queue-editor request. Attachment bytes are bound by exact current CouchDB
revisions and immutable receipt hashes; it does not download or listen to audio.

For each of five locales it executes the real production APIs:

- `acdc_cardinal_media:prepare/3`: exact counts 31/131/161/53/208 and every
  content-addressed path, exact intro and empty suffix, then `playlist/3` for 19
  fixed numbers (95 playlists). The number matrix includes French 89, compound
  scale boundaries, and 999999999; this is not an exhaustive grammar proof.
- `acdc_gemini_prompts:callback/5`: both menu modes, entry key 6, full built-in
  42-asset preflight, six media fields, three auxiliary paths and all ten digit
  paths. Ten readbacks of `00123456789` retain leading zeros; no callback is sent.
- `acdc_wait_time_media:prepare/3`: ten exact stock paths and `playlist/4` across
  16 threshold cases per locale. The receipt's 80 wait cases each check unknown
  prior sample, equal prior sample, and increased estimate (240 playlist calls),
  plus invalid-stat preservation. This is the helper the real wait-time branch
  now uses; no AMQP statistics request or announcement worker is started.

The script checks a 150-second monotonic budget at operation boundaries; SUP and
its local wrapper have separate timeouts. This is **not a proven hard end-to-end
deadline** for every datastore call. A timeout, unexpected output, changed source,
wrong model/path/metadata, absent mapping, or custom frame produces no successful
receipt and no publication. Errors use fixed sanitized categories.

The receipt binds actual input/inventory/script/build/media receipt hashes and
the measured completion response. `installed_media_sha256` is the SHA256 of the
explicit two-receipt hash bundle, not an invented evidence value. The receipt is
create-only, fsynced and root-private. Source and pinned input prerequisites are
revalidated before and after RPC. Normal read caches may be populated; there are
no requested DB/config/map writes, queue changes, calls, provider requests, or
service restarts. No receipt can establish exactly-once or audible mobile/SIP
behavior.

## Separate explicit publication

```
node scripts/publish-acdc-prerecorded-capabilities.cjs \
  --account EXPLICIT_EXISTING_32_LOWERCASE_HEX_ACCOUNT \
  --receipt /absolute/runtime-receipt.json --receipt-sha256 SHA256 \
  --output /explicit/protected/language-capabilities.json \
  --previous-sha256 SHA256_OR_absent
```

The publisher requires that the explicit account exactly match the receipt's
account, a complete receipt no older than five minutes, and repins the
production files locally, validates v2 output, and preserves native review as
false/null. It never synthesizes a listening approval. The exact receipt byte
hash becomes `runtime_evidence_sha256`. The previous artifact must be valid and
match the explicit hash; existing native-reviewed artifacts need a separate
reviewed migration and are refused. Replacements retain a create-only `.before-`
hash backup, use an exclusive publisher lock, stage/fsync privately, then rename
atomically; absent targets use exclusive linking. Publication changes only the
explicit output and its protected lock/backup. It does not choose web/config
precedence, copy UI artifacts, regenerate `/apis`, or restart services.

Root must serialize publication with deployment and other capability writers.
The lock coordinates this helper's writers; it is not an OS compare-and-swap
against arbitrary noncooperating root processes. The local file recheck cannot
detect an intervening in-memory hot reload after the probe. A root deployment
window and fresh backend verification remain required. A failure after rename
is reported as unconfirmed, not as a guarantee of rollback.

## Guarded validation / handoff

Run `bash scripts/test-probe-acdc-prerecorded-runtime.sh` only in the root's
serialized offline guard. Tests exercise synthetic receipt tampering, strict
inventory/readiness/age/type boundaries, protected pin reads, symlink/hardlink
refusal, create-only output and pinned replacement/backup behavior. Node exits
before the actual Erlang parser checks the production template and evaluates
only its three pure bounded-reader closures. The real reader is exercised for
successful bounded reads and oversize, bad hash, empty/nonregular, symlink,
hardlink, writable-file, wrong sidecar mode and writable-parent refusals. These
fixtures do **not** execute native functions or manufacture deployed proof.
An additional regression calls the real `buildInput` body with explicit source
loader doubles, the actual fixed210 header, and the real fixed document adapter,
document constructor and receipt validator. It checks all 210 projected records
and rejects changed receipt/map pins. Fixed-map parsing is local, seven-field
literal-only, and does not depend on an unexported cardinal helper API.

Then root must review/build/install the real modules, verify all source/import
receipts and both mapping activations, construct the reviewed BEAM manifest,
execute this read-only DEV probe, and publish its actual successful receipt.
Main-SH integration is a separate root-owned change. Live queue/callback call
tests and native listening remain separate, explicitly uncompleted gates.
