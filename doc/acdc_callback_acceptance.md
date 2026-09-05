# Callback completion acceptance

Status at 2026-09-05 16:20 UTC: **the requested one-agent callback/retry path
passes its live functional and packet gates; the overall run still fails its
log gate**. Run `20260905T161308Z` reports one known Kamailio script error, no
file-log errors and no new core dumps. This is not production, full cleanup
or distributed-recovery certification.

## Failure and repair

The isolated run `20260905T132127Z` registered a durable callback, answered the
returned call, received digit 1, and connected an agent. Native FreeSWITCH
intercept emitted `CHANNEL_BRIDGE` on the initiating agent leg. The queue's
listener tracked the returned caller leg, so the durable ticket did not reach
`completed`; the 15-second proof timeout cancelled the connected call.

Selected-agent acceptance now also starts an asynchronous, correlated query of
ecallmgr channel state. Completion requires a complete response set, the correct
account, reciprocal answered/active caller and agent legs on the same media
node, and an exact match to the currently selected/accepted agent. Acceptance
alone is not bridge proof. Old generations, incomplete responses, unknown
state and conflicting legs cannot complete a callback. At most one query or
retry timer is outstanding per selection, and retries do not extend the
existing proof deadline.

The channel API reads ecallmgr's event-derived channel records. A fresh query
is **not** a direct FreeSWITCH `uuid_dump`, nor a guarantee against all stale
state during a node failure. The live gate independently checks reciprocal
FreeSWITCH channel fields and packet evidence. Distributed failure and restart
recovery remain separate acceptance work.

The existing durable commit remains the completion boundary. Failed CAS,
cancelled tickets and completed rows for other legs do not retire the broker
delivery or emit handled statistics. See the [earlier menu, resume and
settlement repairs](acdc_callback_menu_repair.md).

## Build and private verification

- Full queue suite: 27 tests passed.
- Focused snapshot suite: five tests passed against both the reconstructed
  production baseline and the separately staged source tree. This includes the
  actual asynchronous acceptance/query/retry/commit path, durable failure and
  successful retirement, stale replies, and reciprocal-channel negative cases.
- Existing recovery I/O suite: 16 tests passed, including account/correlation
  rejection, missing responders, conflicting owners and incomplete bridges.
- The old reconstructed queue BEAM matches the saved and loaded bytecode MD5:
  `f03290b569eb702207a0d4845c5c451b`.
- The new baseline queue BEAM SHA-256 is
  `6d9d2bee2ffd4645655506fb5a75709ac06096b14d802ea4a75b7af4ab467e69`.
  Record declarations are unchanged, with no TEST options or test exports.
- The default ACDC integration patch includes the repair. The atomic-answer
  patch is rebased separately, without activating its pending behavior.
  Exact layered forward/reverse replay and installer regression checks pass.

At 13:52:25 UTC, deployment under the shared lock verified zero FreeSWITCH
calls, backed up the previous BEAM to
`/var/lib/kazoo/callback-bridge-backup.zbBsZJ`, and loaded the new module. The
first load reported `not_purged`; `code:soft_purge/1` then returned `true` and
the subsequent load succeeded. No forced purge or process kill was used. The
loaded bytecode MD5 is `efba078d318683611ed14053dbbad05d`; ebin SHA matches the
private artifact. All five voice/test-phone service PIDs and zero restart
counts remained unchanged.

## First run after the bridge repair

Run `20260905T135303Z` reached durable `completed` with one attempt and unchanged
enqueue identity/order metadata. Fresh post-failure FreeSWITCH observations
showed the exact reciprocal, answered, same-account pair at the fixture's
loopback carrier and agent endpoints. Independent packet analysis found payload
101, thirteen digit-1 packets and one agent INVITE, 892 ms after the completed
digit. These are partial receipts, not a full acceptance pass.

The test incorrectly required a poll to observe durable `confirming`. The
caller worker waits internally, then the queue writes `caller_answered` and
`caller_confirmed` back-to-back after the digit; that database phase is not the
eight-second test-phone wait. The invalid polling assertion is removed. All
exact bridge, waiting-sentinel, enqueue-metadata and final packet assertions
remain mandatory. Eleven private extracted-lifecycle tests cover that correction
and its negative cases.

The aborted test also exposed incomplete fixture cleanup: the terminal callback
API correctly did not end a completed conversation, but the helper treated
terminal status as proof that both calls were down. The two remaining fixture
legs were freshly checked against the durable IDs, account, reciprocal bridge
and exact local endpoints. Only the verified returned leg was cleared with
`NORMAL_CLEARING`; both legs then ended and FreeSWITCH returned to zero calls.
No broad hangup, MASTER change or service restart was used. The isolated fixture
helper was subsequently hardened to verify live-leg cleanup before resource
removal; the production callback-cancellation API is unchanged.

## Second run after the bridge repair

Run `20260905T143709Z` reached durable `completed` with one attempt, unchanged
enqueue identity/order, and the exact reciprocal same-account caller/agent
bridge. The later sentinel was still present and unbridged at that point.
The sentinel, returned carrier and agent subsequently ended naturally, each
with one successful SIP call and zero failed calls. FreeSWITCH returned to zero
calls. **The run still failed** its agent bidirectional-RTP assertion (zero
packets in both directions); the final packet and aggregate acceptance gates
were therefore not reached.

The installed SIPp source and test-phone logs identify a fixture defect: the
three phones generating an audio pattern also enabled RTP echo, reserving the
same limited port range. Their streaming bind failed, although SIPp still
reported successful SIP calls. The fixture now removes echo only on those
three pattern generators, retains the echo-only agent, and rejects streaming
startup warnings even when SIP reports success. A private kernel-bind test
reproduces the collision and corrected allocation without sending packets.
The stronger packet gate also checks the actual agent offer/answer/ACK,
negotiated PCMU tuple and at least ten unique progressing valid RTP packets in
each direction. All 93 packet cases and 32 dynamic-payload cases pass. This
proves test behavior, not speech quality or a successful live retry. The new
two-attempt diagnostic below may run with the known Kamailio error still
counted; functional evidence must not be reported as a clean-log pass.

Cleanup retained the isolated fixture because a historical ticket remained
`cancelling` with reconciliation required. Zero current channels is not proof
of settled origination. This safety gate is not bypassed or converted to a
manual terminal ticket write. The completed-conversation helper hardening has
passed eleven private fault groups and independent review: exact durable IDs,
account, reciprocal live legs and loopback endpoints are required before a
single owned caller hangup; routing-resource deletion additionally requires
settled tickets and confirmed idle local FreeSWITCH.

At the follow-up read-only check, all nine services remained active/enabled
with zero recorded automatic restarts and no core dumps. A broader installer
check subsequently found actual Kamailio authentication and unresolved
acceptance-realm routing errors during test setup. The initial journal counter
missed native `ERROR:` messages; it is corrected and the errors are not waived.
A separate file-log keyword match was a normal `CHANNEL_EXECUTE_ERROR` event
subscription. Both counters now distinguish identifier parts from diagnostic
words and recognize native `[ERR]`/`[CRIT]` levels. Fourteen private file/journal
test pairs plus four routing/AMQP cases exercise real failures, mixed
event/error lines and exclusion of file entries predating the test baseline.
There is no clean-log or full production certification claim.

Reproduce the private checks without changing running service bytecode:

```sh
bash scripts/test-acdc-callback-bridge-snapshot.sh
bash scripts/test-acdc-callback-queue.sh
bash scripts/test-acdc-callback-recovery-io.sh
node scripts/test-fixtures/assert-callback-confirmation-pcap.test.cjs
node scripts/test-callback-carrier-media.cjs
node scripts/test-callback-capture.cjs
node scripts/test-callback-cleanup-exit.cjs
node scripts/test-callback-timing.cjs
node scripts/test-callback-lifecycle.cjs
node scripts/test-callback-fixture-cleanup.cjs
node scripts/test-call-log-evidence.cjs
node scripts/test-callback-media-binding.cjs
```

## Busy-agent callback and unanswered-first-attempt diagnostic

Latest run `20260905T161308Z` passes the strict lifecycle and all three
phase-scoped SIP/RTP gates:

- One agent was connected to the first conversation while the second caller
  entered callback digit 6 at 4.9892 seconds after answer.
- The complete installed 6.124-second confirmation was received before
  hangup, correlation 0.999991, with zero missing samples.
- The first conversation remained bridged through the announcement and was
  released 5.796588 seconds after its end. This includes the explicit
  two-second wait plus proof/capture overhead; it is not an exact two-second
  media-to-release timing claim.
- The first callback rang for 15.103999 seconds without being answered.
  INVITE/100/180/CANCEL/200-CANCEL/487-INVITE/ACK is fully captured and
  correlated to the first native caller, with no first-attempt agent offer.
- The durable ticket entered `retry_wait` after one attempt and recorded
  `last_cause=routing_failed`. The second INVITE started 17.735992 seconds
  after the first CANCEL (17.726553 after ACK). The configured retry delay
  is 15 seconds; the reported elapsed time includes settlement/scheduling.
- The second caller confirmed with negotiated telephone-event payload 101.
  One agent INVITE followed digit completion by 911 ms; the exact native
  reciprocal bridge completed the same durable ticket on attempt two without
  changing enqueue identity/order. PCMU packet proof found 4,916 progressing
  packets in each direction at the agent.
- Both original conversations and both agent conversations reported two
  successes and zero failures in aggregate. All four waited SIPp processes
  exited zero. The agent-ready check passed before normal fixture logout.
  After cleanup, FreeSWITCH had zero calls, the five checked service PIDs
  were unchanged/active, and automatic restart counts remained zero.

The immutable receipt is
`/var/log/kazoo-acceptance/20260905T161308Z/retry-packet-evidence.json`.
The overall script exits **1**, not zero: its final log gate reports one
Kamailio `consume_credentials` error at 16:13:46.068 UTC and no file-log
errors. There are no new core dumps. The separately tested installer patch
`kamailio-registered-source-credentials.patch` removes only the redundant
digest-credential consumption on the registered/trusted-source branch;
`MAIN` still strips both credential headers before forwarding and the digest
authentication path is unchanged. Ten focused regression groups pass. The
patch is in the repository/installer but **was not activated on the running
proxy during this test**. Historical unresolved callback resources remain
retained. No MASTER configuration or external-carrier changes were made.

Corrected run `20260905T160240Z` reached durable `completed` on attempt two.
Its original entry digit arrived 4.987037 seconds after answer, and its entire
6.124-second installed confirmation was received with correlation 0.999991 and
zero missing samples. The first conversation was released 5.916599 seconds
after prompt completion, including the explicit two-second post-proof wait
and verification/capture setup overhead. The first returned phone reported
INVITE/100/180, then CANCEL/200/487/ACK, with process exit zero. The durable
ticket entered `retry_wait` after attempt one with `last_cause=routing_failed`;
that recorded cause is not relabelled `NO_ANSWER`.

The second attempt reached an exact reciprocal native bridge. Independent
inspection of its captured SIP/RTP passed: negotiated telephone-event payload
101, thirteen digit packets, one agent INVITE 980 ms after digit completion,
and 4,912 progressing PCMU packets in each direction at the agent. All four
waited SIPp processes exited zero, and normal teardown/cleanup left FreeSWITCH
idle. **The overall diagnostic still failed**: the first-attempt capture
contained INVITE/100/180 but not its final CANCEL/200/487/ACK. SIPp counters
alone cannot replace that missing packet evidence. Capture buffering/drain is
was independently reproduced before a new full run; no full unanswered/retry
packet pass is claimed for this run. With the old buffered capture, a private
loopback receiver got 36 datagrams but the PCAP omitted all four late datagrams
when stopped 500 ms afterward, despite zero kernel drops. `--immediate-mode`
and an explicit 16 MiB capture buffer retained all 36, including the late four,
with zero drops in both tested timing phases. The scoped live captures use
those settings and keep their strict zero-drop gate. `-U` alone flushes the
PCAP writer; it does not guarantee delivery of unread kernel-buffered packets.

The first new run, `20260905T155305Z`, connected the first caller to the sole
agent. Independent read-only inspection of the aborted run's packet capture
then verified callback digit 6 at 4.990916 seconds after the second caller's
answer, the complete installed 6.124-second confirmation prompt, correlation
0.999991, zero missing phrase samples and prompt completion before server BYE.
This is partial media evidence, not a completed retry test.

SIPp reported one successful original-call transaction and zero failed calls,
but its process returned failure. The active-pattern fixture also checks for
echo of its generated pattern; receiving queue music and the announcement is
not that echo. The original queued phone therefore uses a bound echo-only RTP
receiver without the outbound pattern comparator, plus its negotiated DTMF;
the independent packet checker still requires the full received confirmation.
The busy/returned conversations retain their
separate bidirectional-media requirements. The runner must not waive an
unexplained process exit merely because SIP counters show success.

Aborted-run cleanup additionally released the busy agent before cancelling the
new queued callback, briefly allowing an attempt during cleanup. That attempt
does not count as the requested deliberately unanswered first attempt. The
new diagnostic's cleanup order is corrected to cancel/settle the exact
current callback before releasing the freshly verified busy pair. The new
ticket ended cancelled and FreeSWITCH returned to zero calls; historical
unresolved resources remain retained. No full retry result is claimed for
this run. Focused scenario, process-exit and actual-shell cleanup-order checks
pass before the corrected rerun. Nonzero SIPp exits are recorded explicitly;
exit 97 is not converted to success.

`scripts/test-acdc-callback-retry.sh` exercises the requested sequence on the
existing isolated acceptance tenant, not MASTER and not the public telephone
network. Its preparation checks do not constitute a live pass. The test logs
out only that tenant's test agents, logs in one, connects a first conversation,
and sends a second caller to the busy queue. Packet evidence must show the
callback entry digit approximately five seconds after answer and receipt of
the entire installed `en-us/acdc-callback-success` prompt before server hangup.

The first conversation remains bridged until after the audio proof and an
additional two-second wait. Capture startup and proof processing add overhead;
the report records the actual prompt-end-to-first-call-release interval rather
than asserting an exact two-second media boundary. The first returned call is
deliberately unanswered: the simulated carrier sends ringing, then completes
the server's CANCEL/487/ACK transaction without accepting the INVITE. The test
requires durable `retry_wait`, positive settlement, native absence of the
first returned leg, and a distinct second attempt after the configured
15-second backoff. The retry must accept the negotiated confirmation digit,
complete an exact reciprocal native caller/agent bridge, exchange progressing
bidirectional RTP, end normally and leave the agent ready.

The temporary queue callback policy is two attempts with a 15-second originate
timeout and a 15-second retry delay. The helper preserves the original queue
configuration for eventual safe restoration. Because an older unresolved
callback prevents safe routing-resource deletion, `--keep-fixture` is mandatory;
the current call must still be cleaned up. This is explicitly a retained-fixture
functional diagnostic, not full cleanup, restart recovery or production
acceptance. Existing Kamailio server errors remain failures of the log gate.

The confirmation reference must be privately retrieved from the installed
system-media attachment, decoded to raw 8 kHz mu-law, and accompanied by a
protected `reference-receipt.json` binding its hash to that attachment. A
repository WAV or a made-up transcript is not substituted. The checker proves
received PCM delivery by correlation; it does not claim human listening or
subjective speech-quality verification.

```sh
# No API writes or SIP traffic:
./scripts/test-acdc-callback-retry.sh --prepare-only \
  --confirmation-reference /protected/reference/acdc-callback-success.ulaw

# Explicitly authorized isolated live diagnostic; acquires the shared lock:
./scripts/test-acdc-callback-retry.sh --live --keep-fixture \
  --confirmation-reference /protected/reference/acdc-callback-success.ulaw

node scripts/test-callback-retry.cjs
node scripts/test-callback-retry-policy.cjs
node scripts/test-fixtures/assert-callback-registration-audio.test.cjs
node scripts/test-callback-unanswered.cjs
node scripts/test-sip-challenge-ack.cjs
```

The SIP fixtures preserve the actual challenge transaction headers when
acknowledging non-2xx responses. Static parsing alone cannot validate SIPp's
runtime header expansion, so a separate private-loopback UDP exchange checks
the rendered transaction before the Kazoo live run. No public carrier or
production SIP listener is used for that fixture-only check.

## Live fixture safeguards

The fixture uses only its isolated tenant and exact loopback carrier. It
generates RFC2833 digit 1 using the payload negotiated in the actual SIP offer,
not SIPp's fixed default. Packet proof requires matching offer/answer/ACK,
native caller/agent SIP dialog IDs, exact negotiated media endpoints, and a
completed digit before the first agent INVITE. Capture filters are bound to
the exact fixture addresses and ports; unrelated agent dialogs are rejected.

The later sentinel caller must still be waiting, unbridged, when the callback
completes with its original enqueue metadata and exactly one attempt. The
returned caller then holds for 100 seconds, outlasting the sentinel's 90-second
normal hold. This prevents a legitimate later sentinel offer after callback
hangup from invalidating the single-agent-dialog gate. The carrier's bounded
219-second process timeout includes all legal scenario waits and teardown.
No packet checks are relaxed and no additional agent state changes are used.

Seven actual-shell cleanup test groups verify that cancellation or owned
fixture cleanup failure produces a nonzero test exit status; original errors
are preserved and unresolved fixtures are retained for safe recovery. Six
timing groups, 93 packet cases, all 32 dynamic payloads and 28 capture-filter
cases pass privately. `--prepare-only` also passes without API mutation or SIP
traffic. Those results do not substitute for a successful `--live` run.

## Account configuration is a separate requirement

The reported MASTER-account call used a nonnumeric SIP username as caller ID,
with alternate-number entry disabled. A selected callback user authorizes and
supplies defaults for outbound calling; it does not itself define the return
destination or create a routable number. At the 13:51 UTC read-only check, the
selected user/account lacked an outbound caller-ID number and owned-number and
carrier-resource inventories were empty. No MASTER settings or routing were
invented during this repair. See [return identity and routing prerequisites](acdc_api_reference.md#return-destination-is-separate-from-the-callback-user).

Protected live captures, call documents, credentials and diagnostic logs must
remain outside Git. The [acceptance status](kazoo5_acceptance_status.md) records
the latest live result and outstanding deployment limits.
