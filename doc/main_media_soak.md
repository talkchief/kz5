# Main development media promotion and 30-call soak

September10,2026. This is the remaining new-media load gate from INST-06,
not the cluster producer/broker drain or coordinated upgrade/rollback gate.

## Installed media — PASS

The previous main FreeSWITCH build did not expose `fsctl maintenance_check`.
The newer core had already passed normal private installation, live supervision
while fenced and process-restart persistence, but the older main30-minute soak
could not establish its load behavior.

Main44 (`10.1.0.44`, `dev-testing`) therefore received a normal
`scripts/install-kazoo5.sh freeswitch` installation on source `9972d12`.
Unit `kz5-main-media-promotion-20260910` exited0 and was collected. The protected
backup/run directory is `/root/kz5-main-media-promotion-20260910.xSDOxZhF`:
previous media/config/unit files, checksums, `run.log`, `media-after.json` and
`independent-install.json`. Root login environment, shared acceptance lock,
zero main agent workers and zero media sessions were verified before maintenance.
The existing30-agent synthetic fixture passed read-only capacity validation.
SIP ingress was stopped while media was rebuilt, and reopened only after success.
Applications/controllers were not rebuilt or restarted by this media installation.

Independent native observation confirms open admission, zero sessions and the
same installed process/core identity as the install receipt. The installed
`libfreeswitch` SHA256 is
`4550d0720645ec826f0c402ef0da6b8186cb34231159da56350b02fc72f6a1b1`.
No hot-load, Gemini request, production database write or historical callback
disposition was performed. This backup is not a tested rollback.

## Repeatable load gate

Run as root on the exact main dev host after normal media installation:

```sh
node /opt/kz5/scripts/test-main-media-soak.cjs --live
```

The wrapper refuses a different host/IP, deployment root, database/broker host,
public hostname or synthetic account. It admits only the existing isolated
acceptance account,30 configured agents, no running agent workers/calls and no
retained supervision fixture. It holds the shared acceptance lock, including
an inherited descriptor in the actual call process. Child setup cannot override
the saved deployment targets through inherited KAZOO/ACCEPTANCE variables.

It requires the normally installed helper bytes and durable-admission build
fingerprint, observes the actual media API, then runs the existing unmodified
`test-kazoo-calls.sh --live --stress --stages 30 --queued-excess 0
--soak-seconds 1800 --no-install-deps` workload. This is30 concurrent ACDC
conversations with real SIP/RTP, paced at2 starts/sec, not80CPS. Native media
admission and process/core identity are sampled during the run. Passing requires
the exact30/30 caller/agent successes, zero failures/errors/new cores, the full
1800-second verified hold, at least512MiB available memory, observed60 media
sessions, unchanged binary/config/call-harness bytes, and empty final native
media/agent inventories. Logs and receipts are root-only under
`/var/log/kazoo-main-media-soak-*`.

The existing capacity script retains its RTP, per-second concurrency, exact
SIP counters, agent recovery and scoped cleanup gates. Native observation does
not replace those checks. Interrupted/failed receipts remain failed; inspect
the exact running unit/receipt and native state before any retry. In-progress
output, an active service, or a short concurrency peak is not a completed soak.

Offline native epoch/admission and complete capacity-summary rejection tests
pass (`node scripts/test-main-media-soak-guards.cjs`). Invalid arguments refuse
before any native actions.

## Active native campaign — result pending

Runner `8472024` was pushed and synced before launch. Exact systemd unit:
`kz5-main-media-soak-20260910`, with `User=root`, `MemoryMax=4G`,
`TimeoutStartSec=3000`, private output and the wrapper's inherited acceptance
lock. MainPID128396 was confirmed live after launch; the same handle must be
polled, not restarted after an observation timeout.

Protected receipt: `/var/log/kazoo-main-media-soak-zrYHkl/receipt.json`.
Underlying campaign log: `calls.log` in that directory. Wrapper log:
`/root/kz5-main-media-promotion-20260910.xSDOxZhF/soak.log`.
An interim31-sample observation reported phase `real_acdc_soak`, current/peak60
native media sessions, and the30-conversation stress stage. This is a running
test, **not** its final result or evidence that1800seconds has passed.
Collect the exact unit, successful full receipt and underlying summary, then
independently verify final media/agent/registration cleanup and logs.
