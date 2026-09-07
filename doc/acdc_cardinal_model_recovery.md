# Saved-model candidate verification and recovery planning

These tools are **read-only release-authoring tools**. They do not call Gemini,
read credentials, write media, install prompts or activate runtime language maps.
Use the existing installer for deployments, never a synthesis tool.

## Verify saved 3.1 candidates

`scripts/acdc-cardinal-model-trial-assets.cjs` exports:

```js
openResolution({
  sourceDirectory, sourceManifestSha256, approvalSha256,
  trials: [{directory, sha256}]
})
```

Supply independently reviewed exact trial-manifest hashes, not hashes calculated
from arbitrary new files just to make validation pass. All trials must refer to
the same explicitly pinned original 2.5 source snapshot. At most 64 terminal
receipts are accepted. In-progress, conflicting and duplicate successful
outcomes fail closed. An earlier failed request followed by a later success is
retained, not hidden. Unsent SELECTED entries do not count as requests.

Every success is checked against its original FAILED source entry, approved
transcript/context and exact request body. The model must be 3.1/Sulafat; STOP,
mono 24 kHz format, WAV metrics, hashes and actual SoX resampling must match.
Changed files, unsafe paths, aliases and unverified readiness claims are rejected.
The original ledger and trial request counts remain separate.

`summary()` returns terminal outcomes and separate request counts;
`resolve(locale, id)` returns defensive copies of QA candidate audio/provenance;
`sourceManifest()` returns a defensive source copy. Each operation rechecks pins.
Candidates remain explicitly unapproved for listening, import and runtime.

## Plan only missing, unrequested roles

`scripts/plan-acdc-cardinal-model-recovery.cjs` accepts:

```text
--source-pack ABSOLUTE_DIRECTORY
--source-manifest-sha256 EXACT_HASH
--approval-sha256 EXACT_HASH
--prior-trial ABSOLUTE_TRIAL_DIRECTORY EXACT_TRIAL_MANIFEST_HASH
--max-requests 1..12
```

Repeat `--prior-trial` for **every known prior trial**, including failed receipts.
The tool cannot discover omitted private authoring history. Its returned scope
explicitly states this limitation; do not treat a partial allowlist as global
deduplication proof. The planner never executes its proposed requests.

It verifies the supplied artifacts, then uses stable catalog order to select
original FAILED HE/AR/ES roles in batches of at most three. Saved successes,
all previously reserved 3.1 requests, exact ES4/ES9 reuse candidates and capped
identities are excluded. A prior 3.1 failure requires a manual diagnostic decision,
not an automatic retry. FR89 remains outside this experiment and retains its six
original failures. Source, approval, prior-trial, entry/history and request-body
hashes are included in the plan; no source history is reset.

## Validation

The resolver passed seven groups / 379 checks with 58 actual SoX operations
(`a081cd/session40816/30e895`), using synthetic source history and copied real
trial WAVs. Source hashes remained unchanged. Receipt:
`/tmp/acdc-cardinal-trial-assets-proof.buHInw`.
The following planner test initially stopped on a missing fixture-function brace;
that test-only syntax fix is recorded separately. A failed combined command is
not proof that the planner suite passed.

After the one-brace fixture fix, the planner passed 204 offline checks
(`09dbb9/session81517/726e08`), including real CLI subprocess execution and
write/provider denial. Its resolver is mocked in that suite; the seven-group
resolver suite above supplies independent artifact validation.

Actual root replay `6a83cb/session68011/904157` verified all eight then-saved
real receipts: 21 QA candidates, 22 additional trial requests and unchanged 697
original source requests. The real planner proposed 12 still-unrequested roles,
excluded 23 saved/reused identities, and reported 148 eligible roles. All candidate
resolutions and final source pins were rechecked. This replay made no provider
calls or writes and did not claim listening/runtime acceptance. Counts are a
checkpoint, not an automatically refreshed release inventory.
