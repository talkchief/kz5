# Requested points 1, 2, 4 and 6 — September 9 checkpoint

This checkpoint does **not** close all four requested groups or certify a
production release. Keep dashboard/history work postponed. Do not regenerate
voices or repeat passing normal callback campaigns without a relevant change.

Latest verified results:

- September10 main44 applications/controller promotion **PASS** through the
  normal installer on `4cd9953`; eight loaded module identities match disk.
  All four supervision modes also passed new actual main-runtime calls and
  independent RTP/authorization/stop/bridge-survival checks, evidence
  `/var/log/kazoo-monitor-acceptance-WTrjrC`. Fresh cleanup and bounded journal
  crash-pattern scan pass. See `main_dev_runtime_promotion.md` for successful
  receipts and retained first-launch/teardown failures. This closes the main
  applications/controller promotion gap mentioned in older entries below,
  not full cluster drain/coordinated upgrade/rollback or the private media
  build's sustained-load gate.

- September10 cold state restoration passed on both apps VMs, including paired
  finite/infinite-paused and empty-membership agent/queue inventories:
  `/var/lib/kazoo5-install-lab/cold-agent-state-tbT2Rt/receipt.json` on dev44.
  Actual follow-up queue calls passed audio but exposed a separate strict
  listener-drain defect. Source `8343d47` fixes terminal-leg cleanup and delayed
  control notifications; eight focused regressions and the broader maintenance,
  recovery and channel-event suites pass. Normal private installs16/12 passed
  and were collected. Actual healthy and apps-broker-partition queue campaigns
  also passed with independently verified audio, same FSMs, all-six strict drain
  and zero-session cleanup (`...-5ZZRCj`, `...-e3Y5w1` under
  `/var/log/kazoo-monitor-acceptance-` on dev44).
  See `acdc_listener_terminal_cleanup.md`. Full coordinated maintenance and
  deployment of this latest source to the main44 runtime remain unproven.

- New calls after both native media restarts PASS all four supervision/audio
  modes: `kz5-stage-monitor-after-media-restart-1` (runner `4cc4540`, exit0),
  protected evidence `/var/log/kazoo-monitor-acceptance-DeA1qp` on dev44.
  Independent capture analysis confirms privacy and original bridge survival
  after supervisor stop; cleanup is open/zero sessions/no fixture. Five relevant
  services active, zero error-priority journal entries in the checked restart
  window. Full coordinated upgrade/rollback remains open.

- Native media process-restart persistence PASS on September10:
  `kz5-stage-media-restart-2`, runner `2abb5c5`, installed media `935d544`.
  Receipt `/var/lib/kazoo5-install-lab/media-restart-1789004453657.json` on dev44
  independently verified: two changed process/core identities, closed admission
  after both starts, lost marker restored by the actual boot guard, identical
  internal probes rejected while fenced and answered before/after, operator
  pause retained on release, and clean open/zero-session final state. The
  first run refused a stale collected installer handle before touching media;
  its failed log remains. Full cluster maintenance is not closed by this test.

- September10 actual-call retest PASS for Listen/eavesdrop, Whisper, Barge and
  Join: `kz5-stage-monitor-media-fence-1`, runner `a2b7946`, media `935d544`.
  All four synthetic RTP captures independently reanalyzed, including privacy
  while new media admission is fenced. Every supervisor stop202 preserves the
  original bridge; internal probes answer before/after and fail while fenced.
  Evidence `/var/log/kazoo-monitor-acceptance-xD4WRr` on dev44. Cleanup verified
  open admission/zero sessions/no retained fixture. Process-restart persistence
  now passes above; full coordinated maintenance acceptance remains open.

- Normal private media retry6 on `935d544` completed and was collected PASS in
  `freeswitch-install-6.log`. The actual native observer now works under the
  container's existing privileges. An explicit media-fenced real SIP/RTP
  supervision campaign and process-restart persistence now pass natively as
  recorded above; complete coordinated acceptance is still required.

- Media build5 compiled and started the service, then FAILED verification on
  a restricted-container proc read (root EACCES). The same-UID proc verifier
  correction passes24 focused tests and an actual native observation without
  relaxing privileges. Collect the failed receipt and perform a normal helper
  deployment retry. Full fence/call/restart acceptance still follows.

- Private media normal build started on `88bf049`, exact unit
  `kz5-stage-install-freeswitch-5`, MainPID2947 active/running. Guarded admission
  checked six ready replicas and zero media/callback work. Collect before native
  acceptance; deploy the subsequent helper-only directory-fsync correction
  after collection. Do not modify compiling inputs. See `maintenance_media_fence.md`.

- Initializer rollout completed: jobs15/11 on `494ee28` collected PASS, then
  version2 combined native inventory PASS (two nodes/six replicas):
  `queue-inventory-1789002002127-97f89a97.json`. The startup prerequisite is now
  deployed/verified; full maintenance fence/drain/restore remains open.
- Durable media allocation fence and installer integration are implemented.
  21 focused tests plus both full modified C translation units compile/pass;
  normal media deployment and native call/restart acceptance remain required.
  See `maintenance_media_fence.md`.

- Corrected source `494ee28` is pushed and synced to main44 root. Normal
  private retries15/11 are active/running, verified MainPID506156/363012;
  admission checked zero work and all6 ready replicas. Start receipt:
  `init-readiness-deploy-494ee28-1789001079511.log`. Collect these exact jobs,
  then verify version2 inventories; no runtime success claimed yet.

- Normal private startup-readiness jobs14/10 on `c6e0c36` FAILED, exit2:
  six missing gen_server callback type specifications are fatal under the
  normal warn_missing_spec compiler flag. Both exact jobs were collected with
  their failed logs retained. The focused runner now uses the normal warning
  flags for production modules and reproduces the failure; source specifications
  are added and all18 tests pass (`/tmp/kazoo-acdc-init.3egwot`). Normal
  redeployment remains required.

- Earlier launch of startup-readiness source `c6e0c36` (now failed above):
  units `kz5-stage-install-kazoo-apps-14` and `kz5-stage-install-apps-peer-10`,
  actual nonzero MainPID and active/running verified. Admission observed zero
  media/callback work and6 ready replicas. Collect these exact jobs, then run
  version2 combined inventory. Do not change their compiling inputs. See
  `acdc_initialization_readiness.md`; no runtime pass or full closeout yet.

- ACDC startup completion gap corrected in source: owned monitored startup/
  agent/retry jobs, native installer readiness, and version2 queue/agent
  snapshot tokens and strict agent-status reads (no error-to-unknown fallback).
  18 production initializer/status tests and26 installer/
  native-guard/journal tests pass. Normal private deployment and new native
  combined acceptance still pending; see `acdc_initialization_readiness.md`.
  Earlier version1 combined native result on `25be59c` passed with two queues/
  six replicas (`queue-inventory-1788999277496-9ba05000.json`), but is not proof
  of the new startup prerequisite. Full cluster drain/restore/rollback is open.

- Persistent local ingress fence is integrated into the installer and role
  startup guards, with16 focused tests, real kernel packet acceptance and actual
  systemd acceptance PASS. Unknown/corrupted/releasing state prevents startup;
  lost kernel rules are restored from durable intent. Private apps14 receipt:
  `/var/lib/kazoo-stage/fence-systemd-E8BQOL/receipt.json`. Native concurrent
  startup regression failed before and passes with bounded lock serialization.
  Main/modular/read-only installer suites pass. No apps restart.
  Complete cluster producer/media fence, drain and cold restore/rollback remain
  OPEN. See `maintenance_ingress_fence.md`; this is not a full coordinator pass.
- Normal apps builds13/9 on `25be59c` completed and were collected successfully
  (`kazoo-apps-install-13.log`, `apps-peer-install-9.log`). Native queue inventory
  passed again: `queue-inventory-1788998060332-c90cb0ed.json`. These supersede
  the build-running statements in the earlier checkpoints below.

Earlier checkpoints (retain their evidence; deployment statements are historical):

- Normal apps builds12/8 passed and were collected. Installed `e405aab` native
  queue inventory PASS on both nodes, one queue/three workers each:
  `queue-inventory-1788996716962-6fdd7ae9.json`. This does not prove full drain.
  New normal builds13/9 target `25be59c` with paused-agent correlation; collect
  their exact units before the next native check. See the maintenance document.

- Corrected a false refusal in the new maintenance guard: paused agents also
  publish busy. Busy identities now require complete current paused-agent and
  queue-membership correlation instead of being treated as active calls.
  Before-fail/after-pass regression,138 production maintenance tests and16
  journal/merger tests pass. The correction is not deployed yet; current
  private normal builds12/8 still target the earlier `e405aab`.

- Queue work-drain observations added in source with134 passing maintenance
  cases (54 queue cases), evidence `/tmp/kazoo-acdc-maintenance.fLiIkJ`.
  Read-only queue inventory checks paired workers, residual callback/timer/
  delivery work, announcements and manager cancellation ownership; ordinary
  ready/current_call status is insufficient. Native deployment/collection is
  still pending. Full cluster admission fence/drain and cold restore/rollback
  remain open; see `acdc_coherent_upgrade_readiness.md`.
- Native full agent-cohort merger PASS:
  `agent-inventory-merged-1788994874158.json`,6 replicas with agreeing epochs,
  memberships, effective states and document revisions. This is an inventory
  result, not complete cluster fence/drain evidence.

- Installer maintenance baseline now reproduces pause loss on actual nodes:
  both45-second-paused agent replicas returned ready after supervisor restart,
  within5597ms of host admission. Private baseline receipt
  `agent-restart-baseline-1788990948224.json` is FAIL and retained. Independent
  after-check verifies all6 test replicas ready with original membership and
  active consumers. Both preceding normal apps installations passed. A separate
  stale consumed sync-reference source fix passes27 recovery and43 maintenance
  cases; it is not yet deployed and does not solve pause restoration. Point4
  remains open for fenced checkpoint/restore and coordinated rollback.

- Native Blackhole fanout soak PASS: unit
  `kz5-blackhole-fanout-soak-20260909`, exit0, receipt
  `/var/log/kazoo-blackhole-fanout-6f4ed2b1f3bd165f0a2c551ddd4d4595.json`.
  32 subscribers,3600 broker events,115200 exact deliveries,60 batches,
  1901seconds, zero other-call leaks and clean socket shutdown. Three source
  hashes unchanged throughout. Max control ping580.1ms, peak native memory
  156285952bytes, peak processes3315. Main44 all9 services active, zero media
  channels and zero apps/eCallMgr error-priority journal entries in the final
  35-minute readback. The defined fanout gate is closed; no indefinite-scale
  or media-failover claim. See `blackhole_fanout_acceptance.md`.

- Queued applications-node broker partition run5 PASS: native unit
  `kz5-stage-queue-partition-5` exited0, evidence
  `/var/log/kazoo-monitor-acceptance-aKrXXe`. Both actual queued calls carried
  directional audio; both original FSMs recovered after missed hangup during
  apps14-only AMQP loss, with no re-login/re-registration. Scoped cleanup passed.
  Production source `2e91984`, runner `0ac6fb9`; main44 normal deployment is
  PASS as `kz5-acdc-replica-deploy-20260909` on `58c0194`, exit0. No main44 calls
  were active at admission. Final installer validations, all9 active services,
  zero media channels and zero error-priority apps/eCallMgr journal entries
  since21:00:05UTC passed at readback.

- Queued multi-node acceptance exposed a genuine same-agent replica discrepancy
  before fault injection: primary answered, peer ready. Both listeners/bindings
  were live. Root ACDC source now chooses one originate owner per agent and
  broadcasts its shared identity on bridge-first completion too. Original-source
  regressions fail;34 strategy and26 recovery tests pass after correction.
  Both normal lab rebuilds passed. Native run4 passed first-call audio and
  same-FSM recovery, but the second test phone refused INVITEs after OPTIONS
  exhausted its one-call budget. Native loopback regression validates a runner
  fix; run5 subsequently passed the full after-test. See
  `acdc_distributed_partition_acceptance.md`.

- All four monitoring modes now also pass real active-call controller broker
  partition/recovery (roughly14seconds per interruption). Unit
  `kz5-stage-monitor-partition-3` exited0, evidence
  `/var/log/kazoo-monitor-acceptance-o7yewF`. Native Join specifically observed
  broker-ready/query-consumer-not-ready, then passed after consumer recovery.
  Installer source now checks that readiness phase. Audio/privacy, same VMs,
  supervisor-only stop202, original bridge survival and scoped cleanup pass.
  See `ecallmgr_query_readiness.md`; not media-node failover or indefinite soak.
- All four distributed supervision modes passed real SIP/RTP audio routing,
  privacy, authorization and supervisor-only stop: native unit
  `kz5-stage-monitor-distributed-5`, exit0; evidence
  `/var/log/kazoo-monitor-acceptance-6xZDTb`. Peer automatic startup with both
  source fixes passed (`ecallmgr-peer-boot-1788981642738.log`).
- Main44 normal apps/eCallMgr deployment `ae12cbf` passed, native unit
  `kz5-amqp-registration-deploy-20260909`, exit0; all9 services active, zero calls,
  zero error-priority apps/eCallMgr entries since19:14UTC at readback. Real
  supervised AMQP replacement already passed without replacing the VM.
- Fresh separate bridge normal installation and automatic guest startup passed
  on source `9b151d2`: `push-bridge-install-1.log` and
  `push-bridge-boot-1788979389226.log` in `/var/lib/kazoo5-install-lab`.
  Uses a dedicated private broker namespace and synthetic provider identity;
  no real mobile notification was sent (physical delivery was previously waived).
- Distributed supervision attempt2 exposed a real separated-role admission bug:
  REGISTER succeeds, Kamailio authorizes INVITE, but FreeSWITCH returns403 and
  rejects the exact SBC address in its authoritative ACL. Native discovery is
  disabled by default despite the standalone installer assuming it. Source fix
  `9c75fe8` enables/verifies supervised discovery; seven regression cases pass.
  Normal peer installation, boot and real call after-tests now pass.
  See `distributed_sbc_discovery.md`.

- Native bounded slow-reader WS and verified WSS passed (`c0c550c`): stalled
  socket removed after5390/6825ms, control pings at most7.6/9.5ms, reconnect
  passed before token expiry. No service change needed for this case. See
  `blackhole_slow_client_acceptance.md`; not prolonged network soak.
- eCallMgr peer normal installation and automatic guest boot passed on source
  `7b206fc`: `ecallmgr-peer-install-1.log` and
  `ecallmgr-peer-boot-1788977215685.log` in `/var/lib/kazoo5-install-lab`.
  Normal verification includes reconnection to the separate FreeSWITCH role.
  Initial PID1 startup failure was host inotify exhaustion, not Kazoo; completed
  cold fixtures were parked without deleting data/evidence and the retained
  stopped peer resumed. Lab tooling now checks headroom before creating guests.
- Cross-node signing-secret revocation P0 fixed in required root source patch
  `8fffdd2`; six pristine before-fail/after-pass regressions, repeat-patch and
  missing-source rejection pass. Both normal lab rebuilds passed (`b8523ec`).
  Healthy and peer-only RabbitMQ partition acceptance passed: HTTP200/200 before
  →401/401 after revocation, both WS1008/no leaked event, unchanged app PIDs and
  broker connection restored. Receipts `cluster-auth-1788975173069.json` and
  `cluster-auth-1788975191194.json` in `/var/lib/kazoo5-install-lab`.
  Main44 normal deployment passed (`2b52bd7`, unit
  `kz5-identity-authoritative-deploy-20260909`, exit0), followed by four native
  HTTPS/WSS revocation checks. All9 services active, zero calls, error-priority
  apps/eCallMgr journal entries0 since17:28UTC at readback. Updated OpenAPI bytes
  match over verified HTTPS. See
  `cluster_identity_revocation.md`; this is not SIP/RTP partition recovery.
- Three consecutive30-agent broker outages passed (`c8796e2`, native unit
  `kz5-repeated-broker-30-20260909.service`, exit0). Same apps process and all30
  FSMs retained;90 subsequent calls succeeded,0 failures, errors0/0 and new cores0
  each cycle. Separate30-minute30-call hold passed (`20260909T145906Z`).
- Final empty-data CouchDB/RabbitMQ/apps first installs passed, including first
  account creation and working SUP discovery. Apps source `e8e3a46`; receipt
  `/var/lib/kazoo5-cold-bootstrap-final/kazoo-apps-install-1.log`. Exactly one
  master account; no manual bootstrap, installer restart or cache intervention.
  Slow package mirrors/OS metadata contention required only the test watchdog
  to increase60→90minutes, keeping original PID79 and all acceptance checks.
- That fresh apps guest automatically started after reboot and passed normal
  verification: `kazoo-apps-boot-1788971648675.log` in the same evidence root.
  This closes the SUP archive first-bootstrap defect, not all release gates.
- FreeSWITCH automatic guest restart passed, followed by dependent eCallMgr
  verification (`freeswitch-boot-1788969733352.log` and
  `ecallmgr-verify-1788969827870.log` in `/var/lib/kazoo5-install-lab`).
- Additional DNF coordination source fix `33254c0`:8 private cases and native
  real metadata-job pause/cached transaction/timer restoration passed. This
  installer-only change requires no applications rebuild; main44 has the code.
- Main44 final readback: all9 services active, zero calls, zero apps/eCallMgr
  error-priority journal entries since16:10UTC. No claim beyond that window.

Details: `sup_archive_bootstrap.md`, `installer_dnf_coordination.md`,
`distributed_install_lab.md`, `acdc_extended_soak.md` and `acdc_native_node_loss.md`.
Earlier failed attempts remain failed; successful later runs do not erase them.

September10 follow-up: the newly installed main media also passed the full
30-call/1800s soak (`kazoo-main-media-soak-zrYHkl/receipt.json` under `/var/log`),
with zero failures/errors/new cores and clean native teardown. Four subsequent
actual main supervision calls pass Listen/eavesdrop, Whisper, Barge and Join,
including independently reanalyzed RTP privacy and original bridge survival:
`/var/log/kazoo-monitor-acceptance-cwWdKC`. Both native units exited0 and were
collected. See `main_media_soak.md` and `channel_monitor_acceptance.md`.
The coordinator and historical-ticket decisions below are unchanged.

September10 broker follow-up: native inventory and installer helper deployment
passed on `8601f57`. Actual synthetic publication and unacknowledged delivery
both prevent an empty result; acknowledgement returns it to empty. The exact
temporary vhost was removed and verified absent. Installed default-vhost scan
observed586 queues/6 connections/724 channels with all work counters zero and
unchanged broker process. Receipts and remaining producer/coordinator limits:
`maintenance_broker_inventory.md`. This does not promote a sequential snapshot
to complete cluster drain or coordinated activation/rollback acceptance.

| Point | Current verified work | Still open |
| --- | --- | --- |
| 1 — ACDC reliability | Same-FSM recovery/next-call SIP/RTP passed after eCallMgr loss and full RabbitMQ outage, without re-login/re-registration. Three consecutive30-agent broker outages passed with unchanged apps/FSM identities and90 successful subsequent calls.30-concurrent1800s hold passed:30 caller/30 agent successes,0 failures/errors/cores. Multi-apps-node broker partition now also passed both queued calls/audio and unchanged replica recovery; source fix deployed normally on main44. | Defined recovery gates passed. These bounded tests do not establish indefinite reliability or physical media-node HA. |
| 2 — Callback edge cases | Worker killed during ringing: cleanup/backoff/completed retry passed. Invalid/empty input, alternate1001, unanswered first return/completed second return passed. Alternate-disabled rejection played complete built-in audio, retained caller until caller BYE, created no ticket and left the busy conversation intact. Earlier five-language/queue-restart passes retained; no Gemini generation. | Historical ambiguous ticket stays quarantined pending operator disposition; cannot infer its old outcome from current zero channels. |
| 4 — Installer | Source fixes include host locking, role ownership, remote-broker monitoring/private CA, dispatcher/media readiness, fresh dependencies, Pivot ports, Crossbar registration, SUP packaging and DNF coordination. All seven backend roles passed normal installation. Independent empty-data CouchDB/RabbitMQ/apps first installs passed. Data roles, HAProxy, FreeSWITCH, Kamailio, fresh apps and normally installed eCallMgr peer guest boot passed. Fresh separate bridge install/boot and exact remote SBC admission with real calls pass; earlier separate UI install is documented in fresh_host_tls_acceptance_20260908.md. Main44 latest apps/eCallMgr normal deployment passed. | Cluster admission/drain and coordinated upgrade/rollback acceptance. Separate UI was not repeated in this lab. Containers are not independent-machine HA proof. |
| 6 — API/Blackhole | Native command-auth, delivery, expiry1008, overload1013 and7 ordinary-principal HTTP/WSS scope checks passed. Two-node signing-secret revocation passes healthy and peer-only broker-partition modes, with HTTP401/401 and WS1008/no leak before expiry. Main44 deployment and HTTPS/WSS after-checks passed. Bounded real WS/WSS slow-reader cleanup, control client and reconnect passed. Distributed Listen/eavesdrop, Whisper, Barge and Join audio/privacy and authorization passed in actual SIP/RTP calls, including controller broker partition, same-VM recovery and supervisor-only stop. Full native AMQP-to-WSS soak passed115200/115200 deliveries across32 subscribers over1901seconds with zero other-call leaks and clean socket shutdown. | Defined API/Blackhole gates passed. These bounded checks do not claim media-node failover or indefinite reliability/scalability. |

Code commits include `f99ff81`, `98f3829`, `6c8d341`, `b3a67ec`, `c3f11bb`,
`3125096`, `f88b306`, `7d036fc`, `75f2517`, pushed to kz5 master and synced
to `10.1.0.44:/opt/kz5`. ACDC remains tracked directly in kz5; no nested ACDC
commit was made. The unrelated untracked dashboard design draft was preserved.

Earlier command-auth applications deployment: systemd unit
`kz5-blackhole-command-deploy-20260909.service`, exit0,10m55.760s.
Native WSS after-test: `kz5-blackhole-command-after-20260909.service`,
exit0,6.844s, five checks passed. All nine stack services were active afterward;
FreeSWITCH reported zero calls. Subsequent fault tests used only the isolated
acceptance account `8310dc3170a18de37f205d0da172df65`; the imported company was
not mutated or called. Stream acceptance's normal signing may initialize this
fixture account's missing identity secret, never reset an existing secret.

New native fault acceptance:

- `kz5-final-capacity-20260909.service`, exit0, evidence
  `/var/log/kazoo-acceptance/20260909T140415Z`:35 caller and35 agent successes,
  zero failures,30 answered plus5 queued,180s continuously verified concurrency,
  real SIP/RTP and clean drain. Errors0/0, new cores0; peak sampled CPU72%, minimum
  available memory18830056KiB. Offered rate2 starts/sec, not30 or80 calls/sec.
- `8966bd7` corrects a real fresh Crossbar registration `undef`: use exported,
  uncached `kz_datamgr:open_doc/2`, not private `kapps_config:get_category/2`.
  Mandatory fresh and old-source transition patches preserve config ownership.
  Old-source regression reproduced7 failures; corrected strict-export mocks
  passed all9 cases (`/tmp/kazoo-module-scope.Ct4kPqQr` on the source host).
  Main44 targeted production build/restart and normal apps verification passed:
  `kz5-crossbar-public-read-deploy-20260909.service`, journal terminal success
  14:30:58UTC. Backup/source/BEAM receipts:
  `/root/kz5-acceptance/crossbar-public-read.GirlR7qt`.
- Separated normal installer terminal receipts, all PASS:
  `/var/lib/kazoo5-install-lab/ecallmgr-install-4.log` (`e780af1`),
  `kamailio-install-4.log` (`6eddc28`) and `kazoo-apps-install-6.log` (`8966bd7`).
  See [lab setup and complete role evidence](distributed_install_lab.md).
- `kz5-acdc-broker-loss-30-fixed-20260909.service`, exit0, evidence
  `/var/log/kazoo-acceptance/node-loss/20260909T133950Z`. Both30-call batches
  completed; same FSMs recovered after missed hangups during broker loss.
  Post-recovery error counts0/0, new cores0. Peak sampled CPU43%; this is not soak.
- `kz5-callback-invalid-reject-20260909.service`, exit0, evidence
  `/var/log/kazoo-acceptance/20260909T134742Z`; full immutable unavailable audio,
  no callback ticket, caller-controlled hangup. Existing conversation unaffected.
- `kz5-native-revocation-20260909.service`, exit0,4 native checks passed.
  Only fixed acceptance user signing secret changed; do not restore revoked keys.
- `12313fd` removes URI credentials from25 AMQP connection logging sites;
  actual-module AMQP/AMQPS regression passed. Normal apps+eCallMgr deployment
  `kz5-amqp-redaction-deploy-20260909.service` completed exit0, all normal checks
  passed. All9 services active with NRestarts0, zero calls and zero error-priority
  apps/eCallMgr journal entries since deployment start13:50:25UTC.
  Old protected logs may still contain credentials; never print them unredacted.

- `kz5-acdc-broker-loss-20260909.service`, exit0 (fc13ec), evidence
  `/var/log/kazoo-acceptance/node-loss/20260909T125202Z`: native broker-outage
  missed-hangup/same-FSM recovery and next-call SIP/RTP passed.

- `kz5-callback-invalid-alternate-complete-20260909.service`, exit0 (885e00),
  evidence `/var/log/kazoo-acceptance/20260909T123654Z`. The two preceding
  harness failures are retained, not counted as full retry passes. Existing
  success-audio minimum remains unchanged; the shorter invalid-entry matcher
  requires the complete exact committed auxiliary clip. Fixture retained.

- `kz5-node-loss-location-after-20260909.service`, exit0 (1bd8da), evidence
  `/var/log/kazoo-acceptance/node-loss/20260909T113605Z`.
- `kz5-callback-worker-loss-native-20260909.service`, exit0 (3d4e5c), evidence
  `/var/log/kazoo-acceptance/20260909T114942Z`.
- `kz5-stream-guard-baseline-native-20260909.service`, expected failure before
  deployment: valid event received, then a post-expiry event received (caebc8).
  The initial setup refusal lacked a fixture identity secret, not a service bug.
- `kz5-stream-guard-deploy-20260909.service`: completed, exit0 (053096).
- `kz5-stream-guard-after-native-20260909.service`: completed, exit0 (711103),
  all three delivery/expiry/overload checks passed. Native command regression
  completed exit0 with all five checks (d8cad3).
- All nine services active, zero FreeSWITCH channels (c42013). Apps, eCallMgr,
  FreeSWITCH and Kamailio automatic restarts0; apps/eCallMgr error-priority
  journal entries0 since deployment start (d8cad3). All12 `/apis/` assets
  matched committed bytes over verified HTTPS (711103).

Details: [Blackhole fix and evidence](blackhole_command_auth.md),
[installer lock](installer_host_lock.md),
[agent recovery](acdc_agent_recovery.md),
[native node-loss fix](acdc_native_node_loss.md),
[native callback worker-loss acceptance](callback_active_worker_loss.md),
[outbound stream fix](blackhole_outbound_delivery.md),
[existing callback evidence](focused_acceptance_20260908.md),
and the authoritative root [task register](../PROJECT_TASKS.md).
