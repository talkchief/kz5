# Separate Kamailio admission

The distributed call test registered successfully but its INVITE received403
from FreeSWITCH. Kamailio's journal proved authorization and forwarding to the
media server; the exact SBC address failed its authoritative ACL. The installer
previously assumed remote discovery while eCallMgr defaults that worker off.

Normal eCallMgr installation now persists `enable_discovery_server=true`, starts
the existing supervised worker if absent, and verifies effective configuration
and the running process. The worker uses native Kazoo Proxy advertisements to
maintain exact listener ACLs and publish media reloads. This also handles an SBC
installed after its controller. No entire private subnet is admitted.

The zone's AMQP credentials are a trust boundary: only authorized Kazoo services
may publish node advertisements. Native discovery also maintains media ACLs.
Do not share broker credentials or a writable configuration database with an
untrusted deployment. Existing operator ACL entries are retained by discovery.
A node-specific override disabling discovery causes verification to fail; resolve
that conflicting configuration deliberately instead of reporting readiness.

Regression: `node scripts/test-ecallmgr-sbc-discovery.cjs` tests initialization,
already-running, write failure, rejected result, start failure, effective override,
dry run, and normal installer wiring. Native call after-test remains pending.
