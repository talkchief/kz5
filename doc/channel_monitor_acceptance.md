# Opt-in call monitoring acceptance

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

Only RTP involving these synthetic endpoints is captured. Captures and numeric
evidence stay in a root-only `/var/log/kazoo-monitor-acceptance-*` directory;
there is no SIP packet capture or production recording. Temporary credential
injection files are removed during cleanup.

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

Offline tests have passed. The first live attempt on 2026-09-05 found a
direct-call `kz_bridge` dialstring parsing failure before an agent connected;
the isolated caller, registrations, and temporary users were cleaned up.
All four live audio proofs remain a separate deployment gate.
Passing on one server proves media routing on that topology; it does not by
itself prove multi-node failover or geographically distributed cluster behavior.
