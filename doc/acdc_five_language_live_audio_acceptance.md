# Five-language live position and callback-offer acceptance

This harness uses the saved EN, HE, FR, ES and AR WAV artifacts. It never calls
Gemini. It is an acceptance tool, not a production announcement worker.

## Scope

`scripts/test-acdc-callback-offer-calls.sh` accepts an explicit
`--prerecorded-locale` of `en-us`, `he-il`, `fr-fr`, `es-es` or `ar-sa`.
The test creates a marked queue/callflow at extension2098 only in the existing
isolated acceptance account (legacy default `7807ad61761269a1ccec833dde63f621`,
or explicit `--fixture-account ACCOUNT_ID` matching protected state), with caller
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

For an installer-managed deployment, the same reference input can now be
reconstructed without copying old-host options:

```sh
node scripts/test-fixtures/callback-prerecorded-reference.cjs prepare-installed \
  /etc/kazoo/acdc/language-capabilities.json CAPABILITY_SHA256 \
  /protected/empty-reference-dir
```

Supply the current exact capability hash. This validates its installer ownership
marker and retained successful runtime receipt, current media receipts, BEAM
manifest and full source input hash before capturing the local installed WAVs.
It does not execute the runtime probe, publish capability or call Gemini.
Changed/unowned proof is rejected; do not substitute a new hash to excuse a
mismatch between current sources and the measured runtime proof.

Main-host preparation on September8: the actual CLI passed10b220 under a
512MiB/no-swap,100% CPU,128-task,600-second bounded unit. Index
`/root/kazoo-prerecorded-reference.main44-cli.crP0f4Ny/index.json` has SHA256
`62ba5a55668dd60a52a8f3470ffa2dc09fe314ac4e7a138228e66877172d887b`, five locales,
zero provider requests and `runtime_probe_executed:false`; retained runtime
receipt SHA256 `13916b3bb3fff756d5a6a908f28f95c36c3882aed607ec7cdff60b651fe87700`.
An earlier invocation failed safely before reference files; a direct helper
preparation and this independent CLI preparation produce the same index hash.
Keep the failed log `/root/kz5-acceptance/callback-main44-prerecorded-reference-20260908.log`.
No periodic call test is implied by reference preparation. The prepared index
uses only saved assets and local installed media, not the old development host.

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
  --fixture-account "$callback_account" \
  --prerecorded-locale en-us \
  --reference-index /protected/empty-reference-dir/index.json \
  --reference-index-sha256 INDEX_SHA256 --runtime-md5 LOADED_SCHEDULER_MD5
```

On the fresh main host, add `--allow-absent-master-test-phones` only for the
confirmed not-installed helper. All core services must still be active; the
helper's exact not-found/inactive/dead/PID0 state is recorded and compared before
and after. The test refuses existing caller registrations and verifies live
Acceptance resources before creating its marked2098 queue/callflow. The shared
lock is validated/created without truncating an existing file. Loopback or an
IPv4 address actually assigned to this host is accepted for local CouchDB;
remote databases remain outside this acceptance helper's scope.

Repeat for the other four locales. Each call rechecks the selected installed
bytes and pins the exact index into its private run evidence. The final audio
assertion binds that index to the selected introduction, number, model and
source maps. `--prepare-only` performs no calls or queue writes and is not live
acceptance. Keep call captures and account-bearing receipts outside Git.

Offline regressions are `callback-prerecorded-reference.test.cjs`,
`assert-callback-offer-audio.test.cjs` and `callback-offer-queue.test.cjs` under
`scripts/test-fixtures/`. Synthetic passes do not establish live audio quality.
Current execution results belong in `PROJECT_TASKS.md`.
