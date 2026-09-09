# Native Blackhole command authentication

September9 source fix, pending deployment acceptance.

The native callback skipped authentication whenever its context already had an
account identity. The token helper also skipped verification for a previously
authorized handshake. Consequently expiry/rejection or a replacement token in
a subsequent command could bypass token validation and continue to command
dispatch under the old identity.

`scripts/patches/blackhole-command-auth.patch` is a required root-owned installer
overlay on the existing Blackhole integration. It affects only
`src/blackhole_socket_callback.erl`, outside the base integration's overlapping
source inventory, so fresh and repeated installs can apply/check both patches.
No ACDC nested repository or manually edited deployed BEAM is used.

Each native command now obtains fresh proof through `kz_auth:validate_token/1`,
requires a nonempty account claim matching any existing identity, and runs the
authentication hooks with that verified context. Missing/non-context positive
results and explicit denials fail closed. Validator errors, malformed results
and exceptions return a fixed failure without credential-bearing details. The
verified context avoids a second validation in the token helper; the next
command must obtain fresh proof again. A different nonempty token requires
reconnecting; subscriptions are not transferred between identities.

Payloads are removed from callback-stage debug logs, including nested credentials.
Existing rate limits, validation, resource authorization and command hooks remain.
This guard is not authorization to access another account or queue.

## Evidence

- Pinned original callback in a private replay: five failures/nine passes,
  `/tmp/kazoo-blackhole-redaction.oytQjL`, exit1 (abe992). Four new cached-auth
  tests expose the bypass; the fifth reflects the intentionally earlier denial
  stage. No production bytecode changed during this baseline run.
- Candidate: all14 public-entry groups, exact source replay/reverse checks,
  eight production compiles with warnings as errors and31 dependency-path checks
  pass. `/tmp/kazoo-blackhole-redaction.PeFU5x`, exit0 (e4e667).
- OpenAPI source contract:55 schema checks pass (9da911).
- Queue-live compatibility initially failed because its generic-path fixture
  assumed authentication could be absent. Its isolated fixture now uses the
  real native ping/auth binding path with an explicit token-validator double;
  no real JWT or broker acceptance is inferred from that fixture.

Replay:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 180 -- /usr/bin/unshare --net -- \
  /bin/bash /opt/kz5/scripts/test-blackhole-auth-redaction.sh
```

The same script's `--baseline-command-auth` option reverses only the command
overlay inside the private replay and proves equality with the pinned original.
It is expected to fail the new regressions; it never reverts deployed source.

## Remaining boundaries

This change revalidates commands. It does not yet periodically terminate an
already subscribed generic event stream when its token expires or is revoked.
The validator retains its native identity/key cache semantics; immediate
cross-node revocation is not claimed. Queue-live delivery retains its separate
fresh authorization worker and scope checks. Slow-client/backpressure and
cross-node API/supervision acceptance remain part of the requested closeout.
