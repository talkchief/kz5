# Single-key queue callback registration

The no-alternatives flow now has a focused source fix: after the caller presses
the configured entry key (default 6) and the wrapper obtains a correlated queue
pause, a valid current destination requests registration immediately. There is
no extra registration key 1. `allow_alternate_number=true` retains its existing
selection/readback/confirmation menu. Returned-call acceptance key 1 is separate
and unchanged.

Only `acdc_callback_menu:new/3` changes production behavior. The wrapper changes
are TEST-only helpers. The same existing request action still reaches queue
authorization and durable registration; publication alone does not play success
or hang up. Correlated durable acknowledgment precedes success playback, and
the original leg ends only on the existing completion/failure/timeout contract.
Invalid destinations still fail safely; no routing/number checks are relaxed.

## Root evidence, September 7

- All17 canonical reducer tests passed (`e0b0b7/47676e`). The launcher now
  compiles kz5's tracked reducer, not its obsolete historical import patch.
- All22 wrapper tests passed (`6ed1f5/256a55`), including no extra DTMF,
  stale pause rejection, exact request scope, durable-success ordering and
  policy rejection followed by resuming the same queue slot.
- The subsequent broad canonical suite did **not** finish: the combined run
  reached its600-second unit deadline (`00e86e`, journal `3deed4`). Completed
  feedback/integration/caller cases passed, but remaining worker/success cases
  and the final stable-input check did not finish. Do not report all87 passed
  for this new source. Rerun the canonical suite alone with an adequate budget.
- An earlier128MiB attempt was OOM-killed inside its isolated validation unit
  (`83e236`); an immediately started same-cap retry was intentionally cancelled,
  not accepted despite its transport exit code. No Kazoo application was killed.
- Updated strict retry harness passes80 scenario/lifecycle/scope groups and79
  audio groups; actual setup/retry policy/readback tests and shell syntax pass
  (`a0b8db/221870`). No SIP or API traffic in those tests.
- Fresh focused production build passed for all8 modules with unchanged pinned
  inputs, no TEST exports and no live writes (`a0b8db/5fb0a7`):
  `/tmp/kazoo-callback-media-build.2YgHe7`.
- Private OpenAPI regeneration/validation passed (`aaee56/53c392`), with358
  paths,653 operations,504 schemas and1601 resolved references. Output:
  `/tmp/kazoo-single-key-openapi.EDdgLJ`. Not published to the live portal.
- The subsequent standalone run cancelled during one default-five-second mock
  setup (`e3ba68/644f8c`), not a product assertion failure. With that fixture's
  bounded setup corrected, the full standalone canonical run **passes all87**
  (`142a1a/654902`), including the final unchanged-input check. Details:
  [fixture budget](callback_media_test_budget.md).

OpenAPI descriptions belong to tracked `scripts/api-docs-overlays.cjs` and are
applied before queue PATCH/editor schema copies. Do not hand-edit the untracked
patched-upstream `queues.json` or historical import patches to preserve this
documentation. Installation compiles the tracked ACDC production source.

## Source deployed; isolated English live acceptance passed

**Strict entry-only live run passed** `d26b83/0fcc7e`: only6, full installed
confirmation audio before BYE, unanswered first attempt, durable retry and
successful second bridge. Protected evidence and limitations:
[single-key live acceptance](acdc_single_key_live_acceptance_20260907.md).

The single changed production module was deployed on the development apps node
(`cd4e17/6fbfad`), after real zero-channel/baseline/checksum preflight. Loaded
and disk module MD5 is `f2395173bdf3183659ac45fc0b7fa6c5`; old code was released.
No database/provider writes, restarts or unrelated dashboard deployments.
Rollback BEAM and receipt: `/tmp/kazoo-single-key-deployment.LKf1lf`.

`scripts/deploy-single-key-callback.cjs` is a development-only, fixed-baseline
one-module promotion helper, **not** a replacement for the general installer.
It verifies private production build inputs/artifacts, inspects metadata locally,
preserves service-readable0644 mode under umask077, atomically replaces only
the menu, uses soft-purge/load verification and retains a protected backup. It
never force-purges. If rollback cannot load, it preserves known disk/runtime
agreement and reports failure. Seven mocked control-flow tests passed
(`343822`); actual successful load evidence is separate. Fresh deployment through
the main installer compiles tracked ACDC source including this change.

The retry harness defaults to historical `confirm-current`. For the new flow,
explicitly supply `--registration-mode entry-only` alongside its existing
`--live --keep-fixture --confirmation-reference FILE` arguments. It requires
exactly one received digit6 at about5seconds and rejects an additional1 or6.
Mode, input/scenario hashes and verified no-alternatives fixture policy are
pinned in the receipt and rechecked; old receipts gain no retroactive proof.
Full installed-WAV delivery before server BYE, retained busy conversation,
unanswered-first-attempt retry and exact reciprocal bridge checks remain.

The dev MASTER test-phone helper was temporarily stopped only after zero native
channels to provide validation memory. Restoration `4fc1cc/0b5d16` passed, then
the live guard refused160MiB+512MiB reserve admission before any call started.
It was paused again (`c64fa7/2c757e`); all eight checked core/web/data services
remain active. The retry creates its own isolated tenant SIP agent. The explicit
`--allow-paused-master-test-phones` option permits only that independent helper
to be inactive/dead/PID0 and preserves exact before/after service snapshots.
Default requirements remain unchanged;27 scope checks and80 retry groups pass
(`17a4a7/4929f3`). See [scope limitation](callback_retry_paused_test_phones.md).
Root restored the helper after the completed test and zero native channels:
`7268a4/898117`, active/running, all eight core/web/data services active.
Gemini remains one-time authoring only; no provider was invoked by these code,
API or call-harness checks. Five-language/real-MOH/30-second and release gates
remain separate from this focused fix.
