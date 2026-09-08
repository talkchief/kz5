# Mobile bridge: actual cross-server TLS consumer acceptance

## Installed-service idle broker outage recovery

**PASS 53408/858b7f:** the real installed `.26` bridge survived an actual stop
and start of the isolated `.44` RabbitMQ process. The broker PID changed from
58463 to 0/inactive (`af536f`), then 58729 (`53835e`). Main RabbitMQ stayed
PID 2355 with zero automatic restarts. Bridge PID 2437369 remained unchanged
through the outage. Its disconnected status was observed for at least five
seconds, followed by TLS 1.3 socket/connection/consumer correlation and exactly
one consumer across six samples over at least ten seconds.
The queue was empty throughout; no mobile messages or provider requests were
made. This proves idle transport recovery, **not** recovery of pending/provider
in-flight work, duplicate prevention, provider availability or node failover.

The normal SH installed the temporary remote configuration and restored the
original local configuration after testing. Original config bytes and provider
file hashes match; restored service PID 2439533 is active/registered. Final
cleanup `b419b5` stops only the temporary broker and verifies all nine main `.44`
services remain active. Its test listener ports are absent (`41de81`).

The AMQPStorm warning with an `OSError: connection closed by server` traceback
was inspected (`d9bc73`). It occurred at the deliberate broker stop; subsequent
five-second reconnect attempts ended with `consumer_started` in the same
process. It is expected evidence of the forced disconnect, not an unhandled
process crash. No runtime code change was needed for this idle recovery case.

Receipt on the main development host:
`/root/kz5-acceptance/bridge-service-remote/outage-receipt.json`, SHA256
`0df7d13a5e92162992f2d0ee6d78d683de930b5e9817e5547e0dcf9b7f342576`.
It was copied and independently matched (`41de81`). Local latest receipt,
protected config backups and logs are under
`/var/log/kazoo-acceptance/bridge-service-remote/`. Previous successful install
state and test CA were moved intact into
`/var/log/kazoo-acceptance/bridge-service-remote-install-20260908/` before this
new run. The main host retains both separate receipts. No backups were deleted.

### Controlled replay, not an unattended general-purpose test

The source runner remains fixed to the original development client `.26` and
isolated broker `.44`, and refuses existing proof state. Do not repoint it at
production or delete existing state to force a rerun. Review and archive exact
completed state/config/CA first; verify the current config matches the saved
original and no installer process remains. Start the existing owned test broker
and check its short-lived test certificate before beginning.

Run the guarded acceptance on `.26` using the installed bridge Python:

```sh
bash /opt/kz5/scripts/run-kazoo-validation.sh \
  --memory-mib 384 --reserve-mib 512 --runtime-sec 900 -- \
  /usr/local/lib/kazoo-push-bridge/current/venv/bin/python -B -I \
  /opt/kz5/scripts/accept-bridge-remote-service.py \
  --run-development-service-proof --broker-outage
```

Observe the protected receipt phase without printing config backups. Only
after `awaiting_broker_outage`, run `systemctl stop kz5-bridge-remote-proof.service`
on `.44` and verify it is inactive/PID 0. Only after `broker_outage_observed`,
start that exact test unit again. Each observation/recovery window is bounded
to 120 seconds. The runner requires same-process survival and stable single
consumer recovery; it restores through the normal installer on success/failure.
After final restoration, stop the test broker again. An outer interruption
requires inspection and explicit `--restore-only` before further tests.

18 offline tests cover positive recovery, missing outage, missing recovery,
process replacement/exit, unstable consumer verification, and restoration on
failure (`e08181`). No SSH credentials or generic remote commands are accepted
by the runner. Actual broker stop/start is an explicit operator action.

## Subsequent normal installed-service acceptance

**PASS65096/3e586e:** the ordinary `install-kazoo5.sh push-bridge` installed
and restarted the real non-root systemd service on10.1.0.26 against the separate
TLS broker on10.1.0.44. The test correlated service PID2428399 with its actual
TCP socket, broker TLS1.3 connection and the queue's single registered consumer.
The queue was empty; no pushes were published and no provider calls requested.
The same main SH then restored the original local-broker configuration;
byte-for-byte config/provider hashes and registered service PID2429632 passed.
This is a real installed-service topology change on an existing development
host, not a new clean-host installation or a provider-delivery test.

Source runner: `scripts/accept-bridge-remote-service.py`. Its fixed host, broker,
identity, queue/exchange UUID and configuration guards deliberately refuse blind
reruns over retained state. The current successful receipt is retained on .44:
`/root/kz5-acceptance/bridge-service-remote/receipt.json`, SHA256
`c8cc5878884541f191761d57499a76e49f89b12df2e92f5646796e6198104fb6`.
Local source receipt/config backups/logs remain in
`/var/log/kazoo-acceptance/bridge-service-remote/`; the config backups contain
secrets and must never be committed. Only the non-secret receipt was copied to
the main development host. The successful test's empty UUID resources are
retained in the stopped isolated broker, not deleted as production resources.

Earlier attempt35086/b9d5a5 exceeded its180-second installer deadline while
refreshing package metadata. The previous Bash-only timeout orphaned DNF and
blocked restoration on its lock. That orphan was terminated; independent audit
verified original config/provider bytes and the unchanged original service.
The harness now terminates only its own process group on timeout before
restoration; eleven offline regression tests pass5e64a2. The earlier receipt
remains as `prerequisites-failed-receipt.json` on .44. Original local attempt
state/CA was moved, not deleted, to
`/var/log/kazoo-acceptance/bridge-service-remote-prerequisites-20260908/`.

The installer also rewrote rocky.repo on every run to enable already enabled
CRB. DNF expires metadata older than repository configuration, so this forced
unnecessary revalidation. The new `ensure_crb_repository` reads CRB state and
only enables it when disabled, then verifies success. Unknown/ambiguous state
and command failures remain errors; normal DNF install/freshness/signature
checks are unchanged. Both successful installs preserved the original
rocky.repo timestamp. A bounded metadata-only diagnostic downloaded BaseOS and
AppStream before its120-second deadline; it was not an installer success.
The subsequent normal installers completed with the remaining native metadata
checks and all service verification, without cache-only flags. This behavior
matches [DNF configuration-age expiry](https://dnf.readthedocs.io/en/latest/conf_ref.html#main-options)
and [config-manager's persistent enable operation](https://dnf-plugins-core.readthedocs.io/en/latest/config_manager.html).

`test-crb-repository-idempotence.sh` covers enabled, disabled, malformed,
ambiguous, failed query/enable and dry-run states plus installer wiring.
This and the main installer and bridge rollback/selection suites pass35756/edd5be.
The temporary broker is stopped again; main .44 RabbitMQ PID2355/restarts0 and
all nine main services remain unchanged9b6706. Fresh-host remote/reboot,
pending-work/in-flight recovery and duplicate-dispatch gates remain open.
The subsequent idle-outage acceptance above adds only that specific coverage.

## Result and scope

The subsequent same-host normal bridge redeployment on the main development
host .44 also passes14352/30a1d9 at source `2b2043c`, with unchanged CRB mtime,
locked dependency/config/source verification and registered service PID57635.
All nine main services remain active, and the temporary test broker is inactive
with PID0 (fa350f). This follow-up does not add clean-host or outage coverage.

**PASS ef7ad0 / session6035:** the original development host10.1.0.26 ran the
actual bridge consumer/owner loop against a distinct native RabbitMQ3.13.7
instance on the main dev host10.1.0.44. The connection negotiated TLS1.3.
The production TLS option builder, AMQPStorm2.11.1 connector, HTTPS management
verifier, quorum topology, registered consumer, worker pool, freshness checks
and counted retry/settlement logic were exercised. Provider construction and
provider outcomes alone were substituted; no FCM/APNs request was made.

Verified:

- Trusted matching certificate succeeds; wrong hostname and untrusted CA fail
  with the corresponding certificate-verification reasons, not timeouts.
- Authenticated HTTPS identifies the exact isolated broker. The cluster display
  name is `rabbit_kz5_bridgeproof@dev-testing`; its Erlang node is
  `rabbit_kz5_bridgeproof@localhost`.
- One registered consumer; zero Basic.Get polling calls on the work queue.
- Synthetic503 then200 yields broker counters0,1 and two dispatches. A companion
  message is acknowledged before the delayed retry is requeued.
- Repeated synthetic503 yields counters0,1,2, exactly three dispatches, then
  dead-letter readback with the unchanged synthetic body.
- Consumer closes, queues drain, and this run's exact empty queue/exchange
  resources are removed. Source hashes stay unchanged throughout the run.

This is **not** a normal installed-service remote-broker deployment, provider
delivery, broker restart, reconnect/failover or exactly-once acceptance. Existing
normal bridge services were not reconfigured. The next gate is the ordinary
`install-kazoo5.sh push-bridge` service deployment against the reviewed remote
TLS topology, followed by independent verification and recovery tests. The later
normal installed-service acceptance above closes that installation step only.

## Isolation and retained evidence

The separate test broker uses `/var/lib/kz5-bridge-remote-proof`, a dedicated
`kz5-bridge-proof` service user, separate cookie/data/logs/plugins and fixed
ports: .44:35671 AMQPS, .44:35672 HTTPS; EPMD35369/distribution35370 stay on
loopback. No main RabbitMQ settings, credentials, queues or bindings changed.
No production service or deployed wildcard certificate was used. A synthetic
two-day CA/server certificate was generated solely for this acceptance.

Unit `kz5-bridge-remote-proof.service` has1GiB memory, no swap, CPU200%,256 tasks,
one-hour runtime, no automatic restart and no boot enablement. It is now
**stopped**, MainPID0/resultsuccess (ab490b). All nine main .44 services remain
active. Main RabbitMQ PID2355 and automatic restart count0 stayed unchanged.

Receipts and public test-CA copies are preserved on .44, root-only, under
`/root/kz5-acceptance/bridge-remote-tls/` so they survive deletion of the old host:

- Passing run: `bridge-remote-tls-b9d09e2c-bf6d-43a9-9cd9-62dfeb448433/receipt.json`.
- First failed identity assertion: `bridge-remote-tls-b807ad4a-bf1a-4dc7-b1c6-208330cac60f/receipt.json`.
- Failed conditional cleanup after successful consumer cases:
  `bridge-remote-tls-30e836e7-cb70-417c-9b77-33b69e505b53/receipt.json`.

Original copies remain under `/var/log/kazoo-acceptance/` on .26. The failed
cleanup run's two empty synthetic queues/exchanges remain in the **stopped
isolated broker** for inspection; no customer data is involved. The passing
run removed only its own fresh UUID-named resources, not earlier evidence.
Protected setup receipt, broker state and synthetic credentials remain under
the .44 fixture directory. Never commit that directory or its generated keys.

## Source and reproduction

Tracked helpers:

- `scripts/prepare-bridge-remote-proof.py`: root/host-specific exclusive
  preparation; refuses existing state/user/unit rather than replacing them.
- `scripts/accept-bridge-remote-tls.py`: fixed original dev client and isolated
  broker authority; reads a protected fixture, never production configuration.
- `scripts/accept-push-bridge-consumer.py`: reused native consumer proof; now
  obtains TLS options from the production builder instead of hardcoding none.

The broker was already prepared. **Do not rerun creation** against its existing
state. Its synthetic certificate expires after two days; do not weaken TLS to
reuse an expired fixture. A new clean fixture/certificate preparation needs
explicit scope review if this retained fixture is replaced.

The original client reads only
`/root/kz5-bridge-remote-proof-client/client.json`, transferred over pinned SSH
from the isolated broker's root0600 `client.json`. That file contains synthetic
broker credentials and public CA material, not provider credentials. To rerun
while this exact fixture/certificate is valid, start only the isolated unit,
then run on the original development client:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 256 --reserve-mib 512 \
  --runtime-sec 300 -- \
  /usr/local/lib/kazoo-push-bridge/current/venv/bin/python -B -I \
  /opt/kz5/scripts/accept-bridge-remote-tls.py --run-development-remote-tls-proof
```

Stop only the isolated unit afterward. The runtime itself remains general;
this acceptance harness intentionally refuses other hosts/ports/vhosts.
Replacing the deleted original client requires a newly reviewed distinct
development-client scope, not silently running a local loopback substitute.

## Corrections found during acceptance

The initial temporary-broker setup failed first at CHDIR (umask077 removed
group traversal) and then while replacing its expanded-plugin directory (the
parent was deliberately root-owned). Source now sets exact requested modes and
places plugin expansion under its service-owned `state` directory. Ten setup
regressions include real restrictive-umask filesystem checks and the guarded
exact old-to-new unit transition. Unknown unit edits are refused.

The first client reached TLS but expected RabbitMQ's display cluster name to
equal its node name. Actual authenticated overviewa3e753 identified the mismatch;
the fixed assertion requires **both** exact expected names.

The next run passed TLS/consumer/retry but failed cleanup. RabbitMQ3.13 rejects
the if-unused and if-empty flags for quorum queue deletion, confirmed by the
actual NOT_IMPLEMENTED response1d3cf2 and the pinned
[quorum queue delete implementation](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbit/src/rabbit_quorum_queue.erl#L684).
The fixture-only cleanup now checks both queues are empty and have no consumers
before deleting, and checks the broker reports zero removed bodies. This is not
an atomic/general-purpose cleanup guarantee; it relies on this run owning the
sole synthetic producer/consumer in its isolated UUID scope. Foreign scope,
nonempty/active/unknown counts and unexpected removed bodies all fail tests.
Thirteen remote-proof tests and eleven existing native-consumer model tests
pass. These offline tests do not replace the actual passing remote proof.

Broker TLS and management configuration follow the upstream
[TLS guide](https://www.rabbitmq.com/docs/ssl) and
[RabbitMQ3.13 management guide](https://www.rabbitmq.com/docs/3.13/management).
