# One-time cardinal synthesis recovery experiment

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
