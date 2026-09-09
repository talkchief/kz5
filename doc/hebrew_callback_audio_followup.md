# Hebrew returned-callback recording: focused follow-up

The September8 Hebrew callback capture failed the strict returned-phrase
coverage check by160 samples; see `focused_acceptance_20260908.md` for the
unchanged original evidence. The later bridge-peer identity fix changes
unbridged callback playback from broadcast to direct playback. Its EN case
passed strict coverage, but that does not establish a Hebrew pass.

Initial main44 source was master `da839ed`. Read-only check c02a5e/d6e2f5 confirmed
the loaded `ecallmgr_fs_channel` MD5 is `349067bcb00612035743d1f1d64b55a0` and
the existing Hebrew registration reference verifies as Gemini/Sulafat/he-il:
`/var/log/kazoo-acceptance/gemini-reference.main44-he-il.B4uWEpFv/acdc-callback-success.ulaw`.
No calls were active before this follow-up. No production system is in scope.

The additive `assert-callback-returned-audio.cjs` checker still hard-coded the
original development account. It now uses the same explicit fixture-account
selector as the callback harness. It never infers authorization/scope from a
captured receipt. Account mismatch, master/imported-company scopes and malformed
selection are rejected. PCAP/reference hashes, exact phrase and every-sample
coverage, timing, single-stream and media identity checks remain unchanged.

The planned check was to capture the existing installed Hebrew returned WAV,
run one isolated main44 HE callback/retry, then replay its returned audio against
that reference. This is not regeneration, a provider request, a human listening
approval or a five-language release claim. Preserve failed evidence separately.
Only the existing isolated account `8310dc3170a18de37f205d0da172df65` is allowed
for the native case. Main/production customer accounts remain untouched.

Checker validation54a412 passes four groups, including explicit main/legacy
scope, receipt-account mismatch, forbidden master/imported accounts and the
unchanged strict waveform cases. Source `ce7487e` is on main44.

First reference-capture unit `kz5-he-returned-reference-main44-20260909` failed
before HTTP (da5883). Main's configured CouchDB host is its own10.1.0.44 address;
the old helper accepted only literal localhost/127.0.0.1. Source asset lookup
succeeded separately (8d5d2a). Initial correction `de0a75a` accepted owned IPv4
addresses but still requested loopback. Replacement unit ending20260909b failed
(4d5e0c); sanitized stack608ca3 locates fetch failure, and socket read a6512e
proves CouchDB listens only on10.1.0.44:5984. No database binding was changed.

The helper now requests the configured IPv4 address only after proving that it
belongs to the local host. Literal localhost remains mapped to127.0.0.1. No
DNS-based or remote database target, redirect, or provider request is added.
Four reference-validation groups pass cbb9b6, including exact private/loopback
URLs and rejection of remote addresses, deceptive hostnames, invalid ports,
malformed settings and unowned addresses. Failed captures remain failed;
replacement capture and native outcomes follow below.

Source `d579521` is pushed to master and on main44. Replacement reference unit
`kz5-he-returned-reference-main44-20260909c` exited0 (91ef14),440ms. Receipt:
`/var/log/kazoo-acceptance/returned-reference.G2bIPdPk/reference.json`, SHA256
`9bef7b57924303156243db019726585ac5b74d312898f90d2e3b98f68f526597`.
Capture62baab reports database_writes0 and provider_requests0. No recording was
regenerated or replaced.

## Scoped native result: PASS

Native unit `kz5-he-returned-audio-case-main44-20260909` exited0 (113c8e),
runtime3m59.455s. Run `/var/log/kazoo-acceptance/20260909T043058Z` explicitly
selected he-il and entry-only6 in the isolated fixture: full registration audio,
first returned attempt unanswered, and confirmed second attempt with reciprocal
bridge. Ticket `acdc-callback-5616955090f2adbd4efd250c1d9a52d746a485202e85fd733fc38cac26ff5c49`
was completed at attempt2, language he-il and originate_success_recorded=true.
The test's agent-ready and unchanged-service gates passed; summary caller2/0,
agent2/0, fresh journal/file errors0/0 and cores0. FreeSWITCH had zero calls
afterward (7a889b); five named platform services were active (8135a4).
No service restart or timer edit was performed. The isolated fixture is retained;
this is not full fixture cleanup or a customer-account/default-language change.

Additive replay unit `kz5-he-returned-waveform-main44-20260909` exited0 (18e4df),
590ms, using the pinned installed reference above and the unchanged strict
coverage/matching/timing checks. Result8023be:

- Entire42,648-sample /5.331-second phrase covered; correlation0.999993.
- Phrase starts0.540450s after ACK and ends5.871450s after ACK.
- It finishes2.145401s before confirmation digit1.
- `returned_confirmation_verified=true`.

This closes the known HE returned-waveform gap on the current main development
deployment. It does not rewrite the old failed capture, prove its complete
historical cause, approve pronunciation/naturalness, prove general language
inheritance, or pass the overall five-language/full-position release gate.
The additive receipt deliberately retains native_listening_approved=false and
full_language_ready=false. No voice generation or provider requests were needed.

Evidence SHA256 (files under the run directory unless stated otherwise):

- `retry-packet-evidence.json`: `01fb9a3cf5f500538629bf277e2d8e621aac0f31d0fcb45a9bc889521470e365`
- `retry-bridge-evidence.json`: `aeacc23ce55abb7835ae9700bf936228e6ccd62ea096aef73cfbc0add7e2efaf`
- `retry-returned.pcap`: `184456f2c73afa2b2adff8039cd30c810691b8a6b81f96b344532976acb43937`
- `he-returned-waveform.json`: `a8fda67753ab2579a26f8557b24db1a06544f6ae632b63a0d68cde2166f1cd66`
- `/root/kz5-acceptance/he-returned-audio-case-main44-20260909.log`: `bcf98498dfa917d056a342b3eb39eb2bd23cc1f64070310beb64ae6040976033`

All reference/native/replay jobs are terminal. Reuse this passing evidence;
do not rerun without a relevant code or deployment change.
