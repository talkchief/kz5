# Arabic initial authoring checkpoint — September 7, 2026

All 584 planned cardinal identities have now had an initial generation attempt.
Technical QA is **404/584**; this is not listening approval or runtime readiness.

| Language | Technical QA | Failed |
| --- | ---: | ---: |
| EN | 31 | 0 |
| HE | 84 | 47 |
| FR | 160 | 1 |
| ES | 25 | 28 |
| AR | 104 | 104 |

There are no PENDING or REQUESTING entries. The immutable ledger records 676
requests, including 92 cumulative retries. Relative to `cc1d202`, this checkpoint
adds 123 first-attempt Arabic requests and 65 successful recordings (130 WAVs).
It does not retry failed identities or regenerate successful clips.

## Reproducible assets and evidence

- Checked-in pack: `scripts/assets/acdc-gemini-cardinals-20260907/`.
- Protected authoring origin:
  `/usr/local/src/kazoo5-installer/acdc-cardinal-release-20260907/`.
- Approved catalog: `scripts/acdc-cardinal-catalog.cjs`.
- Authoring approvals: `doc/acdc-cardinal-approvals-five-locales-20260907.json`.
- Generator: `scripts/generate-acdc-gemini-cardinal-pack.cjs`.
- Ledger and WAV verifier: `scripts/acdc-cardinal-pack.cjs`.

Six bounded batches used the unchanged default `cardinal-verbatim-v1` recipe,
Gemini 2.5 Pro TTS, Sulafat female voice, approved text and language context.
Each successful 24 kHz mono PCM master has a deterministic 8 kHz SoX derivative.
Run receipts are retained alongside the ledger; no keys or raw provider errors
are part of these assets.

| Guard / session / completion | Requests | QA | Failed |
| --- | ---: | ---: | ---: |
| `93af13/16601/6572a0` | 3 | 1 | 2 |
| `476511/83838/bf548f` | 36 | 6 | 30 |
| `8d49c1/67278/225849` | 36 | 14 | 22 |
| `22b91d/87188/19061a` | 2 | 1 | 1 |
| `d8d9b2/47508/ae8b39` | 36 | 35 | 1 |
| `1cbd01/58413/b20894` | 10 | 9 | 1 |

These generation commands exit nonzero when any requested recording fails.
The successful files are retained. HTTP 500 and incomplete provider output
remain failures, not accepted audio; the differing success rate across number
groups does not establish a provider root cause.

Offline verification `4e6f91/session99094/fbe779` passed both complete ledgers,
every saved WAV hash and actual SoX resampling checks. Repository and protected
origin manifests are identical. Every preexisting attempt prefix and successful
entry from `cc1d202` is unchanged; approvals also match exactly. Six new run
receipts are saved, and no indeterminate request remains.

## Remaining work

Recover only failed identities using explicit bounded authoring policy; preserve
French terminal 89's six-attempt ceiling and all historical attempts. Consider
the already documented exact-word reuse path for eligible Spanish clips before
requesting new recordings. Do not reset history or claim listening approval from
waveform/hash checks.

The existing fixed Gemini queue announcements and responses are separate from
this incomplete expanded number pack. Complete all-locale artifacts, reviewed
listening, map generation, runtime integration and live playback remain required.
Gemini is used **only to author checked-in WAVs**. Installation, future accounts,
queue configuration and calls must consume prerecorded artifacts without Gemini.
