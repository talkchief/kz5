# Test-phone recovery after host overload

On September5,2026 the thirty receive-only SIPp phones stopped at
23:22:27–23:23:22 UTC. Every retained statistics file reported one fatal error,
eleven major watchdog trips and zero failed SIP transactions. Matching SIPp
3.7.7 source terminates after more than ten major watchdog delays. The
supervisor stayed running with no SIPp children; this is not healthy phone
readiness and preceded the host-global OOM recorded at23:27.

Two guards prevented recovery:

1. Runtime ownership verification incorrectly required the original thirty-
   agent roster. The operator had deliberately selected one agent. Changing
   that roster is not authorized by phone recovery.
2. The zero-call parser rejected FreeSWITCH's valid `{"row_count":0}` response
   because it demanded a `rows` array.

The source fix adds `--verify-phones-only`, checking exact saved user/device
ownership and authentication plus the protected MicroSIP identities. Startup
and periodic phone recovery use that mode. Full `--verify-only` remains
unchanged for provisioning, explicit agent operations and cleanup. Recovery
still requires dead owned children and complete zero-call evidence; it never
changes roster, login or pause state, relaxes the watchdog or kills healthy
phones. Status reporting now exposes the registered count and sanitized
blocked-repair reason.

`clear_fixture_calls` now returns immediately without channel actions for the
same strict zero-call proof. Malformed/error/contradictory listings are rejected
before its unchanged per-channel account/device/source-IP authorization.
Cleanup still requires the original full ownership gate first.

Offline gates are `test-live-test-phone-ownership.cjs`,
`test-live-test-phone-recovery.sh`, `test-live-test-agent-state-snapshot.cjs`
and the existing provisioner tests. They use mocked data/functions, not live
SIP or queue writes. `snapshot-live-test-agent-state.cjs` can record exact
pre/post roster and reported agent status/membership in exclusive0600 files
under a root0700 evidence directory. It refuses redirects, caps responses and
does not print credentials. A protected non-agent's missing queue membership
is recorded as explicit absence only after confirming the user document also
lacks that field; it is never inferred as logout or an empty configured list.

Activation requires separately reviewed root execution. A successful ordinary
service stop has cleanup semantics and is not automatically a status-preserving
reload. Preserve the exact roster/agent snapshot and protected restart marker,
prove the actual unit's failure-restart behavior, and recheck zero calls and
exact process ownership before any targeted supervisor action. No broad
process signals or backend restarts are part of this repair.

## Live recovery, 2026-09-06 00:12–00:14 UTC

The reviewed source is deployed. All 20 phone-ownership, 17 snapshot and 13
existing provisioner checks passed, along with the shell-function mocks and
`shellcheck -x -P SCRIPTDIR`. An actual authenticated phone-only verification
passed all 62 exact user/device reads without queue or status writes.

Protected before/after snapshots retain exactly one queue member (owned agent
12), 29 `logged_out`, one `ready`, and the protected MicroSIP user's reported
`unknown` status with explicitly absent queue membership. They are sequential
latest-reported observations, not an atomic runtime/FSM snapshot. No snapshot
was automatically restored and no roster or login/logout command was sent.

At 00:12:36 the exact stalled supervisor PID 2170317 was signalled with SIGKILL
after checking its executable, command line, start ticks, complete service
cgroup, unit contract, protected preservation marker and zero native calls.
The first private activation gate had refused an incorrect expected sleep
argument before any signal; the original source confirmed its two-second
monitor sleep before the fresh successful check. SIGKILL deliberately bypassed
the old Bash exit trap, whose saved dead child PIDs could have been reused.
The fixture operation lock was immediately released before automatic restart.
The journal explicitly confirms failed-stop cleanup was skipped to preserve
agent state. This procedure is for that exact zero-phone incident, not a
general instruction to kill a running phone supervisor.

The replacement supervisor PID 3323761 reached `30/30` registered at 00:12:58,
with one intentional fixture-service restart. All 30 exact SIP contacts were
independently checked. The members/device acceptance returned 31 members and
31 devices, **30 online / 1 offline**, complete registrar observations, unchanged
catalogs and passing anonymous/malformed-cursor checks. It did not place calls.
Applications, eCallMgr, FreeSWITCH, Kamailio, RabbitMQ and CouchDB retained their
previous main PIDs with no restarts; the current-day Kazoo crash logs were empty.
The prior day's 23:27 crash records remain in the normal midnight `.0` rotation.

Protected evidence: `phone-recovery-deploy.JNM0iR` below
`/usr/local/src/kazoo5-installer/`, and
`/var/log/kazoo-acceptance/phone-recovery-members.RFdj9y/`.
Registration recovery is not post-incident callback, load or HA acceptance.
