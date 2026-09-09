# Mobile push bridge: modular installation and validation

September9 watchdog correction: hard broker-loop stalls now use exit78, matching
the existing uncertain-delivery no-replay policy. Exit1 previously allowed
systemd automatic restart despite unknown dispatch/ACK state. Ordinary idle
reconnect is unchanged. See [watchdog restart safety](../../doc/push_bridge_watchdog_replay.md)
for regression, deployment evidence and the manual-recovery availability limit.

## Current deployment checkpoint — September 8

Main-SH installation and independent verification pass74779/c9f0f1. Current
development release is `0a3a5ba26bdf26caa9fea2343fb565c3ce218079cf976eb5be801ac9143e94da`;
source205 tests and installer smoke checks pass82499/98c851. It includes
unfinished-worker deadlines and bounded process exit78 before blocked cleanup;
see [worker deadline](../../doc/push_bridge_worker_deadline.md).
Registered-consumer readiness is verified, not actual mobile ringing.
Quorum/freshness/counted retries remain opt-in; native production traffic is
not connected to this development acceptance queue. Actual registered-consumer
retry passed83390/9d4620 with synthetic503/200 outcomes and isolated local
broker resources: companion progress, counts0→1, exhaustion0→1→2 and DLQ
readback. Zero provider calls, stable source pins and exact resource cleanup.
See [focused acceptance commands and receipts](../../doc/focused_acceptance_20260908.md).
DLQ-failure retention, remote AMQPS and designated-phone tests remain open.

The following implementation checkpoints retain historical release identities;
they do not supersede the current release above.

Explicit strict-quorum FCM500/503 retries without Retry-After are a source candidate only.
See [counted retry policy and open broker acceptance gates](../../doc/push_bridge_counted_retry.md).
The retry setting is not activated; legacy behavior and topology remain unchanged.
The code is installed on development as release `b20944143ade6ae0ad3ffb4c4c69094305348d7220f890669ca57606fb3810f8`:
main-SH install `feccd8/4664d3` and independent verify `b0c4d8/02b4a6` pass.
Isolated real-broker retry acceptance passes `feecd1/ac00b2`; no provider sends
were made. Actual Android/iOS delivery remains open. The installer now also
rolls back a distinct previous release when post-start verification fails;
seven isolated rollback scenarios pass `943abf/2ca19d`.

Versioned producer expiry is now available as an explicit quorum-only opt-in.
See [freshness configuration, tests and release boundaries](../../doc/push_bridge_freshness.md).
It does not silently change legacy routing or prove real phone delivery.

## Main installer integration (development installation verified)

Verified `quorum-v1` mode now quarantines malformed payloads and conservative
provider-specific permanent rejections without stopping the next delivery.
All145 bridge tests and an actual isolated broker proof pass. Legacy routing and
transient/uncertain outcomes remain unchanged. See
[`permanent quarantine`](../../doc/push_bridge_permanent_quarantine.md).

New explicit `quorum-v1` topology and fresh policy/queue verification pass132
offline tests plus actual isolated broker declaration/dead-letter/policy-refusal
acceptance. Main SH includes both new modules. Legacy behavior remains default;
no native traffic is migrated automatically. See
[`doc/push_bridge_quorum_topology.md`](../../doc/push_bridge_quorum_topology.md)
for protected configuration, bounded limits, same-host management requirements
and the remaining retry/freshness/fault-injection/device gates.

Latest AMQPS update: strict optional broker TLS and protected CA parsing pass112
bridge tests and installer dispatch (`0d2bfe/b60ebe`). Main-SH deployment
`1ff54f/02ae6d` and independent verify `9f2d32/f1ad28` pass. Enabled active
consumer PID323748, zero automatic restarts, release
`24e085e77183a418ded9df942a6dd16dc5883eacb2e7ca30d85a3cc7e4ab6c76`.
Development still uses its isolated local plaintext broker; real remote AMQPS
and mobile-device delivery remain open. See `doc/push_bridge_amqp_tls.md`.

Latest OAuth transport update: dedicated reusable session,3.05-second connect
and5-second read timeouts, redirect rejection and a64KiB decoded-body cap before
Google-auth parsing. This is not a total refresh/send deadline. All103 bridge
tests plus installer dispatch pass `325b4d/c536f1`; main-SH deploy
`3f5035/aa39ab` and independent verify `67c5ba/a1b50e` pass. Current release
`5d3745fd54bc8297f586c8ebb9c8e917de410957d9f02b6c04070c75997b5afa`,
enabled active consumer PID301642, zero automatic restarts. No provider push or
production change. See `doc/push_bridge_oauth_deadline.md` for exact scope.

Latest FCM concurrency change: each send exclusively leases an HTTP session
through both attempts, then returns it for connection reuse. The pool cannot
exceed the configured FCM worker count; excess direct calls return a fixed
capacity failure instead of allocating indefinitely. Closing rejects new work
and waits for the last active send before closing every retained session, even
if closing an earlier session fails. FCM sessions ignore ambient proxy/netrc
configuration and keep normal certificate verification enabled.

All88 bridge tests plus installer dispatch pass (`0f958e/5f962f`), including
real pinned-Requests adapters with simultaneous workers, capacity rejection,
session reuse, exception release and deferred shutdown. The old shared-session
implementation fails the concurrent-send and multi-session-close cases
(`5a4c73/2c5540`, two focused baseline regressions). This is not
real provider delivery or proof of bounded OAuth/whole-operation latency.
Main-SH deployment `01728e/abcc83` passes; release
`c36d971f6f8a1630af942cc1e8b7ee51c3adced67d6d124c500caea329a04db2`, enabled
active consumer PID259472, automatic restarts0. Previous release retained.

September7 root acceptance: the main SH installed Python3.11 and all18
hash-locked packages, passed dependency/version checks, enabled and started
`kazoo-push-bridge.service`, and verified actual consumer registration
(`d789ab/55d3b0`). Separate `--verify-only push-bridge` passed
(`d6a984/c0c60f`). It runs as the dedicated service user with zero automatic
restarts at initial readback. The development configuration uses a separate
local acceptance exchange/queue, not the production broker or production queue.
The configured FCM and both APNs signing keys load with the installed SDKs as
that service user in a network-isolated check (`b5fb19`); this does not validate
provider permissions or delivery. Production bridge state/PID stayed unchanged.
Credentials and populated configuration remain outside Git. See
`doc/push_bridge_development_acceptance.md` for scope and remaining gates.

FCM transport checkpoint: six additional offline tests (`be4d36`) use the
installed pinned Requests session/response implementation and a socket-free
adapter. Sends now disable redirects and stream responses without reading their
bodies. A response hook rejects all3xx before Requests can prepare a redirect
and consume its body, even with redirects disabled. Responses are closed on
success, rejection and server retry. Tests cover8 redirect statuses,5 client
statuses, success, server retry and fixed-category transport failures. Prior79
bridge tests and installer dispatch still pass (`a6ee6e/73b78f`). This does not
bound OAuth refresh, resolve shared-session concurrency or prove mobile delivery.
Run the new fixture using the installed bridge venv under network isolation:

```sh
/usr/local/lib/kazoo-push-bridge/current/venv/bin/python -B -I scripts/test-push-bridge-fcm-transport.py
```

Use `sudo bash scripts/install-kazoo5.sh push-bridge`, or `--verify-only
push-bridge` to verify. Aliases: `bridge`, `mobile-bridge`, `kazoo-push-bridge`.
`ALL` now includes the bridge. Missing protected mobile configuration rejects
bridge/ALL **before host mutation**, instead of silently omitting the component.
Other selected modules do not require mobile credentials. `--dry-run
push-bridge` prints the plan without reading credentials or sending traffic.

Prepare `/etc/kazoo-push-bridge/config.json` from `config.json.example`, with
reviewed broker host/user/password, queue and binding. Put service-account JSON
and optional Apple key files directly in the same directory. Start with root
ownership, directory0700 and files0600. Explicit installation changes that
directory to root:kazoo-push-bridge0750 and only the validated files to0640.
Symlinks, writable ancestors, duplicate/unknown keys, oversized files and
alternate OAuth token endpoints are rejected. Configuration is JSON data,
**never shell code**; values including numeric settings are strings.
Do not commit populated configuration. APNs fields use the runtime names below.

The separate mobile broker settings support standalone and co-located nodes:
selecting only bridge never installs/reconfigures RabbitMQ or Kamailio.
Do not point a development consumer at the production mobile queue. The new
installer-managed bridge supports verified remote AMQPS explicitly with
`PUSH_BRIDGE_AMQP_TLS="true"`; port5671 alone never enables TLS. Existing local
AMQP remains available with TLS absent or `"false"`. Remote TLS deployment and
broker acceptance have not been performed by this source change.

Installation provisions Python3.11 and a private venv with hash-verified wheels
only; checks exact versions against `requirements.lock`; and stages root-owned
content-addressed releases under `/usr/local/lib/kazoo-push-bridge/releases/`.
The current lock targets Rocky9 x86_64; other architectures fail explicitly.
Previous releases remain available; failed new service start attempts rollback
to the previous link/unit. Dependencies/configuration are validated before
publishing a new current link. No fabricated release-ready marker is used.

`kazoo-push-bridge.service` runs as a dedicated non-login user and is enabled
and started by the main SH. `Type=notify` waits for actual AMQP consumer
registration, not just process creation. Startup90seconds, shutdown15seconds,
memory384MiB, no swap/core dumps, three starts per five minutes. Status2/78
prevent automatic restart for configuration/delivery uncertainty. The unit
uses read-only filesystem, hidden home directories, no privileges/capabilities
and private temporary files. Disconnect clears the consumer status; a running
consumer does **not** prove a phone received/rang. Verification checks exact
release/unit bytes, no drop-ins, effective user/type/status, enabled/running
state and dependency/configuration checks. Reboot, actual SDK/broker recovery
and real mobile delivery acceptance remain open. Root performed the development
installation described above; the original editing agent did not deploy it.

Root-owned new offline commands, not executed by the editing agent:

```sh
python3 -B -I scripts/test-push-bridge-service.py
bash scripts/test-install-kazoo5-push-bridge.sh
```

Also rerun config/runtime/settlement/APNs suites. The lock uses primary PyPI
version metadata; see `doc/push_bridge_dependency_lock.md`. Dependency
provenance alone is not package installation or runtime compatibility evidence.

Latest root checkpoint September7: `219760/1a2178` passes8 configuration,
19 startup/payload/lifecycle and14 owner-thread settlement tests, in a network-
isolated128MiB validation unit. Provider, broker and executor integrations are
fixtures; no real credentials, pushes, service changes or deployment occurred.
This verifies the bounded ACK-safety source change, not durable retries, mobile
ringing or installer readiness. The bridge remains a required component of the
main modular deployment SH, both standalone and co-located; not a manual add-on.

Root checkpoint September 7: sanitized source reviewed; the standalone offline
configuration validator passes eight tests (`71f4f8`) under an isolated network
namespace with128MiB memory and512MiB reserve. No sender was imported/executed,
no credential file was read and no broker/provider was contacted by those tests.
This is source/configuration progress only; all activation blockers below remain.

This directory contains a **partially offline-tested source/installer candidate** from internal, user-provided production files. Controlled development installation now has an explicit path above; this is not evidence of reliable production delivery. No production unit, credential file, token, project/team/key identifier, bundle identifier, broker address or private provider endpoint has been copied into the repository.

The original licensing and redistribution permissions have not been established. Treat this as internal user-provided source; do not assume an open-source license.

## Provenance and retained behavior

The supplied `bridge.py` SHA-256 was `33f651f3ee0e895bbcf609c98a08219404a5a1d311e6dc642249b6024a7a531e`; supplied `apns_sender.py` was `ea1c0087c1bd5c2df430529ee24d78dfb60674f4fab7aba634bd570f87615773`. These identify the private originals, not the modified files here. The accompanying production systemd unit contained inline environment configuration and was not imported. The private originals must not enter Git.

Kazoo's pusher role publishes native `notification/push_req` events on the `pushes` AMQP exchange. This is not an integration with the SaaS product named Pusher. The operator must verify the exact broker binding and authority before configuring this consumer.

The candidate retains separate FCM/APNs thread pools, payload mapping, FCM's two-attempt policy, per-send APNs HTTP/2 connection, provider JWT caching and the original watchdog/shutdown strategy. Worker-thread unconditional ACK has been replaced by the owner-thread safety slice below; reconnect is now forbidden while a generation has unsettled deliveries. The watchdog elapsed clock is monotonic; its limitations remain. The old minute-bucket call UUID has been replaced with stable identity. `Payload` maps native call/caller/registration/proxy fields to mobile data. `apple`, `apns`, `ios`, `apple_dev`, and `apple_sandbox` select APNs; `firebase`, `android`, `fcm`, or a missing type select FCM.

Intentional sanitization changes:

- Deployment values are environment inputs rather than embedded defaults. FCM's project comes from the configured service-account file; its URL template is now explicit.
- Logs contain fixed categories and numeric provider status, not device-token prefixes, call identifiers, caller payloads, provider bodies, credential identifiers, or raw exception text. Provider result tuples retain `(success, status, text)` shape, but `text` is a fixed category.
- Explicit provider-test entrypoints require `PUSH_BRIDGE_TEST_PAYLOAD_JSON` instead of hard-coded caller/registration/proxy values. The current candidate requires the native `Payload` object with a `call-id`, not arbitrary provider data. They still send real pushes and take the device token on the command line; they are not offline tests and are not approved activation tooling.
- APNs initialization explicitly rejects missing key/topic configuration, and a missing selected host returns a failure. No provider host is silently selected.

Only static source inspection and sanitization have been performed for the sender import. A separate offline configuration preflight and test source have since been added; neither imports or activates the senders. No module execution, build, dependency installation, provider call or regression test was performed by the importing agent. Production use of the originals is not acceptance of these modified files.

## Offline configuration preflight candidate

`validate_config.py` uses only Python's standard library and reads a supplied
environment mapping. It does **not** import `bridge.py` or `apns_sender.py`, load
credentials, inspect their contents, resolve hosts, open sockets, or install
anything. Invoke it with `python3 -B -I services/push-bridge/validate_config.py`
from a process with the proposed protected environment already supplied. Do not
pass passwords, tokens or populated configuration as command arguments. Do not
shell-source unreviewed configuration files.

Exit 0 and `push_bridge_config_shape_valid; activation_not_validated` mean only
that the proposed configuration passes this lexical policy. Exit 2 reports
fixed error codes and recognized field names without supplied values or unknown
field names. No raw exceptions are printed by the CLI failure boundary. This
does **not** sanitize the existing senders' startup boundaries.

The candidate policy is deliberately narrower than the imported senders:

- Unknown `PUSH_BRIDGE_*` variables and provider-test payload settings fail
  service preflight; unrelated process environment variables are ignored.
- Worker counts are bounded to 1–64 FCM and 1–32 APNs, stall timeout to 30–300
  seconds, and broker port to 1–65535. These bounds are not a tested capacity
  recommendation, and do not fix unbounded executor queues.
- Broker host must be an IP literal or ASCII DNS name, not a URL, port-bearing
  address, or credential string. Topology names have bounded ASCII syntax;
  reserved `amq.` queue/exchange names are rejected. Wildcard binding syntax is
  allowed, but account authority and actual Kazoo routing must be reviewed
  separately; syntax validation is not an authorization check.
- Credential paths must be absolute, normalized lexical paths using a limited
  ASCII character set. This does not prove existence, regular-file status,
  ownership, permissions, protected ancestors, key validity or provider access.
- FCM is restricted to `https://www.googleapis.com/auth/firebase.messaging`
  and `https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`.
  Alternate hosts, schemes, credentials, queries or format expressions fail.
  The service-account project value is not loaded or validated by this lexical
  checker. Explicit runtime validates it; FCM redirects are now rejected before
  redirect processing as described above.
- APNs is optional when all its main fields are absent or empty. Setting any
  APNs value requires the complete main key/team/base-topic contract and both
  explicit hosts: `api.push.apple.com` for production and
  `api.sandbox.push.apple.com` for sandbox. Key/team IDs use ten uppercase
  alphanumeric characters; base topics must not already end in `.voip`.
  Sandbox key overrides must be a complete nonempty pair or entirely absent.
- Control characters, surrogate code points, oversized values and surrounding
  whitespace in broker credentials/vhost fail. No supplied value is echoed.

These are candidate deployment constraints for root review. Explicit bridge
startup now runs this preflight before provider initialization, and the APNs
constructor validates its explicit key/topic/host inputs. This does not prove
transport correctness: configuration shape alone does not prove an AMQPS
handshake or make port5671 imply TLS. The protected service launcher checks
deployment file permissions separately. FCM redirect rejection is a
separate sender-level control, tested above.

Root-owned offline test command:

```sh
python3 -B -I scripts/test-push-bridge-config.py
```

The test fixtures use nonexistent credential paths and synthetic values only.
They cover required inputs, numeric bounds, endpoint redirection/template
rejection, lexical paths/hosts, APNs completeness, unknown/test settings, CLI
redaction and failure boundaries. The agent adding these files did not execute
the tests; record the root's actual result separately before claiming a pass.

### Installer and release boundary

The main SH now includes the bridge in explicit selection and `ALL`, with
protected JSON configuration, pinned dependencies, a least-privilege service,
and broker-consumer readiness. The development installation is verified above.
Configuration validation alone is never service readiness, and consumer
readiness is never mobile delivery or production acceptance. Remote-broker,
reboot, failure/retry and actual device tests remain required. Provider secrets
remain separate from ordinary persisted Kazoo settings and from the repository.

## Configuration contract

`config.env.example` deliberately leaves required values empty; it is not runnable configuration. Protect populated configuration and credential files outside the source tree. Module import no longer reads this environment or opens credentials. Explicit `BridgeRuntime(environment)` startup validates the proposed environment before importing provider dependencies, loading the FCM service account, or constructing a requests session. `ApnsSender` requires explicit validated configuration and loads its provider dependencies/key only during initialization. Neither operation belongs in an offline configuration-only check.

| Inputs | Contract |
| --- | --- |
| `PUSH_BRIDGE_SA_FILE` | Required Google service-account JSON path; bridge startup loads it even for APNs-only traffic. |
| `PUSH_BRIDGE_AMQP_HOST`, `PUSH_BRIDGE_AMQP_USER`, `PUSH_BRIDGE_AMQP_PASS`, `PUSH_BRIDGE_AMQP_VHOST` | Required broker connection and credentials. In TLS mode this exact host is also the certificate identity; no alternate hostname override exists. |
| `PUSH_BRIDGE_EXCHANGE`, `PUSH_BRIDGE_QUEUE`, `PUSH_BRIDGE_BINDING_KEY` | Required exact deployment topology. Durable queue; existing exchange checked passively, otherwise created as topic. No automatic account authorization is added. |
| `PUSH_BRIDGE_FCM_SCOPE` | Required OAuth scope approved for this service account. |
| `PUSH_BRIDGE_FCM_URL_TEMPLATE` | Required exact FCM URL from the policy above; `{project_id}` expands only after validation of the service-account project as a bounded Google project identifier. All3xx responses are rejected without following Location or consuming their bodies. |
| `PUSH_BRIDGE_AMQP_PORT` | Optional integer; default `5671` when TLS is true, otherwise `5672`. An explicitly supplied port is retained. |
| `PUSH_BRIDGE_AMQP_TLS` | Optional exact string `"true"` or `"false"`; default `"false"`. Empty, case variants and other boolean spellings fail. True enables verified AMQPS with TLS1.2 minimum. |
| `PUSH_BRIDGE_AMQP_CA_FILE` | Optional absolute PEM trust-bundle path, permitted only with TLS true; omit for system roots. The service launcher requires it directly under `/etc/kazoo-push-bridge`, root-owned with protected parent/file permissions, maximum64KiB and no private-key block. |
| `PUSH_BRIDGE_WORKERS`, `PUSH_BRIDGE_APNS_WORKERS`, `PUSH_BRIDGE_STALL_TIMEOUT` | Optional integers, defaults `32`, `8`, `70` seconds respectively; explicit startup enforces the candidate bounds above. Load acceptance remains open. |
| `PUSH_BRIDGE_DELIVERY_TIMEOUT` | Optional integer seconds, default `60`, range `10`–`300`. The owner loop detects unfinished work at its monotonic admission deadline, including executor/token-lock wait. It fails stopped with exit78, without acknowledging or replaying uncertain pushes. This is distinct from broker-loop STALL_TIMEOUT and producer freshness TTL; see the worker-deadline section below. |
| `PUSH_BRIDGE_APNS_KEY_FILE`, `PUSH_BRIDGE_APNS_KEY_ID`, `PUSH_BRIDGE_APNS_TEAM_ID`, `PUSH_BRIDGE_APNS_TOPIC` | Required when an APNs sender is initialized. Topic is the base bundle topic; code appends `.voip`. |
| `PUSH_BRIDGE_APNS_HOST_PROD`, `PUSH_BRIDGE_APNS_HOST_DEV` | Both explicit canonical hosts are required when APNs is configured. TLS certificate/hostname validation and `h2` negotiation are used on port `443`; partial-response handling remains unaccepted. |
| `PUSH_BRIDGE_APNS_KEY_FILE_DEV`, `PUSH_BRIDGE_APNS_KEY_ID_DEV` | Optional sandbox overrides; absent variables fall back to the main key values, as in the original. Review this explicitly for the intended Apple team/environment. |
| `PUSH_BRIDGE_TEST_PAYLOAD_JSON` | Required only for the explicitly invoked, real-send command-line test modes. Not a deployment default. |

The provider hosts and broker binding must come from a reviewed deployment contract, not guessed endpoints. Never expose populated environment/configuration, command-line device tokens, or exception tracebacks in acceptance output. Explicit logger calls and the new main-entrypoint exception boundaries contain only fixed categories/status codes. This is not a whole-process secrecy guarantee: third-party logging, thread/future failures and direct library invocation outside those boundaries still require review.

### Explicit remote AMQPS configuration

For an operator-reviewed remote broker, set TLS true and its TLS listener port.
The following fragment contains no usable authority or credentials; merge it
into the protected service configuration only during an authorized deployment:

```json
{
  "PUSH_BRIDGE_AMQP_HOST": "broker.example.invalid",
  "PUSH_BRIDGE_AMQP_TLS": "true",
  "PUSH_BRIDGE_AMQP_PORT": "5671",
  "PUSH_BRIDGE_AMQP_CA_FILE": "/etc/kazoo-push-bridge/broker-ca.pem"
}
```

Omit the CA key entirely when the broker chains to the system trust store.
A custom bundle selects that trust bundle; it does not disable certificate
validation. Start its permissions at root0600 in the protected service
directory. The existing launcher permission-preparation path now includes this
exact validated trust file in the root:service-group0640 set. The plain JSON
example retains local AMQP defaults; changing TLS without changing its explicitly
set5672 port preserves5672, so choose the actual TLS listener deliberately.

The bridge creates a standard client SSLContext with `CERT_REQUIRED`, hostname
checking and TLS1.2 minimum. Pinned AMQPStorm2.11.1 receives `ssl=True` and exactly
`ssl_options={"context": context, "server_hostname": configured_host}`. Its
`IO._ssl_wrap_socket` uses that supplied context directly. This bypasses the
library's legacy no-context path, whose defaults permit `CERT_NONE` and disable
hostname checking. No certificate/hostname-disable switch, alternate SNI name,
client-certificate mode, or fallback to plaintext is provided. CA load errors
fail startup with a fixed category; TLS handshake errors do not select plaintext.

Offline configuration checks remain free of CA-file reads and network calls.
The protected launcher validates the CA file's owner/mode/size and parses the
exact protected PEM bytes with stdlib ssl during installer preflight, before
service or permission mutations. The runtime constructs its verifying context
before provider credentials are loaded. The socket timeout remains10seconds; this does not
establish a total connect/reconnect/settlement deadline or durable retry policy.
Legacy plaintext mode remains accepted for compatibility and must not be mistaken
for encrypted remote transport.

Prepared `scripts/test-push-bridge-amqp-tls.py` checks the real pinned AMQPStorm
parameter/context handoff without opening a broker connection, then uses real
in-memory TLS with synthetic certificates to check trusted/matching acceptance
and hostname/untrusted-chain rejection. Config, runtime, service and settlement
fixtures cover strict option parsing, default/explicit ports, trust-file
protection and unchanged plaintext wiring. Root ran all112 bridge tests and
installer dispatch successfully (`0d2bfe/b60ebe`), then deployed and independently
verified the development service (`1ff54f/02ae6d`, `9f2d32/f1ad28`). These are
offline TLS tests; the actual development broker remains local/plaintext.

## Candidate payload and import-safety changes

`push_payload.py` is provider-independent and performs no I/O. It accepts UTF-8
JSON objects up to 32 KiB; rejects duplicate keys, nonfinite numbers, malformed
nested `Payload`, invalid types, control/surrogate characters and excessive
field sizes; and projects only the existing mobile fields. Caller display
strings remain Unicode. Null optional caller/registration/proxy values remain
omitted from provider payloads, not stringified as `None`. Extra native envelope
headers are accepted but not forwarded. Present event category/name must be
`notification`/`push_req`; this is not an `endpoint_push_req` implementation.

A nonempty call ID is now mandatory. It may come from `Payload.call-id` or
top-level `Call-ID`; contradictory nonempty values fail. The APNs `call_uuid` is
UUIDv5 of a versioned, unambiguously encoded `[Account-ID, call-id]` identity,
including an absent-account marker when Account-ID is missing. It is stable
across retries/minute boundaries, display changes and token changes. It does
not create broker/provider exactly-once delivery, persist retry state, or supply
missing account authorization. If publishers omit account identity they must
provide globally unique call IDs, as normal SIP call IDs are intended to be.

FCM tokens remain opaque visible-ASCII strings (up to 4096 characters); the
validator does not assume a base64 alphabet or reject JSON-safe punctuation.
APNs tokens remain opaque bytes encoded as nonempty even-length hex (up to 512
hex characters), optionally with one bounded legacy prefix plus `:`. Hex case
is normalized. The candidate does not hard-code the common 32-byte device-token
length. These resource limits and prefix contract still need mobile acceptance
before release. Forwarded data is capped at 3072 UTF-8 JSON bytes;
APNs payloads are capped at 4096 bytes. The APNs transport candidate below adds
response bounds; FCM now closes responses without reading their bodies. OAuth
refresh and whole-operation deadlines remain open.

Root-owned source regression command (not run by the editing agent):

```sh
python3 -B -I scripts/test-push-bridge-runtime.py
```

This uses synthetic payloads and mocked provider dependencies only. It covers
import-side-effect guards, explicit initialization, configuration-before-I/O,
project/endpoint injection, native payload mapping, aliases, rejection/bounds,
stable identity, APNs configuration forwarding, and fixed-error startup/test
boundaries. The existing configuration tests remain a separate regression gate.

Root verification September 7: both commands above passed in one network-
isolated, 128 MiB validation unit with a 512 MiB reserve (`edf013/d8b505`):
8 configuration tests and 19 runtime/payload tests. All credentials/provider
dependencies were synthetic or mocked; no real notifications, service startup,
installer integration or delivery-engine acceptance is implied. The activation
blockers below remain mandatory.

Source self-review also added a startup configuration snapshot (the runtime uses
exactly the mapping it validated) and an HTTP-session closing fence: closing the
runtime rejects new FCM sends and lets the final already-active send release the
session, without waiting or closing underneath an active request. This is not
worker draining, cancellation or delivery assurance; those remain activation
blockers below. The later settlement slice replaces unconditional ACK separately.

## Owner-thread settlement safety candidate (not complete retry)

`delivery_settlement.py` tracks at most the configured consumer prefetch count
of futures (twice FCM worker count, bounded by 128). Workers receive the immutable
body argument, not an AMQP message/channel argument or worker-side ACK callback.
The same broker owner thread that consumes messages inspects completed futures
and ACKs only the sender's exact `(True, 200, "provider_response")` result. Other
results, malformed messages, worker exceptions/cancellation, and ACK exceptions
remain unacknowledged. ACK exceptions are uncertain, so the controller cannot
blindly retry an ACK on a second drain. The separate APNs transport candidate
below addresses partial-response acceptance; it needs its own verification and
does not inherit the earlier settlement fixtures' passing result.

Each broker generation owns its controller and a separately bound callback.
Invalidation prevents late completion/callback activity from settling a prior
message or attaching work to a new generation. Pending deliveries also prevent
automatic broker reconnection, avoiding immediate replay while old workers can
still reach providers. Idle connection failures retain the existing reconnect
behavior. Accepted completed deliveries are settled before a discovered provider
failure terminates the generation; failed/uncertain deliveries are left for the
broker to retain according to its topology/durability policy. No message is
rejected, requeued or republished by this slice.

Fatal settlement uncertainty returns status **78** from the main entrypoint and
logs only `push_delivery_unsettled_manual_recovery_required`. Any future unit
must prevent automatic restart for that status until a reviewed durable bounded
retry/dead-letter policy exists. Manual restarts can redeliver messages and
duplicate already accepted pushes when ACK outcome was uncertain; do not treat
them as an automatic recovery policy. A poison message currently stops this
candidate deliberately instead of being silently acknowledged or endlessly
requeued. This is **not activation-ready**, not a production availability policy,
and not proof of broker persistence or mobile delivery.

Root-owned offline fixture command (not executed by the editing agent):

```sh
python3 -B -I scripts/test-push-bridge-settlement.py
```

The fixtures cover exact positive acceptance, pending futures, invalid results,
worker failure/cancellation, uncertain ACK, capacity, cross-thread ownership,
invalidated generations, and actual bridge owner-loop integration using fake
executors/connections. The two earlier config/runtime test commands must also
be rerun. Tests against the pinned real AMQP client and broker remain mandatory.

## APNs transport safety candidate (offline tested, not deployed)

Root `943db9` passes23 offline transport tests. Related configuration8,
runtime19 and settlement14 tests pass `76b36d`. Those results precede the
installer/service candidate above; no real broker/provider or installer
acceptance is implied.

`apns_sender.py` now returns `(True, 200, "provider_response")` only after both
valid final response headers and the requested HTTP/2 stream's `StreamEnded`
event. Header-only EOF, reset, timeout or GOAWAY is not acceptance. Events for
an unrelated stream cannot settle this one. A completed stream followed by
GOAWAY remains accepted; GOAWAY received before completion is conservatively
uncertain even if another event in the same batch reports an end. Complete
non-200 responses retain their numeric status and fixed category, never the
provider body. This proves neither delivery to a phone nor exactly-once delivery.

The source candidate counts response body bytes instead of accumulating them:
16 KiB cumulative DATA limit, 16 KiB decoded final-response header limit and
64 KiB total received HTTP/2 bytes (including control frames). The wire limit is
checked before HTTP/2 parsing, and reads are at most 16 KiB, with at most one
additional byte used to detect overflow. HPACK decompression/parser internals
still depend on the separately required pinned `h2`/`hpack` validation; these
application limits are not a proven whole-parser memory bound.

A single eight-second monotonic budget covers token-lock acquisition, TCP/TLS,
writes and response reads. Each blocking socket operation receives only its
remaining budget; partial progress does not reset it. JWT `iat` still correctly
uses wall-clock time, while cached-token age uses monotonic time. Signing or
other library work that returns after budget expiry cannot report acceptance.
TLS construction/handshake/ALPN failures close whichever raw or wrapped socket
the sender currently owns, including failures before `_open()` returns.

**Remaining deadline limitation:** Python's platform DNS lookup inside
`socket.create_connection()` is not interrupted by socket timeouts, and that
helper can try multiple resolved addresses before returning. The budget is
checked immediately afterward, but cannot cancel a stuck resolver or CPU/library
operation. This is a shared I/O budget, not a hard whole-worker wall-time bound.
Resolver/cancellation and full worker-shutdown acceptance remain mandatory.
FCM redirect/body handling is covered by the later checkpoint above. Token
refresh, durable retry and broker TLS remain open; dependency pins and the
development installer/service readiness are verified separately above.

Root-owned isolated fixture command (not run by the editing agent):

```sh
python3 -B -I scripts/test-push-bridge-apns-transport.py
```

Fixtures mock sockets, clocks, HTTP/2 events and signing. They cover complete
acceptance/rejection, native headers/sandbox routing, partial responses, GOAWAY
ordering, resets, stream identity, malformed status, cumulative body/wire/header
limits, shared deadlines, token-lock/cache behavior and TLS socket ownership.
They do not load real provider dependencies or credentials, create connections,
or send pushes. Rerun the config, runtime and settlement suites as well, and
verify the protocol behavior with pinned real HTTP/2 libraries before release.

## Historical production dependencies (not the current lock)

The supplied production environment was reported to use these versions. They are provenance information, not an endorsed or installed lockfile; root owns dependency pins and compatibility/security testing.

| Import | Distribution | Reported production version |
| --- | --- | --- |
| `amqpstorm` | AMQPStorm | 2.11.1 |
| `google.oauth2`, `google.auth.transport.requests` | google-auth | 1.35.0 |
| `requests` | requests | 2.25.1 |
| `ecdsa` | ecdsa | 0.19.2 |
| `h2.connection`, `h2.events` | h2 | 3.2.0 |

Other imports are Python standard-library modules (`base64`, `binascii`, `concurrent.futures`, `hashlib`, `json`, `logging`, `os`, `signal`, `socket`, `ssl`, `sys`, `threading`, `time`, `uuid`). The current tracked `requirements.lock` and `kazoo-push-bridge.service` supersede this historical inventory; their installation evidence is above.

## Production-release blockers and minimum next fixes

1. **Delivery loss and duplicates:** owner-thread positive-result-only ACK is now a source candidate, not full delivery acceptance. Define terminal rejection versus transient failure, bounded expiry-aware durable retry/dead-letter behavior and stable delivery identity; prove broker durability, ACK/channel ownership, reconnect and duplicate behavior with the pinned real library before activation. The current fail-closed/manual-recovery policy is not production availability. An HTTP 200 only means provider acceptance, not delivery to the phone.
2. **Bounded work and shutdown:** owner-loop admission deadlines and production exit78 before potentially blocked cleanup now have offline regression coverage, including actual termination with a blocked executor worker. OAuth transport bounds and per-thread HTTP leases are implemented separately. See [worker deadline](../../doc/push_bridge_worker_deadline.md) for exact guarantees and evidence. Remaining: real consumer/broker failure acceptance, blocked broker-loop behavior, ordinary signal shutdown/draining and whole-process deadline limits. Uncertain sends are not automatically replayed; this remains a manual-recovery availability limitation.
3. **Input and response limits:** strict input normalization and outgoing payload caps have offline coverage, but mobile compatibility acceptance remains open. Malformed messages fail closed unacknowledged and require a reviewed poison-message policy. APNs caps and protocol fixtures pass23 offline tests. FCM closes responses without reading their bodies, including redirects, with six pinned-Requests adapter tests. OAuth response parsing and total operation bounds still need review before production acceptance.
4. **Transport/configuration security:** Explicit verified AMQPS is now a source candidate with offline tests prepared; remote-broker deployment/acceptance remains open. FCM3xx are rejected before redirect/body processing. Numeric settings and initial provider endpoints are constrained. Protected credential permissions and the least-privilege service are installed and verified; the new CA-file path still needs root validation. Never reuse the production AMQP authority in a development consumer or copy the inline production unit into Git.
5. **APNs lifecycle:** a failed lazy initialization is cached permanently until process restart. Monotonic token-cache/request budgets, actual response stream completion, and TLS-failure socket cleanup have offline coverage and are deployed in the isolated development consumer. Platform resolver/CPU cancellation remains outside the socket budget. Actual configured production/sandbox keys load offline with pinned SDKs, but provider authorization is unverified. Test initialization recovery, real HTTP/2 partial responses/GOAWAY, total worker bounds and duplicate semantics. No end-to-end delivery evidence exists.

Dependency pins, the protected service and listed offline regressions are now present. Before broader activation, resolve the remaining reliability/security gaps and complete broker recovery and designated-device acceptance. Provider credentials alone do not identify an authorized test device. The development installation above is not production approval.
