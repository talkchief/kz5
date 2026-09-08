# Main development SIP/RTP acceptance — September 8

## Scope and safety

Tests run on `10.1.0.44` from `/opt/kz5`, using the dedicated 30-agent tenant
created by `scripts/test-kazoo-call-provision.sh --agent-count 30`. Protected
base64 state is `/etc/kazoo/acceptance-secrets.env`; do not source or print it.
The fixture uses caller 1001, agents 1002–1031 and queue 2000, not the imported
Talkchief inspection copy or PSTN routes. Test contacts use 127.0.0.20; SIPp
control sockets are explicitly loopback-bound. No production host is modified.

Provisioning passed `63307/e48133`: roster, devices, internal callflows,
logout/login transitions and runtime queue/agent ownership. It initially left
all 30 fixture agents logged in. The functional harness now logs them all out
before making only agent 1 available, and scopes cleanup to the whole fixture.
The old orchestration fails `e244ce`; fixed 1/30-agent cases pass `ccabae`.

## Source-backed setup fixes

Commit `5167a32` fixes the fresh SIPp build. Commit-only shallow fetching omitted
the release tag, so upstream `git describe` generated `369b3c1-TLS-PCAP-SHA256`
instead of `v3.7.7-TLS-PCAP-SHA256`. The installer now fetches only the exact
release tag and verifies it resolves to the existing immutable commit pin
before building. Existing correct tags do not require another fetch. Wrong
tags and fetch failures are fatal; version/feature checks were not relaxed.
Five offline cases pass `ccabae`; actual main-host prepare run `90596/dbfb39`
passes with protected log `/root/kz5-acceptance/sipp-tools-tagfix-20260908.log`.
The earlier failed log remains `/root/kz5-acceptance/sipp-tools-20260908.log`.

Commit `ae87595` fixes the negative REGISTER scenario. Previously any failure
of the positive-registration scenario counted as rejection, including timeout.
An expected 401 also triggered SIPp's default BYE, despite REGISTER establishing
no dialog. Kamailio then attempted DNS resolution of the synthetic `.invalid`
realm and logged three errors. The new scenario requires 401/407/403 after
the authenticated REGISTER, successful SIPp counters, and no location binding.
Real loopback-only SIPp regression `14871/a6c2f4` exercises all three rejection
codes without BYE, and rejects 200, 503 and timeout. Six cases in two test groups
pass; no Kazoo account or network beyond loopback is involved.

## First real functional result — incomplete due to log gate

Run `83070/049934` completed caller and agent SIP legs (1 success / 0 failure
each), bidirectional RTP (caller 1504 incoming / 1482 outgoing packets), hangup
and agent-ready checks. Final gate failed on the three negative-test DNS errors
above. There were zero new core dumps, peak sampled CPU 20%, and minimum
available memory 21,221,188 KiB. Do not label this run an overall pass.

Protected results:
`/var/log/kazoo-acceptance/main44-functional-20260908/20260908T164957Z/`.
Top-level log: `/root/kz5-acceptance/functional-call-20260908.log`.
Cleanup left zero FreeSWITCH calls (`a0fb56`). Raw RTP capture is removed only
after packet checks; counts and SIPp stats remain protected on the main host.

## Recheck and outstanding capacity gate

The source-fixed functional recheck is unit
`kz5-functional-rejectionfix-20260908`, observer session `91284`, protected log
`/root/kz5-acceptance/functional-rejectionfix-20260908.log`, results under
`/var/log/kazoo-acceptance/main44-functional-rejectionfix-20260908/`.
**PASS `91284/2464e2`:** full functional gate, including clean service/file logs,
passes. Summary readback `3de0cb`: 1/1 caller and agent success, zero failures,
zero log errors and zero new core dumps; peak sampled CPU 18%, minimum memory
21,263,728 KiB. Result directory is `20260908T165414Z`. Cleanup left zero calls
and all four call services active. The unit had 1 GiB memory, no swap, CPU 200%,
512 tasks and a 900-second deadline; it is now terminal, not enabled for boot.

The subsequent load gate must measure 1, 5, 10, 20, then 30 simultaneous calls,
with the existing 180-second simultaneous hold at 30 and full drain/RTP/log
checks. This is concurrency at two call starts per second, not 30 or 80 CPS.
No capacity, callback retry, supervisor privacy, actual audio-quality or HA
claim follows from a one-call SIP/RTP test. See the broader release-gate report.

Capacity run launched after the clean zero-call readback, using the unchanged
staged harness at `ae87595`: unit `kz5-capacity-stages-20260908`, observer
session `11093`, log `/root/kz5-acceptance/capacity-stages-20260908.log`, results
under `/var/log/kazoo-acceptance/main44-capacity-20260908/`. It includes five
queued excess callers at the 30-agent stage. Boundaries: 1536 MiB memory, no
swap, CPU 200%, 512 tasks, 2400-second deadline. This run is pending; poll the
same unit/session and inspect its terminal receipt, never restart because an
SSH observation times out. Do not count launch as a passed load test.
