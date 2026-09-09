# Bounded extended ACDC hold acceptance

The existing `scripts/test-kazoo-calls.sh` now accepts `--soak-seconds 180..1800`.
Values above180 require `--stress --stages 30 --queued-excess 0`: extending a
connected conversation must not silently increase queue wait policies. Defaults,
including the180s30-answered/5-queued campaign, are unchanged.

Run only on the isolated acceptance fixture with the shared fixture lock and
zero unrelated calls:

```sh
flock --nonblock /etc/kazoo/monitor-acceptance.lock \
  bash /opt/kz5/scripts/test-kazoo-calls.sh --live --stress --stages 30 \
  --queued-excess 0 --soak-seconds 1800 --no-install-deps
```

Extended mode derives SIPp process/BYE timeouts and registration lifetime from
the requested duration, with startup/drain margins. It changes only the BYE
timeout in a private copy of the pinned agent scenario, leaving the original
untouched. Concurrent legs are checked every second; existing exact SIP success,
RTP, ready-agent recovery, error-log, coredump and resource checks remain required.
Traffic is paced at2 starts/sec, not a high-CPS claim. Native result pending:
main44 `kz5-extended-soak-20260909.service`, started14:58:59UTC at source `c875758`,
verified running with30 connected calls. Protected log:
`/root/kz5-acceptance/extended-soak-20260909.log`. Wait for terminal service status,
successful summary/RTP/error gates and cleanup before labeling it passed.
A30-minute pass would be bounded duration evidence, not an indefinite reliability
guarantee or multi-node failure acceptance. Results remain under the normal
root-only `/var/log/kazoo-acceptance` run directory.
