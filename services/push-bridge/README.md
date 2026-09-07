# Mobile push bridge: sanitized source import

Root checkpoint September 7: sanitized source reviewed; the standalone offline
configuration validator passes eight tests (`71f4f8`) under an isolated network
namespace with128MiB memory and512MiB reserve. No sender was imported/executed,
no credential file was read and no broker/provider was contacted by those tests.
This is source/configuration progress only; all activation blockers below remain.

This directory is an **unvalidated, non-activation-ready source import** from internal, user-provided production files. It is not a new service design, a deployment, or evidence of reliable provider delivery. Installer activation is paused pending the gates below. No production unit, credential file, token, project/team/key identifier, bundle identifier, broker address or provider endpoint has been copied into the repository.

The original licensing and redistribution permissions have not been established. Treat this as internal user-provided source; do not assume an open-source license.

## Provenance and retained behavior

The supplied `bridge.py` SHA-256 was `33f651f3ee0e895bbcf609c98a08219404a5a1d311e6dc642249b6024a7a531e`; supplied `apns_sender.py` was `ea1c0087c1bd5c2df430529ee24d78dfb60674f4fab7aba634bd570f87615773`. These identify the private originals, not the modified files here. The accompanying production systemd unit contained inline environment configuration and was not imported. The private originals must not enter Git.

Kazoo's pusher role publishes native `notification/push_req` events on the `pushes` AMQP exchange. This is not an integration with the SaaS product named Pusher. The operator must verify the exact broker binding and authority before configuring this consumer.

The candidate retains separate FCM/APNs thread pools, broker reconnect/prefetch behavior, payload mapping, manual ACK behavior, FCM's two-attempt policy, per-send APNs HTTP/2 connection, provider JWT caching and the original watchdog/shutdown strategy. The watchdog elapsed clock is now monotonic; its limitations remain. The old minute-bucket call UUID has been replaced with the stable identity described below. `Payload` maps native call/caller/registration/proxy fields to mobile data. `apple`, `apns`, `ios`, `apple_dev`, and `apple_sandbox` select APNs; `firebase`, `android`, `fcm`, or a missing type select FCM.

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
  The service-account project value is not loaded or validated here. Redirect
  rejection and credential loading still need to be fixed in the sender.
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
transport correctness: in particular it does not add AMQP TLS or make port 5671
imply TLS, prevent FCM response redirects, or validate credential permissions.

Root-owned offline test command:

```sh
python3 -B -I scripts/test-push-bridge-config.py
```

The test fixtures use nonexistent credential paths and synthetic values only.
They cover required inputs, numeric bounds, endpoint redirection/template
rejection, lexical paths/hosts, APNs completeness, unknown/test settings, CLI
redaction and failure boundaries. The agent adding these files did not execute
the tests; record the root's actual result separately before claiming a pass.

### Remaining installer integration boundary

Do not add this preflight's exit 0 as service readiness or put the imported
consumer in `ALL`. First close the delivery, input, transport and lifecycle
gates below and freeze a dependency manifest. The candidate now wires validation
before provider initialization through sanitized main-entrypoint boundaries;
root must verify those offline tests and runtime behavior. Then add the
explicit mobile bridge option to `scripts/install-kazoo5.sh`'s component
normalization/selection and execution/verification dispatch. Use its existing
dry-run, protected configuration, `write_file`, systemd installation and
post-start verification conventions, but keep bridge credentials separate from
ordinary persisted deployment settings. A protected environment file must be
parsed as data, not shell code. A dedicated unprivileged service, bounded
restart/shutdown, least-privilege filesystem/network access, effective-unit
readback, broker-consumer readiness and controlled provider acceptance tests
are still required. The optional service must work with a remote broker and
must not implicitly install or change a production Kamailio/broker.

## Configuration contract

`config.env.example` deliberately leaves required values empty; it is not runnable configuration. Protect populated configuration and credential files outside the source tree. Module import no longer reads this environment or opens credentials. Explicit `BridgeRuntime(environment)` startup validates the proposed environment before importing provider dependencies, loading the FCM service account, or constructing a requests session. `ApnsSender` requires explicit validated configuration and loads its provider dependencies/key only during initialization. Neither operation belongs in an offline configuration-only check.

| Inputs | Contract |
| --- | --- |
| `PUSH_BRIDGE_SA_FILE` | Required Google service-account JSON path; bridge startup loads it even for APNs-only traffic. |
| `PUSH_BRIDGE_AMQP_HOST`, `PUSH_BRIDGE_AMQP_USER`, `PUSH_BRIDGE_AMQP_PASS`, `PUSH_BRIDGE_AMQP_VHOST` | Required broker connection and credentials. The imported connection currently uses non-TLS AMQP. |
| `PUSH_BRIDGE_EXCHANGE`, `PUSH_BRIDGE_QUEUE`, `PUSH_BRIDGE_BINDING_KEY` | Required exact deployment topology. Durable queue; existing exchange checked passively, otherwise created as topic. No automatic account authorization is added. |
| `PUSH_BRIDGE_FCM_SCOPE` | Required OAuth scope approved for this service account. |
| `PUSH_BRIDGE_FCM_URL_TEMPLATE` | Required exact FCM URL from the policy above; `{project_id}` expands only after validation of the service-account project as a bounded Google project identifier. Redirect rejection remains open. |
| `PUSH_BRIDGE_AMQP_PORT` | Optional integer; default `5672`. |
| `PUSH_BRIDGE_WORKERS`, `PUSH_BRIDGE_APNS_WORKERS`, `PUSH_BRIDGE_STALL_TIMEOUT` | Optional integers, defaults `32`, `8`, `70` seconds respectively; explicit startup enforces the candidate bounds above. Load acceptance remains open. |
| `PUSH_BRIDGE_APNS_KEY_FILE`, `PUSH_BRIDGE_APNS_KEY_ID`, `PUSH_BRIDGE_APNS_TEAM_ID`, `PUSH_BRIDGE_APNS_TOPIC` | Required when an APNs sender is initialized. Topic is the base bundle topic; code appends `.voip`. |
| `PUSH_BRIDGE_APNS_HOST_PROD`, `PUSH_BRIDGE_APNS_HOST_DEV` | Both explicit canonical hosts are required when APNs is configured. TLS certificate/hostname validation and `h2` negotiation are used on port `443`; partial-response handling remains unaccepted. |
| `PUSH_BRIDGE_APNS_KEY_FILE_DEV`, `PUSH_BRIDGE_APNS_KEY_ID_DEV` | Optional sandbox overrides; absent variables fall back to the main key values, as in the original. Review this explicitly for the intended Apple team/environment. |
| `PUSH_BRIDGE_TEST_PAYLOAD_JSON` | Required only for the explicitly invoked, real-send command-line test modes. Not a deployment default. |

The provider hosts and broker binding must come from a reviewed deployment contract, not guessed endpoints. Never expose populated environment/configuration, command-line device tokens, or exception tracebacks in acceptance output. Explicit logger calls and the new main-entrypoint exception boundaries contain only fixed categories/status codes. This is not a whole-process secrecy guarantee: third-party logging, thread/future failures and direct library invocation outside those boundaries still require review.

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
APNs payloads are capped at 4096 bytes. Provider response bounds remain open.

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
worker draining, cancellation, delivery assurance or a fix for the existing
unconditional ACK; those remain separate activation blockers below.

## Dependencies observed, not newly pinned or verified

The supplied production environment was reported to use these versions. They are provenance information, not an endorsed or installed lockfile; root owns dependency pins and compatibility/security testing.

| Import | Distribution | Reported production version |
| --- | --- | --- |
| `amqpstorm` | AMQPStorm | 2.11.1 |
| `google.oauth2`, `google.auth.transport.requests` | google-auth | 1.35.0 |
| `requests` | requests | 2.25.1 |
| `ecdsa` | ecdsa | 0.19.2 |
| `h2.connection`, `h2.events` | h2 | 3.2.0 |

Other imports are Python standard-library modules (`base64`, `binascii`, `concurrent.futures`, `hashlib`, `json`, `logging`, `os`, `signal`, `socket`, `ssl`, `sys`, `threading`, `time`, `uuid`). Transitive dependencies and Python/OpenSSL versions still need a reproducible manifest. No requirements lockfile or systemd unit is supplied in this slice.

## Activation blockers and minimum next fixes

1. **Delivery loss and duplicates:** worker `finally` ACKs every message, including provider errors, malformed payloads, missing APNs configuration and unexpected exceptions; ACK exceptions are swallowed. The future is not observed. Conversely, a lost ACK/reconnect or FCM retry can duplicate a push. Define terminal rejection versus transient failure, bounded expiry-aware retry/dead-letter behavior and delivery identity; prove broker ACK/channel ownership and reconnect behavior with the real library before activation. An HTTP 200 only means provider acceptance, not delivery to the phone.
2. **Bounded work and shutdown:** executor queues are unbounded; broker prefetch only bounds one live consumer, not retained tasks across reconnects. Google token refresh has no explicitly supplied timeout. Shared `requests.Session` thread behavior is unproven. The watchdog measures broker-loop progress, not worker completion. Shutdown stops without draining and force-exits after three seconds. Add bounded admission, total operation deadlines, observed worker results, explicit channel-generation fences and bounded shutdown tests. Do not solve loss with an unbounded requeue loop.
3. **Input and response limits:** candidate strict input normalization and outgoing payload caps are implemented above, awaiting root and mobile compatibility acceptance. Malformed messages are still ACKed by the unaccepted worker-finally behavior. APNs accumulates response data without a cap; requests eagerly buffers FCM responses. Add provider response caps and protocol error cases.
4. **Transport/configuration security:** AMQP TLS is not configured and FCM requests follow redirects. Candidate startup now bounds numeric settings and constrains initial provider endpoints, but credential permissions are not checked. Define trusted broker/network authority, TLS/redirect policy, protected credential loading and a least-privilege service account/unit before enabling an installer option. Do not reuse inline production credentials or the supplied production unit.
5. **APNs lifecycle:** a failed lazy initialization is cached permanently until process restart. JWT and APNs request deadlines still use wall-clock time. The call UUID is now stable, but duplicate/retry behavior still needs acceptance. APNs connection close is currently treated as stream termination even if the response was incomplete; there is no end-to-end delivery evidence. Test initialization recovery, correct key curve/JWT shape, sandbox selection, partial responses/GOAWAY, deadline bounds and duplicate semantics. `_open()` also needs socket cleanup if TLS wrapping fails.

Before any controlled provider test: root should freeze dependency pins, add offline configuration/redaction/payload/HTTP2/broker lifecycle regressions, resolve the above blocking reliability and security policies, and define a reviewed protected service unit. A later real-device test needs separate explicit authorization and test credentials. This directory alone does not justify activation.
