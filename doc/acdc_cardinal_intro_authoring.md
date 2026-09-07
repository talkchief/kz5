# Two current-position introductions: source candidate

This separate authoring tool creates only new HE/AR introductions. It does not
change the 210 existing assets, the 584-role cardinal catalog, any historical
manifest, installer, backend or runtime. No real provider requests have been
made for this candidate; root offline tests pass as recorded below. The existing
user authorization for one-time missing
audio does not constitute native-speaker listening approval.

## Exact catalog for source review

Both locale-qualified IDs are
`acdc-cardinal-intro-v1-current-position-number`:

| Locale | Exact transcript |
| --- | --- |
| he-il | מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא. |
| ar-sa | رَقْمُ مَوْقِعِكَ الْحَالِي فِي طَابُورِ الِانْتِظَارِ هُوَ. |

Both explicitly name the number of the caller's **current queue position**;
neither changes it to a ticket number or a count of callers ahead. The Hebrew
number is an abstract feminine label; Arabic is a masculine nominative numeric
predicate. The source-review rationale and primary references are in
`acdc_cardinal_authoring_readiness.md`. These texts are distinct from the old
immutable introductions, which remain preserved.

Files:

- `scripts/acdc-cardinal-intro-pack.cjs`: finite catalog, exact request shape,
  strict manifest/WAV verifier and verified intro-input projection; no provider.
- `scripts/generate-acdc-gemini-cardinal-intros.cjs`: explicit one-time authoring,
  protected output and durable attempt/run ledgers.
- `scripts/test-acdc-gemini-cardinal-intros.cjs`: 12 prepared offline groups with
  synthetic review/provider/audio fixtures and real deterministic SoX replay.

The tool reuses the existing protected Gemini `requestSpeech`, PCM extraction
and WAV helper, plus the cardinal verifier's exact no-dither SoX recipe and
technical QA. It does not use the older helper's different resampling command.
Sulafat and `gemini-2.5-pro-preview-tts` remain fixed. Output never changes gain,
trims boundaries or inserts silence; a natural final pause is requested and
measured. No duration/format test establishes the spoken words or cadence.

## Source-review artifact and CLI

Default `--plan` has no filesystem, key, provider or subprocess effects:

```bash
node scripts/generate-acdc-gemini-cardinal-intros.cjs --plan
```

It returns both transcripts, `catalog_sha256` and a pending review template.
After actual source review, create a protected JSON file with exactly:

```json
{
  "schema_version": 1,
  "catalog_sha256": "<catalog hash from the reviewed plan>",
  "decision": "AUTHOR_INTROS_ONLY",
  "review_kind": "source-backed-engineering",
  "evidence_sha256": "<SHA-256 of the actual source-review evidence>"
}
```

Independently pin `pack.digest(review)` as `--review-sha256`. This is the
canonical JSON digest exported by the pack, not a claim to authenticate a human
reviewer or the raw file-byte digest. Do not use synthetic fixture approvals.
Pending/wrong reviews fail before fresh output creation, provider loading or key
reads. An existing pack's review cannot change on resume.

Generation shape for the root-controlled, serialized authoring window:

```bash
node scripts/generate-acdc-gemini-cardinal-intros.cjs --generate \
  --output /usr/local/src/kazoo5-installer/cardinal-intros-REVIEWED \
  --request-limit 2 \
  --review-file /usr/local/src/kazoo5-installer/intro-source-review.json \
  --review-sha256 <independently-reviewed-canonical-review-digest> \
  --key-file <protected-key-file>
```

Two initial requests, one serial worker, at most two attempts per identity.
`--request-limit` is explicitly 1 or 2. Durable REQUESTING reservations and run
journals precede transport; keys and response prose never enter their output.
The reused provider bounds each request at 90 seconds and never redirects or
automatically retries. The root's execution guard must allow the chosen request
count plus verification without weakening resource admission.

`--resume` preserves/reverifies successful bytes and requests only pending work.
`--resume --retry-failed --retry-budget N` allows already-failed first attempts
only, with N=1 or 2 bounding all retries; total requests cannot exceed four.
An incomplete audio response may allow the other initial identity to continue;
HTTP/auth/rate/transport or local technical failure stops further scheduling.
REQUESTING and retained locks require explicit reconciliation, never implicit
rebilling. A complete resume needs neither key nor review file and does not
rewrite manifest/audio. Existing output files, drift, unsafe modes, symlinks and
hardlinks fail closed; failed attempts and partial files are retained.

Provider-free verification:

```bash
node scripts/generate-acdc-gemini-cardinal-intros.cjs --verify-only \
  --output /usr/local/src/kazoo5-installer/cardinal-intros-REVIEWED \
  --review-sha256 <independently-reviewed-canonical-review-digest>
```

Successful verification replays each master through the exact cardinal SoX
recipe and compares actual telephony PCM hashes/sample counts. It returns
`intro_inputs`: locale, canonical_id, transcript, transcript_sha256 and the
verified **8 kHz telephony** wav_sha256. These are facts for the existing
cardinal approval schema, not automatically APPROVED records. Listening,
native-speaker review, deployment and runtime readiness remain false. The
cardinal authoring review must deliberately adopt these verified inputs and
retain its own independently reviewed approval-set hash.

## Prepared proof and remaining boundary

Root-only offline test command (executed with512MiB reserve; checkpoint below):

```bash
bash scripts/run-kazoo-validation.sh \
  --memory-mib 128 --reserve-mib 512 --runtime-sec 90 -- \
  /usr/bin/unshare --net /usr/bin/node \
  /opt/kz5/scripts/test-acdc-gemini-cardinal-intros.cjs
```

Coverage candidates include exact contexts, invalid/pending review with no
output, same-path retry, durable serial reservations, partial/full no-provider
resume, explicit retry/unchanged success/history, REQUESTING/lock refusal,
changed review refusal, max-four attempts, safe failures, immutable filesystem
rejection, and equal-duration rehashed wrong-frequency telephony rejection.
The fixture pins every source dependency and SoX before/after, retains a private
receipt on failure, and forbids actual HTTPS requests. A fixture pass will not
establish speech accuracy or provider provenance.

After generation, commit reviewed immutable files/provenance and add these two
new IDs to the future separate cardinal importer/map. Do not put them into the
fixed 42-per-locale callback completeness check or overwrite old intros.
Actual full-number listening, runtime whole-playlist integration and live
playback/cancellation remain separate release steps.

## Root verification checkpoint — September7

The isolated root run `96b914/64a1be` passed12 groups and215 checks with12 mock
requests,zero real provider requests/key reads and actual SoX conversion.
Source hashes stayed unchanged. Receipt:
`/tmp/acdc-cardinal-intros-proof.NWjyDb/receipt.json`. This validates authoring
mechanics, not real HE/AR recordings, pronunciation, listening or deployment.
