# Focused handover — 2026-09-09

Work wrapped up at the user's explicit instruction. The overall release is not
certified production-ready. The authoritative detailed register is
`PROJECT_TASKS.md`; preserve its open items and historical failed evidence.

## Location and ownership

Main development host: `10.1.0.44`, repository `/opt/kz5`, branch `master`.
The original development host's `/opt/kz5` is not the long-term home. All ACDC
source belongs to the kz5 repository. Installer changes for pinned components
belong in root-owned patches, not nested repositories. Do not commit secrets.
Preserve the unrelated untracked `doc/dashboard_caller_sidecar_design.md`.

## Last completed work

- Standalone apps/eCallMgr installers now generate only their selected service
  units and log paths. Source `2dde850`, rollout evidence `ff010a9`; focused
  generator/CLI checks passed and main44's running units/services were preserved.
  Details: `doc/installer_role_unit_isolation.md`.
- Remote broker preflight monitoring permissions and persisted private management
  CA handling are corrected and narrowly verified. Full split-stack install,
  migration and rollback acceptance remain open. See `doc/acdc_broker_upgrade.md`.
- Loading recovery harness `1225cc1` passed six native-browser checks on main44:
  ACDC failed-read Retry/idle, recovery, stalled-read timeout, late-response
  isolation; SmartPBX failed-read global-indicator idle and navigation recovery.
  Log: `/root/kz5-acceptance/loading-recovery-main44-20260909.log` on main44.
  Unit: `kz5-loading-recovery-main44-20260909.service`, exit0, 22.222 seconds.
  Failures were injected only into browser GET responses; real login and successful
  backend reads were used. No account writes or service outages were performed.
  This adds acceptance evidence, not a new runtime frontend change.

## Subsequent SmartPBX completion, at the user's request

The user resumed work specifically to finish SmartPBX. Source `e7dfa14` fixes
the reproduced stalled GET, dashboard error completion, local menu locks,
visible Retry, service-plan failure and late-render ownership. The fix is carried
in required installer patches and their build fingerprints. Normal Monster UI
installation on main44 passed, followed by six focused native-browser checks
for stalls, HTTP503, Retry, indicator/menu recovery and late responses after
recovery/navigation. No account writes were performed. See
`doc/smartpbx_loading_recovery.md` for exact before/after evidence and replay.
Do not repeat these passed checks unchanged. Never-settling AMD construction
remains a separate open gap; a timeout alone must not permit late shared-object
mutation. The whole production release remains uncertified.

## Important release boundaries

Callbacks and prerecorded Gemini clips have scoped deployed acceptance evidence;
neither broad failover reliability nor every language's human listening/position
coverage is certified. Do not synthesize voices at runtime or during deployment.
See `doc/callback_originate_receipt.md` and
`doc/hebrew_callback_audio_followup.md`. Preserve ambiguous historical callback
tickets for reconciliation; zero current calls does not authorize clearing them.

The mandatory installer/bridge and production release gaps remain in the task
register. Dashboards are lower priority; historical dashboards are postponed.
The imported Talkchief company remains inspection-only. Shared writable CouchDB
between v4 and v5 is NOT approved, and rollback compatibility is unproven.
