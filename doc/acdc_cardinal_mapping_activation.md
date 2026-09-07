# Cardinal map activation and read-only verification

Targeted cache activation is verified below. Audible acceptance remains separate.

Actual development activation and separate read-only check now pass
`f7bee8/session67837/e30111`. The fixed helper verifies210 documents/420 maps;
the cardinal helper verifies586 documents/1172 maps, adds1172 missing owned
paths during activation, then reports zero missing in independent check mode.
Expected cardinal inventory SHA256
`6cc0b5cd9912f7ef2ce228ac8b98b70eab2223f72ac974440786e0faa4f516b0`.
No database/account/queue write or language-capability publication occurred.
This is live cache evidence, not coherent playback-code deployment or listening.
The prior sourced driver `31175c/9bac13` failed before mapping calls because it
omitted `KAZOO_NODE_NAME_TYPE`; setting the verified local `-sname` corrected
that invocation. Applications remained running throughout.

The bounded-sidecar implementation passes root run
`72fdba/session53601/8501c9` under the unchanged384MiB guard. All seven Node
groups and the separate actual Erlang template pass, covering586 documents,
1172 mappings, read-only check, idempotence, custom preservation, metadata and
revision races, and sidecar hash/permission/size/link refusals before reads.
Source input SHA256
`3f7d5521ac4fc1ba5338a0b4cf69420a37de9298ac6c7b3d27b8b9a9cb3efe1e`;
private artifacts `/tmp/kazoo-cardinal-map-validation.JbbLrw`. Both earlier OOM
runs remain failed historical attempts; this passing run preserves their scope.

`scripts/refresh-acdc-cardinal-mappings.cjs` is separate from the existing210
fixed/callback mapping helper. It accepts exactly the all-five release plans
from `install-acdc-cardinal-pack.cjs` and runs its real `preflightAll` gate.
Incomplete original/generated or explicitly indexed mixed inventories cannot
be silently substituted for a complete selection.

The protected all-five `VERIFY_ONLY` or `IMPORT_AND_VERIFY` receipt must match
every current locale source field. Each of584 cardinal documents requires its
exact installed revision and attachment identity. The two separately authored
HE/AR intros additionally require the additive `intro_installed` record from
the importer's final readback, with the same fields as an `installed[]` record:
`locale`, `canonical_id`, `prompt_id`, `document_id`, `attachment`, `sha256`,
`revision`. A boolean intro availability flag alone is insufficient. The other
three intros remain in the fixed210 mapping contract.

Generated source maps are parsed as restricted tuple literals, never evaluated.
Their exact rendered bytes, map hashes, counts and canonical catalog identities
are checked. Both original2.5 and explicitly indexed3.1 source models are pinned
per recording; mixed `source_cardinal_resolution` lineage is compared exactly.
Existing EN documents and the two fixed-model intros must not acquire invented
mixed provenance. Runtime checks compare revision, ownership, locale, source
model/voice/content hashes, resolution object, deletion/conflicts, and exact WAV
attachment name/length/digest. Source-file paths are not part of the imported
document verifier's immutable identity; they are not newly claimed as verified.

## Operation

```sh
node scripts/refresh-acdc-cardinal-mappings.cjs --check \
  --node kazoo_apps@CONFIGURED_HOST \
  --receipt /usr/local/share/kazoo5-installer/acdc-cardinal-media.json \
  --model-trial-index /ABSOLUTE/CHECKED_IN/index.json \
  --model-trial-index-sha256 REPLACE_WITH_EXACT_SHA256
```

Supply the complete same explicit resolution flags used by the installer, including Spanish alias
and supplemental paths/pins when applicable. Replace `--check` with `--activate`
only for a deliberate mapping update. There are no provider or database
credentials in argv, generated code or output. Protected SUP uses its existing
configuration; the full expected node is independently checked by the script.

The executable Erlang script stays below16KiB. Its complete586-record inventory
is a separate bounded `expected.json` file, not an enormous binary literal in the
parsed Erlang syntax tree. The wrapper creates the directory root-owned0750 and
both files root-owned0640 with the Kazoo service group. The script pins the
sidecar's absolute path, expected group and SHA256. Before JSON decoding it
checks directory/file ownership and permissions, regular-file/single-link
identity, a maximum8MiB size, opened-file/path stability, and the exact byte hash.
A read of at most the expected size plus one byte rejects growth. Symlink,
hardlink, changed content, writable or oversized files fail before any document
or map access. Both temporary files are cleaned up after the bounded SUP call.

Activation checks every document and existing mapping before the first write.
It sends only missing exact owned entries to both existing map owners,
`media_map` and `kz_media_map`, through synchronous owner calls. Wrong existing
paths fail; no global flush, customer-map deletion, service restart or database
write is requested. Owner PIDs and ETS owners are fenced across the operation.
The final check covers586 documents and1172 exact in-memory paths.

Check mode never calls a lazy `prompt_path` resolver: that API could repair a
cache miss during a race. It performs only exact ETS checks and fresh metadata
reads. No missing entry is repaired in check mode.

The150-second internal admission deadline is checked before and after reads and
map calls. SUP is bounded180seconds and the local process190seconds. This is not
an atomic cluster snapshot: an individual datastore call still has Kazoo's own
timeout, a subsequent external mutation remains possible, and failure can leave
some valid mappings installed. A timeout is unconfirmed completion; do not
blindly overlap another activation. Explicit check or rerun follows inspection.
No readiness/capability flag is published and no queue/account settings change.

## Offline test

Root runs `bash scripts/test-refresh-acdc-cardinal-mappings.sh` through
the serialized validation guard. Fixtures cover exact all-five preflight,
mixed-model provenance, malformed/stale receipts, protected file handling,
SUP command scope, and the actual Erlang template with private datastore/map
stubs. Synthetic metadata proves control flow, not real audio, database state,
live runtime module loading, or listening/native-language acceptance.

The launcher has two mandatory sequential phases. Node executes the wrapper,
receipt and scope fixtures and prepares the complete actual-template input,
then exits with all node:test processes reaped. Only afterward does the shell
compile private stubs and run the standalone Erlang fixture. This removes the
Node+BEAM overlap that exceeded the existing384MiB validation cap; neither the
guard nor the586-document/1172-mapping coverage is reduced. Seven Node groups
alone are explicitly a phase1 result, not full acceptance. The launcher emits
the final PASS only after real Erlang activation/check/race assertions and
source/generated-input stability checks also succeed. Direct invocation of the
Node file without the launcher's protected directory fails closed.

The earlier sequential-only fixture still exceeded384MiB because parsing a1.3MiB
embedded literal expanded a large Erlang syntax tree. The sidecar removes that
production-helper scaling problem as well as the test overlap. The actual
private Erlang fixture includes sidecar tamper, permission, oversize, hardlink
and symlink rejection before datastore reads, in addition to the unchanged full
mapping cases. These edits require a fresh passing run; prior OOMs are failures,
not successful scope coverage.
