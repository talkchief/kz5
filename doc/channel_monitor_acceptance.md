# Opt-in call monitoring acceptance

## Latest actual-call result — September 10, 2026

**Post-terminal-cleanup installation PASS:** after normal private applications
installs16/12 on source `8343d47`, `kz5-stage-monitor-terminal-cleanup-1` exited0
using runner `6b4216e`. All four modes passed actual SIP/RTP, independently
reanalyzed privacy windows before/after keypad3, authorization negatives,
supervisor stop202 and original bridge survival. Protected evidence on dev44:
`/var/log/kazoo-monitor-acceptance-CXndtt`; log
`/var/lib/kazoo5-install-lab/monitor-terminal-cleanup-1.log`.
Fresh strict native inventories also passed for all six agent/listener replicas;
media admission was open with zero sessions and no retained monitor fixture.
This is the installed version containing the terminal-event source correction,
not merely the earlier runtime. Main44 runtime promotion and full coordinated
maintenance remain unproven; see `acdc_listener_terminal_cleanup.md`.

**Fresh user-requested retest PASS:** `kz5-stage-monitor-user-retest-1`
exited0 on runner `40f1712`, after the two-applications-VM cold-restore tests.
Listen/eavesdrop, Whisper, Barge and Join each used a new three-leg SIP call
through the isolated distributed dev44 stack. Independent reanalysis of all
four saved RTP captures confirms both pre/post-keypad3 privacy windows:
Listen leaks no supervisor audio, Whisper reaches only the agent, and Barge
and Join reach both original parties. All five authorization negatives per mode,
supervisor stop202, and original bridge survival pass. This was actual call/audio
testing, not acceptance of an HTTP response alone.

Protected evidence: `/var/log/kazoo-monitor-acceptance-bev21u` on dev44;
log: `/var/lib/kazoo5-install-lab/monitor-user-retest-1.log`.
Independent final checks confirm media admission open, zero media sessions,
no retained monitor fixture, and media/both applications services active.
The harness removed its exact temporary users and registrations. No production
or imported-company calls were used. This proves these bounded supervision
cases, not general availability or full maintenance drain: the separately
observed apps-peer strict agent-drain discrepancy remains open. The legacy
queue-eavesdrop endpoints remain deliberately disabled; use the named
channel-supervision instructions at `/apis/supervision.html`.

**Additional after-restart PASS:** after the native maintenance test restarted
FreeSWITCH twice, `kz5-stage-monitor-after-media-restart-1` exited0 using runner
`4cc4540`. All four modes pass on new SIP/RTP conversations; saved captures were
independently reanalyzed. Privacy before/after keypad3, all authorization checks,
stop202 and original bridge survival pass. Protected evidence on dev44:
`/var/log/kazoo-monitor-acceptance-DeA1qp`; log
`/var/lib/kazoo5-install-lab/monitor-after-media-restart-1.log`.
The test did not restart apps/controllers. Cleanup leaves admission open with
zero sessions and no monitor fixture. Media, two apps and two controllers were
active, with zero error-priority journal entries in the checked window since
the restart test began. This is post-restart call recovery, not live media HA.

**PASS: Listen/eavesdrop, Whisper, Barge and Join on the newly installed private
media build.** Native unit `kz5-stage-monitor-media-fence-1` exited0 using root
runner `a2b7946`, normally installed FreeSWITCH source `935d544` and applications
source `494ee28`. Protected synthetic evidence on dev44:
`/var/log/kazoo-monitor-acceptance-xD4WRr`; terminal log
`/var/lib/kazoo5-install-lab/monitor-media-fence-1.log`.

Each mode used an actual three-leg SIP conversation and captured RTP. Independent
reanalysis of all four captures confirms the expected tone routing and forbidden
supervisor leakage before/after keypad3. Listen is silent to both original
parties; Whisper reaches only the agent; Barge and Join reach both parties.
Authorization negatives pass, supervisor stop returns202, and the original
answered bridge survives every stop.

The post-keypad audio window is entirely within a verified durable media fence:
new internal calls are rejected while all three existing legs remain allocated.
The identical marked internal endpoint answers before fencing and after release.
Process/core identity is unchanged. Scoped cleanup completed; final native
admission is open with zero sessions and no retained monitor fixture.

This is real call/audio verification, not an HTTP-only result. Media process
restart persistence passes separately in `maintenance_media_fence.md`;
whole-cluster drain/restore/rollback and sustained-load acceptance of the new
media gate remain open. Use the documented channel supervision API;
the unsupported legacy queue eavesdrop endpoints still deliberately return503.

## Documentation command regression — September 10, 2026

The generated guide and OpenAPI curl examples contained literal leading plus
characters before continuation options. Eight local shell/argument regressions
reproduce the error and pass after correcting the shared generator. They verify
exact URLs, headers and JSON bodies using a local curl function; no network
request is sent. The normal documentation suite runs these tests and verifies
the regenerated assets. This fixes copy-and-paste instructions, not media code.
The actual-call evidence below remains separately recorded and was revalidated
against all eight retained healthy/partition synthetic RTP captures on September10.

Release `d3eb3c3` is deployed through the normal installer documentation function
on dev44. All13 served files match repository bytes over certificate-verified
HTTPS against the local nginx listener for kz5-dev.talkchief.io. The rebuilt
portal browser check loads653 operations with zero external requests/console
errors; API execution remains disabled. Eight shell-example regressions and
offline deterministic rebuild/schema/tamper checks pass. This does not claim
a new public-network reachability test or a new live call.

## Earlier actual distributed-call results — September 9, 2026

**Additional active-call fault acceptance PASS:** all four modes also pass a
controller16 broker-only partition, retaining controller21 and the media node.
Native `kz5-stage-monitor-partition-3` exited0 on runner `5554a11`; private
evidence `/var/log/kazoo-monitor-acceptance-o7yewF`. Audio/privacy is verified
inside the actual disconnected interval, then native broker/query-consumer
recovery with unchanged controller VMs, stop202 and original bridge survival.
Owned calls/users/registrations were cleaned up and both exact routes restored.
See `ecallmgr_query_readiness.md` for the readiness correction and retained
failed attempts. This is controller AMQP recovery, not media-node failover.

All four modes **PASS**: Listen/eavesdrop, Whisper, Barge and Join. Native unit
`kz5-stage-monitor-distributed-5` exited0. Private synthetic evidence on dev44:
`/var/log/kazoo-monitor-acceptance-6xZDTb`; terminal log
`/var/lib/kazoo5-install-lab/monitor-distributed-5.log`.

This run used real SIP calls and RTP tones through separate applications,
Kamailio, FreeSWITCH and controller guests, not mocked HTTP acknowledgements.
Each mode checked permitted routing and forbidden audio leakage before/after
keypad3, cross-account/non-admin denials, stale targets, forbidden route fields,
supervisor-only stop and survival of the original two-way bridge. Exact temporary
registrations and owned web users were cleaned up. No production/user audio was
recorded; the imported company was untouched.

Two real setup defects were found before this pass: remote SBC ACL discovery
was disabled, and a restarted AMQP connection worker was not registered. Both
are fixed in root kz5 source and normal installer handling; both controllers
passed installation on `0957b33`. Controller-peer automatic guest boot then
passed (`ecallmgr-peer-boot-1788981642738.log`). Failed attempts remain failed.
See `distributed_sbc_discovery.md` and `amqp_supervised_registration.md`.

This closes healthy distributed supervision/audio-privacy acceptance. The
additional broker-partition result above covers that specific active-session
fault, not media-node failover or indefinite production reliability.
Developer instructions have separate Whisper, Barge, Join and Listen sections
at `/apis/supervision.html`, also embedded in the OpenAPI operation. These use
the real shared POST channel endpoint; no nonexistent feature-specific routes
are advertised. Join currently has the same full-audio semantics as Barge.
Documentation release `ce41c0a` is deployed on dev44. All13 served assets matched
source bytes over certificate-verified HTTPS using the local nginx listener;
the browser exercised the named guide and OpenAPI with zero console errors,
external requests or API executions. Source-host public-IP access separately
timed out and is not counted as a successful reachability check.

## Current offline regression checkpoint

### Opt-in active supervision broker partition

`node scripts/test-channel-monitor-live.cjs --distributed --broker-partition --live`
adds a bounded controller16-only broker interruption after the real supervisor
leg answers. It admits the exact owned private lab controllers16/21 and requires
exactly the three owned synthetic legs. A3-minute independent systemd watchdog
removes only the added broker `/32` blackhole route if the harness is interrupted.
The test kills only controller16's existing TCP connections to lab RabbitMQ5672,
requires its native registered broker to become unavailable while controller21
stays available, and measures the post-keypad privacy window entirely during
that partition. It restores the route, requires registered availability with
unchanged controller VMs, then verifies supervisor-only stop and original bridge
survival. No main44 or production service/route is changed. This tests controller
AMQP loss with media preserved; it is not FreeSWITCH loss or call migration.

Ownership, exact-route, watchdog ordering, restoration and invalid native-status
guards pass in `controller-partition.test.cjs` without executing live commands.
Native partition run1 FAILED after Listen/eavesdrop broker recovery: the first
supervisor stop returned503. Cleanup subsequently succeeded without broad call
termination, and the exact route was restored. Evidence
`/var/log/kazoo-monitor-acceptance-sUXwor`, terminal log
`/var/lib/kazoo5-install-lab/monitor-partition-1.log`. Independent analysis of its
retained synthetic capture passes listen audio/privacy within the actual
partition window, including keypad3; same-controller-VM broker registration
recovered. This partial audio result does not convert the failed stop into a
full pass. The failing503 phase was the read-only ownership query. The normal
installer and harness now require native query-consumer readiness in addition
to broker registration. Run2 exposed a transient status-RPC handling gap and
required subsequent guarded cleanup. Run3 passes after bounded unready handling;
see `ecallmgr_query_readiness.md`. No blind API replay was added.

On 2026-09-06, guarded session `94674` passed the fixture ownership/security
checks, synthetic directional-audio checks for all four modes (including
keypad-3 escalation and forbidden leakage), and all three SIPp scenario parses
with zero calls. The run used a private network namespace, a 384 MiB memory
limit and a 60-second deadline. The parser error check now uses explicit
`/usr/bin/grep` because `rg` is absent from the validation guard's PATH.
This checks the acceptance harness; it is not a new live monitoring test and
does not close SUP-01–03 or the cross-node release gates.

## Live acceptance procedure and previous evidence

`scripts/test-channel-monitor-live.cjs` exercises the account-scoped monitoring
API using synthetic audio and the separately provisioned acceptance tenant. It
is never called automatically by the installer. Its default is not a live run;
an explicit mode is required.

Run offline validation first:

```sh
bash scripts/test-channel-monitor-harness.sh
sudo node scripts/test-channel-monitor-live.cjs --prepare-only
```

Only after the monitoring backend has been deployed and other acceptance calls
have ended:

```sh
sudo node scripts/test-channel-monitor-live.cjs --live
```

The harness refuses the MASTER account, non-acceptance realms, altered fixture
device identities, existing acceptance calls, and existing registrations for
the three selected phones. It calls internal extension `1002` from `1001` and
uses the existing `1003` device as the supervisor. It does not change queue
membership, agent availability, existing users, devices, or callflows.

Two marked temporary web users are created only inside the acceptance account:
an account administrator for authorized requests and an ordinary user for
negative authorization tests. The MASTER token is used for fixture ownership
checks and a cross-account denial test, never for MASTER resource changes.
Their generated passwords and durable resource identities are kept exclusively
in root-owned `0600` `/etc/kazoo/monitor-acceptance.json`.

All three SIPp endpoints use `127.0.0.50`, SIP ports `18100–18102`, and RTP ports
`49000`, `49002`, and `49004`. The proxy must be the local server. The customer,
agent, and supervisor transmit separate 440, 660, and 880 Hz tones. They do not
echo received audio, which would invalidate an isolation test.

| Mode | Supervisor hears original call | Agent hears supervisor | Customer hears supervisor |
| --- | --- | --- | --- |
| `eavesdrop` | Yes | No | No |
| `whisper` | Yes | Yes | No |
| `barge` / `join` | Yes | Yes | Yes |

Each mode is checked both before and after the supervisor sends keypad `3`.
The second check catches legacy DTMF escalation from listen/whisper into wider
audio access. The analyzer verifies all three transmitted stimuli, both
directions of the original conversation, expected supervisor injection, and
forbidden leakage. Missing packets or ambiguous streams fail the test.

The harness also requires cross-account and non-admin requests to return 403,
a stale target to return 404, an extra route parameter to return 400, and an
attempt to stop the original agent leg to return 403. A 202 start response alone
is not success: the correlated, answered supervisor channel and audio must be
observed. After stopping supervision, both exact original legs must remain
answered and mutually bridged before the test deliberately ends its own call.
The supervisor must still be present before the stop request, return HTTP202,
and then disappear. Short SIPp metadata also proves the exact original caller
received SIP180 before SIP200 in the same INVITE transaction.

Only RTP involving these synthetic endpoints is captured. Captures and numeric
evidence stay in a root-only `/var/log/kazoo-monitor-acceptance-*` directory;
there is no SIP packet capture or production recording. The private SIPp short
message logs contain only timestamp, direction, Call-ID, CSeq and the first SIP
line, never authorization headers or message bodies. Temporary credential
injection files are removed during cleanup. Crossbar requests use fresh HTTP
connections because blocking fixture subprocesses can outlast an idle pooled
connection; mutating requests are never automatically retried.

On a failed or interrupted run, use:

```sh
sudo node scripts/test-channel-monitor-live.cjs --cleanup
```

Cleanup checks the saved account/device, exact SIP Contact IP and port, local
proxy peer, and (when present) authenticated source IP for the original caller and
the exact monitoring request marker for the supervisor. It never selects calls
by a broad account-wide hangup. Temporary web users are deleted only after
their durable ownership markers match. Incomplete cleanup retains protected
recovery state; no unverified resource is deleted. Registrations expire within
600 seconds even if the registrar is unavailable.

Offline tests and all four live modes passed on 2026-09-05, 11:29–11:31 UTC.
The private evidence directory is
`/var/log/kazoo-monitor-acceptance-9VEPc6`; each mode has its exact call/request
IDs, two acoustic windows, authorization results, SIP ringing timestamps and
supervisor-stop HTTP202 proof. Eavesdrop delivered no supervisor tone to either
original party. Whisper delivered it to the agent but not the customer; barge
and join delivered it to both. All checks passed before and after keypad `3`.
Both original legs survived each supervisor stop, including a further
2.5-second observation. After cleanup, FreeSWITCH had zero channels, all three
fixture contacts were absent, and the temporary web users and protected
fixture state were removed. Fresh apps/ecallmgr/FreeSWITCH logs in the test
window contained no errors; each original caller executed `ring_ready()` and
received SIP180 before SIP200.

Earlier attempts exposed a direct-call `kz_bridge` parsing problem and a
monitor-stop reply-normalization bug, both fixed before this successful run.
An inter-stage HTTP transport failure and the initial short-message timestamp
parser mismatch also failed closed and cleaned up; the harness now uses fresh
HTTP connections and understands the pinned SIPp timestamp columns.
Passing on one server proves media routing on that topology; it does not by
itself prove multi-node failover or geographically distributed cluster behavior.
