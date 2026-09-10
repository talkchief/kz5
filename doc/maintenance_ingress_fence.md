# Persistent local ingress fence

This is one component of INST-06, **not a complete cluster maintenance
coordinator or proof of drain**. It is implemented in root kz5 source at
`scripts/kazoo-maintenance-fence.cjs` and installed by `install-kazoo5.sh`.

## Deployment and startup

Normal installation of apps, FreeSWITCH, Kamailio or Monster UI now installs
Node.js, nftables/iproute/util-linux as needed, copies the self-contained helper
to `/usr/local/libexec/kazoo5-maintenance-fence`, and writes
`35-kazoo-maintenance-fence.conf` under the selected service's systemd drop-ins.
The hook runs as root even when the main service is unprivileged. It runs after
the OS firewall services and before ExecStart. It does not depend on a source
checkout being available during boot. Normal service verification compares
installed helper bytes, checks the effective startup command and performs a
read-only intent/kernel consistency check.

The hook applies existing durable closing intent before permitting startup.
Corrupt state, interrupted release, unknown tables or altered rules refuse
startup. No timer reopens admission. Database, broker and controller services
do not receive this ingress hook; maintenance must keep their control paths
available. Replacing or flushing firewall rules externally still invalidates
fence proof and must be detected before the coordinator proceeds.

## Coordinator interface (root only)

```sh
node /usr/local/libexec/kazoo5-maintenance-fence --close /root/private-maintenance/spec.json
node /usr/local/libexec/kazoo5-maintenance-fence --verify GENERATION
node /usr/local/libexec/kazoo5-maintenance-fence --status
node /usr/local/libexec/kazoo5-maintenance-fence --boot-guard
node /usr/local/libexec/kazoo5-maintenance-fence --release GENERATION
```

The spec must be a root-owned0600 regular file with a root-owned0700 parent:
schema_version1, a32-hex generation,64-hex manifest_sha256, bounded roles and
explicit TCP/UDP port arrays. Accepted roles: kazoo-apps, freeswitch, kamailio,
monster-ui. The coordinator must independently derive and verify **complete
actual listener coverage**; accepting a spec does not prove its ports cover
all ingress. Standard control-plane ports and detected/configured SSH ports
are refused. Arbitrary nft syntax is never accepted.

The helper owns only table `inet kz5_maintenance`. TCP admission on selected
ports is rejected, including existing connections; selected UDP is dropped.
Both IP families are covered. Other tables/ports remain unchanged. The nft
table is created exclusively and checked against the exact expected rules;
unknown tables are never overwritten. See the upstream
[nftables manual](https://netfilter.org/projects/nftables/manpage.html).

Private state is fsynced under `/var/lib/kazoo5-maintenance/fence`:
`active.json` precedes rule installation; `releasing.json` precedes removal;
`released-GENERATION.json` prevents generation reuse. Operations hold a kernel
flock. Boot guards wait up to30seconds for another guard; administrative
operations refuse concurrent writers immediately. Interrupted release permits
only explicit matching-generation release
recovery, never automatic restoration or reopening. The cluster journal must
durably enter its reopening phase **before** local release is invoked. This
local helper does not independently validate the remote coordinator journal.

## Evidence — September9–10,2026

- 11 persistence/kernel-adapter tests and5 actual-installer wiring tests PASS.
  Seven existing address-gate mappings/readback regressions still PASS.
- Real packets in a disposable network namespace: IPv4/IPv6 TCP, UDP, existing
  TCP rejection, unrelated-port/table preservation, volatile kernel-state loss
  and durable reapply, explicit release restoring reachability all PASS.
  No host firewall was changed by that test.
- Actual systemd acceptance on owned private apps14 PASS, native exit0:
  `/var/lib/kazoo-stage/fence-systemd-E8BQOL/receipt.json` inside
  `kz5-stage-kazoo-apps`. Helper SHA256
  `17c5d6971a1807d5e0d6206e99bc728279117d33861451f82a96c6726850ae93`.
  The real installer installed the apps hook. A temporary unprivileged service
  using that hook started normally and with a closed fence; kernel-state loss
  was repaired before startup; a torn intent prevented the main PID starting;
  explicit release restored normal startup. Scoped cleanup verified open
  admission and removed only the generated temporary test unit. Protected
  receipt/log and released-generation history remain. Apps itself was not
  restarted. Main44's main services were not changed by this acceptance.
- A new concurrent-startup regression reproduced a real failure with the
  first helper: `fence-systemd-jJb4tP/receipt.json` is FAIL at phase
  `concurrent_startup_lock`. The initial nonblocking lock could reject another
  service starting at the same time. The corrected bounded startup wait passes
  the identical native fixture (`E8BQOL` above). Earlier `ztWq0x` FAIL and
  pre-concurrency `VHJWan` PASS remain retained; neither is rewritten.
- Main installer dry-run/security/ALL, modular endpoint/service-gate and
  non-mutating verifier regression suites PASS in a network-isolated guard.

Run source tests with `node --test scripts/test-kazoo-maintenance-fence.cjs
scripts/test-kazoo-maintenance-fence-wiring.cjs`. Native packet runner is
`scripts/test-kazoo-maintenance-fence-native.cjs` and refuses the host network
namespace. Systemd runner is `scripts/test-kazoo-maintenance-fence-systemd.cjs
--live`, restricted to the owned apps14 guest; the host must validate guest
ownership, completed builds and empty media, then hold the acceptance lock.

## Still required before INST-06 can close

Pinned FreeSWITCH source inspection on September10 confirms why a runtime
`fsctl pause` alone cannot satisfy restart persistence. At
`ef32e205295e29f034f1453ad245ba5efb07b94a`, SCF_NO_NEW_SESSIONS is the bitwise
union of the inbound/outbound flags (`src/include/switch_types.h`), not a third
independent flag. `fsctl pause_check` tests both bits, while its inbound/outbound
variants report each bit. Session allocation checks the directional and global
ready predicates in `src/switch_core_session.c`. Normal core startup explicitly
clears both bits before api_on_startup (`src/switch_core.c`). Therefore even
reapplying pause from api_on_startup leaves an admission window; a durable
startup barrier must precede that clearing/admission point. This is verified
source behavior, not a native persistent-media-fence acceptance result. No
media pause/resume or firewall mutation was made during this inspection.

Internal media origination, queued AMQP work, durable callbacks and asynchronous
producers are not stopped merely by this input-port fence. Complete ingress
coverage, media/producer fencing, broker/queue/callback drain, startup completion,
durable whole-VM checkpoint/restore (including infinite pauses and empty runtime
membership), verified rollback and controlled cluster reopening remain required.
Passing this helper's tests does not replace those gates.
