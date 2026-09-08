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

A real queue-edit-during-callback acceptance remains pending. Prior
five-language audio/retry results predate this correction and are not proof of
the new queue-edit case. New-account/reseller default inheritance and language
changes during restarted position-announcement workers remain separate review
items; this correction does not close all of VOICE-01.
