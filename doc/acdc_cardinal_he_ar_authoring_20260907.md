# Hebrew / Arabic prerecorded cardinal authoring

## Latest checkpoint, 16:16UTC

Three HE batches attempted96 roles:59 QA,37 failed,35 initial roles still
pending. First AR32 batch yielded22 QA/10 failed,176 initial roles pending.
Second HE run `ae1b34/session84457/c56a92` added18 successes;
third `07ac76/session85745/291eeb` added16. Arabic run
`3645f4/session63215/a00747` added22. Every rejected response and request is
retained; no indeterminate request or authoring process remains.

Additional receipts (requests / successes):

- `run-8ae14f4b-fb41-4fdb-9b78-cadd619a4097.json`:32/18 HE
- `run-819ec284-0826-4b83-95c7-19b5beaa5644.json`:32/16 HE
- `run-0cac4c53-2c89-477e-a44c-0eae8526afbe.json`:32/22 AR

The full ledger now has458 requests,85 cumulative retries and297 QA recordings
including EN31/ES25/FR160. Both separately authored intros are also verified.
Independent offline verification `67c5ba/session51989/a1b50e` confirms exact
repo/private equality, all old attempts and successful entries unchanged from
fe02eb0, and actual WAV/SoX checks. No listening or runtime activation occurred.

## Reviewed text and new introductions

Root read the complete HE/AR release reviews and retained their exact texts,
contexts and intended delivery. The two new introductions passed the real
Gemini request and technical WAV gates on their first attempts:
`622cc4/session17711/289e89`. Their dedicated ledger records exactly two
requests, no retry, with receipt
`run-22d5c45f-edcf-4093-8932-48ce80fe16ac.json`.

Tracked immutable pack:
`scripts/assets/acdc-gemini-cardinal-intros-20260907` (four WAVs).
Private authoring origin:
`/usr/local/src/kazoo5-installer/acdc-cardinal-intros-release-20260907`.
Independent offline copy verification `b13129` passes both WAV hashes,
technical QA and actual deterministic SoX resampling. Intro helper regression
`099fb1/session41030/f9dade` passes12 groups/215 checks using12 mocked requests
and no real provider or key access.

The selected telephony hashes are:

- HE: `e688f91fc0e23f4926a9be5d87ecc993042389eb895e7f10a602137d4e8ad944`
- AR: `312fb7ff3cc60bd2a378027978679302716136504f5ddaf8a3220f6fca2b8598`

Both use new identity `acdc-cardinal-intro-v1-current-position-number`, not
replacement bytes under an old media ID. Existing210 fixed/digit recordings
are unchanged. Technical QA is not listening or pronunciation acceptance.

The five-locale authoring file is
`doc/acdc-cardinal-approvals-five-locales-20260907.json`, independently pinned
approval-set hash
`452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5`.
Existing EN/ES/FR approval records are unchanged; HE/AR now bind their source
reviews and the actual verified new intro hashes. Every listening approval
remains PENDING. Installer staging must use the new global approval pin when
reading the updated full ledger; the existing EN31 map remains unchanged.

## First Hebrew batch

`7233b9/session44970/01b3af` completed32 initial requests:25 technical QA passes,
7 incomplete responses retained as FAILED,99 HE roles still PENDING. No retry
or indeterminate request. Receipt:
`run-b391f41e-8e66-4bff-9bd5-b958d86cf901.json`.
All50 successful master/telephony WAVs and full history are preserved under
`scripts/assets/acdc-gemini-cardinals-20260907`.

At this checkpoint the full ledger contains324 historical requests: EN31 QA,
ES25 QA/28 failed, FR138 QA/23 failed, HE25 QA/7 failed/99 pending, AR208 pending.
No new cardinal runtime deployment, media import or listening approval occurred.
Remaining recordings, failed-request recovery, complete five-locale installation
and actual queue playback are still required. Gemini is release authoring only;
neither installation nor account creation nor runtime calls may synthesize.
