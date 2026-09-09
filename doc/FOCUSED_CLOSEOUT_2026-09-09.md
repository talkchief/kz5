# Requested points 1, 2, 4 and 6 — September 9 checkpoint

This checkpoint does **not** close all four requested groups or certify a
production release. Keep dashboard/history work postponed. Do not regenerate
voices or repeat passing normal callback campaigns without a relevant change.

| Point | Current verified work | Still open |
| --- | --- | --- |
| 1 — ACDC reliability | Real eCallMgr loss/missed hangup exposed two next-call failures. Fixed routing-readiness validation and cold location-cache fallback. Normal eCallMgr deployment and native same-FSM recovery/next-call SIP/RTP passed without agent re-login or re-registration. | Broker partitions, repeated failures and routing under representative fault/load/soak. |
| 2 — Callback edge cases | Actual callback worker killed while first return was ringing: cleanup, durable backoff and completed second return passed. Invalid caller/empty input, full invalid-entry audio, alternate1001 confirmation, unanswered first return and completed second return also passed natively. Earlier five-language and queue-restart-in-backoff passes remain valid; no Gemini generation. | Alternate-disabled rejection and the historical ambiguous ticket. Never force-clear an uncertain ticket from a zero-channel snapshot. |
| 4 — Installer | Host lock, selected-role unit ownership, separate-broker monitoring/private-CA and effective dispatcher admission fixes are required source. Normal eCallMgr rebuild/deploy passed. | Fully separated-role matrix, cluster admission/drain, coordinated upgrades and rollback/failure recovery. A host lock is not a cluster lock. |
| 6 — API/Blackhole | Command-auth and outbound guards deployed through normal installer. Real before-test leaked an expired-token event; after-test passed valid delivery, expiry denial1008 and mailbox closure1013. Five native command regressions passed; OpenAPI published/HTTPS byte-verified. | Cache-wide revocation, real slow-network load, restricted-principal and cross-node supervision/audio-privacy acceptance. |

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
