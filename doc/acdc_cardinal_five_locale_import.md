# Five-locale cardinal staging importer

Root regression September7 `5ce21d/session79446/1d1d70` passed all12 importer
groups, including full synthetic inventories for all five locales, new-intro
creation, unchanged EN map output, bounded AR208 writes, conflict/corruption
rejection and repeated zero-write import. Evidence:
`/tmp/acdc-cardinal-import-proof.UzJ0dZ`. The13 adapter cases and actual checked-in
EN plan also passed. Network was disabled; no real CouchDB writes or provider
calls occurred. This supersedes the editing-agent unexecuted status below,
not the remaining real-media and runtime integration gates.

`scripts/import-acdc-gemini-cardinals.cjs` now stages one explicitly selected
locale from the complete original 584-identity ledger: EN31, ES53, FR161, HE131
or AR208. This is source implementation with prepared tests. The expanded
importer tests have **not been run** during the active guarded authoring jobs.
No source edit in this task imports media, synthesizes audio, changes the live
map, changes an account, or declares runtime readiness.

The existing `LOCALE`, `COUNT`, `INTRO` exports and EN `renderMap()` bytes remain
compatible. The EN default installer path remains the separate responsibility
of `install-acdc-cardinal-pack.cjs`; this change does not modify that file.
The CLI still requires `--locale`, one mode, an exact cardinal directory,
an exact intro file and an independently supplied approval-set SHA-256.
Unsupported names, language aliases and omitted locale fail before source or
database access. There is no implicit multi-locale import or fallback.

## Validation and introduction ownership

For every selected locale, `openPlan()` reads and validates the original full
ledger using `pack.readManifest()`. All original identities, unsuccessful and
successful attempt histories, context/transcript pins, request provenance and
deterministic master-to-telephony SoX replay remain in scope. Other locales may
be incomplete, but malformed records in any locale invalidate the input. The
selected locale must have exactly its complete expected identity set and a
successful verified recording for every entry. The selected authoring approval
must match the independently supplied approval-set hash. Listening remains a
separate declared fact; technical import does not authenticate listening.

The importer separately pins exact intro identity, transcript, transcript hash
and telephony WAV hash for every locale. The new release pins were taken from
`doc/acdc-cardinal-approvals-five-locales-20260907.json`; the supplied approval
declaration cannot substitute different text or bytes even if rehashed.

| Locale | Cardinal roles | Introduction treatment | Telephony SHA-256 |
| --- | ---: | --- | --- |
| en-us | 31 | Verify existing fixed210 current-position intro | `1fe37e0db985dab9765745fca6cc2e78d17026a992a6088dc92fa37ac7be2dd6` |
| es-es | 53 | Verify existing fixed210 current-position intro | `4753cdfe28956fa8ea620508984041b30ab7fb781845c9f80b565e2662f216d4` |
| fr-fr | 161 | Verify existing fixed210 current-position intro | `7ed7292b5feac6a03881c958532d2f9150d39ea4ca7ecf9d1d11385f10be6b2c` |
| he-il | 131 | Create or verify separately authored versioned intro | `e688f91fc0e23f4926a9be5d87ecc993042389eb895e7f10a602137d4e8ad944` |
| ar-sa | 208 | Create or verify separately authored versioned intro | `312fb7ff3cc60bd2a378027978679302716136504f5ddaf8a3220f6fca2b8598` |

EN/ES/FR use `acdc-queue-your-current-position-is`. HE/AR use
`acdc-cardinal-intro-v1-current-position-number`, distinguished by locale; their
files are in `scripts/assets/acdc-gemini-cardinal-intros-20260907/<locale>/`
with the suffix `.attempt-1.telephony-8000.wav` on that identity. The latter
two introductions may be created only as their exact content-addressed media
documents in import mode. Their historical introductions remain untouched.
EN/ES/FR still require the intro to be installed by the existing fixed210 import;
a missing intro prevents cardinal writes. Verify-only mode cannot create either
kind of intro.

Every intro file is securely read, hashed against its frozen pin and checked as
PCM16 mono 8000-Hz WAV with the existing technical QA. These exact-byte checks
do not independently revalidate the separate intro authoring ledger or its
master resampling; that ledger retains its own verifier and provenance. The
cardinal ledger's resampling evidence covers cardinal roles. No intro listening
or provider authenticity claim follows from matching the release WAV hash.

All source files remembered by the plan are rehashed before and after database
operations. Plan from a quiescent, protected artifact snapshot; changing a ledger
while it is being imported fails the stability check. No manifest is reduced,
rewritten or promoted to a readiness state.

## Database scope and emitted maps

The existing media writer verifies ownership, exact attachment bytes, digest,
transcript hash and revision. The cardinal wrapper limits requests to selected
locale content-addressed IDs, asks CouchDB for conflict metadata, rejects
conflicting leaves, and permits only revision-free PUT creation. A 409 triggers
verification of the existing exact document, never revision overwrite. A
transport failure or unrelated acknowledgement is not retried. Custom recordings
and all existing fixed210 IDs are outside the writable set.

Imports are bounded create-only operations, not atomic transactions. If a later
verification fails, earlier successfully created immutable documents can remain;
the next explicit import verifies and preserves them. HE/AR may similarly create
their new intro before cardinal staging encounters an error. Existing documents
are never overwritten to recover from failure.

The bound is `max(128, 2*N + 2*ceil(N/10) + 8)` database requests for N cardinal
roles: EN128, ES128, FR364, HE298 and AR466. This covers a PUT plus readback per
new role, initial/final batch reads and the separate introduction checks/create.
The writer's existing 210-document plan limit is sufficient because each locale
is imported separately and the intro is a separate one-document operation.

The receipt's `created`, `preserved`, `verified` and `installed` retain their
cardinal-only meaning. NonEN receipts additionally report `intro_created`,
`intro_preserved` and `database_request_limit`. Thus a fresh HE import reports
131 created roles plus one created intro, and fresh AR reports 208 plus one.
Every receipt keeps `runtime_ready`, `full_position_language_ready` and
`five_language_release_ready` false.

EN map output retains its historical macros and bytes. NonEN `--emit-map`
produces a staging fragment with locale-qualified `CARDINAL_ES_*`,
`CARDINAL_FR_*`, `CARDINAL_HE_*` or `CARDINAL_AR_*` macros: map hash, full source
catalog hash, locale catalog hash, context hash, intro declaration, intro asset
tuple and full role asset list. Both intro and role tuples use the existing
seven-field media shape: locale, canonical identity, versioned prompt identity,
WAV SHA-256, CouchDB MD5 digest, byte count and transcript SHA-256. The intro
is separate from the role list, so it does not change cardinal inventory or map
hash semantics. The fragment is emitted to stdout; the importer does not publish
it into the live header.

Example read-only staging plan, after the referenced cardinal snapshot contains
all HE successes and the pinned approval set:

```bash
node scripts/import-acdc-gemini-cardinals.cjs --plan \
  --locale he-il \
  --cardinal-pack /opt/kz5/scripts/assets/acdc-gemini-cardinals-20260907 \
  --intro-file /opt/kz5/scripts/assets/acdc-gemini-cardinal-intros-20260907/he-il/acdc-cardinal-intro-v1-current-position-number.attempt-1.telephony-8000.wav \
  --approval-sha256 452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5
```

This example does not claim that the named cardinal directory has already gained
those HE successes. Choose the actual frozen artifact directory. `--emit-map`
also performs no database access; `--verify-only` reads installed media and
`--import` permits scoped creation. No mode calls a speech provider.

## Prepared verification and remaining integration

`scripts/test-acdc-cardinal-import.cjs` retains existing EN fixtures and checks
for failed original attempt histories, exact bytes/maps, source stability,
create-only idempotence, conflict handling, source/WAV corruption, wrong resample,
missing fixed intro, ambiguous transport and final readback. Its former rejection
of now-supported exact locales is replaced with invalid-locale rejection plus
explicit valid CLI parsing. Added fixtures exercise all four additional full
inventories, same-locale tuple selection, separately created HE/AR intros,
preexisting ES/FR intros, request bounds above 128 for AR208, verify-only,
idempotence, selected-locale incompleteness, wrong-locale intro substitution,
intro conflicts and invalid context in an unselected locale. Only CouchDB is
doubled; fixtures use the real ledger validator and SoX. These tests are prepared,
not a claimed pass; run them in the root-controlled guarded window after current
provider work ends.

The inspected `acdc_cardinal_media.erl` consumer still restricts preparation to
EN and uses `CARDINAL_EN_INTRO` with the fixed210 map. It needs deliberate
five-locale role inventory/map integration and new-intro resolution before the
new staging fragments can affect calls. The pure five-language compositor alone
does not supply those media checks. Whole-playlist preflight must verify the
selected locale's complete assets and introduction; customer-override behavior,
distributed system-media resolution, cancellation, completion and bridge safety
remain runtime integration/acceptance work. Actual native listening remains
separate. The release still requires every integer 0..999999999 in all five
locales with one female prerecorded voice per locale and no runtime TTS, native
SAY, digit fallback or language fallback. All ACDC source work remains in `kz5`.
