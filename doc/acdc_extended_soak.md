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
Traffic is paced at2 starts/sec, not a high-CPS claim. Native result **PASS**:
main44 `kz5-extended-soak-20260909.service`, started14:58:59UTC at source `c875758`,
completed with Result=success/ExecMainStatus=0 and normal cleanup. Protected log:
`/root/kz5-acceptance/extended-soak-20260909.log`. Results:
`/var/log/kazoo-acceptance/20260909T145906Z/summary.tsv`.

| Verified hold | Caller / agent success | Failures | Error logs | New cores | Peak CPU | Minimum available memory |
| --- | --- | --- | --- | --- | --- | --- |
| 1800s,30 concurrent answered calls | 30 /30 | 0 /0 | 0 /0 | 0 | 72% | 17476668KiB |

Actual SIP/RTP, final agent readiness and clean drain passed. Other isolated
builds ran on the same host, so CPU/memory samples include that activity. After
all calls ended, the harness memory cap was raised from2GiB to4GiB for repeated
analysis of its2.6GiB packet capture; no call-phase gate or service limit changed.
The temporary packet capture was removed by normal successful-test cleanup;
SIP counters, RTP count receipt, resource samples and summary remain protected.
This proves the bounded30-minute hold, not indefinite reliability, call-turnover
soak, high CPS or multi-node failure acceptance.
