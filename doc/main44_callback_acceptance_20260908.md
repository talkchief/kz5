# Main development callback acceptance

## Current native run

Main sourcefeebbd5; EN unit `kz5-callback-main44-en-20260908`, observer20300,
**terminal exit0/PASS (`8ddb7e`)**,3m59.914s,CPU1m34.683s,peak91MiB. Protected log
`/root/kz5-acceptance/callback-main44-en-20260908.log`. Bounds512MiB memory,
zero swap,200% CPU,512 tasks,900-second outer deadline. Uses internal transport,
entry-only registration, explicit absent-master-test-phone allowance and
owned account8310dc3170a18de37f205d0da172df65. The prepare-only check passed
16453/61bea0. Protected result `/var/log/kazoo-acceptance/20260908T191139Z`.
Independent summary/receipt readback65c9a6 verifies:

- Exactly one observed registration digit6 and complete matching installed EN
  success audio before BYE; recorded reference SHA
  `471631c6421173a3ec63f216914d4c64cfe2d48c2f0546e4f02c5aa0a925f79b`.
- Busy-call release after the two-second post-confirmation wait, deliberately
  unanswered first attempt, durable retry_wait and second reciprocal native
  bridge, with phase-scoped SIP/RTP proof.
- Two successful caller and agent conversations each,zero failures; zero fresh
  journal/file error matches and new cores. Sampled host peak CPU18%, minimum
  available memory20733724KiB. No service restart during the test.
- Zero calls after cleanup (`52ee15`), unit inactive/PID0. Fixture resources and
  saved original configuration intentionally retained; not full fixture removal.

The HE/FR/ES/AR batch **PASSED**: unit
`kz5-callback-main44-locales-20260908`, observer54480, subsequently verified
terminal success/inactive/MainPID0 (449b40). Protected log
`/root/kz5-acceptance/callback-main44-locales-20260908.log`. Sequential locale
order HE,FR,ES,AR; same explicit account,internal transport,entry-only and
absent-helper flags. Each reference is from the table below. Outer bound2400s,
memory512MiB,swap0,CPU200%,Tasks512; the batch stops on any nonzero test result.
Independent receipt and summary readback1c8f56/ba1160 verifies all four results:

| Language | Result directory under `/var/log/kazoo-acceptance/` | Peak sampled CPU | Minimum available memory KiB |
| --- | --- | --- | --- |
| HE | 20260908T191624Z | 17% | 20726828 |
| FR | 20260908T192023Z | 17% | 20720072 |
| ES | 20260908T192424Z | 17% | 20719372 |
| AR | 20260908T192823Z | 20% | 20405596 |

Each has exact observed registration digit6, complete prerecorded confirmation,
two callback attempts, durable retry_wait, successful second native bridge,
2/0 caller and2/0 agent success/failure counts,0/0 journal/file error matches and
zero new cores. Zero remaining calls118998 and all30 fixture agents logged out
ba1160 were verified independently with no status repair writes. Resources are
intentionally retained; this is not full fixture deletion, failure injection,
long soak, native-speaker approval or general production certification.

All five installed confirmation references passed55230/038efd, with zero
database writes or Gemini calls. Protected directories under
`/var/log/kazoo-acceptance/` (each contains `acdc-callback-success.ulaw` and
`reference-receipt.json`):

| Language | Directory |
| --- | --- |
| EN | gemini-reference.main44-en-us.P5mWcmOn |
| HE | gemini-reference.main44-he-il.B4uWEpFv |
| FR | gemini-reference.main44-fr-fr.Qrg2xlQF |
| ES | gemini-reference.main44-es-es.jVuDIczo |
| AR | gemini-reference.main44-ar-sa.aCEHmxp4 |

The references alone prove installed-byte/revision verification; their separate
five-language native callback retry/audio tests now pass above. Earlier failed
empty reference directories remain for diagnosis.

## Source portability fixes

The original retry diagnostic pinned the old development account in its shell
runner, language setup, internal endpoint preflight and final lifecycle checker.
`--fixture-account ACCOUNT_ID` now explicitly selects a tenant that must match
the canonical root-owned0600 `/etc/kazoo/acceptance-secrets.env`. Inherited
account/language overrides cannot silently select a different target.

The state must describe the isolated Acceptance tenant, matching `.invalid`
realm, caller1001 and queue2000. Known master/Talkchief accounts are refused.
Before fixture writes, the helper rejects the authenticated master, reads the
live account identity, runs the ordinary read-only provisioner resource checks,
and validates any existing saved queue restoration identity. It does not copy
old account IDs or credentials onto the new host. The selected identity also
governs native-leg and durable callback evidence checks; the new helper is
included in source hash receipts.

The fresh host has no old manual `kazoo-live-test-agents.service` helper.
`--allow-absent-master-test-phones` permits only its exact not-found/inactive/dead
state with PID0/restarts0, never a failed helper or absent core service. This is
recorded in the receipt as a limitation, not proof of master test-phone health.
The existing paused-helper option keeps its separate, narrower semantics.

The installed SUP wrapper already supports a missing HOME. The stale callback
preflight's early rejection was reproduced natively (`dc247c`); it now tests
actual bounded SUP connectivity and resolves the returned BEAM file instead.
No HOME, cookie or service setting is changed. The shared acceptance lock is
created exclusively when missing, with root ownership/mode0600; an existing
inode and its contents are preserved. Symlinks, hardlinks and unsafe files fail.

Regression evidence: old retry source rejects the new account option
(`b7e75a`); patched explicit/state/ownership/lock cases pass (`df6e3c`). Existing
88 retry cases,8 locale groups, internal scenario checks,25 SUP preflight cases
and38 helper-service cases pass (`4a8cf5`, `1a51cc`). The same88 lifecycle tests
also pass with an explicitly different synthetic account. Bash/ShellCheck and
whitespace checks pass. The first new test invocation had a template-string
escaping error (`14ec64`), corrected before these results; it was not a runtime
failure. Periodic-offer/position harness portability was subsequently added in
08e02ce; its main-host timing/audio gate is separate from these retry results.

## Native execution scope

Use `.44:/opt/kz5`, the main host's owned Acceptance tenant, caller1001 and one
agent. Do not use the imported Talkchief account or PSTN routes. Read the account
ID from protected state without printing SIP passwords; pass it explicitly.
Capture each reference from the already installed WAV and verify its checked-in
hash using `test-fixtures/callback-gemini-reference.cjs`. Never call Gemini here.

Example after selecting the exact verified fixture and capturing its reference:

```sh
bash scripts/test-acdc-callback-retry.sh --prepare-only \
  --fixture-account "$callback_account" --transport internal --language en-us \
  --registration-mode entry-only --confirmation-reference "$callback_reference"
bash scripts/test-acdc-callback-retry.sh --live --keep-fixture \
  --fixture-account "$callback_account" --transport internal --language en-us \
  --allow-absent-master-test-phones --registration-mode entry-only \
  --confirmation-reference "$callback_reference"
```

Run under a bounded root systemd unit, with protected logs and no other call
acceptance task active. Native sequence remains: connected busy agent, second
caller waits5s, digit6, complete recorded confirmation before BYE, wait2s, release
busy call, leave the first returned attempt unanswered, verify durable retry,
accept the second attempt and prove reciprocal native bridge/SIP/RTP.
Keep the original saved queue snapshot and exact current-callback cleanup;
never rewrite unresolved historical callbacks just to pass a test.

**All five main-host retry languages pass.** Source regressions do not replace
native registration, retry, waveform and clean-log checks; those checks were
run separately as recorded above. Periodic offer/position tests remain separate.
The previous five-language old-host evidence remains archived as documented in
`focused_acceptance_20260908.md`.

## Native preparation findings

Sourcec1fd9f8 was pushed and synced to main. Actual no-HOME SUP preflight now
passes (`70318/d8e416`) where the previous source failed `dc247c`.
The first reference command used a non-allowed directory prefix (`cb10bb`);
the next correctly scoped directory exposed the helper's loopback-only host
restriction (`bae0b3`, sanitized stack `f51e02`). Safe field-presence readback
`1f834e` confirms local CouchDB is configured as10.1.0.44:5984, with credentials
present. The reference helper now permits only loopback or an IPv4 address
actually assigned to this host, connects to that same verified local address,
and still checks exact document/attachment hashes and stable revision. Remote
addresses, hostnames and malformed values remain refused; no credentials are
sent to another server. Locale/reference regressions cover this distinction.
No Gemini generation, database write or SIP call occurred in these checks.
