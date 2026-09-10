# Main development runtime promotion — September 10, 2026

Target: `10.1.0.44` (`dev-testing`), root repository `/opt/kz5`.
This is a development maintenance window, **not** a completed cluster
drain/rolling-upgrade/rollback acceptance gate.

## Admission and retained recovery material

Read-only admission found zero main FreeSWITCH sessions and zero main ACDC
agent supervisors. The old main runtime does not export the newer initializer
or agent maintenance observation functions; a strict snapshot therefore refuses.
The applications service itself was active, not broken. Both saved database and
broker endpoints resolve to this development host, and the separate compatibility
runtime uses `/var/lib/kazoo-compat-runtime/apps`, not the tree being rebuilt.

The normal broker preflight passed for two compatible callback work queues.
This checks queue properties, not complete producer/broker drain. The historical
quarantined callback documented in `callback_originate_receipt.md` belongs to the
original source server; its exact document returns404 on dev44. It was not
deleted, redialled or settled on either server.

Protected backup/run directory on dev44:
`/root/kz5-main-promotion-20260910.wAZTViMW` (root-only).
It contains the previous runtime tree, previous protected Kazoo configuration,
SHA-256 checksums and separate initial/retry logs. Backups are recovery material,
not evidence of a tested rollback. Do not publish their contents.

Initial unit `kz5-main-promotion-20260910` failed before installation because
its systemd launch lacked a login home. Backups and the idle recheck had passed;
SIP ingress, applications and eCallMgr were stopped. Keep this failed receipt.

The retry `kz5-main-promotion-retry-20260910` runs with explicit `User=root`,
a login shell, `TimeoutStartSec=2400`, the shared acceptance lock and private logs.
It verifies both backup checksums, then executes the real installer:

```sh
bash scripts/install-kazoo5.sh kazoo-apps ecallmgr
```

The source pin is `4cd9953`. Existing stored language artifacts are verified and
imported; no Gemini request is made. SIP ingress is restarted only after the
installer succeeds. A failed install leaves ingress stopped for deliberate
recovery. Do not start duplicate jobs after an observation timeout.

## Main-runtime call acceptance

`scripts/test-channel-monitor-live.cjs --main-dev --live` adds an explicit,
fixed development-host profile. It refuses a different host/IP, source root,
database/broker host or public hostname. It reads the actual master identity
through local authenticated RPC instead of borrowing the original server's ID.
The existing protected synthetic account, resource markers, exact registration
ownership, shared lock, three-leg SIP/RTP privacy tests and scoped cleanup remain
required. Arbitrary targets, production accounts and PSTN calls are not admitted.

The main profile also paces its three setup logins under the normal authentication
rate limit. `--prepare-only` makes no API writes or SIP calls. Local guard and
fixture tests, synthetic leakage checks and all three zero-call SIPp scenario
parses passed through the bounded network-isolated validation runner.

The staged harness is under the protected backup directory's `acceptance/`
subdirectory, separate from the compiling checkout.

## Collected deployment result

`kz5-main-promotion-retry-20260910` exited0 and was collected. The normal
installer reports all requested components passed validation. SIP ingress was
reopened; applications, eCallMgr, Kamailio and FreeSWITCH are active. No running
BEAM was hot-loaded. Authenticated native checks match loaded/disk identities
for `acdc_init`, `acdc_agent_fsm`, `acdc_agent_listener`, `acdc_agent_handler`,
`cb_channel_monitor`, `ecallmgr_call_monitor`, `ecallmgr_originate` and
`kz_amqp_connection_sup`. The installed strict agent snapshot now succeeds,
reports all workers observed and zero agent workers, matching admission.
Protected snapshot: `main-agents-after.json` in the backup directory.

Initial main call campaign `kz5-main-monitor-after-promotion-20260910` **FAILED**
after Listen/eavesdrop passed both privacy windows, stop202 and original bridge
survival. The harness then tested the agent leg synchronously after caller
termination; native SIP BYE propagation had not finished. Final scoped cleanup
completed with zero sessions and no retained fixture. Evidence:
`/var/log/kazoo-monitor-acceptance-jfzKkF`. This is not a four-mode pass.

The harness now waits at most eight seconds for the exact saved agent leg to
disappear. It does not terminate that leg separately, select another call, or
ignore a persistent leg/failed observation. Focused regressions cover delayed
BYE, persistent leg, unavailable native observation and no saved peer. The full
offline harness suite passes. New native unit
`kz5-main-monitor-after-promotion-2-20260910` **PASS**, exit0, collected.
All four modes passed on actual main-runtime three-leg calls, not private guest
calls. Protected evidence: `/var/log/kazoo-monitor-acceptance-WTrjrC`.

Independent reanalysis of all four captures matches the two stored pre/post-
keypad3 privacy windows. Each mode passes all five authorization negatives,
supervisor stop202 and original bridge survival. The protected
`independent-acceptance.json` receipt also confirms a fresh strict zero-agent
inventory, zero media sessions, no retained monitor fixture and five services
active/enabled (applications, eCallMgr, Kamailio, FreeSWITCH, nginx).

The journal scan since applications activation at03:18:42UTC examined23269
entries (about42MB), finding zero crash-report, supervisor-report or exception-
exit patterns in that window. The initial bounded-buffer journal reads refused
with ENOBUFS; the completed check streams entries without exposing message data.
This is a bounded crash-pattern check, not a claim that every log or all future
runtime behavior is error-free. `journal-summary.json` retains the counts.

Main applications/controller promotion and healthy supervision acceptance are
closed. Full cluster producer/broker drain and coordinated upgrade/rollback,
new private media-gate sustained load, and historical callback disposition
remain separately tracked. No production company or historical ticket was
changed by this deployment/test.

## Repository and published reference

Release `718e99c` was pushed to kz5 `master` and fast-forwarded into dev44
`/opt/kz5`. Its changes after the installed `4cd9953` baseline are the acceptance
harness and documentation, not applications/core runtime source.
The normal `install_api_developer_docs` installer function deployed the guide.
All13 served assets matched repository bytes through certificate-verified HTTPS
against the local nginx listener for `kz5-dev.talkchief.io`; protected receipt
`docs-https.json`. The browser loaded653 operations with zero console errors or
external requests, and API execution disabled. Named instructions remain at
`https://kz5-dev.talkchief.io/apis/supervision.html#whisper`, `#barge`, `#join`
and `#listen`. This check does not claim a fresh external-network reachability
test. The unrelated untracked dashboard draft and Python cache were preserved.
