# Hebrew returned-callback recording: focused follow-up

The September8 Hebrew callback capture failed the strict returned-phrase
coverage check by160 samples; see `focused_acceptance_20260908.md` for the
unchanged original evidence. The later bridge-peer identity fix changes
unbridged callback playback from broadcast to direct playback. Its EN case
passed strict coverage, but that does not establish a Hebrew pass.

Current main44 source is master `da839ed`. Read-only check c02a5e/d6e2f5 confirms
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

Next: capture a reference from the existing installed Hebrew returned WAV,
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
succeeded separately (8d5d2a). The helper now accepts IPv4 addresses present on
the local host's interfaces, but still sends credentials only to127.0.0.1.
No DNS-based or remote database target is added. Three reference-validation
groups pass1c9ee9, including rejection of remote addresses, deceptive hostnames,
malformed settings and unowned addresses. Failed capture remains failed;
replacement capture and the native audio case are pending.
