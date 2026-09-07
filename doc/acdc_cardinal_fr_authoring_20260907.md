# French prerecorded cardinal authoring checkpoint

## Latest checkpoint: all initial roles attempted, one bounded retry

September7, approximately15:50UTC: French now has138 QA-passed recordings and
23 rejected identities, with no never-requested or indeterminate FR jobs.
Since the prior38-recording checkpoint,109 missing initial roles were attempted
in32/32/32/13 batches;77 succeeded. The46 failures were each explicitly retried
once in32/14 batches;23 recovered. No successful recording was regenerated and
no identity exceeded two attempts. The complete authoring ledger records292
requests across locales; retry budget47 includes the preexisting one retry.

All200 new master/telephony WAV files, six receipts and the complete ledger
were copied to `scripts/assets/acdc-gemini-cardinals-20260907`. Offline exact
manifest/hash/SoX verification passes `2bf797/session65307/f06077` with network
disabled. EN31, ES25 generated and the separate ES reuse layer are unchanged;
HE131 and AR208 remain pending review/authoring. No new cardinal media was
imported or activated, and listening approval remains pending.

| Run receipt suffix (all start `run-`) | Requests | QA passed | Rejected |
| --- | ---: | ---: | ---: |
| b64c3d73-4968-458a-9912-4477edf25268.json | 32 initial | 27 | 5 |
| 0bf613a0-6bc8-4d82-b143-7da32d600f4e.json | 32 initial | 12 | 20 |
| 4632ad5d-529c-4885-afb4-7e955a3a4040.json | 32 initial | 26 | 6 |
| 100dae08-ed24-45df-9e5b-0818b81e4b1f.json | 13 initial | 12 | 1 |
| 3818991c-5723-4fed-83b1-b2fa62cdc54f.json | 32 retry | 17 | 15 |
| 09689304-13f7-4b42-bd74-c9e2ec87d2b9.json | 14 retry | 6 | 8 |

Execution handles: initial `7b7d91/950125`, `46cf73/ec3f9a`,
`5a5172/57e0cf`, `66f630/eb61e7`; retry `de065c/f1d9e6`,
`ce6421/a1f966`. All exited1 because incomplete responses remain; successful
artifacts and terminal receipts were preserved. No authoring process is running.

The remaining failed IDs use prefix `acdc-cardinal-v1-`, followed by
`terminal-N` for N=12,33,35,36,37,39,51,55,59,86,87,89,97,99;
`hundred-one-N` for N=2,4,6,9; `hundreds-N` for N=7,8,9;
`scaled-tail-1000-36` and `scaled-tail-1000-38`. Their retained failure code is
`AUDIO_GENERATION_NOT_COMPLETE`, provider finish reason `OTHER`.
[Google's API reference](https://ai.google.dev/api/generate-content#FinishReason)
defines OTHER as an unspecified reason, not successful completion. The ledger
does not establish a quota, safety, timeout or exact provider-root-cause finding.
Do not weaken completion checks, erase history, regenerate successes or start
third attempts through the current two-attempt format. Remaining authoring
requires a reviewed recovery approach; it is not runtime TTS or a complete pack.

## Earlier checkpoint: first52 initial roles

Latest batch September7: `422e91/session3932/df710f` made32 bounded initial
requests (two workers, no retries). Twenty-four additional recordings passed
technical WAV QA; eight incomplete results were rejected. French totals are now
38 QA-passed,14 failed identities and109 pending initial roles. Historical
requests across the pack total137; no indeterminate requests remain. Receipt:
`run-31cf1e26-e793-4163-b502-921f4e40a983.json`. The48 new master/telephony WAVs
and immutable request history were copied to the repository. Successful existing
WAVs were not regenerated. No new French media was imported or deployed.
Independent offline verification `ad0253/session21190/516fa8` passes complete
manifest identity/history checks, accepted WAV hashes and deterministic SoX
resampling for this latest copy. Network access was disabled; no provider calls.
The pack correctly remains `artifact_complete=false`.

The following table records the earlier first-batch checkpoint, not latest totals.

First French batch, September7: `7672c3/1d038c` made20 explicitly bounded initial
requests, two workers, no automatic retries. Fourteen recordings passed technical
WAV QA; six incomplete results were rejected. The command exited1 because the
language pack remains incomplete, not because successful recordings were lost.

The existing French transcript/context/introduction review and immutable
approval hash were used unchanged. See `acdc_cardinal_fr_release_review.md` and
`acdc-cardinal-approvals-es-fr-20260907.json`. No successful existing recording
was regenerated. Generation is release authoring only, never runtime TTS.

The private authoring origin remains
`/usr/local/src/kazoo5-installer/acdc-cardinal-release-20260907`; copies of the
accepted28 master/telephony WAVs, updated complete history and run receipt are
under `scripts/assets/acdc-gemini-cardinals-20260907` for Git/redeployment.
The first French run receipt is `run-48564141-68db-4b7f-8c2c-734ce54a45a1.json`.

Independent offline verification `2b68ec/342bc8` checks manifest identities,
successful WAV hashes and deterministic SoX conversion with no provider access:

| Locale | QA-passed | Failed identities | Pending initial requests |
| --- | ---: | ---: | ---: |
| EN | 31 | 0 | 0 |
| ES | 25 | 28 | 0 |
| FR | 14 | 6 | 141 |
| HE | 0 | 0 | 131 |
| AR | 0 | 0 | 208 |

Two provider-free Spanish reuse identities are tracked separately. Historical
requests total105. No indeterminate requests remain. These counts describe the
cardinal pack, not the existing210 fixed/callback/digit recordings, which remain
unchanged. French import, listening review and runtime playback are not complete.
