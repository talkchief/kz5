# ACDC and cluster call-control API reference

Implementation review: 2026-09-05. This describes this project's API, not every
commercial Kazoo product. Features marked **pending** are not yet a verified
deployed contract. See [acceptance status](kazoo5_acceptance_status.md) for live
evidence and outstanding gates.

## Authentication and conventions

All paths below have the `/v2` prefix. Account-scoped paths start with
`/accounts/{account_id}`. Send `X-Auth-Token` and `Content-Type: application/json`.
Write bodies use `{"data": {...}}`; read the response envelope's `status` and
`data`, not HTTP success alone. Examples contain placeholders, never credentials.
Obtain an authentication token through the existing `/user_auth` API. Protect
tokens in a secret store; do not put them into source, URLs, or diagnostic logs.

Use HTTPS for remote API clients. This server's HTTPS deployment is still blocked
on the matching certificate private key; plain HTTP is not an acceptable
production credential-transport substitute.

An account's calls may live on multiple FreeSWITCH nodes. Clients address account
and call IDs, not media-node names or direct FreeSWITCH commands. Cluster routing
does not grant cross-account access.

## Queues and Callflows

| Method | Account-relative path | Purpose |
| --- | --- | --- |
| GET | `/queues` | List queues. |
| PUT | `/queues` | Create a queue. |
| GET | `/queues/{queue_id}` | Read queue configuration. |
| POST | `/queues/{queue_id}` | Update the queue document. |
| PATCH | `/queues/{queue_id}` | Change selected queue settings. |
| DELETE | `/queues/{queue_id}` | Delete a queue; review attached routes first. |
| GET | `/queues/{queue_id}/roster` | Read configured agent IDs. |
| POST | `/queues/{queue_id}/roster` | Replace the complete roster with the `data` array; omitted existing agents are removed. |
| DELETE | `/queues/{queue_id}/roster` | Clear the entire roster; this handler does not use a selective request-body list. |
| GET | `/queues/stats` | Read account queue statistics. |

The deployed handler is the authority for supported paths. Older upstream
comments mention additional queue-specific statistics routes that this handler
does not expose; do not assume those routes work.

A callflow enters a queue with this node:

```json
{
  "module": "acdc_member",
  "data": {"id": "QUEUE_ID"},
  "children": {}
}
```

Monster UI's **Callflows → Advanced actions → ACDC Queue** provides this node
and an account-specific queue picker. The extension belongs to the enclosing
callflow's `numbers` array, not the queue document. Existing callflows may contain
other nodes and branches: preserve them when editing.

## Agent availability and queue membership

| Method | Account-relative path | Purpose |
| --- | --- | --- |
| GET | `/agents` | List agents. |
| GET | `/agents/{agent_id}` | Read an agent. |
| GET | `/agents/status` | Read agent status information. |
| GET | `/agents/{agent_id}/status` | Read one agent's status information. |
| POST | `/agents/{agent_id}/status` | Change availability. |
| GET | `/agents/{agent_id}/queue_status` | Read saved enrollment; opt-in runtime query checks one selected queue. |
| POST | `/agents/{agent_id}/queue_status` | Legacy enrollment change, or opt-in runtime-only queue login. |
| POST | `/agents/{agent_id}/restart` | Request a scoped agent restart; platform/superduper-admin only. |
| GET | `/agents/stats` | Read agent statistics. |
| GET | `/acdc_call_stats` | Read historical call statistics in JSON or supported CSV representation. |

Availability body:

```json
{"data":{"status":"login"}}
```

Supported status actions include `login`, `logout`, `pause`, `resume`, and
`end_wrapup`. Pause can include a nonnegative `timeout` in seconds. A status
update acknowledgment means the command was sent; verify the resulting state.
Changes requested during a call can take effect after that call finishes.

Legacy queue-enrollment body (intentionally changes saved enrollment):

```json
{"data":{"action":"login","queue_id":"QUEUE_ID"}}
```

Use `logout` to leave that queue. Queue membership, agent availability, and SIP
registration are distinct. Adding a roster entry does not register a phone.
Status responses can contain timestamp-keyed history; do not treat every record
as a separate currently logged-in agent. Device registration status is a separate
`GET /devices/status` API; registration collection has an additional staged race
fix described in the acceptance status.

To remove selected roster members, POST the complete intended remaining roster
or use each agent's `queue_status` logout. Do not issue a roster DELETE expecting
only the IDs in its body to be removed.

### Runtime-only login to an already-enrolled queue — source candidate

This opt-in contract and its Monster UI dialog are source changes under review,
not a claim that a live deployment has been updated. The route retains normal
Crossbar authentication and account-scoped authorization. The selected user must
be enabled, not deleted, owned by the account, and already enrolled in the selected
existing account-owned queue. Login never adds a saved roster membership.

First probe the runtime-only GET, including all three query parameters:

```text
GET /accounts/{account_id}/agents/{agent_id}/queue_status?runtime_only=true&action=login&queue_id={queue_id}
```

A legacy array reply reports saved enrollment only: it does not prove support
for runtime-only mode or confirm runtime membership. Do not submit the new login
body to an older server based on that array. With the new handler, request one
selected queue explicitly:

```json
{"data":{"runtime_only":true,"action":"login","queue_id":"00000000000000000000000000000000"}}
```

POST responds **202 Accepted**, with `state:"pending"`, `confirmed:false`,
`runtime_member:false`, `runtime_observed:false` and `agent_status:"unknown"`.
This means the command was published, not that the agent joined the queue.
The response also echoes `account_id`, `agent_id`, `queue_id`, `action:"login"`
and `runtime_only:true`. Poll the same runtime-only GET to check membership.
GET responds 200 with those same fields and either:

- `state:"confirmed"`, `confirmed:true`, `runtime_member:true`,
  `runtime_observed:true`: a fresh correlated reply from the exact agent/account
  listener includes the selected queue. The separate `agent_status` can still be
  paused, ringing or another state; membership is not readiness or ringing proof.
- `state:"pending"`, `confirmed:false`, `runtime_member:false`: no selected-queue
  membership confirmation. `runtime_observed:true` means the fresh listener reply
  omitted the selected queue; false means no usable reply arrived.

Each runtime check is bounded to a two-second AMQP wait. Missing, old, malformed,
stale or foreign replies remain pending; a global Ready event is insufficient.
The runtime-only handler sends `Cache-Control: no-store`, including its own error
responses. Pre-handler authentication/resource-loading errors retain their normal
Crossbar behavior. Do not automatically repeat a POST after an ambiguous timeout.

Runtime-only accepts `login` only; omit `runtime_only` entirely for the legacy
enrollment-changing contract. An explicit false/malformed flag, non-login action
or missing/invalid queue ID returns 400. Disabled/deleted/foreign users or absent
enrollment return 403; missing, deleted, wrong-type or foreign queues return 404;
datastore/publication failures return 503. Existing authentication and resource-load
errors remain unchanged. Queue IDs are nonempty strings of at most 128 bytes.
Enrollment is rechecked during validation, POST execution and AMQP consumption.

An existing agent process keeps its status and other runtime queues. A newly
started process initially receives only the selected queue. No other agent is
started or logged out, and no user/queue document is saved by runtime-only mode.
Later ordinary platform configuration refreshes retain their existing semantics.
Confirmation does not prove queue-manager acknowledgement, SIP registration,
endpoint reachability, audio, or that the next call will ring.

The candidate UI requires an explicit configured-queue selection, probes support
before enabling submission, and makes at most six post-command GET checks. It
shows pending on uncertainty and offers a read-only Check status action; it never
reposts automatically. “Queue membership confirmed” is separate from global agent
status and expires after 30 seconds unless checked again.

## Announcements

The queue API accepts an `announcements` object. Existing fields are:

| Field | Meaning |
| --- | --- |
| `position_announcements_enabled` | Enable spoken queue position. |
| `wait_time_announcements_enabled` | Enable estimated-wait announcements. |
| `interval` | Repeat interval in seconds; minimum 15, default 30. |
| `language` | Lowercase locale, for example `en-us`; absent inherits call language. |
| `media` | Optional queue prompt overrides; see the feature reference. |
| `initial_delay` | Delay before the first announcement; default 30 seconds, range 1–3600. |

The intended delayed-position configuration is:

```json
{"data":{"announcements":{
  "position_announcements_enabled":true,
  "wait_time_announcements_enabled":false,
  "initial_delay":30,
  "interval":30,
  "language":"en-us"
}}}
```

The deployed English-US live audio test (2026-09-05, 09:24 UTC fixture) captured
the full phrase “Your current position is one” twice. The first phrase started
30.261 seconds after the correlated queue-entry event; the next began 29.879
seconds later (within the test's documented ±250 ms media-delivery jitter).
Playback stopped and the owned worker/channel disappeared after hangup.
Only English-US has passed this audible acceptance so far. EN, AR, HE, ES and
FR are requested; additional language assets and spoken-number handling remain
under implementation. A syntactically valid locale does not install audio.

## Virtual callbacks

Configuration is stored under the queue's `callback` object. For the complete
field bounds, outbound-authority checks, prompt overrides, and state machine,
see [Call Center features](acdc_callcenter_features.md#callback-http-and-menu-contracts-staged-live-acceptance-pending).

In the current runtime, the caller worker waits for returned-call confirmation
internally. The durable `caller_answered` and `caller_confirmed` transitions are
written together after the accepted digit, so polling may never observe
`confirming`. Do not use that transient database status to measure the audible
confirmation wait. `completed` records a durable handoff, not the end of the
subsequent conversation; cancelling a completed callback does not authorize
hanging up that conversation. See [callback acceptance](acdc_callback_acceptance.md)
for packet-level confirmation and live bridge evidence.

### Callback user and inherited outbound identity

The simplified configuration selects an enabled account-owned user by name:

```json
{"callback":{
  "outbound_authority":{"type":"user","id":"USER_ID_FROM_THE_USER_SELECTOR"},
  "caller_id_source":"inherit"
}}
```

`outbound_authority` is the internal authorization reference, not a telephone
number or credential. No caller-ID or technical identifier needs to be typed in
the new UI. At registration and before every dial attempt the policy reads the
current user and account: it inherits the user's `caller_id.external.number`
and name, with account external caller-ID defaults for absent fields. If no
external caller name is configured, the user/account display name is used.
Missing, malformed or unowned caller-ID numbers fail closed; the system does
not guess a number. Account/user enablement and call restrictions are still
enforced. This change has passed 17 isolated policy tests and is deployed with
the named-user/dropdown UI.

For an explicit account-number selection, use `caller_id_source: "custom"`
and `outbound_caller_id: {"number": "+12025550100"}`. The optional name still
inherits when omitted. An explicit legacy name is preserved. When
`caller_id_source` is absent, an existing explicit identity remains unchanged;
only a queue without an override inherits automatically. There is deliberately
no schema default that would change existing queues' outbound identity.
Legacy device-authority configurations remain supported until deliberately
changed. Caller identity inheritance is not an override of routing policy or
permission to call a destination that the user/account forbids.

### Return destination is separate from the callback user

The current source contract distinguishes registration from returned-call
acceptance. With `allow_alternate_number=false` (default), pressing the queue's
`entry_key` (default **6**) requests registration of the valid current caller-ID
destination after a correlated queue pause. There is **no additional 1** on
the original call. The queue must authorize and durably persist the reservation
before success audio; the original leg ends after that audio's correlated
completion or its bounded failure/timeout path. Publication alone is not success.

With `allow_alternate_number=true`, the caller instead hears the destination
menu: **1** selects the valid current number, or **2** collects an alternate,
followed by **#**, audible readback and **1** to confirm. On the returned call,
**1** remains a separate acceptance step before the agent connection in either
mode. An older **6 then 1** acceptance receipt does not prove the new single-key
behavior; deployment and live verification are recorded separately.

All built-in audio uses prerecorded release WAVs in EN, HE, FR, ES or AR.
Gemini is a one-time authoring tool only, never a provider dependency during
installation, service startup, queue/account creation or a live call.

| Value | Purpose |
| --- | --- |
| Callback user / outbound authority | The account-owned identity authorizing the outgoing attempt and supplying restrictions/defaults. It is not automatically the recipient. |
| Outbound caller-ID number | The owned telephone number presented by the return call, inherited from the selected user/account or explicitly selected. |
| Callback destination | The original caller's valid numeric caller ID, or the number the caller enters and confirms when alternate entry is enabled. |

A SIP login name is not a dialable return number. If current caller ID is invalid
and `allow_alternate_number` is false, the menu returns to the live queue and
does not register a callback. With alternate entry explicitly enabled, the
repaired menu starts with an audible number-entry prompt, reads the entered
number back, and still requires confirmation. This does not relax number,
account, caller-ID ownership, or outbound routing checks.

The outgoing callback uses Stepswitch originate routing. An ordinary internal
extension callflow alone is not a return route: the destination must resolve as
a provisioned on-net telephone number or match an authorized outbound resource.
Selecting a callback user cannot supply a missing owned caller-ID number, SIP
carrier, or return destination. No carrier or PSTN numbers are automatically
created by enabling the queue setting.

| Method | Account-relative path | Purpose |
| --- | --- | --- |
| GET | `/queues/{queue_id}/callbacks` | Bounded callback list; `page_size` maximum 100 and opaque `cursor`. |
| GET | `/queues/{queue_id}/callbacks/{callback_id}` | Read a queue-owned callback. |
| DELETE | `/queues/{queue_id}/callbacks/{callback_id}` | Request idempotent cancellation. |

There is intentionally no public create-callback API. Only the trusted live
queue-member selection and authorized durable-registration workflow may reserve a position. This prevents an
arbitrary API caller from inserting requests ahead of waiting callers.

When the list envelope contains `next_cursor`, pass it unchanged as the next
request's `cursor` query parameter. Do not construct or reuse another queue's cursor.

Waiting cancellation becomes `cancelled`. An in-flight request can remain
`cancelling` until positive channel/originate settlement is established; that
response is not proof a live telephone leg has already ended. Unknown media-node
state fails closed, rather than allowing a duplicate dial.

Public responses expose callback identity, queue, state, attempt count, original
enqueue ordering, language, timestamps, expiry and safe failure causes. They omit
telephone numbers, private leases, routing metadata and caller/agent leg IDs.
When recovery is unresolved they may expose `reconciliation_required` and an
allowlisted `reconciliation_reason`. Enqueue order is not a calculated live
queue-position value.

Relevant errors include 400 for invalid input/cursor, 404 for a missing or
wrong-parent object, 409 for conflicts or a non-cancellable completed record, and
503 for unavailable storage. Authentication/authorization failures remain 401/403.

The original caller's DTMF menu and durable reservation now work in the isolated
telephone fixture. Full returned-call, human-confirmation, preserved-order,
agent-bridge and restart-recovery acceptance is **not yet complete**.

## Call supervision — deployed APIs, single-server acceptance passed

Account-wide endpoint (not restricted to ACDC):

```text
POST /v2/accounts/{account_id}/channels/{target_call_id}
```

All four modes passed isolated single-server SIP/audio and authorization checks
on 2026-09-05, 11:29–11:31 UTC. Earlier bridge compatibility and stop-response
normalization failures were repaired before that successful run. An HTTP 202
response alone never proves a connected monitoring leg, and these local tests
do not prove multi-node routing/failover. See
[the monitoring acceptance record](channel_monitor_acceptance.md) and the
**Call supervision** section of the current source catalog at `/apis/`.

```json
{"data":{"action":"whisper","device_id":"SUPERVISOR_DEVICE_ID","timeout":30}}
```

| Action | Supervisor audio |
| --- | --- |
| `eavesdrop` | Listen only. |
| `whisper` | Speak only to the selected target leg, normally the agent. |
| `barge` | Speak to both parties in a three-way conversation. |
| `join` | Alias for `barge`; retains the original agent, not a takeover. |

Enforced restrictions: exact account authentication and account-admin permission;
an enabled account-owned SIP supervisor device; timeout 5–60 seconds; fresh
target ownership and active-leg verification on the actual FreeSWITCH node.
Clients cannot supply raw endpoints, dialstrings, media-node names, or commands.
Supervisor keypad input cannot escalate the selected monitoring mode; the live
audio checks also repeated after digit 3. Use `eavesdrop`, not `spy` or `listen`,
as the API action name.

A successful monitoring request returns HTTP 202 with `status: accepted`,
`request_id`, `supervisor_call_id`, `target_call_id`, and `action` inside `data`.
It means the supervision request was accepted, **not that the supervisor has
answered or connected**. Observe channel events and state for completion.

Supervisor-only termination:

```text
POST /v2/accounts/{account_id}/channels/{supervisor_call_id}
```

```json
{"data":{"action":"stop_monitoring","request_id":"MONITOR_REQUEST_ID"}}
```

Termination verifies the supervisor marker, account and request correlation,
and ends only the supervisor leg. The recorded live run verified that both
original legs survived supervisor stop in all four modes.

Do not use the legacy `/queues/eavesdrop` routes as a working fallback: this
checkout has no consumer for their `eavesdrop.resource.req` message. The new
implementation uses the existing node-targeted originate protocol instead.
The upstream [monitoring mode descriptions](https://docs.2600hz.com/call-center/call-center/features/monitoring/)
refer to commercial Call Center Pro; they do not establish that those endpoints
exist or work in this community deployment.

Required verification includes cross-account/non-admin rejection, stale or
ambiguous node evidence, disabled/wrong-owner devices, request correlation,
supervisor-only termination, target hangup, and three-leg audio isolation:
customer audio must never contain a supervisor whisper. A single-node test is
not proof of cluster failover or multi-node routing.
