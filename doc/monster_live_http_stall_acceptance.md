# Deployed queue dashboard HTTP-stall acceptance

September7: the current production UI recovered from an intentionally withheld
real selected-queue response. This tests the deployed bounded-read/controller
behavior, not a mocked successful API or a backend outage.

## Implementation and reproduction

- `scripts/test-monster-live-deployed.cjs`: existing protected normal browser
  login, deployed asset pins, HTTP write guards, native scoped WebSocket guards,
  navigation and exact subscription cleanup.
- `scripts/test-fixtures/monster-live-http-stall.cjs`: opt-in transport hold.
- `scripts/test-monster-live-http-stall.cjs`: eight offline controlled-clock
  groups using real response validators, with nonzero cached-counter fixtures.

Run the offline script in the normal resource guard/network namespace first.
For deployed acceptance, use the existing reviewed deployed-browser environment
and add `KAZOO_TEST_HTTP_STALL=true` plus
`KAZOO_TEST_REQUIRE_WEBSOCKET=true`. Do not combine with natural-call or reconnect
mode. Use Node20+ and the reviewed Playwright dependency, exact account/queue
IDs and deployed asset hashes. Never pass secrets on the command line. The
internal browser deadline is150 seconds; use an outer resource deadline that
allows cleanup. Preserve services and verify zero calls before any temporary
test-only service pause.

Only two exact selected-detail GETs are held. Each response is fetched from the
real server with redirects/retries disabled and schema-validated; release uses
the original response object without changing its body or headers. No API
mutation or fake success response is introduced.

1. Hold normal Refresh beyond the10-second deadline. Require visible stale/error
   state, enabled Refresh, no in-flight request, and the identical cached DTO,
   receipt time and rendered metrics. Release the canceled response, then use a
   normal fresh GET to recover and compare the actual returned DTO to the view.
2. Hold the controller's normal15-second reconciliation GET. Navigate normally
   to Queues, verify native unsubscribe ACK, release the canceled response and
   prove it cannot remount the disposed view or replace the cached snapshot.

Only an exact owned `net::ERR_ABORTED` after the deadline or prepared disposal
is accepted as an expected request failure. Other failures retain the existing
strict browser guards. No broad console/network-error suppression was added.

## Evidence and limitations

- Offline `51b9fc`/`830c4a`: eight groups PASS. Checks scope, mode/bounds,
  nonzero retained counters, fresh-response/view agreement, canceled-request
  ownership, malformed/foreign responses and source immutability.
- Deployed `05bc67`/`65a97a`: nine checks PASS. Receipt:
  `/tmp/kazoo-monster-live-deployed.SYDVca/receipt.json`.
- Deadline response held10,002ms; disposal response held491ms. Both actual
  requests were canceled by the browser. Cached snapshot remained unchanged,
  error/refresh behavior and recovery passed; normal navigation disposed the
  controller. Three subscribe and three unsubscribe ACKs matched.
- Zero page/console/unexpected HTTP/request errors, no supplemental GETs and
  no blocked writes. Actual production asset hashes matched the expected bundle.
  This browser run was idle; nonzero-counter preservation is covered offline,
  not by a live call during this fault test.
- Post-run `930f79`: all nine scoped services active and zero FreeSWITCH calls.
  Ecallmgr and simulated test phones were temporarily paused for browser memory
  and restored. No backend/UI deployment accompanied this acceptance run.

The receipt explicitly reports `late_javascript_callback_executed=false` and
`late_callback_ignore_verified=false`. Playwright accepted the late fulfill
operation, but the browser had already canceled the request; this is not proof
that JavaScript received and ignored a late callback. Delivered-late callback
behavior, never-settling module delivery, restricted-user browser behavior,
cross-node failure and broader production acceptance remain separate gates.
