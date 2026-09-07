# One-time cardinal synthesis recovery experiment

Current checkpoint:412/584 technical QA,697 historical requests/113 retries,
EN31/HE92/FR160/ES25/AR104;172 FAILED, none PENDING/REQUESTING. Diagnostic request
`f28770/session40949/deaca8` recovered Hebrew joined-masculine18; bounded batch
`a878f9/session76034/ba1b64` recovered feminine18 and tens20, while joined-tens20
and tens30 again returned OTHER with zero parts. The new diagnostics report no
prompt block reason and no finishMessage for either failure; no specific cause
was identified. Receipts `run-0ca6bf93-6a32-4e04-86e7-5708dc5a64b7.json` and
`run-2773115e-c63d-4b85-929a-65e9dfb9df75.json` and six new WAVs are checked in.
Whole-ledger/WAV/actual-SoX validation, private/repo equality and every historical
success/attempt prefix from `ec59f31` pass `77739d/session24853/e2d87d`.
Older counts below are historical. Runtime activation/listening remain open.

Latest bounded batch `ae1af9/session14124/7926c4` made12 Hebrew attempt2 requests
with concise-v2 and recovered masculine13, masculine15 and joined-masculine15.
Nine requests remain failed. Inventory is409/584 technical QA,692 historical
requests and108 cumulative retries (EN31/HE89/FR160/ES25/AR104);175 FAILED,
none PENDING/REQUESTING. Six WAVs and
`scripts/assets/acdc-gemini-cardinals-20260907/run-5c7ba1b2-ae43-4a16-b0c8-b1cf83cb10db.json`
are preserved. Verification `1bcc6e/session29370/73ddde` passes full ledger,
hash/WAV/actual-SoX checks, repo/private equality, unchanged approval records
and every old attempt prefix/success from `0c63727`. No runtime import or
listening approval. Older counts below describe earlier batches.

Read-only Hebrew follow-up:89/131 identities pass;42 fail (13 failed under both
v1/v2 and29 have only a first v1 attempt). All13 v2 failures report one candidate,
OTHER and zero content/audio/text parts. Successes include both joined/plain
forms and diacritics, so there is no evidence to blame one prefix or remove
approved spelling. No further identical requests are automatically scheduled.
Next authoring diagnostic should safely classify provider finish/prompt-feedback
categories before choosing another bounded experiment; never store raw provider
text, change approved transcripts or reset the ledger to manufacture success.

The authoring receipt now records an allowlisted `prompt_block_reason` (null
when absent, UNKNOWN when unrecognized) and a boolean indicating whether the
first candidate has `finishMessage`. Its contents are never retained. Enum
source: [Google PromptFeedback.BlockReason](https://ai.google.dev/api/generate-content#BlockReason).
Requests, recipes, existing manifests and STOP rejection are unchanged.
`a40011/session45916/893835` passes19 generator groups/377 checks under network
isolation, including raw-text redaction and malformed enums; zero real provider
calls/key reads. Receipt: `/tmp/acdc-cardinal-generator-proof.6i8Dqi`.

Additional bounded HE experiment `982b59/session1670/4a1521`: four serialized
attempt2 requests recovered joined-masculine9 and10; joined-masculine8 and
joined-feminine10 remained incomplete. Same approved text/model/Sulafat and
concise-v2, default attempt cap2, explicit cumulative retry budget96. No further
request was automatically scheduled. Combined inventory is406/584 technical QA
(EN31/HE86/FR160/ES25/AR104),680 requests and96 cumulative retries. All original
attempts remain intact; new successes are four checked-in WAVs. No runtime
import, listening approval or provider-root-cause claim follows from this trial.
Verification `602a4b/session71755/d80b23` passes full ledger/WAV/actual-SoX checks,
repo/private-origin equality, unchanged approvals and every historical attempt
prefix/success from `d61c91f`. Run receipt:
`scripts/assets/acdc-gemini-cardinals-20260907/run-b27e2dea-61d3-4007-8946-78157cc3cd66.json`.

Offline validation `6a52f3/session77127/e5dc60` passed15 verifier groups/4926
assertions,18 generator groups/299 checks and the EN/five-locale installer
adapter suite. Provider/key access was mocked and the network namespace was
isolated. Receipts: `/tmp/acdc-cardinal-pack-proof.p872p2` and
`/tmp/acdc-cardinal-generator-proof.Tv1AwI`. All584 legacy request shapes and
mixed-recipe provenance were checked; tests confer no audio listening approval.

The September 7 diagnostic request for Hebrew
`acdc-cardinal-v1-joined-feminine-1`, attempt 2, returned one candidate with
`finishReason=OTHER` and zero content, audio or text parts. Its receipt is
`run-d6d57d7b-1115-4ca1-bb5d-fb05e7786748.json`. This proves that request did
not return a usable recording; it does not establish why the provider rejected
it or explain older HTTP 500 responses.

The authoring tool now records bounded structural response counts and an
allowlisted finish reason. It does not persist provider text, response IDs,
raw error bodies, credentials or raw response audio. Non-STOP output is still
rejected even when it contains audio.

## Explicit experiment

`--synthesis-recipe cardinal-concise-v2` selects a shorter speech instruction.
The exact catalog transcript, language, professional female delivery intent,
Sulafat voice and Gemini 2.5 Pro TTS model remain unchanged. Arabic retains
the complete pausal-chunk and written internal-inflection instruction.

This is a hypothesis-driven authoring experiment, not a proven provider fix.
Google recommends limiting unnecessary performance rules in its
[speech-generation guidance](https://ai.google.dev/gemini-api/docs/speech-generation).
That page's specific HTTP 500/text-token explanation concerns Gemini 3.1 Flash;
it is not evidence of the cause of our Gemini 2.5 failures.

Omitting the option retains the exact `cardinal-verbatim-v1` request bytes and
legacy attempt schema. Explicit selection records `synthesis_recipe` in each
new attempt and run receipt. The verifier independently reconstructs the selected
recipe and checks both instruction and request-body hashes. Unknown recipes are
rejected. Earlier attempts and successful WAVs are never rewritten.

Existing request budgets, explicit failed-only recovery and the six-attempt
absolute ceiling still apply across recipes. Changing recipes does not reset
history. French terminal 89 has already reached six failures and is not eligible
for a seventh request under this policy. Do not erase or recreate its ledger.

This option belongs only to the one-time authoring command. Installation,
account creation, queue editing and calls must use checked-in WAV artifacts and
must never call Gemini. Technical waveform checks are not listening approval;
full five-language runtime admission remains a separate gate.

## Actual bounded experiment results

- `0ff950/session41613/bc0ed6`: Hebrew joined-feminine1 attempt3 passed technical
  QA; receipt `run-a08c496d-eccd-4a44-9c65-251b26c0b32d.json`.
- `1e7318/session45410/a379c2`: five further HE requests yielded3 QA/2 incomplete;
  receipt `run-4ba06dfa-eb07-4dd3-b08a-2af07937d69d.json`.
- `5656ae/session27876/907c68`: four first-attempt AR scale chunks all returned
  OTHER with zero parts; receipt `run-faac7b43-d1a4-4817-a304-9fdefe27641e.json`.

The shorter instruction did not eliminate failures. All four new successful
recordings (eight WAVs) and four diagnostic/experiment receipts are preserved in
the checked-in release pack. Total339/584 technical QA;553 historical requests,
92 retries. No recording was imported into runtime by these commands.

Whole-ledger/WAV/actual-SoX verification and repo/private equality passed
`6770af/session57511/914a21`. Every old attempt prefix and successful entry from
parent commit `cc961d2` is unchanged. Importer3890 checks and the actual existing
EN31 plan passed `6302ed/session41803/15cc5d`; the EN map bytes stayed unchanged.
