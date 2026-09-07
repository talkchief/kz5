# Actual browser call-transition acceptance

Status, September 7, 2026: **actual deployed browser detail and summary both
passed isolated-call tests** (a0d26078 detail; f965e9fb summary). The browser verified waiting → handled → gone,
each with a fresh native hint, later authorized GET and matching visible rows
and counts. These are single-call development checks, not production/load claims.

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

## Summary mode

`--dashboard-browser-summary-live` uses the same prerequisites and owning call
lifecycle, through `runWithNaturalSummaryCall` with the same five validated
arguments. It remains on the actual overview page: no detail GETs or injected
refreshes. The selected card must show0/0 →1/0 →0/1 →0/0 for waiting/handled,
with a fresh exact queue hint and later authorized overview GET at each phase.
Every visible card must match the validated overview DTO; the displayed page
queue count and queue identities must remain consistent. Unavailable data cannot
be interpreted as observed zero.

Successful native subscription ACKs must exactly cover the validated page's
queue IDs before and after the call. Cleanup requires each correlated unsubscribe
ACK and an empty final native subscription set before home restoration.
The overview DTO intentionally contains no call IDs or detailed agent rows:
the separate owned-call proof establishes the physical bridge, not an identity
join inside the summary snapshot. No account-wide or historical totals are claimed.

Actual summary f965e9fb passed9 browser checks; receipt
`/tmp/kazoo-monster-live-deployed.4jYi2Y/receipt.json`, call/cleanup evidence
`/var/log/kazoo-strategy-acceptance-Y68nYp/`. There were7 overview GETs,0 detail
or supplemental GETs,3 natural hints, and2 page subscription/unsubscription ACKs.
Both visible queue cards agreed with the DTO. One offer/bridge and12 stable
channel samples passed. Console/page/HTTP/request/scope failures were all zero.
The30 simulated phones were restored and before/after-summary snapshots compared
the exact roster/31 reported statuses/memberships without changes.

Shared-source offline revalidation: observer0343ce18 groups (original12 plus6
summary), CLI b59a7b, company scope c7937d16 groups, original SIP/ownership5a6a8e
and shared DTO/native observer b1bc1212 groups all passed. Independent source
review found an omitted-page-subscription evidence gap; the exact membership
and final-empty checks above closed it before the live run.

After the summary changes, the unchanged detail entry point was re-run against
the same final helper/harness source and passed11 browser checks again:
`/tmp/kazoo-monster-live-deployed.IBFBXo/receipt.json` and
`/var/log/kazoo-strategy-acceptance-ULzxV9/`. This run had5 detail GETs,3 natural
hints,3 subscribe/unsubscribe ACKs, no browser/HTTP/scope errors, and one
offer/bridge with12 stable channel samples. Source hashes:
helper `513baa69a28fa2024f9666ec811a9f58b7235bac32833ec2058d01b94fb368bd`,
harness `1194df32be84c562c068b61272ee3ef70c9481accd43f46fcfee08d42b627d32`.
Final snapshot `phone-snapshot-after-summary-detail-recheck.json` matches the
pre-first-call roster and31 reported statuses/memberships. All nine services
active,30 phone children/sockets restored, zero calls and no recovery ledger.
Platform journal checks since04:18 UTC found no crash-report/OOM/service-failure
markers; this is a narrow test-window check, not a full log or soak audit.

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

Restricted-principal isolation, cross-node faults and load/soak are separate
remaining gates. Historical dashboards, WFM and ClickHouse work remain postponed.
