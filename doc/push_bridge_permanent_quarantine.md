# Verified-quorum permanent-message quarantine

Main-SH deployment `e1b349/session76962/b94ad2` passed. Running release:
`51d97e626ef28d68e788b4579cf4ebf94ad93073c6e4a21ceb636d6c869eea79`,
PID423856, automatic restarts0. The previous release is retained. Existing
isolated legacy routing was preserved; quorum behavior was tested separately
against actual isolated broker resources, not enabled silently for native traffic.
Independent main-SH `--verify-only push-bridge` also passed
`55f252/session16031/cbbb2c`, including source/dependency/configuration and
enabled registered-consumer checks.

This focused change prevents malformed or conservatively classified rejected
messages from stopping the consumer in **explicit, verified `quorum-v1` mode**.
Legacy mode remains fail-closed. It does not implement transient retry, event
freshness, exactly-once delivery or complete broker/process recovery.

## Dispositions

| Exact worker outcome | Verified quorum disposition |
| --- | --- |
| Provider acceptance, HTTP200 | Owner-thread ACK |
| Local invalid payload | Owner-thread reject, `requeue=false` |
| Local invalid APNs token | Owner-thread reject, `requeue=false` |
| FCM HTTP400 or404 provider response | Owner-thread reject, `requeue=false` |
| APNs HTTP410 or413 provider response | Owner-thread reject, `requeue=false` |
| Other, malformed, authentication, transient or uncertain result | Remain unsettled; stop with existing fixed failure |

This rejects the current message, not the device token or account. FCM's
existing internal attempts are unchanged: a final rejection does not prove an
earlier uncertain attempt never reached the provider. Provider responses are
still validated by their existing transport; no new response-body parsing is
introduced. APNs400 is excluded because it can represent IdleTimeout.

Sources: [FCM errors](https://firebase.google.com/docs/cloud-messaging/error-codes),
[Apple APNs response codes](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html).

## Safety and ownership

`BridgeRuntime` enables the settlement mode only after `configure_topology`
successfully declares and independently verifies this connection's quorum
topology. Provider classification is local normalization metadata, not a
message-controlled disposition instruction. Exact Python types are required;
boolean/integer equality and overloaded result objects cannot impersonate a
verified outcome.

Provider workers never receive AMQP message/channel handles. Only the owning
consumer thread can ACK or reject. Oversized/malformed body admission remains
bounded; oversized bodies are not copied into worker futures. The original
AMQP message remains pending until disposition. An ACK/reject exception is
uncertain: retain pending state and fail, never blindly resend a disposition.
Invalidated generations cannot settle late worker results.

Reject completion is not proof that the DLQ already accepted the message. The
verified at-least-once dead-letter topology retains the source message until
transfer succeeds. Full/unavailable DLQ and lost-disposition fault tests remain
required. No silent queue migration or native traffic rebinding is performed.

## Evidence

`7916a6/session35726/8d3a01`: all145 bridge tests and installer dispatch pass
under network isolation. Thirteen new regressions cover strict type checks,
legacy compatibility, owner-thread rejection, uncertainty, real pinned
AMQP Basic.Reject framing and the runtime processing the next accepted message.

The isolated broker harness `scripts/accept-push-bridge-quorum.py` additionally
uses real work/DLQ deliveries and a separate thread returning synthetic provider
outcomes. It sends no FCM/APNs requests and reads no production credentials.
The initial run `e9a85e/session45847/5455cb` proved quarantine/readback and
continued acceptance, but failed final restoration because queue statistics
still contained the removed policy. Both temporary resources were removed;
receipt `kz5-topology-proof-5336815e-c546-4c44-b371-3cc402776733/receipt.json`
is retained under `/var/log/kazoo-acceptance/`. The harness now retries only that
restoration check within a15-second checked budget. Production verification is
unchanged and never accepts contradictory statistics.

Rerun `51559a/session54486/3e77be` passed every check, including restoration.
Receipt `/var/log/kazoo-acceptance/kz5-topology-proof-34fdf57a-b9b4-432e-9a6a-bbf53ad2325e/receipt.json`.
Both generated test resources were removed; the protected receipt remains.
