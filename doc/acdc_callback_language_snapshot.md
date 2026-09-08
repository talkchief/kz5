# Callback language snapshot — VOICE-01

## Defect and correction

Queue admission already applies `announcements.language` to the call (or keeps
its inherited call language when the queue has no override). However callback
registration overwrote that admitted language from a fresh queue document,
and returned-call confirmation read the current queue language again. A queue
edit while the caller waited or a callback was pending could therefore switch
the response language.

The focused actual-source regression reproduced English being replaced with
French after a queue edit (`54360/2dc817`). The correction:

- Preserves the admitted language from queue-member registration metadata.
- Canonicalizes locale spelling before persistence (`HE_IL` becomes `he-il`).
- Restores the reservation's saved language when starting a returned-caller
  attempt, including a retry with a reconstructed original call.
- Resolves returned confirmation using that language, not a later queue edit.
  Legacy reservations without a language retain their original call language.

Current routing authorization, retry limits and explicit legacy media selection
are unchanged. Queue edits still affect new callers. This adds no database
schema fields or account writes: the existing reservation `language` field is
used consistently. All built-ins remain shared prerecorded assets, with no
Gemini requests during installation, account creation or calls.

Source: `acdc_queue_fsm:registration_settings/3`,
`acdc_queue_member:registration_metadata/1`, and
`acdc_callback_caller:reservation_call/2, confirmation_prompt/2` under
`applications/acdc/src/`. ACDC remains tracked directly by kz5. The helper
test exports are TEST-only. OpenAPI's `CallbackPublic.language` documents this
snapshot contract through `scripts/api-docs-overlays.cjs` and generated assets.

## Verification and limits

All10 language tests pass (`48690/90b612`), including all five supported locales
against a different current queue language, restoration from persisted language,
legacy fallback and unchanged registration metadata/retry defaults. All6
returned-caller tests pass (`76261/ef9e17`), preserving cleanup/lease ownership,
event correlation and explicit-media failure handling. The earlier legacy
prompt mock expected noncanonical `fr-FR`; it now checks canonical `fr-fr`.
The first reproduction attempt lacked debug metadata for its passthrough mock;
the corrected runner compiles private TEST artifacts with debug_info before the
recorded baseline reproduction. No live BEAM was replaced by those tests.

```sh
bash scripts/test-acdc-languages.sh --snapshot-only
bash scripts/test-acdc-languages.sh
bash scripts/test-acdc-callback-caller.sh
```

Run inside the normal bounded validation environment. Tests use private
artifacts, not the running node. Fresh OpenAPI generation passes with358 paths,
653 operations and1653 resolved internal references (`42627/8d0841`).

## Main-server deployment

Source73cd173 was deployed on10.1.0.44 through the normal installer command
`bash scripts/install-kazoo5.sh kazoo-apps ecallmgr`. Unit
`kz5-callback-language-install-main44-20260908` completed successfully, exit0,
in12m6.872s with381.5MiB peak memory (observer84142/09ff6a). Protected log:
`/root/kz5-acceptance/callback-language-install-main44-20260908.log`, SHA256
`698a8bdea4458d2868a34f0ecd92207b4041d555d861ff2750f1749b4ec1a862`.
The installer verified existing media, API access, eCallMgr/FreeSWITCH connectivity
and callback commands. It generated no voices. Both selected services are active
and native FreeSWITCH call count is zero (7389d7).

Independent read-only runtime/disk BEAM comparisons passed for all three changed
modules (4250/ce4046), loaded from `/opt/kz5/applications/acdc/ebin/`:

| Module | Runtime and disk MD5 |
| --- | --- |
| acdc_queue_member | c2b648fd9eb9e579d993fb0465e12521 |
| acdc_queue_fsm | 804ed9a364017a5d2709b29128ede2e9 |
| acdc_callback_caller | f79d2df9272b171cdfa78faa64d4aabf |

The normal static-documentation installer function also completed, exit0
(unit `kz5-callback-language-docs-main44-20260908`,80685/9e6886).
HTTPS readback of `/apis/openapi.json` confirms `CallbackPublic.language`
contains the new contract (27aec6). No UI rebuild was needed for this backend fix.

A focused native mode is implemented in `scripts/test-acdc-callback-retry.sh`:
`--edit-pending-language`, restricted to the main isolated fixture, explicit
`--language en-us`, internal transport and entry-only registration. It keeps
the normal busy-agent/unanswered/retry sequence, uses the unified editor API
to switch only the pending callback's queue to French, checks saved English
language and the complete installed English returned-confirmation waveform,
then conditionally restores English using the exact post-edit queue revision.
It never changes roster or routing. Uncertain writes or intervening edits are
retained for review, not blindly retried or overwritten. A private receipt in
the run directory records the edit, audio proof and restoration. Existing
returned-audio analysis is reused; no provider requests or new audio generation.
Focused patch/restoration, CLI guards and returned-waveform regressions pass.

The first native attempt (`kz5-callback-language-edit-main44-20260908`,
70556/3a0158) stopped before any queue-language write: the new helper omitted
the JSON Accept header and CouchDB returned a valid multipart attachment body.
Registration itself saved `en-us`; its owned callback was settled and native
call count returned to zero. Evidence is retained in
`/var/log/kazoo-acceptance/20260908T215630Z`. This is a helper failure, not a
missing recording or a callback-language failure. Source958ccd7 explicitly
requests JSON and adds a regression. Full read-only helper preflight passes
68149/6374ec, including identity/auth/editor/saved registration/installed audio.
The corrected live attempt is unit `kz5-callback-language-edit-main44-20260908b`,
observer20007, with protected log
`/root/kz5-acceptance/callback-language-edit-main44-20260908b.log`. It terminated
with exit1 in3m55.714s (20007/e8c76b): the busy call, key6 registration,
unanswered first attempt, retry_wait and second native bridge all passed, but
the strict returned-audio timing check failed. The queue was conditionally
restored from French to English; zero calls and both services active were
independently verified17edb7. Do not rerun this scenario merely to obtain a PASS.

The retained capture isolates the timing issue: zero kernel capture drops,
continuous RTP packet sequence numbers, an80ms timestamp gap before the prompt
and a20ms timestamp gap within it (1a2f50). An additive, committed diagnostic
`scripts/test-fixtures/diagnose-callback-language-payload.cjs` independently
rechecks exact SIP/dialog/digit1/agent media correlation and compares the ordered
received payload to the complete installed English recording. It proves saved
English language, the entire English phrase before digit1 (correlation0.999995),
queue French during the retry, and restoration to English. No missing packet
sequence or wrong-language prompt was found. The strict RTP-timing result stays
failed: this language proof is not uninterrupted-playout/voice-quality approval.

Replay evidence13098/a4b1e3 is retained under
`/var/log/kazoo-acceptance/20260908T220213Z/`:

- `callback-language-payload-diagnosis.json`, SHA256
  `aa81b2fa9cf8bb0490d1d55d25192b763172921d5e169a596d12111fe338093c`.
- `callback-language-edit.json`, SHA256
  `362ee55e6a430ea4adb1e1a4849a3ff493b5d946c7030a387594a9c5d7afba5e`.
- `retry-returned.pcap`, SHA256
  `013d7fe99b2a17889f2fdfe48711cb873e4a35a8d77fe4464b54379157fc35e4`.

Next focused action: explain the20ms in-prompt RTP timestamp advance in the
media playback path; retain the strict timing failure rather than silently
relaxing the assertion. No additional call or Gemini generation is needed to
inspect this existing evidence.

Source inspection on main confirms FreeSWITCH revision
`ef32e205295e29f034f1453ad245ba5efb07b94a` and SIP profile `rtp-timer-name=soft`.
The inspected `src/switch_rtp.c` SHA256 is
`a0a0b95ece6342d9089660f3b242aa25cd97d6956136c10f030b30038f542f87`;
`src/switch_time.c` is
`ca714f0454f02b1bc57713a70fbb2d3d0aac2bfcf2fd868163c85e5f8b286284`.
`get_next_write_ts` uses the writer timer's sample count, and soft `timer_next`
can resynchronize an overdue timer rather than replay missed ticks. This is a
source-supported candidate explanation, not instrumentation proving which
branch ran during the retained call. RTP sequence counts packets while its
timestamp represents a media sampling clock; a timestamp gap alone does not
prove packet loss ([RFC3550 section5.1](https://www.rfc-editor.org/rfc/rfc3550.html#section-5.1)).
No global timestamp workaround, FreeSWITCH patch/rebuild, new call or voice
generation was performed for this investigation. Audible playout quality and
the strict timing failure remain distinct from the verified language result.

## Resumed announcement-worker consistency correction

A second source defect was reproduced: after an EN admission, serializing the
call and resuming its announcement worker with the queue's updated FR settings
changed its position/offer language to FR, while callback responses remained EN.
Corrected actual-source baseline1483/ff1843 fails exactly that assertion; the
initial baseline63732/96935a lacked configuration mocks needed by ordinary call
serialization and is not the behavioral reproduction.

Queue admission now stores the canonical effective language in the call's
existing serialized Key-Value-Store (`acdc_admitted_queue_language`). Resumed
announcement workers honor that value. Admission to another queue replaces it;
legacy calls without it retain their prior queue-override behavior. This is
per-call metadata, not a new CouchDB schema field or a change to saved account
defaults. Explicit queue language avoids unnecessary inherited-default reads.
No audio assets or voice-generation behavior changed.

Final source tests44618/5b971e pass all12 language tests, including all five
locales through call serialization, next-queue override, inherited HE_IL
canonicalization and legacy fallback. Queue-schema documentation now states
this admission contract. Source18eef3e is pushed and synced to main; deployment
of this second correction completed through normal `kazoo-apps` installation:
unit `kz5-announcement-language-install-main44-20260908`, observer35217/1d8bcf,
protected log `/root/kz5-acceptance/announcement-language-install-main44-20260908.log`.
It exited0 in11m44.063s,383.1MiB peak, at22:35:41 UTC. Journal8cdd46 confirms
successful completion. Log SHA256:
`8e6f32d701fb35c01c523736997ab10f7d12d603a4a64f2e8edf8f006d333307`.
Read-only check86091/c2092a confirms both running modules match their production
BEAMs under `/opt/kz5/applications/acdc/ebin/`:

- `cf_acdc_member`: MD5 `a10d768e376e896104ceb4b3f5443b20`.
- `acdc_announcements`: MD5 `ef729957c6b7d8ac86b90edbd397d7ce`.

The pre-install native call count was zero31aa97; post-install7ece16 confirms
zero calls and active apps/eCallMgr. The job is terminal; do not rerun it merely
to repeat this evidence. Account/reseller default resolution and actual
worker-failure lifecycle acceptance remain separate from these deterministic
language checks.

The separate static documentation publication unit
`kz5-announcement-language-docs-main44-20260908` completed successfully at
22:25:26 UTC on September 8. Journal verification3382da and HTTPS readbackeeee73
confirm the queue-schema language description at `/apis/openapi.json`. This
was a separate static operation from the successful application deployment above.
The readback used the
private main-server address with certificate validation, not a public-routing
test.

The real queue-edit case proves language retention, with the separate RTP
timing discrepancy above still open. Prior
five-language audio/retry results predate this correction and are not proof of
the new queue-edit case. New-account/reseller default inheritance and language
defaults remain separate review items; these corrections do not close all of
VOICE-01.
