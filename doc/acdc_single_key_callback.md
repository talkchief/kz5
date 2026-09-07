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

OpenAPI descriptions belong to tracked `scripts/api-docs-overlays.cjs` and are
applied before queue PATCH/editor schema copies. Do not hand-edit the untracked
patched-upstream `queues.json` or historical import patches to preserve this
documentation. Installation compiles the tracked ACDC production source.

## Deployment and strict live acceptance remain open

This source is not yet loaded on the development apps node. Earlier eight-
module runtime parity and6+1 live receipts describe the pre-single-key code,
not this candidate. Preserve the old module for rollback, verify current calls
and deploy only the reviewed callback change, not unrelated dashboard records.

The retry harness defaults to historical `confirm-current`. For the new flow,
explicitly supply `--registration-mode entry-only` alongside its existing
`--live --keep-fixture --confirmation-reference FILE` arguments. It requires
exactly one received digit6 at about5seconds and rejects an additional1 or6.
Mode, input/scenario hashes and verified no-alternatives fixture policy are
pinned in the receipt and rechecked; old receipts gain no retroactive proof.
Full installed-WAV delivery before server BYE, retained busy conversation,
unanswered-first-attempt retry and exact reciprocal bridge checks remain.

The dev SIP test-agent helper was temporarily stopped only after zero native
channels were verified, to provide memory for validation. It was restored:
`93f4d5/146ae7` confirms active/running, with all eight checked platform services
active. This is service-state evidence, not a new call or registration proof.
Gemini remains one-time authoring only; no provider was invoked by these code,
API or call-harness checks. Five-language/real-MOH/30-second and release gates
remain separate from this focused fix.
