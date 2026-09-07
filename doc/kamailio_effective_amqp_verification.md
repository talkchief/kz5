# Kamailio effective AMQP endpoint verification

September7 follow-up: main-SH producer-freshness deployment
`0de2e3/session54822/95d41c` passes the full SIP/AMQP/dispatcher/database/RPC/SBC
and current journal/JWT checks. This was a required configuration deployment,
not a restart to erase a failed gate. Backup:
`/var/lib/kazoo-kamailio-freshness.5xk2fp/kamailio`. Prior malformed-Via evidence
below remains preserved; its sender and cause remain unproven. No journal
filter or acceptance condition was weakened. See `push_bridge_freshness.md`.

The installer previously probed `KAZOO_AMQP_HOST/PORT` even when the rendered
Kamailio configuration used a different explicit `KAZOO_AMQP_URI`. It also
queried the default vhost of any active local RabbitMQ service. This could reject
a healthy standalone SBC using a remote broker or a nondefault vhost, or accept
queue evidence from the wrong broker.

`verify_kamailio_amqp_connection` now reads the effective URI through a bounded
stdin-only parser. Its host, explicit/default port (AMQP 5672, AMQPS 5671), and
once-decoded vhost drive verification. No URI or credential enters diagnostic
output or child command arguments. A missing path means `/`; an explicit `/`
path means the empty vhost. Query/fragment options, malformed encodings and
unsupported endpoint syntax fail closed rather than being silently ignored.

Transport evidence must be an established socket to the exact resolved peer and
port, owned by `kamailio`. Queue inspection applies only with an active local
RabbitMQ service and entirely local resolved broker addresses. Its diagnostics
must identify a listener matching the connected address, port and AMQP/TLS
protocol before a bounded `rabbitmqctl -p <effective-vhost> list_queues name`
inspection. Another address or port on the local node is not sufficient.

Remote/mixed-locality brokers and inactive local RabbitMQ explicitly report
transport-only verification: unrelated local queues are never treated as remote
evidence. A TCP socket alone does **not** establish remote authentication, vhost
permissions, consumer readiness or end-to-end distributed call handling. This
change does not add services/dependencies to a per-server module selection.

Offline regression: `node scripts/test-kamailio-amqp-verification.cjs`. It parses
synthetic URIs and extracts the actual installer functions into a shell with
stubbed DNS, socket, interface, service and RabbitMQ commands. It never sources
deployment configuration or reads real credentials. Cases cover split-setting
mismatches, remote brokers with unrelated local RabbitMQ, local nondefault/empty
vhosts, IPv6/TLS, exact listener identity, wrong peer/process/queues, malformed
inputs and redacted errors. These fixtures are not live deployment acceptance.

Root `d9be50/session50204/1578f8` passed all43 offline fixtures, modular installer
tests and bridge dispatch; the43 cases passed again in `37a62e/fb9511`.

Live main-SH `--verify-only kamailio`, `23b62b/session86116/c623a0`, passed the
effective AMQP transport, exact local-vhost consumer queues and eCallMgr SBC
checks. The whole command remains FAIL because its activation-wide journal gate
retains four earlier `core/receive.c:554 receive_msg(): no via found in reply`
errors. September7 UTC:15:16:37.934893,15:16:37.936639,15:20:36.111614 and
15:20:36.112976. Matching Kamailio6.1.4 source rejects replies with missing or
invalid Via. These are not JWT/AMQP errors; the journal alone does not establish
their sender. No gate was weakened, log deleted or Kamailio service restarted.
Attribution and combined clean current-runtime acceptance remain open.
