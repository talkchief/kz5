# Native broker maintenance inventory

## Status — September 10, 2026

The read-only inventory helper and its normal RabbitMQ installer wiring are
implemented. Actual development-broker acceptance passed, including a queued
message and a delivered but unacknowledged message. This is a component of
coordinated maintenance, **not a completed producer fence or upgrade executor**.

Source: `scripts/kazoo-maintenance-broker.cjs`. Normal `rabbitmq` installation
installs the required Node runtime and deploys the helper as
`/usr/local/libexec/kazoo5-maintenance-broker`. Role verification compares exact
source bytes and checks executable syntax. Standalone broker hosts do not need
Monster UI installed. Current native command shapes are checked for the pinned
RabbitMQ 3.13.7 version; another version refuses until reviewed and tested.

Run on the named broker host as root, using its configured Kazoo vhost:

```sh
umask 077
/usr/local/libexec/kazoo5-maintenance-broker --snapshot rabbit@BROKER_HOST KAZOO_VHOST
```

Replace both placeholders. The output contains internal queue/connection
identities: keep any saved receipt root-private and do not publish it in Git.
Exit zero means a complete observation, **not necessarily an empty broker**.
Inspect `broker_work_empty`; any missing/invalid/changing observation exits
nonzero with `MAINTENANCE_BROKER_INVENTORY_REFUSED`. No automatic retry, mutation,
restart, message acknowledgement or message deletion is performed by the helper.

## What it checks

- All cluster members are running, without partitions, alarms or maintenance.
- Native process PID and Erlang creation identity are unchanged across the scan.
- The selected vhost exists. All its queues, including unavailable queues, are
  requested; an unavailable or unsupported queue refuses rather than disappearing.
- Queued and unacknowledged queue counts agree with channel observations.
- Connections, channels and consumers reconcile; missing identities refuse.
- Uncommitted messages, uncommitted acknowledgements and outstanding publisher
  confirms also prevent `broker_work_empty` from becoming true.
- Queue and connection observations and cluster membership are checked again.

The exported `requireQueues` additionally verifies an expected runtime queue
list is present, empty and has consumers. It must be supplied from authoritative
runtime inventory by the future coordinator; it is not wired into an executor.

The helper uses the underlying native CLI as the existing RabbitMQ service user,
with `/var/lib/rabbitmq` as its working directory. It does not use delayed
management statistics or invoke the root wrapper that can repair cookie modes.
CLI deadlines, response bounds and strict JSON decoding fail closed.
The native queue/channel meanings are described in the
[RabbitMQ CLI reference](https://www.rabbitmq.com/docs/man/rabbitmqctl.8).
Cluster-wide collection was checked against the pinned 3.13.7
[channel command source](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_cli/lib/rabbitmq/cli/ctl/commands/list_channels_command.ex).

## Actual broker acceptance

`scripts/test-kazoo-maintenance-broker-live.cjs --live` is restricted to main
development host `dev-testing` / `10.1.0.44`, with the shared acceptance lock.
It creates one randomly named, previously absent test vhost and grants the
configured test connection user permissions only inside that vhost. Credentials
reach the already installed AMQPStorm client through private stdin, not argv.
No customer queues, calls or CouchDB documents are used.

Native unit `kz5-native-broker-drain-20260910` completed with exit zero. Protected
evidence on dev44: `/var/log/kazoo-broker-acceptance-trloi2/receipt.json`, plus
`empty.json`, `ready.json`, `unacknowledged.json` and `settled.json` in that
directory. Launcher log: `/var/tmp/kz5-broker-acceptance.J2kCWhNt/run.log`.

1. An empty native queue reported empty.
2. Publishing one synthetic message reported one ready message and not empty.
3. Retrieving it without acknowledgement reported one queue and one channel
   unacknowledged delivery and not empty.
4. Acknowledging it returned the native observations to empty.
5. The client closed and its exact test vhost was deleted and verified absent.

All 41 focused broker, installer-wiring and cold-maintenance guard tests passed.
The same change fixes the cold-maintenance harness's private staging list to
include the previously added callback inventory helper. Its regression runs
the actual installer functions against only the staged source files.

## Remaining coordinated-maintenance acceptance

These sequential observations are not an atomic snapshot or a promise that
producers cannot publish after the scan. Both `producer_fence_proven` and
`complete_cluster_drain_proven` remain explicitly false. Before version
activation, the coordinator still needs an enforced business-producer barrier,
runtime/broker/durable callback reconciliation under that barrier, and tested
cohort activation and rollback. Do not use this helper alone as permission to
restart services. See `maintenance_callback_inventory.md` and the current
point 4 entry in `FOCUSED_CLOSEOUT_2026-09-09.md`.
