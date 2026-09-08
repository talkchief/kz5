# P0-22: selected-queue login verification

## Logout stale-proof correction

Source `f820d18` fixes an additional stale-label defect in the same login UI.
An actual-source offline event regression (`ee769d`) failed before the fix:
clicking Logout left the selected agent's cached state `confirmed`. The handler
now invalidates that agent's proofs immediately, without changing any other
agent or account. Per-agent epochs reject proof GET replies and Login
acceptances started before invalidation. An uncertain Logout result cannot
restore obsolete confirmation; a fresh runtime read may confirm current state.
Pause/resume retain queue membership semantics. No API or backend mutation
contract changed.

All27 focused groups pass (`94f869`), including four new groups covering
invalidation scope, delayed reads, delayed Login acceptance, failed Logout and
pause/resume. The test reads actual ACDC source and actual Monster request
handling; it is not a deployed-browser claim. The browser acceptance helper now
requires a confirmed table label before Logout and an unconfirmed visible
label within two seconds afterward, rather than waiting for the30-second TTL.

Deployment through the normal `monster-ui` installer PASS:
`kz5-login-proof-ui-install-main44-20260908`, observer87070/c84568, exit0,
79.425 seconds. Only `js/main.js` and `js/templates.js` changed;1942 other
files were preserved and none removed. Owned deployment, served bytes, HTTPS,
same-origin API and catalog checks passed. nginx was restarted by the installer;
no telephony service restart was requested. Retained rollback and exact plan:
`/usr/local/src/kazoo5-installer/monster-owned-plan.jcWlVY/`.
Private installer log:
`/root/kz5-acceptance/login-proof-ui-install-main44-20260908.log`, SHA256
`316efbd979af261a52877641e3982b3da33597162212c054e027bc380fe51f21`.

Actual deployed browser PASS:
`kz5-login-logout-proof-browser-main44-20260908`,77891/5350d1, exit0,
19.819 seconds. Login confirms, failed-read recovery succeeds without another
Login, and the visible confirmed table label is invalidated within two seconds
of Logout. Selected agent returns to logged out, other29 statuses and persisted
memberships are unchanged, and no unexpected browser issues are captured.
Private receipt `/var/log/kazoo-acceptance/queue-login-browser.khcydd/receipt.json`,
SHA256 `23125c4bf53b4083105ad147739f25a5f090f50aa50354c635352df9eca7b2c4`.
Independent post-check4c9386 confirms zero FreeSWITCH calls and active
kazoo-apps, kazoo-ecallmgr and nginx. Both jobs are terminal; do not rerun them
without a new relevant defect or source change.

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
displayed queue-proof label after logout. That gap subsequently produced the
offline regression, source correction and successful deployed post-Logout
assertion above. Delayed-reply fencing is covered by offline tests, not live
network-reordering acceptance. This is scoped login-display closure, not a
whole-platform reliability claim.
