# Actual queue Create/Save acceptance — main development host

September8,2026: **PASS** on10.1.0.44, source6ebb5fd. This directly exercises
the reported queue-create/Save and language/interval persistence path.

The browser logged in normally, switched to the protected acceptance account,
clicked Add queue, filled the actual controls and clicked Save. No request body
or server response was injected. A write guard permitted only the expected
single create and subsequent updates of that newly created queue, with empty
roster and no extension. It rejected duplicate/unexpected writes and required
the exact five-field unified-editor body, including no unwanted `ui_metadata`.

Six real saves passed:

1. Create with EN, generic interval17 and callback interval30.
2. Reopen and save HE.
3. Reopen and save AR.
4. Reopen and save FR.
5. Reopen and save ES.
6. Disable callbacks through the form and save, preserving the saved intervals.

Each acknowledged operation returned complete, followed by a fresh API readback.
The final real form was reopened and verified as ES/17/30/callbacks disabled,
then cancelled. Existing queue IDs remained present with exactly one additional
queue. No captured page/HTTP/insecure-request errors, request counter0 and inactive
blue loading bar at completion. Imported Talkchief and master account resources
were not edited. No SIP calls, agent login or external provider generation.

## Retained state and evidence

- Unit: `kz5-queue-browser-schedule-save-main44-20260908`, terminal exit0
  in20.619s (observer97969/d810a2).
- Evidence on main: `/var/log/kazoo-acceptance/browser-queue-save.p3Qg3O/receipt.json`.
  SHA256 `34f0a535627a0354969889824e62f229521a7e2078307b5715d0b6223e8b9708`.
  Root-only receipt retains guarded request bodies, operation results and
  readbacks; authentication envelopes/tokens are excluded.
- Retained fixture account: `8310dc3170a18de37f205d0da172df65`.
- Retained queue: `51765a97f9c6dcdffbab1d80cd5d0ef8`, with empty roster,
  no extension requested and callbacks disabled. It is intentionally retained,
  not automatically deleted or presented as complete cleanup.
- Independent readbackb4dc8c confirms ES/17/30, callbacks disabled and no agents;
  FreeSWITCH reports zero calls. The sampled recent journal has zero binding
  responder failures or HTTP500-generation matches (not a whole-log audit).

Initial run66425/489061 failed safely before any write. The guard expected a
callback interval while callbacks were disabled, but the real serializer
intentionally omits disabled timing fields. Independentfd4ea8 confirms no queue
with that run's marker. Evidence `browser-queue-save.aaPpUW` remains retained.
The corrected test selects only the fixture's internal user and enables callbacks
while testing their timing, then disables them in the final Save. At no point is
the queue assigned agents or a dialable extension. This was a harness correction,
not a production serializer change.

## Focused replay

```sh
cd /opt/kz5
bash scripts/run-dev44-company-browser.sh --queue-create-save --allow-fixture-writes
```

Run only on the retained main development server, preferably in a bounded unit.
The launcher requires root, exact explicit arming and the protected fixture
identity, and holds the shared non-truncating acceptance lock. Each successful
run retains one new fixture queue plus operation audit records; do not run it
repeatedly without need. Failures never trigger automatic mutation retries or
cleanup. Inspect the protected receipt before deciding recovery/deletion.

Scope limits: private-route certificate-verified HTTPS, master-admin workflow,
no dialable route/roster assignment. This is not restricted-user authorization,
new-account inheritance, uncertain-network recovery, external storage, real
callback audio or whole-platform production acceptance. Those have separate
tests/gates. It closes the actual browser Save gap for this exercised path.
