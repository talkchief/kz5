# Fenced agent checkpoint executor and cold-restart acceptance

This is a component of INST-06, not a complete cluster upgrade coordinator.
The root coordinator must authorize the current journal phase, close all
admission, prove producer/broker/callback/media drain, and retain the checkpoint
before invoking restoration. Never replay restoration after reopening.

## Installed local executor

The applications installer packages immutable copies of the snapshot, queue
inventory and restore escripts under `/usr/local/libexec/kazoo5-maintenance-*`.
Normal service verification checks their bytes against the selected source.

```sh
escript /usr/local/libexec/kazoo5-maintenance-restore --validate LOCAL_BIND_IPV4 /root/private/request.json
escript /usr/local/libexec/kazoo5-maintenance-restore --restore LOCAL_BIND_IPV4 /root/private/request.json
```

The request is a root-owned0600 regular, single-link file in a root-owned0700
non-symlinked directory. Its exact fields are `schema_version:1`, `generation`
(32 hexadecimal characters), `node`, `expected_epoch`, and `agents`. Each agent
has `account_id`, `agent_id`, `state`, `pause_until_unix_ms`, `queues`, and
`document_revision`. Ready requires deadline0; paused accepts an absolute Unix
millisecond deadline or `"infinity"`. Empty queues are valid. Use the actual
pre-restart checkpoint and document revisions, not the saved user queue roster.
The node/epoch identify the newly started target VM, not the old source VM.

Before the first write, the executor requires the exact complete target agent
cohort, paired drained FSM/listener identities, consuming listeners and matching
bindings, unchanged user document revisions, and a completed stable initializer.
The local installed firewall helper verifies the matching generation against
actual kernel rules. It rechecks that fence, node epoch, initializer, request
bytes and workers while restoring. Restoration invokes the production FSM then
listener APIs, requires successful notification/binding queuing, and checks the
resulting state, deadline, membership and binding registry. An expired finite
pause becomes ready; it is never extended. It never logs an empty-membership
agent out, releases a fence, retries writes blindly, or claims full cluster
drain. Failure can be partial: retain the protected checkpoint and all fences.
The coordinator still must prove broker binding delivery and cluster agreement.

## Validation and native test

`node scripts/test-kazoo-maintenance-restore.cjs` compiles the actual executor's
validation functions and tests five valid checkpoints,13 invalid checkpoints
and five private-file guards without RPC/network access. The installer has nine
focused helper/startup tests; four cold-fixture guards cover deadline/membership/
revision/cohort and ownership rejection.

`node scripts/test-acdc-cold-maintenance.cjs --live` is restricted to dev44 and
the original owned private lab. It holds the acceptance lock, verifies collected
apps/media installations, six ready agents, no fixture callbacks/calls or
preexisting fences, then installs only the helpers via the real installer
function. It does not change compiled Erlang code or either build checkout.
It fences both apps API ports and native media allocation, prepares one finite
pause, one indefinite pause and one ready agent with empty membership per node,
captures the actual runtime state to disk, restarts both applications VMs,
requires new epochs and completed initializers, and restores the hash-checked
checkpoint. Finally it restores the owned baseline and explicitly releases the
test fences only after verification. An interrupted/failed run retains private
state under `/var/lib/kazoo5-install-lab/cold-agent-state-*`; do not blindly rerun
while a generation or changed fixture state remains.

Native cold restart PASS: `kz5-stage-cold-agent-restore-1`, runner `e671f23`,
normally installed applications source `494ee28`. Receipt
`/var/lib/kazoo5-install-lab/cold-agent-state-R7xT5b/receipt.json` on dev44 was
independently verified: two changed VM epochs, six actual restored replicas,
hash-checked disk checkpoint, finite deadlines not extended, indefinite pauses
and empty membership retained. Baseline restoration and open/zero-session
cleanup pass. Fixture SHA256
`36ee7ae91a6c9c9145015743e23e8098945a65417d098643462fa2e15a5ddfa1`.

The strengthened fixture additionally correlates the native queue-manager
inventories with all six agents before restart and after restoration, and
requires the last restore request's preflight to refuse after fence release.
The extended campaign PASSES: `kz5-stage-cold-agent-restore-2`, runner `e0f4777`,
receipt `/var/lib/kazoo5-install-lab/cold-agent-state-tbT2Rt/receipt.json` on dev44.
Independent verification confirms both six-agent/two-queue inventories,
disk checkpoint restoration across both changed epochs, refusal of retained
request preflight after release (zero restored), and clean baseline recovery.
Fixture SHA256 `d4fc5ef222de74f124697746b2486b6107c0bc618d8f69bef7bbfbbeb781ecef`.
Main installer, modular and read-only source suites also pass in a network-
isolated validation guard after helper packaging changes.

The actual follow-up call profile is
`node scripts/test-channel-monitor-live.cjs --distributed --queue-calls --live`.
It routes two real calls through queue2000 and verifies both directions of RTP,
same agent FSMs and recovery to ready, without a broker interruption or an
agent login/SIP registration between calls. The first follow-up exposed retained
listener control-queue placeholders despite ready FSMs. After source8343d47 was
normally installed on both nodes, the strengthened follow-up passed with strict
all-six-replica drain: `kz5-stage-queue-terminal-cleanup-1`, evidence
`/var/log/kazoo-monitor-acceptance-5ZZRCj`. A second campaign with a real apps
broker interruption also passed: `kz5-stage-queue-terminal-partition-1`, evidence
`/var/log/kazoo-monitor-acceptance-e3Y5w1`. Both results were independently checked;
see `acdc_listener_terminal_cleanup.md` for the source fix and exact scope.
The fixture does not attest a complete cluster producer/broker drain, release
activation/rollback, host reboot or media HA.
