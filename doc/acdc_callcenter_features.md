# Call Center feature implementation and acceptance

These requirements extend, rather than replace, the system-wide deployment,
voice, load, HTTPS, and production-readiness gates in
`kazoo5_acceptance_status.md`. The callback implementation and installer
integration are staged, but the complete telephone workflow has not yet passed
live restart/recovery and SIP/DTMF/RTP acceptance.

## Announcements and language

Queue configuration uses the existing authenticated Crossbar queue endpoints:
`PUT /v2/accounts/{account}/queues` and
`POST` or `PATCH /v2/accounts/{account}/queues/{queue}`.

- `moh`: caller hold media.
- `announce`: optional media ID or URI played once after agent selection and
  before the selected-agent notification is released.
- `announcements.position_announcements_enabled`: spoken live position.
- `announcements.wait_time_announcements_enabled`: estimated wait announcement.
- `announcements.interval`: seconds, minimum 15, default 30.
- `announcements.initial_delay`: seconds before the first announcement, minimum
  1, maximum 3600, default 30; independent of the repeat interval.
- `announcements.language`: optional lowercase locale; absent means inherit
  the call language. This controls both prompt lookup and spoken numbers.
- `announcements.media`: custom prompt identifiers for `you_are_at_position`,
  `in_the_queue`, `the_estimated_wait_time_is`, and `increase_in_call_volume`.
  The existing API schema requires all four when the media object is supplied;
  the runtime additionally handles partial older documents with safe defaults.

The default English-US position playlist is “Your current position is” followed
by the spoken position. A separately installed prompt preserves existing system
audio; explicit custom prompt selections and other languages keep their normal
prefix/number/suffix playlist. Kazoo prompt identifiers are resolved through the
media manager before FreeSWITCH playback. Source and isolated timing tests cover
the initial delay and cancellation; deployment and audible call acceptance are
tracked separately in the acceptance status.

Runtime tests cover inherited/overridden language, JSON/proplist normalization,
default media, missing position, unavailable wait statistics and intervals.
Unknown statistics must not be announced as an hour-long wait. An empty
playlist must not interrupt caller audio. Actual playback and interruption
behavior must still be checked with SIP calls.

The legacy top-level `announce` field was only stored by the queue FSM, not
played. Its new source implementation uses asynchronous playback/noop completion
before selecting-agent notifications, bounded playback time, hangup/max-wait
handling, and once-per-caller tracking. Twenty-four isolated checks pass. Audible
playback and interaction with periodic position announcements still require
live audible acceptance. The Monster ACDC source now contains the corresponding
optional media control and save/edit contract checks, but it must not be
deployed until that audible gate passes.

Locale syntax validation is not proof that audio exists. The pinned official
sound repository contains en-us, en-gb, nl-be, ru-ru, es-us, es-es, de-de, fr-fr
and fr-ca directories. Only en-us prompt attachments and local speech files
have been installed and verified so far. Additional selected languages need
prompt coverage, FreeSWITCH speech-module/configuration checks and audible
call acceptance; the user's desired languages are still being requested.

## Virtual callback requirements

### Queue editor and keypad behavior

In Monster UI, open **Call Center → Queues → Edit**. The **Virtual callback**
section controls enablement, entry digit, callback user, attempts, and retry delay.
The separate **Callback announcement** controls use:

- `callback.announcement.enabled`: default `true`, effective only when callback
  registration itself is enabled. Turning this off leaves the entry key active.
- `callback.announcement.initial_delay`: seconds before the first offer,
  default 30, range 1–3600.
- `callback.announcement.interval`: seconds between offer scheduling, default
  60, range 15–3600.

`announcements.initial_delay` and `announcements.interval` remain exclusive to
position/wait announcements. A single worker maintains independent monotonic
deadlines and combines prompts due together into one playlist. Audio already
queued may affect the exact audible start; these settings do not interrupt an
existing prompt to force an exact wall-clock start. Missed intervals do not
produce catch-up bursts. The worker is stopped during callback menus, queue
exit and connection; resuming the waiting caller starts both delays again.
Older queues without the new object use the new 30/60-second defaults once this
backend is deployed. The previous unconditional queue-entry offer is removed.

Source and private timer/browser tests do not establish live deployment or
received-audio timing. Record that acceptance separately before calling the
controls operational.

With `allow_alternate_number=false` (the default), the current source flow is
**6 → correlated queue pause → authorize and durably register the current
caller-ID destination → success audio → hang-up**. No additional registration
digit is required. This source contract must not be confused with acceptance
of an older deployed build that required **6 then 1**; record single-key live
acceptance separately.

With `allow_alternate_number=true`, 6 still opens the destination-choice menu:
1 confirms the valid current caller-ID number; 2 starts alternate-number entry,
then `#`, audible readback and 1 confirm that alternate. If current caller ID
is unusable, this opt-in mode starts alternate entry directly. The returned
outgoing call separately requires 1 before connecting to an agent in both modes.
An alphabetic SIP username is not a valid numeric callback destination. If
alternate-number entry is disabled, it cannot be registered as a return number.
Allowing alternate entry does not provision outbound caller ID or a carrier route.

The simplified editor removes the ten individual announcement/callback recording
selectors. Choose a supported installed language instead (EN, HE, AR, FR, ES);
unready packs remain disabled. Hold music and pre-connect media remain separate.
Existing custom overrides are preserved on unrelated saves and shown with a
warning; removing selectors does not delete recordings or clear those overrides.
Fresh queues use standard prompt IDs, including when older values are empty.
The API still accepts explicit overrides and retains its validation requirements.

`scripts/test-monster-acdc-language-only.cjs` checks real browser form validity
and serialization with no API writes. A standalone component also carries its
own `VERSION` file, matching `metadata/app.json`; that is the app version, not
the Kazoo server version.

The required flow is: an announcement offers a keypad callback option; the
caller confirms the return number, hangs up, retains queue priority/position,
and is called back when eligible. The return call requires keypad confirmation
before connecting to an agent, so voicemail cannot accept the queued call.

Required invariants and acceptance cases:

1. A callback is registered against a real waiting member of the authenticated
   account and queue. Repeated requests are idempotent and cannot add duplicate
   reservations or move the caller forward.
2. Registration must be acknowledged before the caller hears success and is
   disconnected. Failure or timeout must preserve the live waiting call.
3. Preserve original ordering/priority in the same queue, not a separate
   best-effort redial list. Callers who arrived earlier remain earlier.
4. Preserve accepted reservations across worker/node restarts, with atomic
   ownership of each outbound attempt so competing nodes cannot double-dial.
5. Honor destination normalization and account calling restrictions. Alternate
   return numbers need explicit configuration/validation; caller-supplied
   strings must never become raw FreeSWITCH dialstrings.
6. Bound answer/confirmation time, retries, retry delays and reservation
   lifetime. Wrong digits, no answer, busy, voicemail, agent failure, hangup,
   cancellation and successful completion must have distinct tested outcomes.
7. Provide authenticated account-scoped configuration and callback visibility/
   cancellation APIs, corresponding UI controls/status, language-aware prompts,
   and documented error responses. Do not expose controls before their backend
   behavior exists.
8. Test real SIP/DTMF/RTP with multiple ordered callers, including a callback
   leaving and rejoining, duplicate requests, restart recovery and cancellation.
   Unit tests or API persistence alone cannot pass this feature gate.

## Callback implementation reference

Public MPL-licensed reference source was checked out read-only at
`/usr/local/src/kazoo5-installer/kazoo-classic-reference`, revision
`c57b3ac0a477302aa04098369502d4be715e15c7`. The original port commit
`feba033e1b450ee9aeaa52aef1a74cc6c4a8a88f` is also available locally for review.
This reference has not replaced the user's community ACDC source.

It provides a `breakout` queue configuration, caller confirmation menu in
`cf_acdc_member`, callback registration messages in `kapi_acdc_queue`, manager
callback tracking, queue-worker callback handling, and agent
`ringing_callback`/`awaiting_callback` states with outbound origination.
The full historical port also changes many unrelated features; it must not be
applied wholesale without review. Registration acknowledgement, durable
reservation recovery and outbound-human confirmation require specific review
and tests rather than assuming the reference satisfies the requirements.

The implementation below was adapted as narrowly reviewed Kazoo 5 integration;
the historical reference was not applied wholesale.

## Durable callback implementation (live acceptance pending)

`acdc_callback_store` and its `acdc_callbacks/by_queue` account view are captured
in the reproducible ACDC integration patch. Registration is wired only to the
trusted live queue-member protocol; there is intentionally no public callback
creation endpoint.

- Deterministic account/queue/original-call identity, immutable original enqueue
  time/sequence/priority, and idempotency without resetting finished records.
- Revision-CAS attempt claims, private ownership tokens, caller UUID persisted
  before origination, explicit agent-leg binding, and caller-leg-specific
  answer/confirmation/bridge transitions.
- Bounded retries/delays/lifetime, tenant/queue checks, numeric destination
  syntax only, and allowlisted failure causes. Actual destination normalization
  and account calling restrictions remain dispatch-layer requirements.
- Waiting cancellation is immediate. In-flight cancellation is `cancelling`
  and retains private channel/lease metadata for cleanup; it is not falsely
  reported as a terminated phone call.
- An expired active lease explicitly requires channel reconciliation; it never
  gives permission to redial. The queue recovery coordinator collects fresh
  per-eCallMgr channel observations and the correlated FreeSWITCH originate
  result before it can cancel, settle, rebind, or complete a bridge. Missing,
  stale, duplicate, conflicting, timed-out, or post-FreeSWITCH-restart evidence
  is `unknown` and fails closed without a second originate.
- Paginated per-queue listing and an explicit projection are provided internally.
  The HTTP API must additionally omit phone numbers, original-call identifiers,
  private leases and routing metadata unless a separately reviewed permission
  and use case requires them. Stored enqueue order is not a live queue-position
  estimate and must not be mislabeled as one.

Run `scripts/test-acdc-callback-store.sh` for the isolated store regressions.
The opt-in live probe
`KAZOO_TEST_CALLBACK_STORE=true scripts/test-acdc-live.sh` also passed against
a new temporary account: idempotence, conflicting registration, one real
CouchDB claim winner, cancellation and queue-scoped listing. Its fixture was
deleted. This caught and fixed a compatibility error: the pinned Couchbeam
requires the `include_docs` atom and silently drops `{include_docs,true}`.

## Callback HTTP and menu contracts (staged; live acceptance pending)

The reviewed Crossbar adapter intentionally has no public callback creation
method. Creation remains a trusted queue-coordinator operation. Its
authenticated, account-and-parent-queue-scoped surface is:

- `GET /v2/accounts/{account}/queues/{queue}/callbacks` for a bounded list;
  `page_size` is capped at 100 and `cursor` is an opaque, queue-scope-validated
  base64url JSON cursor (it is not cryptographically signed).
- `GET /v2/accounts/{account}/queues/{queue}/callbacks/{callback}` for detail.
- `DELETE /v2/accounts/{account}/queues/{queue}/callbacks/{callback}` for
  idempotent cancellation. Waiting records become `cancelled`; active records
  become `cancelling` until their live-leg cleanup completes.

The response allowlist contains `id`, `queue_id`, `status`, `attempts`,
`enqueued_at`, `enqueue_sequence`, `priority`, `language`, `next_attempt_at`,
`expires_at`, `last_cause`, `created`, and `modified`. It explicitly excludes
the callback number, original call ID, lease, caller/agent leg IDs and every
private field. It does not report a synthetic queue position. Store states are
`registering`, `queued`, `dialing`, `confirming`, `connecting`, `retry_wait`,
`cancelling`, `completed`, `cancelled`, `failed`, and `expired`.

Draft HTTP failures are `400` for a malformed cursor, `404` when the parent
queue or queue-owned callback is absent, `409` for a revision conflict or an
attempt to cancel an already finished reservation, and `503` for unavailable
storage. Parent queue lookup must succeed before any callback store operation.

The pure reducer emits a registration request immediately after the entry-key
and pause workflow when the current number is valid and alternatives are
disabled (the default). There is no second registration confirmation key in
this mode. Destination-choice menus retain confirmation key `1`, alternate-number
key `2`, three input retries, a 30-second absolute menu/registration deadline,
and a separate 10-second success-playback deadline. Alternate-number collection
must be deliberately enabled; when enabled it accepts
at most 15 digits, `#` finishes collection and reads the number back, a second
confirmation is required, and `*` cancels. Success requires a trusted durable
ack correlated by queue, original call and request; the accepted reservation is
handed off before success playback and the original leg ends only after the
correlated playback completion (or its bounded failure/timeout path). The caller
flow does not register or open a menu until the queue FSM acknowledges its pause, and it
resumes the same queue slot after invalid input, timeout, or registration
failure. Queue ordering, restart recovery, actual returned calls and human DTMF
remain live gates; the persistence probe never originates a call.

The staged queue schema and Monster source use `callback.enabled=false` by
default. Bounds are: `max_attempts` 1–10 (default 3), `retry_delay` 15–3600
seconds (default 60), `ttl` 60–86400 seconds (default 3600),
`originate_timeout` 5–300 seconds (default 60), `ready_ack_timeout` 1–10
seconds (default 5), returned-caller `confirmation_timeout` 3–30 seconds
(default 10), `handoff_timeout` 1–10 seconds (default 5),
`menu_timeout_ms` 1000–120000 (default 30000), and `success_timeout_ms`
1000–30000 (default 10000). `entry_key` defaults to 6; returned-caller
confirmation is fixed to 1; alternate-number entry uses 2 and remains disabled
unless `allow_alternate_number` is explicitly enabled. The UI rejects conflicts
between these active digits and the ordinary queue exit key.

`callback.use_local_resources` defaults to `false`. When explicitly true, the
policy sets `Hunt-Account-ID` only to the already authenticated current account;
it cannot select another tenant's resources. This supports a tenant-owned
carrier while retaining the ordinary stepswitch selection and restriction path.

Outbound attempts require an enabled, account-owned
`callback.outbound_authority` (`id` plus `type` of `device` or `user`) and an
account-owned `callback.outbound_caller_id` (`number` and `name`). These fields
are configuration, not delegated authorization: ownership, endpoint state,
number normalization, caller-ID ownership and call restrictions are rechecked
before registration and every attempt.

Optional language-aware prompt/media overrides are
`callback.media.offer`, `menu`, `number_readback`, `confirmation`, `success`,
and `returned_confirmation`. The canonical returned-caller field supersedes
legacy `callback.return_confirmation_prompt`; staged UI reads the legacy value
only when the canonical field is absent and writes only the canonical field.
The pinned sounds package contains no historical `breakout-*` prompts, so the
installer generates 16 deterministic English-US prompts: one offer for each
possible entry digit, separate current-number-only and alternate-number menus,
number readback, confirmation, success, and returned-caller confirmation.
Configured media always wins. A non-English call without every required
localized override fails closed to the normal live queue instead of silently
playing English. Only English-US callback media has been installed so far.

The source-only acceptance fixture uses an account-local resource restricted to
the NANP fictional range `+12025550100` through `+12025550199` and a SIPp
gateway on `127.0.0.30:16060`. It exercises the real number-ownership,
authority, call-restriction and stepswitch path; it does not inject channel
authorization or expose a PSTN route. Running
`scripts/test-acdc-callback-calls.sh --prepare-only` validates the protected
fixture helper and both SIP scenarios without changing APIs or sending traffic.
The live flow remains pending after the aggregate ACDC deployment.

All Erlang regression tests must compile into isolated temporary directories.
Do not run `make eunit` or `make compile-test` in the live shared source tree:
those targets can overwrite service beams, including shared dependencies, with
test-only behavior. A production rebuild/mode audit is mandatory after any such
contamination; ordinary timestamp-based `make all` does not necessarily fix it.

## Queue wait-time regression

`cf_acdc_member` now measures its finite wait from the original monotonic
entry time. The previous per-message whole-second decrement could extend a
wait indefinitely under frequent subsecond events. Four isolated tests cover
subsecond progress, expiry, infinite waits and bounded OTP timer chunks.
Live short-timeout tests with repeated caller events remain part of acceptance.
