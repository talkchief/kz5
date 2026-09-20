# Production readiness plan — system, installer, services, ACDC, callbacks

Owner goal, September 18, 2026: the failures of September 17–18 are not
acceptable; the platform must be production ready for the host itself, the
deployment script, service behavior after reboot, ACDC and callbacks.

"Bug free" cannot be proven for any system. What can be proven is that every
failure class we know of is **prevented, detected loudly, or recovered
automatically**, with native evidence. A gate below is closed only by the
evidence named in its row, recorded in `PROJECT_TASKS.md`. Offline tests alone
never close a gate.

## What September 17–18 actually exposed

| # | Failure | Class |
|---|---|---|
| 1 | Hostname change made RabbitMQ start an empty broker; API dead 7 h | identity not pinned |
| 2 | systemd reported kazoo-apps/ecallmgr `active` the whole time | no health gate |
| 3 | kazoo-apps silently fell back to `127.0.0.1` | silent default instead of refusal |
| 4 | Hand-edited Kamailio `local.cfg` crash-looped 4,367 times | unvalidated operator config, unbounded restart |
| 5 | `SELINUX=disabled` stopped every lab guest | unverified host prerequisite |
| 6 | Lab CouchDB OOM loop from an unbounded tmpfs journal | unbounded resource |
| 7 | Editing a deployed patch in place broke the next install | installer patch model |
| 8 | Retained lab eCallMgr does not start after a restart | reboot not part of acceptance |
| 9 | Queue worker stuck forever on a lost hangup | ACDC fault handling |
| 10 | Cancellation markers leaked on every abandoned call | ACDC resource leak |
| 11 | Broker redelivery rang agents for a dead caller and logged them out | ACDC fault handling |
| 12 | `max_connect_failures=0` logged every agent out | unsafe configuration value |
| 13 | `sup ... allow_carrier` stored ACLs where nothing reads them | operator command correctness |

Items 6, 7, 9, 10, 12, 13 are fixed; 11 is fixed in source and awaiting native
proof. Items 1–5 and 8 were recovered by hand and are **not yet prevented**.
Workstream A exists to prevent them.

## A. Host and service resilience (installer-owned)

| Gate | Work | Closing evidence |
|---|---|---|
| A1 | Pin RabbitMQ `NODENAME` in `rabbitmq-env.conf`; verify the broker runs under it and has the Kazoo user | Rename the hostname in a lab guest, reboot: broker keeps its database and users |
| A2 | Start guard for kazoo-apps/eCallMgr: refuse with one clear journal error when hostname, hosts mapping, `config.ini` host lines or broker login disagree with the installed identity. Never start on defaults | Each mismatch injected in a lab guest: service refuses, error names the cause; nothing starts half-configured |
| A3 | Permanent `kazoo5-stack-health` unit + timer (boot and periodic): API, AMQP login, SUP, media link, SIP listeners, agents supervisor. Failing state is visible in `systemctl --failed` and at `err` priority | Kill each dependency in the lab: unit fails within one interval and recovers when the dependency returns |
| A4 | Kamailio: configuration check as `ExecStartPre`, bounded restart (`StartLimit*`) so a bad config fails visibly instead of looping | Inject the September 18 `local.cfg` lines: unit enters `failed` after the limit, health unit reports it |
| A5 | Installer verifies host prerequisites it depends on (SELinux not `disabled`, identity mapping, cloud-init host rewriting off) in install and `--verify-only` | `--verify-only all` fails with the exact cause for each injected fault |
| A6 | Supported hostname change: a tested migration, or an explicit refusal that names this document | Migration run end to end in a lab guest, or refusal proven |
| A7 | Reboot is part of acceptance for every role | Scripted reboot of every lab guest and of main44 with a receipt; recreate the two retained legacy guests so they boot unaided |

## B. Deployment script

| Gate | Work | Closing evidence |
|---|---|---|
| B1 | Deployed patches are immutable: append-only hash manifest checked by a test; stacks for later edits | Test fails when a listed patch changes; done for the helper (September 18), manifest open |
| B2 | Audit all 129 patches for same-file overlap that the plain helper cannot re-verify | Fresh, repeat and upgrade-from-previous install pass for every role |
| B3 | Fresh install, repeat install, upgrade from the previous release and reboot on a clean Rocky 9 VM, all roles, split and all-in-one | Receipts per cell of that matrix |
| B4 | Installer never leaves a role half-changed: every mutating phase is preceded by a check that can refuse | Fault injection at each phase boundary |

## C. ACDC

| Gate | Work | Closing evidence |
|---|---|---|
| C1 | Deploy and natively prove: redelivery admission, auto-logout threshold, settled call id | Partition campaign passes; healthy node logs the verification and no automatic logout; inventory clean |
| C2 | Promote C1 and the carrier command fix to main44 | Promotion receipt, loaded module identity, real call on main44 |
| C3 | Fault matrix with real calls: apps node kill mid-ring and mid-call, broker restart, eCallMgr loss, FreeSWITCH restart, CouchDB outage | One campaign per fault: no stuck worker, no leaked marker, no duplicate bridge, no unrelated agent state change |
| C4 | Ring strategies: single winner, fairness, cleanup for ring-all, round-robin, most-idle | Native strategy campaign |
| C5 | Load and soak at the owner's target concurrency and agent count | Soak receipt at target for the agreed duration, resource ceilings recorded |

## D. Callbacks

| Gate | Work | Closing evidence |
|---|---|---|
| D1 | Recovery under worker, registry, node and broker loss at each callback phase (offer, registration, waiting, originate, returned leg, bridge) | One native case per phase and fault; exactly one callback, one bridge, durable terminal state |
| D2 | No duplicate callback or bridge after redelivery, restart or partition | Covered in D1 plus an explicit duplicate-injection case |
| D3 | The historical ambiguous ticket | Reconciled by evidence or formally closed by the owner; never force-settled |
| D4 | Five-language offer and position audio on the production media path | Native call per locale after the final media build |

## E. Cutover

Kazoo 5 on its own CouchDB and broker; rehearsal with a full copy of production
including the global databases; single-writer cutover; Kazoo 4 stack kept intact
as the rollback (`doc/kazoo4_kazoo5_couchdb_findings.md`).

## Needed from the owner

1. Target load: concurrent queued calls, agents, queues, and soak duration (C5).
2. Production topology: how many apps, eCallMgr, FreeSWITCH and database nodes.
3. Whether the hostname must change (A6) or stays `dev-testing`-style stable names.
4. Host changes (hostname, SELinux, firewall, `/etc/kazoo`) go through the
   installer or are announced first, so they are tested rather than discovered.

## Order of work

A1–A4 first: they turn silent multi-hour outages into prevented or loud ones.
Then C1–C2, which are already in flight. Then C3 and D1 together, since they
share the fault-injection harness. B2–B3 and C5 need the longest wall-clock time
and run alongside.

## Status on September 18, 2026, end of day (evidence in `PROJECT_TASKS.md`)

| Gate | Status |
|---|---|
| A1-A4 host and service resilience | Done natively: node identity and Kamailio start guards, broker name pin (refuses a name without a host), socket-activated port mapper, functional health timer, third-party telemetry opt-in. |
| A7 reboot | **PASS, twice**: whole-host reboot of main on September 18 (30 checks, no failed unit) and again on September 19 on the final runtime **with 100 agents logged in**: all 100 agent processes back unaided 95 s after the kernel started, no datastore pool timeout, post-boot verifier `failures=0`, and an unattended 100-call stage 100/100 with no error line. Also a bare applications-node restart with 100 agents: API back in 26 s, slowest datastore request 248 ms. Legacy lab primaries still need `--repair-legacy-pivot` after a guest boot (lab artifact). |
| B deployment script | Single entry point with interactive menu; nine side paths removed; fresh-broker and low-memory defects fixed; `--verify-only all` PASS on main (9 components); all offline suites triaged (no product defect); **B1 done** (134 patches pinned). Fresh installs on brand-new guests: `couchdb`, `rabbitmq` and a from-scratch `kazoo-apps` build **PASS** (two fresh-host-only defects found on the first attempts and fixed, failed logs retained). Open: the remaining fresh roles and the upgrade matrix from a production copy. |
| C1-C2 | Done earlier and promoted. |
| C3 fault matrix | **COMPLETE natively**: node kill mid-ring and mid-call, broker restart and outage under 30 calls, eCallMgr kill and loss, CouchDB outage, FreeSWITCH restart. THREE agent defects found and fixed: paused agents returning to rotation after a restart; an agent leg stranded by a lost event; an agent offered as ready while still talking after a node restart. The controller link after a media restart went from 19 s (16 s when the attempt met a not-yet-answering FreeSWITCH) to 9 s including FreeSWITCH's own 5 s stop and start; the lost 5 s attempt is gone. SIP is callable 14 s after the restart is ordered: the rest is FreeSWITCH itself and the deliberate wait before `mod_sofia` loads. One media server cannot do better; see `doc/media_server_restart_window.md`. The health check now fails on a media server with no running SIP profile. |
| C4 ring strategies | **PASS natively** on main, twice (before and after the agent start-up changes). |
| C5 load and soak | **PASS at the owner's target**: 100 concurrent answered calls held 7200 s on main, 0 failures, no fresh error line, no core, average CPU 30 % (peak 72 %) with the load generator on the same host, no measurable RTP loss. The first 100-agent run failed and exposed a datastore starvation at agent start-up (introduced September 18, fixed in `fd8a86d`). Earlier: 30 calls for 1800 s, and 30 calls with 5 queued in excess. |
| D1 callback recovery | **PASS natively**: queue supervisor loss, worker loss during ringing, applications node restart during `retry_wait`, applications node restart while the callback is bridged. |
| D2 duplicates | **PASS natively**: 64 concurrent identical registrations from both applications nodes against the real datastore give one ticket at its first revision; a differing one is refused (`doc/callback_duplicate_registration.md`). After a node restart with the callback bridged the ticket stays `completed`, same legs, no new attempt. |
| D3 historical ambiguous ticket | **Closed by owner decision** (September 18): left as it is; never force-settled. |
| D4 five-language audio | **PASS natively** on main for en-us, he-il, fr-fr, es-es, ar-sa; offnet (carrier) path PASS. |
| E cutover rehearsal | **Run once, conditional; gate open.** Read-only copy of production into a dedicated rehearsal lab, Kazoo 5 installed on it (third attempt), full migration 1527 s, API verified with production's own master key. Found and fixed: a deleted account still registered for ACDC failed initialization for the whole node (`adebf25`); a rehearsal node re-sends pending customer notifications and holds live customer webhooks (nothing escaped; neutralize step added, `338f875`). Sizing: the datastore needs far more memory than the lab default during migration (16 GiB recommended). Owed: one clean single-pass rehearsal, call path on production data, rollback drill, owner's cutover decisions. `doc/cutover_rehearsal_runbook.md`. |
