# Requested points 1, 2, 4 and 6 — September 9 checkpoint

This checkpoint does **not** close all four requested groups or certify a
production release. Keep dashboard/history work postponed. Do not regenerate
voices or repeat passing normal callback campaigns without a relevant change.

| Point | Current verified work | Still open |
| --- | --- | --- |
| 1 — ACDC reliability | Existing source recovery handles lost-result delivery, offer correlation and conservative ended-channel recovery; prior regression evidence is retained. No new native fault campaign in this turn. | Real missed-hangup, broker/node loss, repeated-failure and routing acceptance under representative load. |
| 2 — Callback edge cases | Existing successful five-language registration/retry/bridge and queue-restart-in-backoff evidence is retained. No new callback source change in this turn. | Invalid/alternate-number native paths, active worker-loss recovery and the historical ambiguous ticket. Never force-clear an uncertain ticket from a zero-channel snapshot. |
| 4 — Installer | Added host-wide concurrency guard and passed actual-helper tests locally and on main44; normal apps deployment completed successfully. Prior fresh/repeat/reboot evidence remains valid for its measured topology. | Fully separated-role matrix, cluster admission/drain, coordinated upgrades and rollback/failure recovery. A host lock is not a cluster lock. |
| 6 — API/Blackhole | Fixed native cached-command authentication bypass in required installer source overlay; source tests and real before/after WSS acceptance passed. Updated reference published and HTTPS byte-verified. | Generic outbound stream expiry/revocation, slow-client backpressure, restricted-principal and cross-node supervision/audio-privacy acceptance. |

Code commits: `f99ff81`, `98f3829`, `6c8d341`, pushed to kz5 master and synced
to `10.1.0.44:/opt/kz5`. ACDC remains tracked directly in kz5; no nested ACDC
commit was made. The unrelated untracked dashboard design draft was preserved.

Applications deployment: systemd unit
`kz5-blackhole-command-deploy-20260909.service`, exit0,10m55.760s.
Native WSS after-test: `kz5-blackhole-command-after-20260909.service`,
exit0,6.844s, five checks passed. All nine stack services were active afterward;
FreeSWITCH reported zero calls. No imported-company mutations or new live-call
tests were performed in this turn.

Details: [Blackhole fix and evidence](blackhole_command_auth.md),
[installer lock](installer_host_lock.md),
[agent recovery](acdc_agent_recovery.md),
[existing callback evidence](focused_acceptance_20260908.md),
and the authoritative root [task register](../PROJECT_TASKS.md).
