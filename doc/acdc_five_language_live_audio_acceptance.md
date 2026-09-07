# Five-language live position and callback-offer acceptance

This harness uses the saved EN, HE, FR, ES and AR WAV artifacts. It never calls
Gemini. It is an acceptance tool, not a production announcement worker.

## Scope

`scripts/test-acdc-callback-offer-calls.sh` accepts an explicit
`--prerecorded-locale` of `en-us`, `he-il`, `fr-fr`, `es-es` or `ar-sa`.
The test creates a marked queue/callflow at extension2098 only in the existing
isolated acceptance account `7807ad61761269a1ccec833dde63f621`, with caller
127.0.0.20. It does not use the operator's extension1000 or a PSTN route.

Each 86-second call checks callback offers at30/60seconds and the complete
position-one introduction plus number at45/75seconds. The two configured
intervals remain independent. Wait-time announcements are disabled in this
test: it does not prove the live wait-statistics branch, callback registration,
retry, or native-speaker approval.

Evidence requires exact SIP dialog and negotiated local PCMU endpoints,
complete RTP capture with zero kernel drops, complete reference-audio
correlation, ordered position components, no DTMF, expected timing, normal
teardown, unchanged service restart/error baselines and conditional fixture
cleanup. Between the matched prerecorded clips, silence MOH may contain quiet
comfort noise and at most two energetic20ms windows; an extra truncated offer
must not pass merely because it is not a complete third phrase.

## Prepare immutable references once

After matched deployment and the actual prerecorded runtime probe, create a
protected JSON file containing its original real arguments:

```json
{"schema_version":1,"probe_args":["--node","...","--account","...","..."]}
```

Use the actual installed receipts, BEAM manifest, source-map/index/alias pins
and probe output path; do not invent successful runtime evidence. The source
account is recorded separately from the isolated live-call account.

Create an empty protected0700 reference directory, then run under the shared
validation guard:

```sh
node scripts/test-fixtures/callback-prerecorded-reference.cjs prepare \
  /protected/probe-options.json OPTIONS_SHA256 /protected/empty-reference-dir
```

This validates the full original source inventory once, then reads selected
installed CouchDB attachments twice, verifies exact revision/model/lineage and
WAV hashes, and converts them with local SoX. It saves a pinned all-five index.
The original assets use Gemini2.5Pro; separately recorded cardinal assets may
use3.1Flash according to their saved provenance. Never relabel their metadata.

## Run each language serially

```sh
bash scripts/test-acdc-callback-offer-calls.sh --live \
  --prerecorded-locale en-us \
  --reference-index /protected/empty-reference-dir/index.json \
  --reference-index-sha256 INDEX_SHA256 --runtime-md5 LOADED_SCHEDULER_MD5
```

Repeat for the other four locales. Each call rechecks the selected installed
bytes and pins the exact index into its private run evidence. The final audio
assertion binds that index to the selected introduction, number, model and
source maps. `--prepare-only` performs no calls or queue writes and is not live
acceptance. Keep call captures and account-bearing receipts outside Git.

Offline regressions are `callback-prerecorded-reference.test.cjs`,
`assert-callback-offer-audio.test.cjs` and `callback-offer-queue.test.cjs` under
`scripts/test-fixtures/`. Synthetic passes do not establish live audio quality.
Current execution results belong in `PROJECT_TASKS.md`.
