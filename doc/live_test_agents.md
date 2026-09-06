# MASTER account live test agents

`kazoo-live-test-agents.service` supplies 30 **test phones**, not production
human-agent workstations. The phones auto-answer and echo incoming RTP audio.
They never initiate calls, use a PSTN destination, or change the user's MicroSIP
device. They serve only the marked fixture users/devices 1002–1031 and queue
2000 in MASTER account `302ae5a70c403124f764cbc54229cfcd`.

The protected manifest is `/etc/kazoo/live-test-agents.json` (root:root 0600).
The provisioner verifies ownership markers before each login/logout operation.
Each SIPp phone binds a unique port on `127.0.0.40`: SIP 17100–17129 and RTP
46000–46119. REGISTER refresh and inbound calls share the same socket. Contacts
expire after 600 seconds and refresh every 240 seconds.

Preview without changing services or making SIP/API requests:

```sh
bash scripts/install-live-test-agents.sh --dry-run
bash scripts/run-live-test-agents.sh --dry-run
```

After provisioning and coordinated Kazoo deployment:

```sh
bash scripts/install-live-test-agents.sh --install
systemctl start kazoo-live-test-agents.service
systemctl status kazoo-live-test-agents.service
```

Installation enables the service but deliberately does not start it. Every start,
restart and reboot preserves the operator's current queue roster and agent
login/pause statuses. Startup waits up to 240 seconds on local unauthenticated
read probes, checks phone ownership once, and reports ready only after all exact
SIP contacts are present. The supervisor checks child processes,
registration failures, contact loss, and ownership drift. During live operation
a dead phone is restarted individually only after zero-active-call proof;
healthy phones and agent login/pause states are preserved. A running phone keeps
its registration-refresh loop even after a transient refresh failure. Ownership
uncertainty pauses repairs rather than logging everybody out.

A fatal supervisor failure preserves agent statuses across automatic restart;
systemd has a bounded restart policy. Service start and stop manage registrations
only. The runtime preservation marker is diagnostic evidence; losing `/run`
across reboot never authorizes login, logout or roster changes.
The unit uses `Wants` and startup ordering, not `Requires`/`BindsTo` lifecycle
coupling. Restarting FreeSWITCH does not implicitly stop all test phones or
reset their agent statuses.

Stop the test phones with:

```sh
systemctl stop kazoo-live-test-agents.service
```

Routine stop stops only owned phone children and, after fresh phone ownership
verification, deregisters their exact loopback contacts. It does not log agents
out or issue native call hangup commands. Stopping a phone process can still
interrupt that phone's active SIP dialog or media; drain its calls before an
operator stop. If ownership or the API is unavailable,
deregistration is refused; remaining contacts expire in at most 600 seconds.
The post-stop hook retries only this phone cleanup for a deployment that started
phones. An early dependency failure on a cold start without a started-phone
marker does not trigger authentication or cleanup. If a matching marker survives
an earlier incomplete cleanup, the post-stop hook retries ownership verification
and exact deregistration for those prior contacts, even when the new start fails
its dependency check. It still never changes agent statuses or the queue roster.

Initial provisioning, all-fixture login/logout and full fixture teardown remain
separate explicit operations. `provision-live-test-agents.cjs --agent-status
login|logout` and `run-live-test-agents.sh --cleanup` retain their complete
ownership and 30-agent roster gates. They are not invoked by the service and
will refuse an operator-selected partial roster. Full explicit cleanup can log
out owned agents and clear strictly identified fixture call legs; it never
deletes users, devices, queues or callflows. Do not run provisioning to reset an
operator's roster as a way to make phone startup succeed.

SIP passwords remain in private runtime injection files, never process
arguments or service logs. Runtime statistics are private and bounded; SIP
message tracing and packet capture are not enabled by this service. The fixed
port ranges must remain reserved for these test phones. Ordinary acceptance
tests retain their separate tenant and `127.0.0.20` fixtures unchanged.
