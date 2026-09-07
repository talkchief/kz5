# Actual browser call-transition acceptance

Status, September 7, 2026: **actual deployed browser plus one isolated call
passed** in guarded job a0d26078. The browser verified waiting → handled → gone,
each with a fresh native hint, later authorized GET and matching visible rows
and counts. This is detail acceptance, not a production/load or summary-call claim.

Earlier admission53882e refused before payload at approximately754MiB available.
The successful run temporarily stopped only `kazoo-live-test-agents.service`
(30 receive-only simulated phones), after a zero-call check and state snapshot.
All eight platform services stayed running; the320MiB cap and512MiB reserve
were unchanged. An EXIT trap restored the phone service. Before/after snapshots
matched the exact roster and31 reported statuses/memberships; no status restore
was performed. Final state: all nine services active, zero FreeSWITCH calls,
no strategy recovery ledger. This fixture pause is not a production capacity test.

## Entry point and ownership

Run `scripts/test-acdc-strategies-live.cjs --dashboard-browser-live` with root,
Node20+ and the reviewed Playwright installation. Use the serialized resource
guard; all call-path services must stay running. The mode requires explicit
`KAZOO_TEST_LOGIN_QUEUE_ID`, `KAZOO_TEST_EXPECT_MAIN_SHA256`,
`KAZOO_TEST_EXPECT_TEMPLATES_SHA256` and
`KAZOO_TEST_EXPECT_ACCOUNT_BROWSER_SHA256` before preparation. Stage overlays
and disabled TLS verification are refused. Artifact hashes must describe the
actual deployed build, not a substitute source tree.

The existing strategy harness owns isolated caller1001, agents1002–1004, the
marked temporary queue/callflow2700, SIP registrations and call cleanup. It
derives the target account and temporary queue from its protected verified
state. The existing queue2000 and MASTER queue are not edited. MASTER supplies
normal administrator web login followed by the native company picker; this
does not prove restricted-user authorization. No browser token/account state
is injected. Browser HTTP writes remain limited to its one normal login.

`runWithNaturalCall({accountId,queueId,loginAccountId,loginQueueId,runCall})` in
`scripts/test-monster-live-deployed.cjs` is an internal same-process interface,
not a public API or arbitrary module loader. It overlays only validated scope
options locally, without changing `process.env` or `process.argv`. It returns
an explicit sanitized result; the owning harness rejects anything except PASS.

## What the proof requires

Before caller launch, the actual selected detail must be empty, complete,
authorized, visible and subscribed, with a native ACK-triggered GET completed.
The browser then supplies only a frozen `waitForPhase` observer to the existing
call lifecycle:

1. Start the isolated SIP caller; require visible waiting row/counts.
2. Verify the actual answered reciprocal FreeSWITCH bridge, exactly one offered
   agent/winner and12 stable channel samples; require visible handled row/counts.
3. Hang up only the verified owned call; require the visible row to disappear
   and waiting/handled counts to reach zero.

Each phase has a10-second bound and requires a new exact account/queue native
invalidation after the previous phase boundary, a later real selected-detail
GET, and an exact match between its validated DTO and the current rendered
snapshot. No synthetic event, API reply, refresh or application state is used.
Hints contain no causal call nonce; temporal evidence is not causal attribution.

The observer checks the active ACDC app/current account, controller generation,
the exact attached controller view, visible ancestors/metrics/rows/cells, native
transport ACK state and absence of stale/refresh errors. A hidden dashboard
continuing to refresh cannot pass. Only the latest compact HTTP sample, bounded
event-order records and three sanitized phase proofs are retained. Call IDs,
tokens, names and raw response/frame bodies are not written to browser evidence.

Normal selected unsubscribe ACK and native home-account restoration must finish
before browser PASS. The outer strategy finally block then restores borrowed
agent states and removes only its owned resources. Failures retain the protected
strategy ledger when cleanup cannot be verified; never broaden cleanup scope.

## Evidence and remaining gates

- Actual run a0d26078: `/var/log/kazoo-strategy-acceptance-elItb6/`
  contains `dashboard-browser-evidence.json` and the natural-call proof. One
  offered agent, one bridge event and12 stable reciprocal-channel samples passed.
- Browser receipt: `/tmp/kazoo-monster-live-deployed.CkHl41/receipt.json`:
  11 checks,3 natural hints,6 detail GETs,3 subscribe and3 unsubscribe ACKs;
  zero console/page/HTTP/request/scope errors and no supplemental detail calls.
  Normal company switching and home restoration completed before PASS.
- The owning harness restored the three borrowed agents and removed only its
  marked queue/flow and contacts. MASTER snapshots
  `phone-snapshot-before-fixture-pause.json` and
  `phone-snapshot-after-fixture-pause.json` under the private rollout directory
  compared exactly. Test phones restarted with all30 sockets/children observed.

- CLI/failure-path fixturef3ea3d: pass, including invalid inputs before writes,
  browser failure/throw propagation and existing shared cleanup/signal guards.
- Original SIP/ownership fixture3ebc21: pass.
- Shared production DTO/native observer45380:12 groups passed.
- New actual-helper/controlled-DOM/clock fixture93501:12 groups passed, including
  hidden/stale/wrong-scope views, mismatched rows/counts and no-hint failures.
- Existing browser company-scope fixtured3c369:16 groups passed.
- Live read-only preflight18152: pass; isolated identities unchanged, no existing
  calls/contacts and restorable agent states. No fixture mutations.
- MASTER snapshot18604 compared exactly via423ce0 to the original roster and31
  reported statuses/memberships; no restoration was performed.

Offline commands: `test-acdc-dashboard-live-mode.cjs`,
`test-acdc-strategies-harness.cjs`, `test-queue-live-observer.cjs`,
`test-monster-live-call-observer.cjs`, `test-monster-live-deployed-scope.cjs`, all
under `scripts/` and the resource guard with an isolated network namespace.

The direct development launcher is
`/tmp/kazoo-live-rollout.OYdOqh/test-browser-natural-call.sh`; inspect its current
hash pins and resource admission before use. The successful run used the private
`test-browser-with-fixture-pause.sh` wrapper in that directory to pause/restore
only the unrelated simulated-phone service. Snapshot and compare state around
any such pause; never run the full fixture logout/cleanup operation. Execution must
produce both the private browser receipt and the owning strategy call/cleanup
evidence. The existing natural HTTP/native call PASS79231 and deployed navigation
PASS74850/69219 remain separate earlier evidence.

This slice targets detail call rendering. Summary rendering during real calls,
restricted-principal isolation, cross-node faults and load/soak are separate
remaining gates. Historical dashboards, WFM and ClickHouse work remain postponed.
