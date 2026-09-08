# Main development callback acceptance

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
failure. The older periodic-offer/position harness remains separately pinned
and is not implicitly covered by this retry portability change.

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

**Native main-host callback result is not yet proven.** Source regressions do
not replace five-language registration, retry, waveform and clean-log checks.
The previous five-language old-host evidence remains archived as documented in
`focused_acceptance_20260908.md`.
