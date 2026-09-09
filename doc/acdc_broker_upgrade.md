# ACDC callback queue upgrade guard

The callback retry fix retains `acdc.queue.<account>.<queue>` work queues with
`auto_delete=false`, `durable=false`. Older deployments declared auto-delete
queues. RabbitMQ cannot change that property on an existing queue. Starting new
consumers against an old declaration can fail instead of restoring callbacks.
See [callback repair evidence](callback_originate_receipt.md).

`scripts/install-kazoo5.sh kazoo-apps` now calls the read-only
`scripts/acdc-broker-preflight.cjs` before media imports/build and again immediately
before the apps restart. It rejects incompatible work queues, unreadable metadata,
unknown work-queue naming or incomplete inventories. Normal secondary
`acdc.queue.manager.*` auto-delete queues are not work queues and are excluded.
No AMQP declaration, message read/ack, purge, deletion or ticket mutation occurs.
Dry-run reports the planned check, not a successful live check.

## Local and separate broker hosts

The effective `KAZOO_AMQP_URI` determines host, port and vhost; explicit URI
settings take precedence over split host variables. On a local broker, every
resolved address must belong to this server, and the RabbitMQ CLI listener must
own the exact AMQP port/protocol/address before its queue inventory is accepted.
CLI calls are bounded and run as the installer user, normally root.

For a remote broker, supply these deployment inputs through the existing
protected installer environment/config mechanism, not command-line secrets:

- `KAZOO_RABBITMQ_API_URL`: management origin on the **same broker host** as the
  AMQP URI, for example `https://rabbit.internal:15671`. No URL credentials,
  path, query or fragment. An AMQPS configuration requires HTTPS management.
- `KAZOO_RABBITMQ_API_USER` and `KAZOO_RABBITMQ_API_PASSWORD`: optional overrides
  for the AMQP credentials. The identity must have the RabbitMQ `monitoring` or
  `administrator` tag and visibility of the configured vhost. The normal Kazoo
  AMQP service user may not have a management tag; the installer does not grant
  privileges automatically. Prefer a dedicated monitoring identity.

The operator must point the management origin at the same broker/cluster as the
AMQP endpoint. Do not point it at a different RabbitMQ instance on that host.
TLS certificates are verified; use trusted internal certificates when applicable.
Management credentials are persisted with the other root-only deployment inputs.
They are not passed in process arguments or printed on API/CLI failure.

The remote reader checks identity and the configured vhost's built-in default
exchange, then GETs paginated, name-filtered
queue metadata for that vhost only. It requests no message bodies. Redirects,
partial/changing counts, duplicate queues and foreign vhosts fail closed. Limits:
100 pages of100 queues, 4MiB per response,15s per request and60s metadata budget;
the shell bounds the whole helper to90s. If a limit is reached, upgrade is blocked,
not certified safe. API shape/reference:
[RabbitMQ HTTP API](https://www.rabbitmq.com/docs/http-api-reference).

The default-exchange check deliberately avoids `GET /api/vhosts/{vhost}`:
RabbitMQ3.13.7 makes that endpoint administrator-only, including GET. Its scoped
exchange GET uses vhost authorization and works with monitoring access. This was
confirmed against the installed broker (401 versus200), not inferred from mocks.
Source: [vhost authorization](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_management/src/rabbit_mgmt_wm_vhost.erl),
[exchange authorization](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_management/src/rabbit_mgmt_wm_exchange.erl).

## An old declaration was found

Do not delete it merely because the message count is zero. Coordinate every old
consumer on this vhost/account; stop new admissions, drain calls and outstanding
callback tickets, and verify no pending delivery or recovery work. Only then stop
all legacy consumers together so their old auto-delete queues can disappear.
Re-run the installer after verifying this coordinated drain. Investigate any
retained incompatible queue explicitly; this guard never removes it for you.

New retained queues survive loss of their last consumer. Rolling back to code
that declares `auto_delete=true` likewise requires a coordinated drained
migration; blindly removing retained queues can discard callbacks. Do not share
these work queues between old and new consumers or writable v4/v5 deployments.

## Validation and boundaries

`bash scripts/test-acdc-broker-preflight.sh` covers legacy rejection, retained and
fresh inventories, malformed metadata, local endpoint identity, remote scoping,
pagination, restricted access, TLS downgrade and failure before apps mutation/
restart. These are focused regression fixtures, not split-server acceptance.
The local main-dev broker is checked separately without restarting services.

September9 evidence: source commit `3b284b0`; eleven regression groups and both
real apps-installer abort-order checks passed (bd0b59). After master sync, executing
`acdc_broker_upgrade_preflight` from the sourced installer using saved settings on
10.1.0.44 returned exit0 and `{"work_queues":2,"compatible":true}` (c9cbca).
No metadata writes or service restarts occurred in that local check.

### Separate-server metadata acceptance — September9

The first real remote check failed (a357d7): a monitoring user could read the
queues but received401 from the single-vhost details request. Diagnostic4e7227
confirmed the exact isolated broker and permissions. The regression reproduces
this (ba89ac: three failed groups before correction); all11 groups and both real
installer abort-order checks pass after the default-exchange correction (7837a1).

`scripts/accept-acdc-broker-preflight.cjs --run-development-remote-preflight`
then exercised the **actual shell installer helper** from10.1.0.26 against the
existing isolated RabbitMQ3.13.7 instance on10.1.0.44, with certificate-verified
HTTPS on35672 and its monitoring identity. This runner is explicitly fixed to
that development fixture and refuses general/production destinations.

Native result24bfc5, exit0:

- Initial inventory accepted with no ACDC work queues.
- One fresh UUID-owned classic queue with `auto_delete=true` correctly blocked
  the real installer guard, despite being empty and having no consumers.
- After broker-conditional removal of that exact empty queue, its retained
  `auto_delete=false` replacement passed.
- Exact owned queue removed with `if-empty` and `if-unused`; final inventory
  passed. No messages published, provider calls or runtime installations.

TLS used the existing short-lived test CA through `NODE_EXTRA_CA_CERTS`; no TLS
verification was disabled or certificate generated. For a private management CA,
provide a trusted CA file to Node before launching the installer. This environment
input is not persisted by the installer; a reusable CA-input option remains a
separate deployment improvement, not something this run proves.

Receipt: `/var/log/kazoo-acceptance/acdc-broker-preflight.3FZ8FO/receipt.json` on
the original dev client; also retained on main44 as
`/root/kz5-acceptance/acdc-broker-preflight-3FZ8FO.json`.
SHA256: `2b91dffb2c64e0e619b0cdeb2cad15c19d32c72e32ffb96db3356c1ddc4df3eb`.
Helper SHA256: `3249377ba05632d073702337cd6720a993c5bae03c03059a7ca38610b1ae11ca`.
Normal RabbitMQ remained PID2355/restarts0. The isolated broker was stopped
afterward and35671 had no listener (ce25fc). No production broker was accessed.

This proves the remote **preflight** path and declaration discrimination, not a
fresh remote apps deployment, AMQPS consumer connection, full migration/rollback
or real callback failover. Earlier fixture-only status is superseded only for
the exact metadata cases above.

This is a refusal guard, **not automatic migration, distributed deployment locking,
broker persistence or failover proof**. Two reads reduce the build-window risk but
cannot prevent another old node from declaring a queue afterward. Operator
coordination is still mandatory. A true separate-broker acceptance run, old queue
migration/rollback and crash-atomic multi-role deployment remain open release gates.
