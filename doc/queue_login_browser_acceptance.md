# P0-22: selected-queue login verification

## Main-host result — September 8, 2026

PASS for actual Login confirmation and recovery from one failed verification
read, using the isolated acceptance account on kz5-dev. No production app code
changed in this acceptance run; source4b4fcf3 adds the reusable browser check.

- Unit: `kz5-queue-login-browser-main44-20260908`.
- Terminal observer/result:72753/569476, exit0,20.561 seconds.
- Private main-host receipt:
  `/var/log/kazoo-acceptance/queue-login-browser.dgN5R0/receipt.json`.
- Receipt SHA256:
  `17e7a22de2add87338249d2579c90ab02e1f60e1a082b44f6fd17c258215c20f`.

The actual Agents screen opens Login for fixture agent1, selects its queue and
sends exactly one runtime-only Login request. The dialog shows confirmed
membership and an independent API read agrees. Exactly one subsequent proof
GET is intentionally aborted: the dialog shows verification unavailable and
disables Login. Check again recovers through a real successful GET, without
another Login POST. No successful responses or login payloads are fabricated.

The selected agent is then logged out through the actual UI. All30 individual
statuses match the initial logged-out states; the other29 agents and selected
agent's persisted memberships are unchanged. Unexpected writes are blocked.
The copied Talkchief company is not changed. Independent post-check found zero
FreeSWITCH calls, active apps/ecallmgr/nginx, and no matching binding/HTTP500
errors in the narrow recent journal window; this is not a complete log audit.

## Reproduction, only when needed for this defect

Run on main from `/opt/kz5` with the protected acceptance fixture available:

```sh
bash scripts/run-dev44-company-browser.sh --queue-login-check --allow-fixture-writes
```

The launcher requires explicit write arming and takes the shared acceptance
lock. Implementation is `scripts/test-fixtures/queue-login-browser.cjs`.
Failure retains evidence and does not automatically retry or reset all agents.
Inspect the receipt and live selected-agent state before any scoped recovery.

## Remaining limits

This check does not prove SIP ringing, restricted-user authorization, arbitrary
stale navigation, or resolution of the earlier unclassified TypeError. Prior
call acceptance is separate. It verifies API logout but does not assert the
displayed queue-proof label after logout. Source review shows cached proofs
have a30-second lifetime and the explicit Logout handler does not invalidate
them; this is a candidate stale-label defect to reproduce under P0-22, not a
claimed runtime reproduction or completed fix. Delayed proof replies must also
be considered if an invalidation fix is needed.
