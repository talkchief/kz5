# Requested points 1, 2, 4 and 6 — September 9 checkpoint

This checkpoint does **not** close all four requested groups or certify a
production release. Keep dashboard/history work postponed. Do not regenerate
voices or repeat passing normal callback campaigns without a relevant change.

Continuation: the30-minute30-call hold passed natively (1800s,30/30 successes,
zero failures/errors/cores; `20260909T145906Z`). An empty-data installation exposed
missing helpers in the SUP archive: account creation succeeded, CLI discovery
failed. Required source fix `5e6f87a` passed native rebuild/normal installation,
without creating a duplicate master. Current cold apps automatic guest boot
passed, as did original-lab HAProxy and Kamailio guest boots. Legacy eCallMgr/
FreeSWITCH guest failures remain recorded with successful restoration. A final
untouched apps attempt1 is running in `kz5-final-kazoo-apps`, source `e8e3a46`;
do not label it passed until terminal collection. Details: `sup_archive_bootstrap.md`,
`distributed_install_lab.md` and `acdc_extended_soak.md`.

Final focused handover: source fixes are deployed and the seven isolated backend
roles passed their normal installer checks, including apps attempt6 (`8966bd7`).
The final capacity campaign passed with30 answered and5 queued calls and a180s
verified concurrent hold. Corrected30-call broker recovery, callback edge cases
and cached-identity revocation passed natively. Main44 has all nine stack services
active, zero calls and zero apps/eCallMgr error-priority journal entries since
14:28UTC at final readback. This supersedes pending-retry checkpoints, not the
retained failed evidence. The apps pass was a normal retry after diagnostic lab
bootstrap, not an untouched first-install pass. Broader release gates below remain
explicitly open; the focused implementation work is handed over, not certified
as a complete enterprise release.

| Point | Current verified work | Still open |
| --- | --- | --- |
| 1 — ACDC reliability | Same-FSM recovery/next-call SIP/RTP passed after eCallMgr loss and full RabbitMQ outage, without re-login/re-registration. Corrected30-concurrent broker-loss test passed. Subsequent30-concurrent1800s hold passed:30 caller/30 agent successes,0 failures/errors/cores. | Multi-node broker partitions. Three consecutive30-agent broker failures are now under test (`kz5-repeated-broker-30-20260909.service`, `c8796e2`), not yet passed. The30-minute hold does not establish indefinite reliability. |
| 2 — Callback edge cases | Worker killed during ringing: cleanup/backoff/completed retry passed. Invalid/empty input, alternate1001, unanswered first return/completed second return passed. Alternate-disabled rejection played complete built-in audio, retained caller until caller BYE, created no ticket and left the busy conversation intact. Earlier five-language/queue-restart passes retained; no Gemini generation. | Historical ambiguous ticket stays quarantined pending operator disposition; cannot infer its old outcome from current zero channels. |
| 4 — Installer | Required host lock, role ownership, remote-broker monitoring/private-CA and dispatcher fixes. Fresh dependencies, Pivot reservation, eCallMgr readiness, Crossbar public-API registration and SUP archive packaging fixed. All seven isolated backend roles passed normal installation. CouchDB/RabbitMQ, HAProxy, Kamailio and current cold-apps automatic guest boots passed. | Untouched final cold apps bootstrap confirmation, remaining repeat/boot matrix, cluster admission/drain and coordinated upgrade/rollback acceptance. Legacy FreeSWITCH/eCallMgr guest boot failures are retained with successful restoration, not relabeled. Separate UI/bridge provisioning was not tested in this lab. Containers are not independent-machine HA proof. |
| 6 — API/Blackhole | Native command-auth, delivery, expiry1008, overload1013 and7 ordinary-principal HTTP/WSS scope checks passed. Cached token was revoked by exact isolated-user CAS: next event denied1008/no leak and HTTP401 before expiry. OpenAPI assets HTTPS byte-verified. | Multi-node cache-wide revocation, real slow-network load and cross-node supervision/audio-privacy acceptance. |

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
