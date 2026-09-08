# Main development server: periodic queue audio acceptance

Scope: installed prerecorded callback offers and complete position-one
announcements, EN/HE/FR/ES/AR, on `10.1.0.44`. These tests make no Gemini
requests. They are separate from the five-language key6/confirmation/retry
tests in `main44_callback_acceptance_20260908.md`.

## Deployed source and test isolation

Server checkout `0155673`; loaded `acdc_announcements` module MD5
`7d496238cabb662bc538e202584658f5` was read before admission and required by
the test. The main host's protected Acceptance tenant is explicitly selected;
the script refuses the imported Talkchief tenant and master accounts. Each run
creates its own marked queue/callflow at extension2098, with no agents assigned
and no agent status changes. Actual caller contact absence, no existing calls,
resource ownership and the shared exclusive acceptance lock are checked first.

The installed reference index is
`/root/kazoo-prerecorded-reference.main44-cli.crP0f4Ny/index.json`, SHA256
`62ba5a55668dd60a52a8f3470ffa2dc09fe314ac4e7a138228e66877172d887b`.
Its independent preparation checked the retained installer runtime proof and
exact source/media hashes. Each call rechecks its selected installed attachments
and keeps a pinned copy of the index in its protected result directory.

Run command, repeated serially for each locale:

```sh
bash scripts/test-acdc-callback-offer-calls.sh --live \
  --fixture-account 8310dc3170a18de37f205d0da172df65 \
  --allow-absent-master-test-phones --prerecorded-locale en-us \
  --reference-index /root/kazoo-prerecorded-reference.main44-cli.crP0f4Ny/index.json \
  --reference-index-sha256 62ba5a55668dd60a52a8f3470ffa2dc09fe314ac4e7a138228e66877172d887b \
  --runtime-md5 7d496238cabb662bc538e202584658f5
```

Both units use root,512MiB memory,no swap,200% CPU and512 tasks. English
unit `kz5-periodic-main44-en-20260908` has a600-second deadline; it exited0
in1m47.603s with60.2MiB peak (48661/2cb3e8). The remaining-locale batch
`kz5-periodic-main44-locales-20260908` has a900-second deadline and stops on
the first nonzero result. It exited0 in7m10.621s with129.1MiB peak
(45450/07eef3); independent readback4f7417 confirms success/inactive/PID0,
zero remaining calls and all nine services enabled/active. No test remains live.
Protected logs:

- `/root/kz5-acceptance/periodic-main44-en-20260908.log`
- `/root/kz5-acceptance/periodic-main44-locales-20260908.log`

## Received audio and timing

Times below are seconds after the observed queue entry. Evidence directories
are under `/var/log/kazoo-acceptance/` on the main host.

| Locale | Callback offers | Full position-one starts | Directory |
| --- | --- | --- | --- |
| EN | 30.066,60.046 | 45.066,75.046 | 20260908T193929Z |
| HE | 30.058,60.038 | 45.058,75.038 | 20260908T194142Z |
| FR | 30.052,60.052 | 45.052,75.052 | 20260908T194330Z |
| ES | 30.060,60.040 | 45.060,75.040 | 20260908T194517Z |
| AR | 30.051,60.051 | 45.051,75.051 | 20260908T194705Z |

Completed runs prove exact negotiated received PCMU, complete reference
coverage, ordered introduction plus number audio, no offer on entry, no extra
energetic audio over silent hold, normal SIP BYE, producer cleanup, unchanged
service PID/restart snapshots, zero fresh log errors and no new cores. Their
conditional cleanup deletes only the exact marked queue/callflow revisions and
verifies unrelated documents remain unchanged. English/HE/FR independent
audio and deletion-receipt readback passed05f99a; ES/AR readbackd03d89 confirms
their audio, teardown and both owned-document deletion receipts. Before/after
service snapshots match independently for all five. All30 fixture agents are
still logged out7c439e, with no status repair writes. All tests used existing
immutable installed media; no generation was performed.

This is not native-speaker pronunciation approval, arbitrary spoken positions,
wait-time playback, real music-on-hold mixing, every callback response branch,
failure injection or high-availability certification. Readiness flags for those
unperformed checks are not promoted by these passes.

## Queue language controls: deployed browser acceptance

The expanded `scripts/test-dev44-company-browser.cjs` passes0b7f2c against
certificate-verified private-route HTTPS. It verifies the existing Talkchief
inspection copy, SmartPBX, ACDC and the inactive blue loading line, then opens
one real queue editor. Exactly five enabled language values are present:
`en-us`, `he-il`, `ar-sa`, `fr-fr`, `es-es`. Each is selectable in the local
draft; distinct callback and position interval fields are present. Cancel
returns with counter0, no active progress indicator and no HTTP/page errors.

During this editor phase, the browser blocks non-read requests to the copied
company. It never saves, changes an agent, registers a device or places a call.
This proves deployed control availability, not save/reload behavior or
new-account/reseller inheritance. The imported account remains inspection-only.
