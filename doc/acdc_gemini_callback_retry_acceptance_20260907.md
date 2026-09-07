# Installed Gemini callback confirmation and retry — September 7

Result: the isolated retained-fixture diagnostic passed, exit 0
(`f99df0/67005/90042a`). This is a real SIP/RTP and durable-state result, not
complete cleanup, all-language acceptance or production certification.

Protected evidence: `/var/log/kazoo-acceptance/20260907T121515Z`. Do not commit
captures, credentials, device registrations or raw call identifiers. The fixture
routes only authorized fictional numbers through its tenant-local loopback
carrier; this was not a PSTN or production mobile notification test.

## What actually passed

- One fixture agent was already connected to the first conversation. A second
  caller joined the queue and sent key 6 at 4.985 seconds after answer, followed
  by registration-confirmation key 1. **This was not a key-6-only test.**
- The installed immutable EN Sulafat success recording matched the checked-in
  asset. The full 5.491-second phrase arrived before server BYE, with no missing
  phrase samples and correlation 0.999993. This proves PCM delivery, not human
  transcription or subjective voice quality. Prompt identity:
  `en-us/acdc-callback-success-gemini-sulafat-1c49c7478b66e744`.
- The first conversation remained bridged through confirmation. The harness
  waited two seconds after its proof/setup work before releasing that exact
  call. Measured release was 7.452 seconds after phrase completion: do not
  describe this as exactly two seconds after the caller heard confirmation.
- The first returned attempt remained unanswered for 15.714 seconds and was
  cancelled. Durable `retry_wait` was observed. With configured backoff 15
  seconds, the second INVITE arrived 17.883 seconds after the first transaction
  ACK and 0.920 seconds after the durable due time.
- The second attempt was answered; returned-call confirmation key 1 preceded
  the agent INVITE. The exact caller/agent pair established a reciprocal native
  bridge, exchanged PCMU audio and completed. Agent readiness returned.
- The five monitored call-service PID/restart snapshots were unchanged.
  Stage checks recorded zero new file/journal errors and zero new cores.
  No service restart or Gemini request occurred during this diagnostic.

Reference extraction separately verified the actual installed Couch attachment
against the immutable source bytes, with zero database writes and provider
calls (`d43ec7/5e532f`). Offline reference, retry lifecycle and audio tests passed
15, 54 and 39 checks, plus retry policy/readback and shell syntax
(`54164a/2138cd`).

## Remaining acceptance

Keep the callback task open for the operator's single-key registration flow,
the actual configured 30-second independent announcement, real hold music,
all five languages and the user's authorized return-number configuration.
The earlier invalid `kz5_test` caller-ID value remains a separate configuration
issue; a successful isolated valid-number fixture does not repair it.

The runner explicitly retained its fixture and did not claim full cleanup.
Historical ambiguous reconciliation state was not rewritten. Fresh-install,
distributed/reboot, fault/soak/load and production release gates remain open.
Gemini is release authoring only: installation, startup, account/sub-account
creation, editing and calls must reuse shipped WAVs without a provider key.
