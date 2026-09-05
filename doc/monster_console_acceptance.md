# Monster UI console regression, 2026-09-05

The live browser gate passed again at 22:36 UTC, without a private asset overlay.
This is scoped UI evidence, not complete telephony/production certification.

## Unified-editor repeat — 22:36 UTC

The first repeat at22:35 failed its queue-stage wait because the harness still
expected the separate `/queues/{id}/roster` request. The deployed editor now
uses `/queues/{id}/editor`. That failed receipt is retained; it had no console,
JavaScript or HTTP errors and its other four stages passed.

The harness now validates the real unified response's queue identity, revision,
complete user catalog, unique roster and corresponding selected UI options. It
requires exactly one editor GET and zero separate catalog requests. Missing
users, incomplete catalogs, wrong queue IDs, duplicate members, missing revision
and paginated snapshots fail its self-test contract. The existing15-second
wait limit was not increased.

The unchanged live UI passed all five stages at22:36:47: login, billing, unsaved
queue editing, unsaved Callflows ACDC drag/drop and authenticated WebSocket
subscribe/unsubscribe. The current queue still has one selected member, matching
the API; no roster was modified. There were zero console warnings/errors,
JavaScript errors, failed HTTP requests/responses or blocked non-auth writes.
Two WebSocket upgrades returned101. This is HTTP-only, not TLS acceptance.

Protected receipts:

- Failed old-contract repeat:
  `/var/log/kazoo-acceptance/monster-console-2026-09-05T22-35-08-627Z.json`
- Passing unified-contract repeat:
  `/var/log/kazoo-acceptance/monster-console-2026-09-05T22-36-46-977Z.json`

The separate full installer fingerprint check still fails because its old build
marker does not describe the subsequent incremental deployments. Browser success
does not waive that provenance/rebuild gate.

## Causes and fixes

| Reported symptom | Cause and deployed behavior |
| --- | --- |
| Whitelabel profile, logo and icon HTTP 404 | No remote branding profile was configured. Explicit local branding avoids these probes; a failed remote profile also no longer cascades into asset probes. |
| Repeating WebSocket `/undefined` | Missing browser socket endpoint. Same-origin `/websocket` now proxies to Blackhole; invalid/unconfigured endpoints no longer start retry loops. |
| Braintree customer HTTP 404 | Payment integration was unconfigured. Explicitly disabled Braintree avoids customer/payment queries while keeping manual billing contact forms. |
| Webphone missing-API warning | Startup previously ran without an endpoint. The optional Webphone now starts only with valid configuration. No backend or SIP device was fabricated. |
| Unkeyed/nonasync Google Maps warnings | Maps loaded unconditionally. It now requires a configured key and loads asynchronously; manual E911 entry remains available without Maps. |
| ACDC language capability HTTP 404 | No runtime capability artifact existed. A protected explicit legacy/negative state is now served; it does not claim staged multilingual readiness. |

## Tests and deployment

The private production build completed in about 1 minute 49 seconds. Its browser
preview passed before deployment. Eleven differing build assets were installed;
1,921 unrelated existing files were byte-identical afterward, and one new
language state file was added. Existing operator API settings were unchanged
apart from the socket and explicit optional-integration flags. Static assets
were deployed with public read permissions; no Kazoo or media service restart
was performed. Nginx's proxy configuration passed validation and was reloaded.

The live Playwright gate exercised:

- Login/core rendering and read-only My Account/Billing.
- An unsaved ACDC queue form, matching its current authoritative API roster of
  **one** member. Earlier 30-member snapshots are historical; no roster was reset.
- Actual unsaved Callflows ACDC palette drag/drop and queue selection.
- Authenticated WebSocket subscribe **and unsubscribe**, with two observed
  HTTP 101 upgrades to `/websocket`.

The gate recorded zero console warnings/errors, JavaScript exceptions, failed
requests/responses, non-authentication API writes, or attempted unconfigured
external-service requests. Exactly one authentication PUT was allowed. No calls,
saved queue/callflow edits, or agent-status changes occurred. Static Google Fonts
CSS/font requests were allowed without credentials; Google Maps was not loaded.

Protected server evidence:

- Preview: `/var/log/kazoo-acceptance/monster-console-2026-09-05T12-39-09-908Z.json`
- Live: `/var/log/kazoo-acceptance/monster-console-2026-09-05T12-44-03-853Z.json`
- Prior assets: `/var/backups/kazoo-monster-console.OXRqwb`
- Prior nginx configuration: `/var/backups/kazoo-nginx-console.rv7LuW`

The reported injected `main.js?attr=...`/`console_collector.js` browser frames
were not part of this clean browser's application bundle. The underlying
application requests were reproduced and fixed independently; this test does
not certify third-party browser extensions. HTTPS, real call-event delivery
under load, external payment/Maps/Webphone integration, and telephone callback
completion are separate acceptance gates.
