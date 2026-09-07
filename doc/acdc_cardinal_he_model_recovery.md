# Hebrew saved-voice recovery — September 7, 2026

Hebrew now has all131 required position roles as technically verified saved
recordings:92 original2.5 clips and39 separate3.1 clips. The last36 missing
roles were generated once each in twelve fresh batches of three; no successful
clip was regenerated. This is artifact completeness, not listening approval or
runtime deployment. Gemini remains release authoring only.

## Authoritative inputs and evidence

Original manifest remains unchanged:
`9c97120495c327a66644330d222ae7d4705402c40b1f97b6696a486e4a5d0398`.
Approval set:
`452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5`.

The committed asset root is
`scripts/assets/acdc-gemini-cardinal-model-trials-20260907`.
Subdirectories `he-recovery-1` through `he-recovery-12` retain terminal JSON
receipts and72 WAVs (24kHz master and8kHz telephony). The corresponding private
outputs are under `/usr/local/src/kazoo5-installer/` with prefix
`acdc-cardinal-31-trial-20260907-`. Exact individual receipt hashes are in the
index; no credentials or raw provider response text are included.

At this checkpoint the24-receipt index hash is
`04a236aff8438d7b631463a3f71afef3fe0348c7584d8a5650b0f03d22664249`.
It records67 QA candidates and68 additional model requests, including the
retained first format failure. Original historical requests remain697.

| Batches | Bounded generation evidence |
| --- | --- |
| HE1–4 | `845ab3/session21283/06e83d`, twelve requests, twelve QA clips |
| HE5–8 | `600611/session45455/1f3db2`, twelve requests, twelve QA clips |
| HE9–12 | `566a54/session84567/1f7388`, twelve requests, twelve QA clips |

Read-only complete Hebrew importer plan passes
`4842e8/session30984/8770e2`:131 roles,92 original,39 candidates,0 unresolved;
actual WAV/hash/SoX and source/trial pins checked. Resolved asset set:
`1dc7edd970ea37c1343cf99db22844a1643b17ba9237eee8f253409763947d15`.
No provider or database request occurred in that validation.
An initial root command (`4c311f/a185de`) omitted `.attempt-1` from the intro
filename and failed with ENOENT before import; the corrected command used the
existing pinned intro. The installer adapter already had the correct filename.

The same read-only replay selected twelve still-unrequested Arabic roles and
confirmed103 remaining eligible Arabic roles; no Hebrew role remained eligible.
Its proposal hash is
`b8a31b346a6a9d3ba2ce4f5dcd3a5ec645f41aaa42fdf4268b06a15582f07cdc`.

Combined technical coverage at this checkpoint is EN31/31, HE131/131,
FR161/161, ES53/53 and AR105/208:481/584, including the two reviewed Spanish
whole-word aliases. Original2.5 ledger counts must not be rewritten to reflect
separate model candidates. Listening, runtime model admission, full five-locale
maps, main-shell integration and deployed playback remain release work.

The mixed five-locale installer adapter separately passes root offline proof
`b086d2/session61701/31b376`, including retained13 EN cases and all-locale/mixed
barriers. EN documents remain generated-only; alias resolution is ES-only.
These are adapter doubles, not live database or installation acceptance.
