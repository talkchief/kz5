# French 89: one new-model authoring request

The missing role `fr-fr/acdc-cardinal-v1-terminal-89` retains its six failed
Gemini 2.5 attempts. All six returned OTHER without an accepted recording.
The approved text is unchanged: `quatre-vingt-neuf`.

The explicit `--fr89-model-diagnostic-once` branch allows only this exact role,
source manifest, transcript, entry/history hashes and concise-v2 request body.
`scripts/acdc-cardinal-fr89-one-shot-policy.cjs` contains the reviewed pins.
Model is Gemini 3.1 Flash TTS, voice Sulafat, maximum one request. This changes
both the model and the old v1 instruction to the existing concise-v2 instruction;
it is not a single-variable causal experiment.

The fixed private reservation directory is:
`/usr/local/src/kazoo5-installer/acdc-cardinal-fr89-gemini31-once-20260907`.
It is created atomically before any request and remains consumed after success,
failure or interruption. Do not delete, rename or reset it to obtain another
request. Alternate output, resume, broader identities and ordinary cap overrides
are rejected. Preflight/key failure before reservation makes no request.

The saved ledger's exact `one_shot_diagnostic` marker preserves source count6
and count7 including the new request. The verifier admits this narrow marked
exception and rejects any second reserved FR89 outcome in the supplied history,
even a second failed one. Normal HE/AR/ES authoring caps and the read-only recovery
planner's scope are unchanged. No automatic retry or runtime admission is added.

## Result

`cd1fb9/session46682/a8eb4a` completed one request successfully: exact returned
3.1 model, STOP, accepted mono24k PCM, master/telephony QA and actual SoX/hash
verification. Receipt SHA256:
`6e3a4976cafc2c708f3efaa7734af8e853d6828c5735c0d58f5906e13d965844`.
The receipt and two WAVs are saved under
`scripts/assets/acdc-gemini-cardinal-model-trials-20260907/fr89-once/`.

French technical artifact coverage is now161/161:160 original recordings plus
this separate candidate. The original412/584 ledger and its failures are
unchanged. This is not listening approval, an import or runtime activation.

Pre-request regression `8379b1/session14397/c71072` passed637 authoring checks,
nine verifier groups/447 checks with62 actual SoX calls, and204 planner checks.
Tests use isolated synthetic policy paths and did not consume the real slot.
Evidence: `/tmp/acdc-cardinal-trial-assets-proof.5pMbwi`.
