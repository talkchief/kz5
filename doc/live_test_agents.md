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

Installation enables the service but deliberately does not start it. Startup
reports ready only after all exact SIP contacts are present and all 30 marked
agents have logged in on the first start. The supervisor checks child processes,
registration failures, contact loss, and ownership drift. During live operation
a dead phone is restarted individually only after zero-active-call proof;
healthy phones and agent login/pause states are preserved. A running phone keeps
its registration-refresh loop even after a transient refresh failure. Ownership
uncertainty pauses repairs rather than logging everybody out.

A fatal supervisor failure preserves agent statuses across automatic restart;
systemd has a bounded restart policy. Explicit operator stop is the operation
that logs out the complete owned fixture set. Thus neither a single phone
failure nor routine registration renewal resets healthy agents' selected state.
The unit uses `Wants` and startup ordering, not `Requires`/`BindsTo` lifecycle
coupling. Restarting FreeSWITCH does not implicitly stop all test phones or
reset their agent statuses.

Stop the test phones with:

```sh
systemctl stop kazoo-live-test-agents.service
```

Cleanup logs out only the 30 owned agents, deregisters only their exact loopback
contacts, and may hang up only channel legs whose account, owned device ID, and
SIP peer `127.0.0.40` all match. It does not delete users, devices, queue, or
callflows. Uncertain ownership causes cleanup to refuse mutation. A post-stop
hook retries after an unclean supervisor exit. Lost contacts expire in at most
600 seconds if the SIP proxy cannot be reached during cleanup.

SIP passwords remain in private runtime injection files, never process
arguments or service logs. Runtime statistics are private and bounded; SIP
message tracing and packet capture are not enabled by this service. The fixed
port ranges must remain reserved for these test phones. Ordinary acceptance
tests retain their separate tenant and `127.0.0.20` fixtures unchanged.
