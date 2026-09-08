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
swap, CPU 200%, 512 tasks, 2400-second deadline. This run is now **terminal,
exit1 (`11093/59ad9e`)**; the 30-call arrival assertion failed as detailed below.

| Stage | Caller successes/failures | Agent successes/failures | Peak sampled host CPU | Minimum available memory KiB | New log errors / cores |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 / 0 | 1 / 0 | 7% | 21241044 | 0 / 0 |
| 5 | 5 / 0 | 5 / 0 | 14% | 21192312 | 0 / 0 |
| 10 | 10 / 0 | 10 / 0 | 23% | 21113652 | 0 / 0 |
| 20 | 20 / 0 | 20 / 0 | 28% | 20991072 | 0 / 0 |

Each completed stage also passed bidirectional RTP and agent-ready checks.
These are whole-host sampled CPU values, not per-call or per-core CPU costs.
Readback `dedfd3`; result directory `20260908T165536Z`.

The 30-agent stage intentionally delays five excess callers by 120 seconds,
but the old arrival helper allowed only 60 seconds for all 35 answers. This
could not satisfy its own test scenario. At failure the caller's maximum answer
count was 30, SIP failures zero, with all 30 agent processes having received a
call (`95ba14`). That does not prove sustained simultaneous answered capacity.
After cleanup, unit PID0/inactive and zero FreeSWITCH calls (`719c6f`).

Source fix `0433788` adds the intentional delay only to the arrival allowance;
the ordinary 60-second budget and full 180-second simultaneous hold remain.
Virtual-time tests cover success, missing arrivals, both orchestration budgets
and unchanged hold; control-binding/SIP/RTP argument regression also passes
(`64549/904861`). No server capacity limit was raised or error ignored.

Only the corrected final stage is rerunning, not the already passed smaller
stages: unit `kz5-capacity-delayedfix-20260908`, observer session `31826`, log
`/root/kz5-acceptance/capacity-delayedfix-20260908.log`, results under
`/var/log/kazoo-acceptance/main44-capacity-delayedfix-20260908/`. Same memory,
swap, CPU and task bounds; 1200-second deadline. This run is **terminal exit1**
(`31826/823714`): it reached all 35 answers but failed during the hold when
queued callers received server BYEs. Live queue readback `20ca45` showed
`connection_timeout: 120`. Caller 33 received an unexpected BYE 257 seconds
after SIPp startup (`5e53ff`), consistent with its delayed arrival plus that
120-second queue wait. Both the callflow wrapper and queue FSM enforce this
configured timeout. The six-minute main conversations could not release agents
before that two-minute queued-caller deadline. No core-service restarts occurred
(`fb599f`); the test subsequently cleaned up to zero calls/PID0 (`f0d7ae`).

Fixture fix `23a265c` provisions a 600-second wait for the **owned acceptance
queue only**, not a change to production queue defaults. The actual stale
fixture fails its new read-only preflight (`29802/0a7049`). Normal provisioner
convergence `91419/1fa500` passes all resources and 30-agent logout/login/runtime
checks; independent API readback `a0f19a` confirms 600 seconds. Typed policy,
wrong identity and insufficient-timeout regressions pass `9f653d`.

Follow-up `a4c87f1` confines the long-wait gate to explicit `--verify-capacity`
and normal fixture provisioning. Stress/all modes call it before creating
calls; ordinary status and callback tests may retain their own shorter waits.
Actual dispatch regression `7463/4da657` covers both scopes, unchanged arrival/
hold budgets and SIP control bindings. A separate stale offline cleanup test
lacked the transport variable introduced by the earlier callback work. Its
fixture now covers internal and external contact cleanup, retaining failure
statuses: 8 groups pass `48094/e8ca8d`, along with 8 locale groups. Prior retry
88 and exact fixture-cleanup 13 groups passed `3416/d0b95d`; the original missing
variable failure is retained in that run, not presented as a runtime crash.

The corrected queue-policy run started at source `23a265c` and is **terminal exit1**:
unit `kz5-capacity-queuewait-20260908`, observer `93793`, log
`/root/kz5-acceptance/capacity-queuewait-20260908.log`, results under
`/var/log/kazoo-acceptance/main44-capacity-queuewait-20260908/`. Same 1536 MiB,
no-swap, 200% CPU, 512-task and 1200-second bounds. It completed the timed
concurrent hold and caller-side drain before failing in agent shutdown
(`93793/79f613`). At the first drain readback `b4fd8a`, 30 caller/agent successes
and five live agent calls were present, with no SIP failures. Final agent stats
were 33 successes / 2 failures (`777bca`), so this is not an overall pass; RTP
and final log assertions after shutdown were not reached.

Agents 4 and 5 had both completed two INVITE/ACK/BYE/200 exchanges and were in
their final 500 ms timewait when the harness sent SIGUSR1. Pinned SIPp sets
`quitting=1` on reaching `-m`; its SIGUSR1 handler adds 10, and `quitting>=11`
aborts outstanding tasks (`a64911`). That race counted the final pause as a
failed call despite completed SIP teardown (`331bf7`). No timeout or unexpected
SIP message counter was recorded on those two agents. Cleanup finished with
PID0/inactive and zero native calls (`76fcfe`). Result directory:
`/var/log/kazoo-acceptance/main44-capacity-queuewait-20260908/20260908T171607Z/`.

Fix `53ed7d8` requires all expected successful agent completions and zero active
agent calls before signaling remaining idle listeners. Missing counters, real
failures, excess calls and nonzero child exit statuses still fail the gate;
waiting has a 30-second bound. Actual helper regression `0202ba` passes.
Real loopback-only SIPp regression `59701/b38b3c` reproduces the immediate-signal
failure and verifies normal successful exit after the pause. No production
service code, SIP/RTP scenario timing or concurrency requirement was changed.

The final run is **terminal, log gate failed**, started only after the previous unit became
terminal: `kz5-capacity-agentdrain-20260908`, observer `10423`, protected log
`/root/kz5-acceptance/capacity-agentdrain-20260908.log`, result root
`/var/log/kazoo-acceptance/main44-capacity-agentdrain-20260908/`. Source
`53ed7d8`, same 30+5 calls, 180-second hold and resource/deadline bounds. All
capacity units are terminal; do not poll old observers or start duplicates.

Readback `fcea07` records35 caller successes/0 failures and35 agent successes/0
failures, verified concurrent hold180s, peak sampled whole-host CPU31%, minimum
available memory20497424KiB, zero journal errors and zero new cores. All30 agent
RTP endpoint assertions passed; aggregate caller packets632513 incoming/629973
outgoing (`90ddbd`). Result directory is `20260908T173035Z`. Final file-log gate
found8 errors, so this is **not an overall acceptance pass**. Cleanup readback
`d4a12e` confirms zero FreeSWITCH calls; unit inactive/PID0. All nine services
enabled/active independently confirmed `a4fd9c`.

Diagnostic `93b923` identifies the8 lines at17:37:30–17:37:51, overlapping the
private HTTPS browser check: seven `undef` reports for
`cb_apps_store:content_types_provided/1`, `cb_vmboxes:content_types_provided/1,2`
and `cb_directories:content_types_provided/1`; one `cb_apps_util` error fetching
the imported company's absent apps-store document. Source inspection confirms
those callback arities are absent. The browser succeeded using fallback paths,
but this does not make server-side error logging acceptable. Next: add explicit
default content-type handlers where appropriate, cover missing optional
apps-store handling without masking real datastore errors, then rebuild/deploy
and repeat combined UI/log and capacity acceptance. Do not weaken the matcher
or claim the errors prove a SIP failure; the measured SIP counters are above.
