# French prerecorded cardinal authoring checkpoint

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
