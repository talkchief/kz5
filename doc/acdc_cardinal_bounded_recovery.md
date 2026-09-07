# Explicit bounded cardinal recovery

Root validation September7: `4f8aa5/session50354/4bdc8c` passed the generator's
16 groups/260 checks, the unchanged verifier's13 groups/2542 assertions, and
the13 installer adapter cases, all in an isolated network namespace. Actual
checked-in EN staging plan also passed against the new five-locale approval
pin and unchanged source map. Generator receipt:
`/tmp/acdc-cardinal-generator-proof.HvcEia`; verifier receipt:
`/tmp/acdc-cardinal-pack-proof.a3noXY`. Provider calls/key reads were zero;
technical fixtures do not approve spoken audio or activate playback.

The generator still permits at most two attempts per identity by default. A
separately invoked recovery may now select an absolute attempt ceiling from two
through six using `--attempt-limit N`. This option is accepted only together
with `--generate --resume --retry-failed --retry-budget N`; `--request-limit`
remains mandatory. The direct JavaScript entry point enforces the same policy.
Two attempts was an engineering policy, not a user-imposed lifetime limit.

This changes authoring recovery only. It does not synthesize at runtime, alter
voice or language, modify transcripts, change approval requirements, or activate
media. All ACDC work remains within kz5. Existing fixed210 assets are immutable.

## Exact semantics

`--attempt-limit 3` means at most three total historical attempts on each eligible
identity, including every previous failed attempt. It does not mean three new
requests. The hard ceiling is six. The verifier recognizes intact histories
through attempt six even when a later invocation omits this option; omission
still limits new authoring to the existing two-attempt policy.

Only a `FAILED` entry whose existing attempt count is below the selected limit
can receive a retry. A selected `REQUESTING` reservation rejects the invocation
for reconciliation before provider access. A `QA_PASSED` entry is never a retry
candidate. The verifier continues to reject a history containing any later
attempt after either `REQUESTING` or `QA_PASSED`.

Candidates are snapshotted once. Each identity gets at most one attempt in an
invocation, even when the new attempt fails and its count is still below six.
Pending initial identities may still be included under the existing selection
and request-limit rules. Completed selections remain read-only no-op resumes
without provider, key or approval-file access, including explicit recovery.

`--retry-budget` is the cumulative pack-wide retry budget, not an incremental
allowance for this invocation or locale. It cannot decrease and cannot exceed
584. Every existing attempt beyond the first counts against it across all five
locales. All planned retries must fit before any request is made. Initial
request capacity remains 584 and total reservations remain bounded by initial
capacity plus the cumulative retry budget. Raising an identity's attempt limit
does not reset either counter.

For example, if the ledger already contains 40 retries and the selected batch
contains seven eligible retry identities, `--retry-budget 47 --request-limit 7
--attempt-limit 3` can cover one new request on each, subject to their actual
attempt counts and the other generation gates. Budget seven would not suffice.

The existing manifest schema and per-attempt records stay unchanged. New attempts
append sequential numbers and distinct `.attempt-N.` WAV filenames using
create-only writes. Prior attempts, their audio bytes and request provenance
are preserved. The durable run receipt adds `attempt_limit` and
`explicit_attempt_limit` so the selected policy is reviewable. The effective
limit is invocation-specific; a run receipt is evidence of that invocation,
not standing permission for later authoring.

## Example invocation

The values below are illustrative paths and counts, not a runnable authorization
or a credential. Use the existing protected pack and its independently pinned
approval file; inspect its cumulative usage and eligible failures first.

```bash
node scripts/generate-acdc-gemini-cardinal-pack.cjs \
  --generate --resume --retry-failed \
  --output /tmp/EXISTING-PROTECTED-CARDINAL-PACK \
  --locales he-il \
  --request-limit 7 --retry-budget 47 --attempt-limit 3 \
  --concurrency 1 \
  --approval-file /tmp/PROTECTED-APPROVALS.json \
  --approval-sha256 REVIEWED-APPROVAL-SET-SHA256 \
  --key-file /tmp/PROTECTED-EXTERNAL-KEY
```

The generator does not steal a lock, reinterpret an indeterminate reservation,
regenerate a successful identity, erase failed history, or automatically advance
from attempt three to four. Every additional recovery is a fresh explicit
invocation with its own finite request limit and cumulative budget.

## Source and validation scope

Only `scripts/acdc-cardinal-pack.cjs`,
`scripts/generate-acdc-gemini-cardinal-pack.cjs`,
`scripts/test-acdc-gemini-cardinal-pack.cjs` and this document are changed by this
implementation. The catalog, semantic metadata, context definitions,
`requestBody`, model, voice and approval files are untouched. Consequently the
catalog, locale-catalog and context digest values remain defined by the same
semantic inputs. The verifier's source byte hash changes; earlier review
documents retain their honest historical source pin and must not pretend that
the new verifier has that old byte hash.

Prepared regression coverage checks strict opt-in and limits, default refusal
of a third attempt, opted-in third and sixth attempts, unchanged prior history
and request-body hashes, cumulative budget exhaustion/decrease/584 ceiling,
immutable success WAVs, no re-request of an indeterminate entry, and one attempt
per identity per invocation after a third-attempt failure. Synthetic fixtures
use the existing offline provider seam and real local SoX conversion.

Implementation handoff status: **tests prepared, not executed by the editing
agent**. Root must run the serialized network-isolated guarded regression before
using this recovery with a provider. No provider requests, credential reads,
deployments or commits were performed by the editing agent.
