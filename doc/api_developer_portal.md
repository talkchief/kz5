# API developer portal

The Monster UI module installer now carries a static developer reference at
`/apis/`. `/apis` redirects to `/apis/`. It includes a downloadable, validated
OpenAPI 3.0.3 JSON document, locally vendored Swagger UI, source hashes, and an
explicit coverage report. No running API, credentials, caller data or external
validator is used to generate or view the reference.

This is a source-derived catalog, not a claim that every endpoint is deployed,
enabled, permission-reviewed, or production-tested. Each operation identifies
whether it is upstream-generated or source-reviewed. `coverage.json` records
generic responses, missing schemas/parameters, unsupported upstream schema
keywords preserved as extensions, and literal routing bindings not represented
in the catalog. Missing definitions are explicitly unknown, not fabricated.
For example, the upstream `skels` template schema is absent; its catalog entries
must not be assumed to be available routes. Source inventory is a gap detector,
not an Erlang routing parser. Dynamic bindings and aliases need manual review.

## Safety and authentication

The hosted viewer is read-only: all TryItOut methods are disabled, the external
validator is disabled, authorization actions cannot store a token, and the
request interceptor accepts only same-origin GETs for the two local specs.
Query-string overrides cannot change the spec URL. A content security policy
blocks remote scripts, validators, frames and form submission. No CDN, telemetry
or OAuth flow is configured. Viewing the portal does not place calls or mutate
accounts. Its public availability is equivalent to publishing the repository's
API contracts; do not include private deployment examples in the assets.

Use a separate API client over HTTPS. Authenticate through `PUT /v2/user_auth`
or `PUT /v2/api_auth`, with the request inside `{"data": ...}`. The returned
`auth_token` is a secret and is sent as the `X-Auth-Token` header on subsequent
requests. User-auth `credentials` is the supported hash of `username:password`,
not a plaintext password. Account API keys must also remain secret. The portal
contains only synthetic all-zero identifiers, never functional credentials.
Changing the OpenAPI server URL in an external client does not grant permissions.

For separate-node installations, configure that client's Crossbar HTTPS URL.
The spec's `/v2` server describes the same-origin TLS proxy provided by the
installer. Do not send authentication over the non-TLS installation endpoint.

## Source-reviewed additions

### Native Blackhole and the future Next.js frontend

The generator now includes native Blackhole discovery (`GET /v2/websockets`)
and the reverse-proxy HTTP upgrade (`GET /websocket`, with a root server override
so clients do not generate `/v2/websocket`). The `Blackhole*` component schemas
and `x-blackhole` extension describe subscribe/unsubscribe/ping commands, reply
and event envelopes, and subscription/error/pong payloads. The companion
`/apis/blackhole.html`, linked from the viewer and OpenAPI `externalDocs`, covers
authentication, trusted separate-host WSS configuration, Next.js client effect
cleanup, correlation, stale state and reconnect/resubscribe/resnapshot behavior.

OpenAPI is an HTTP specification, not an automatic WebSocket client generator;
the companion explicitly documents that boundary. The recommended frontend
command schemas are intentionally stricter than the legacy server: send the
token and request ID explicitly and only one binding selector. Source inspection
found `bindings` wins over `binding`, empty unsubscribe is rejected, and
subscription replies use arrays. These override conflicting historical examples.

This documentation does not promise durable replay, exact snapshot ordering or
server-side token expiry/revocation for cached socket contexts. Slow-client
message loss, lifecycle authorization, queue-specific dashboard protocols and
production event acceptance remain BH-02/03/04/05 and DASH-03/04/05 tasks.
Blackhole is included in Kazoo apps by the installer; it is not a separate
replacement event server or standalone systemd service. Publication and test
evidence for these new assets must be recorded separately from earlier receipts.

The Blackhole catalog checkpoint passed offline build/validation in session
`12699`. After the installer source pin was added, guarded session `57164`
regenerated and checked the complete artifact: 356 paths, 651 operations,
33 source-reviewed operations, 485 schemas, 1,556 resolved references and
11 manifest-listed assets (plus the manifest). The schema tests include 21
Blackhole-specific negative cases. Deterministic regeneration, tamper detection
and the actual installer documentation copy into a private test root passed.
The current artifact manifest SHA-256 is
`0f350101477e9ba761bdc84985278fed5563fd1aa4c1e86ee1dab3673921bf3b`.

The same 180-second/384-MiB/reserve-768-MiB network-isolated run used real
Chromium to load all 651 operations, expand the Blackhole upgrade response and
navigate to the Next.js companion page. Ten local GET requests, zero external
requests and zero browser console errors were observed. TryItOut, authorization
storage and query-selected external catalogs remained disabled. The companion
contains no scripts. This proves documentation rendering, not a live WSS
connection, authentication lifetime or ACDC event delivery.

Static publication `73763` then used the actual installer copy function for
source commit `63e6bf738f5c7654afc6054f32b0888f9569fd94`. All twelve served files
(eleven manifest entries plus the manifest) matched repository bytes over
loopback HTTP with `Host: kz5.talkchief.io`, with `Cache-Control: no-store`.
`/apis` returned 308 to `/apis/`; a missing asset returned 404. The previous
eleven-file deployment was hash-verified before and after backup at
`/usr/local/src/kazoo5-installer/api-docs-rollback.0sQoYx/previous`.
The published manifest remains `0f350101477e9ba761bdc84985278fed5563fd1aa4c1e86ee1dab3673921bf3b`.
No service was restarted or reloaded, no backend BEAM was activated, and this
publication does not certify TLS or live authenticated WebSocket behavior.

- Queue CRUD, full roster replacement/clear, statistics, and historical ACDC stats.
- Callback list, read and cancel. There is no public callback-create endpoint;
  a trusted queued caller must explicitly confirm registration. Cancellation of
  an in-flight callback is not immediate leg-termination proof.
- Independent `callback.announcement` options alongside queue position/wait
  announcements. Disabling offer audio does not disable callback digit/menu.
- Agent availability and queue membership as different operations. The legacy
  POST `/agents/status/{USER_ID}` alias is flagged because its advertised method
  lacks a matching source validation handler; use `/agents/{USER_ID}/status`.
- POST `/accounts/{ACCOUNT_ID}/channels/{UUID}` with `eavesdrop` (listen),
  `whisper`, `barge`, `join`, and correlated `stop_monitoring`. These require an
  exact-account administrator and an enabled account-owned SIP supervisor phone.
  Timeout is **20 seconds by default**, bounded 5–60 seconds. HTTP 202 means
  accepted, not connected. Choose the agent leg for whisper; stop uses the
  returned supervisor leg, never the original customer/agent leg. Local synthetic
  acoustic/authentication acceptance is recorded in
  [channel_monitor_acceptance.md](channel_monitor_acceptance.md), not a cross-node
  or production certification. Legacy channel actions are separately identified
  as incompletely typed; old queue eavesdrop routes fail closed with HTTP 503.
- GET/PUT `/accounts/{ACCOUNT_ID}/queues/editor` and GET/PATCH
  `/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/editor`. The coordinated queue editor
  uses bounded, permission-filtered catalogs, complete revision maps and a stable
  idempotency key. Its queue/roster/route writes are explicitly **non-atomic**.
  Inspect recovery phases and reload after ambiguous/partial failures; do not
  blindly repeat writes or change the idempotency key to bypass an incomplete
  receipt. Managed extension changes reserve at most the old and target
  extensions by account-scoped CAS before settings writes, preventing conflicts
  between aggregate editor writers. Direct legacy callflow writers are outside
  this guard. Recovery receipts expose `extension_claims` and
  `reserve_extensions`/`finalize_extensions` phases. Reservations have no expiry
  or automatic takeover; an ambiguous write requires explicit recovery.
  Source presence is labeled separately from deployment verification.

GET `/accounts/{ACCOUNT_ID}/members/devices` is implemented and now included in
the main catalog. It provides bounded member pages and owner_id device mappings
with fresh online/offline/unknown registration evidence. Unassigned/shared and
hotdesk relationships are not expanded. The account device cap is1000, with
explicit incompleteness above that limit; this is not unbounded company-device
traversal. See [live evidence and limits](members_devices_acceptance.md).
The planned spec remains available but currently contains no proposed routes.

## Rebuild and verify

The installer uses committed assets and requires no npm installation for docs.
Maintainers regenerate with the exact dependency lock:

```sh
cd /opt/kz5/scripts/api-docs-tooling
npm ci --ignore-scripts --no-audit --no-fund
cd /opt/kz5
node scripts/build-api-docs.cjs --output scripts/assets/api-docs
node scripts/verify-api-docs.cjs scripts/assets/api-docs
node scripts/test-api-docs.cjs
```

For the browser test, use a compatible Node/Playwright installation and existing
Chromium, setting `KAZOO_PLAYWRIGHT_MODULE` if the package is outside Node's normal
resolution path:

```sh
node scripts/test-api-docs.cjs --browser
```

The test serves only an ephemeral loopback HTTP server, with the same CSP as the
installer, blocks all nonlocal requests, validates both specs, checks negative
schema cases, proves deterministic regeneration, detects asset tampering, and
checks viewer authorization/execution safeguards. It does not call Crossbar.
The build fails on unresolved references or invalid OpenAPI structure. It does
not convert unknown upstream contracts into verified ones.

Swagger UI is pinned to `5.32.15`; its unmodified bundle, CSS, Apache license and
NOTICE are under `scripts/assets/api-docs/vendor/`, with SHA-256 hashes in the
manifest. Swagger Parser `10.1.1` is pinned for the installed Node 18 build
toolchain; the browser harness may require newer Node according to Playwright.
The lockfile retains tarball integrity for reproducible dependencies.

## Deployment boundary

`install_api_developer_docs` verifies committed hashes, refuses a symlinked
`apis` target, copies the static files after Monster UI's ownership-preserving deployment, and
verifies the deployed copy. Both TLS/non-TLS nginx branches have explicit `/apis/`
static locations that return a real 404 for missing assets instead of Monster's
SPA fallback. The normal installer tests nginx before restarting its service.

Publishing this portal alone does not deploy the queue-editor handler, enable
callback media or load monitoring backend modules. Those have separate build,
deployment and acceptance gates. Preserve existing live configuration and test
the exact nginx configuration before reloading; do not rerun an unrelated full
telephony installation merely to publish documentation.

## Post-recovery source refresh — 2026-09-06

After ACDC recovery merge `8548b98`, regenerated coverage binds the changed
agent listener and agent wire API source hashes. The members/devices schema now
requires page and member inventory completeness to agree; incomplete registrar
evidence cannot contain confirmed online/offline devices. Valid empty pages and
Crossbar's omitted-null response form remain supported.

Guarded session `26112` passed all 12 focused contract groups. Generator `2980`
and full offline session `14879` passed: 354 paths, 649 operations, 31 existing
negative schema cases, deterministic regeneration, current source bindings and
tamper checks. These checks neither authenticate live principals nor execute
telephony calls. Restricted-token/cross-account/expiry live acceptance is open.
OpenAPI SHA-256: `aaba0a3d9f75ca54ce498a139a86e1d31468b09fe1879e0289eaa45c1322e4b2`.
Manifest SHA-256: `fb90e2a7e392c68eb2987c75ca3526f8957f0b69a22e47a8d62450dd25413307`.

The committed static catalog was then published using the installer's actual
`install_api_developer_docs` function (session `8585`, exit zero). The previous
verified portal is retained at
`/usr/local/src/kazoo5-installer/api-docs-rollback.eXNs97/previous` (protected
parent). All eleven deployed files, including the manifest, match repository
bytes. Loopback HTTP with `Host: kz5.talkchief.io` verified `/apis` redirects
308, every asset returns 200 with exact bytes and `Cache-Control: no-store`,
and an unknown asset returns 404. No nginx reload, daemon restart, backend
module load, authentication request or call-state change was made.
This is HTTP static-publication evidence, not TLS or browser/runtime acceptance.

## Queue recovery reference refresh — 2026-09-06

Commit `c40f347` binds the repaired queue-editor source and documents exact
roster acknowledgement requirements and conservative recovery after lost
replies. It retains the dated historical live results but marks the latest
revision as not live verified. Generation `43015` and full offline regression
`78714` passed (354 paths, 649 operations, deterministic rebuild and tamper tests).

Publication `83187` then used the actual installer function and passed HTTP
readback for all 11 files, including no-store headers, the 308 redirect and
unknown-asset 404. Its manifest SHA-256 is
`b13291d25d97dde463d0bb2a12c5da1984abcd0bb6367842629d2e26ab343bf2`.
The verified previous catalog is retained at
`/usr/local/src/kazoo5-installer/api-docs-rollback.BmKTkE/previous` under a
0700 parent. Source files were unchanged across publication, and no services
were restarted or backend code loaded. This updates static documentation only;
HTTPS, real principals, callback audio and the new backend deployment remain
separate acceptance gates.
