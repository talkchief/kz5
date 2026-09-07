# Spanish one-time authoring checkpoint

September 7: source-reviewed Spanish text approval is in
`acdc_cardinal_es_release_review.md`, with the separate approval proposal
`acdc-cardinal-approvals-es-fr-20260907.json`. Existing attempted EN approval
was compared unchanged before use (`1644cc/a6b2c9`). The source catalog and
all successful existing recordings were preserved.

First ES batch `b6a104/b29f10` made 32 initial requests, concurrency 2:
14 recordings passed technical WAV QA; 18 returned Gemini finish reason
`OTHER` and were rejected as `AUDIO_GENERATION_NOT_COMPLETE`. The process
exited 1 rather than claiming a complete language pack. No automatic retry.

One explicitly bounded diagnostic retry of `number-4` (`95ec3f/06a97a`) also
returned incomplete and exited 1. That identity has exhausted its two-attempt
limit: do not simply retry it again, erase its ledger, or regenerate successful
recordings. The provider's generic `OTHER` does not identify a proven cause.
Do not weaken complete-response/audio verification to call this a pass.

Offline manifest verification `386c7e/f76721` passed with no provider access,
checking exact hashes and deterministic SoX resampling of successful assets:

| Locale | Valid recordings | Failed identities | Pending | Attempts |
| --- | ---: | ---: | ---: | ---: |
| EN | 31 | 0 | 0 | 31 |
| ES | 14 | 18 | 21 | 33 |

No indeterminate `REQUESTING` entries remain. Artifact directory:
`scripts/assets/acdc-gemini-cardinals-20260907/` contains the new 28 Spanish
WAV files, updated manifest and both attempt-run receipts, alongside the
unchanged English WAVs. Private authoring origin remains
`/usr/local/src/kazoo5-installer/acdc-cardinal-release-20260907`.

This is a partial authoring checkpoint, **not** listening approval, a completed
ES pack or a runtime deployment. Existing 210 queue/callback recordings remain
unchanged. Remaining Spanish failures need bounded provider diagnosis before
another authoring decision; do not repeatedly rerun the full language.
The remaining languages/cardinal runtime integration and installer acceptance
remain open. Gemini must never be called by installation, startup, accounts,
queue editing or calls; ship the finished WAVs for all future deployments.
