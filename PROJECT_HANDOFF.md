# Kazoo 5 — start here / engineering handoff

Last updated: **2026-09-06**. This is the navigation and current-state guide;
`PROJECT_TASKS.md` is the detailed requirement/acceptance register. Neither this
file nor a green unit test means the platform is production-ready.

## 1. Repository and non-negotiable requirements

- Project: `/opt/kz5`; current branch: `fix/acdc-outbound-agent-availability`.
- ACDC is **directly tracked in kz5** under `applications/acdc`. Do not restore
  nested Git metadata, create an ACDC submodule, or commit to an ACDC upstream
  repository. Preserve the team's merged recovery changes and unrelated edits.
- The final deliverable is one modular installer, `scripts/install-kazoo5.sh`,
  supporting separate servers or ALL on one server, with actual dependency,
  named-service, repeat-install, reboot and interoperability validation.
- User wants reviewed work committed and ultimately pushed to **master**.
  The latest release has not been pushed. Do not equate a local commit with a
  deployed/published release, or force-push over other work.
- The user confirmed this host is a **development environment** and authorized
  replacement/deployment/restarts as needed. FreeSWITCH reported `0 total`
  calls during this checkpoint. Recheck before restarting; preserve accounts,
  recordings, queue configuration and rollback evidence.

Start with `git status --short`, `git log -5 --oneline`, the task register and
the relevant evidence document below. Reinspect current processes and Git state;
this handoff is a checkpoint, not a substitute for live observation.

## 2. Most important voice requirement

**Generate the required audio now, package it in this release, and never use
Gemini during installation or runtime.** No provider key or online synthesis
is allowed for calls, queue editing, account/sub-account creation or subsequent
installation of this supported release. Missing assets must fail validation,
not trigger TTS. Do not regenerate successful recordings merely to resume work.

The intended UI is one **Queue language** dropdown: **EN, HE, FR, ES, AR**.
Each has one built-in female voice. The choice applies to position/wait,
callback offers, menus, telephone readback, confirmations and error responses.
No per-prompt voice selector/custom-recording editor. Existing media documents
are retained; adopting built-in defaults must clear obsolete queue references
that otherwise silently override the language choice.

Read `doc/acdc_builtin_queue_voices.md` for the full contract.

### Audio inventory achieved

| Location under `scripts/assets/` | Effective contents |
| --- | --- |
| `acdc-gemini-fixed-20260905` | Fixed messages; failed historical entries are recovered by the completion pack |
| `acdc-gemini-completion-20260905` | Fixed recoveries plus Hebrew/Arabic telephone digits |
| The two packs above combined | 165 effective assets: 145 fixed +20 telephone digits |
| `acdc-gemini-supplemental-20260906` | **45 newly generated assets**: three auxiliary messages ×5 locales +30 EN/FR/ES telephone digits |
| Combined release | **210 effective assets /420 WAVs**, 42 assets per locale |

Voice/model: Gemini `gemini-2.5-pro-preview-tts`, **Sulafat**, requested warm
natural adult female delivery. Masters: PCM16 mono 24 kHz. Telephony: PCM16 mono
8 kHz, resampling only. Every effective recording has transcript/provenance,
hashes, duration, clipping and volume checks in its manifest.

The new 45 clips completed in **47 requests**. French zero and two each had one
incomplete response, then one successful explicit retry. Their previous attempt
records remain in the manifest; retry filenames contain `.attempt-2`. The other
valid files were not regenerated. There is no unfinished provider batch at this
checkpoint: session 7635 returned exit 0 with all 45 QA-passed.

These are **format/content-integrity checks, not listening approval**. Native
pronunciation/translation review and actual call playback remain required.
Telephone digits do **not** complete natural queue-position number composition.
The existing position contract spans 0–999,999,999. Do not silently narrow it,
spell positions digit-by-digit, or use robotic native SAY as a completed fix.

### Source/tool map

| Purpose | File |
| --- | --- |
| Exact new localized text | `scripts/acdc-gemini-supplemental-catalog.cjs` |
| Authoring only; not an installer/runtime dependency | `scripts/generate-acdc-gemini-supplemental-pack.cjs` |
| Verify actual supplemental WAVs | Same generator, `--verify-only --output /opt/kz5/scripts/assets/acdc-gemini-supplemental-20260906` |
| Create-only CouchDB import, byte readback | `scripts/import-acdc-gemini-voices.cjs` (`--supplemental-pack` adds the new pack) |
| Exact import receipt validation | `scripts/validate-acdc-gemini-receipt.cjs` |
| Deterministic 210-asset Erlang table | `scripts/generate-acdc-gemini-map.cjs`; `applications/acdc/src/acdc_gemini_map.hrl` |
| Targeted media-map activation/check | `scripts/refresh-acdc-gemini-mappings.cjs` and `.erl.template` |
| Strict built-in lookup/readback contract | `applications/acdc/src/acdc_gemini_prompts.erl` |
| Menu/key handling and durable registration feedback | `applications/acdc/src/cf_acdc_member.erl` |
| Independent announcement scheduling | `applications/acdc/src/acdc_announcements.erl` |
| Returned callback / caller confirmation | `applications/acdc/src/acdc_callback_caller.erl` |

The installer has been updated in the worktree to require/import/verify the 210
assets using files only. Its mapping/receipt helpers still accept the explicit
older 165 inventory for legacy verification; the new installer requires 210.

## 3. What is actually deployed versus only prepared

**No new supplemental media import, backend deployment or restart has occurred
in this checkpoint.** The 45 WAVs are generated locally. The 210 map and
installer integration are prepared; canonical callback integration is being
finished/tested in the worktree. Do not tell the user the new callbacks are
ready to test until matching source/media are deployed and verified.

A fresh earlier live probe found a critical discrepancy: the loaded
`acdc_announcements` BEAM imported Gemini helpers, but tracked canonical source
still used older language/media paths. The English default offer resolved a
Gemini ID for account `302ae5a70c403124f764cbc54229cfcd`; that did not prove all
queue paths used it. A forced rebuild before source reconciliation could regress
the live behavior. **Do not blindly reverse old aggregate patches**: preserve
the newer scheduler, ownership and agent-recovery fixes.

Canonical work now in progress covers strict exact system-media paths for the
three auxiliary responses; bounded 20-second playback/21-second feedback;
correlated completion/terminal events; callback fixed-message and telephone
readback integration for all five languages; returned-call language; and
pre-resolved callback offer selection. It must pass the new **current-source**
harness before deployment. The historical `test-acdc-gemini-runtime.sh`
reconstructs an older patched baseline and is not proof of this new code.

Actual service names include `kazoo-apps`, `kazoo-ecallmgr`,
`kazoo-freeswitch`, `kazoo-kamailio`, `couchdb`, `rabbitmq-server`, `nginx`, and
`haproxy`. The FreeSWITCH service is **not** named `freeswitch` on this host.
All eight were observed active. Activity alone does not establish readiness.

## 4. Recent completed fixes and evidence

| Evidence | What it proves / where |
| --- | --- |
| Commit `e4c20e8` | ACDC expired-deadline priority and bounded event drains; 12 scheduler/worker tests. `doc/acdc_announcement_mailbox_fairness.md` |
| Commit `6bddf71` | Installer forced Erlang rebuild, targeted number/MIME regeneration and same-invocation content-drift refusal. `doc/installer_build_identity.md` |
| `/tmp/kazoo-force-recompile.8X2lwo/receipt.json` | 12 private real Make/compiler/readback commands |
| `/tmp/kazoo-generated-rebuild.a46KIZ/receipt.json` | Seven groups /17 real private generator/compiler commands; no downloads |
| Session 46576, exit 0 | Build snapshot + ecallmgr reuse + complete installer dry-run smoke |
| `/tmp/kazoo-gemini-supplemental-test.FoMcpN/receipt.json` | 11 offline authoring/retry groups; no real provider/key access |
| Session 6695, exit 0 | Existing voice import and six mapping tests, including private real Erlang template execution |
| Session 84007, partial pass then exit 1 | Actual 45-WAV verification, deterministic210 map and210-asset import tests passed; installer fixture still supplied old asset arguments and failed |
| Session 60775, exit 0 | Rerun after fixing fixture supplemental arguments: all13 installer scenarios passed, including missing assets, no-effect dry run, create-only import, verify-only and failure-before-deployment. Traces: `/tmp/kazoo-gemini-installer-tests.b2nWlC` |

Temporary receipt paths are local evidence and may not survive a new server.
The durable test implementations and explanatory documents are in Git/worktree.
Update this section with final outcomes rather than deleting failed evidence.

## 5. Immediate next work

1. The installer210 regression passed; run the main installer smoke again after
   final integration changes. Never restart a still-running job just because an
   observation timed out.
2. Finish/review the canonical callback changes and run
   `scripts/test-acdc-gemini-canonical-callback.sh`, callback feedback/menu,
   caller/announcement regressions and production compilation. Some new harness
   files are currently being prepared; inspect before invoking.
3. Complete the UI adoption/readiness contract. Existing hidden prompt fields
   preserve overrides despite the simplified display. Editor PATCH needs
   `announcements.media: null`, `callback.media: null`, and
   `callback.return_confirmation_prompt: null` when adopting built-in defaults;
   `{}` recursively preserves old values. Do not delete media documents.
4. Finish the prerecorded position-number catalog/compositor for all five
   languages, generate missing release artifacts once, and verify natural
   playback. Do not enable a full-language capability based on native SAY.
5. Import verified assets through the installer, deploy the coherent backend/UI
   and native media fixes, and run the actual key-6/30-second-offer/confirmation/
   unanswered-first-attempt retry scenario. Inspect logs and queue/agent state.
6. Continue the remaining task register; voice completion alone does not close
   the original platform goal.

Parallel owners at this checkpoint: `native_audio_path_audit` owns canonical
callback source/test changes; `media_prerequisites` is examining the full-range
cardinal composition design. Inspect their status/messages before overlapping
their edits. Root owns importer/map/installer/docs and release integration.

## 6. Wider goal: where remaining work is tracked

- `PROJECT_TASKS.md`: P0 call delivery/recovery/callback acceptance; unified queue
  editor; company members/devices/status; supervision audio/security; Blackhole;
  live/historical dashboards; workforce sessions/break types/reports; installer;
  TLS, load/soak, backup/restore/failover and final release.
- `doc/acdc_coherent_upgrade_readiness.md`: multi-module/source/runtime upgrade
  risks. A single-module hotload is not the complete rollout.
- `doc/installer_regression_acceptance_20260906.md`: existing build/browser and
  installer checkpoint evidence and explicit limitations.
- `doc/blackhole_resilience.md` and
  `doc/blackhole_binding_results_acceptance.md`: native WebSocket robustness and
  authorization work. Reuse Blackhole; no duplicate transport service.
- `doc/api_developer_portal.md`: OpenAPI developer portal publication/evidence.
  `/apis` includes implemented contracts and clearly marked proposals. The
  register reports 356 paths /651 operations; verify fresh source/output before
  quoting it as the current release. Dashboard proposals are not live endpoints.
- `/opt/kz5/dashboards design/`: supplied design references. Dashboard/WFM tasks
  remain open; do not mistake this voice work for their completion.

Outstanding release blockers include real native audio/call ownership tests,
five-language listening, clean/separated-server installs, sustained30 concurrent
calls (not80 calls/sec certification), broker/node failures, TLS/WSS and security.
The last TLS audit found certificates without a matching private key under
`/root/ssl`; recheck/provision with appropriate authority, never invent success.

## 7. Secrets, resources and release discipline

- `/root/key.key` is a protected root-owned0600 file containing distinct Gemini
  and GitHub credentials. Select by provider; never print/copy/commit its text.
  The old token pasted in chat must not be reused. GitHub auth/push is unverified.
- `/etc/kazoo/deployment.env` is protected persisted deployment configuration.
  The installer decodes validated key/value data; do not print secret values or
  replace it with an unsafe shell evaluation. Audio manifests contain no keys.
- Use `scripts/run-kazoo-validation.sh` for resource-bounded heavy validation.
  Recent runs use256MiB cap,768MiB reserve and a task-appropriate deadline;
  offline tests additionally use `unshare --net`. Do not remove the reserve to
  force a test through. Serialize guarded jobs on this small host.
- Generate real audio only in explicitly authorized authoring work; **never**
  put authoring commands in an install hook, runtime path or account workflow.
- Preserve dirty worktree changes. Review/scan/test scoped changes before commit.
  Final master push requires the complete requested release and remote-SHA
  verification. Do not mark the active goal complete while any required item is
  missing, only mocked, untested, undeployed or merely documented as planned.
