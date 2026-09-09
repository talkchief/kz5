# Requested points 1, 2, 4 and 6 — September 9 checkpoint

This checkpoint does **not** close all four requested groups or certify a
production release. Keep dashboard/history work postponed. Do not regenerate
voices or repeat passing normal callback campaigns without a relevant change.

Latest: the corrected30-call broker recovery campaign **passed**, including the
clean-log gate (`20260909T133950Z`). Normal deployment of required patch `b19fde3`
fixed duplicate secondary consumers and corrupt binding state. Invalid-number
callback rejection and cached-identity revocation also passed natively. Standalone
FreeSWITCH repeat4 passed. Apps fresh dependencies/production compilation passed;
remaining container prerequisite and Kamailio inspection fixes are in `58436d9`,
native installer retries pending. This supersedes earlier failed-run checkpoints,
which remain retained as evidence, not relabeled as passes.

| Point | Current verified work | Still open |
| --- | --- | --- |
| 1 — ACDC reliability | Same-FSM recovery/next-call SIP/RTP passed after eCallMgr loss and full RabbitMQ outage, without re-login/re-registration. Corrected30-concurrent broker-loss test:30 caller/30 agent successes,0 failures,0 new errors/cores. | Multi-node broker partitions, repeated failures and extended fault/load/soak. |
| 2 — Callback edge cases | Worker killed during ringing: cleanup/backoff/completed retry passed. Invalid/empty input, alternate1001, unanswered first return/completed second return passed. Alternate-disabled rejection played complete built-in audio, retained caller until caller BYE, created no ticket and left the busy conversation intact. Earlier five-language/queue-restart passes retained; no Gemini generation. | Historical ambiguous ticket stays quarantined pending operator disposition; cannot infer its old outcome from current zero channels. |
| 4 — Installer | Required host lock, role ownership, remote-broker monitoring/private-CA and dispatcher fixes. Fresh curl/diffutils/Erlang-EI/out-of-tree configure/login-environment gaps fixed. CouchDB/RabbitMQ install/repeat/guest-boot passed; HAProxy install/repeat passed; standalone FreeSWITCH repeat4 passed. | Apps/eCallMgr/Kamailio separated-role retries and remaining repeat/boot matrix, cluster admission/drain, coordinated upgrade/rollback acceptance. Containers are not independent-machine HA proof. |
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
  `kz5-amqp-redaction-deploy-20260909.service` is pending terminal verification.
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
