# Callback controls deployment checkpoint — 2026-09-05

This checkpoint is not end-to-end or production certification.

## Deployed

The callback offer has its own enable switch, initial delay and interval. One
per-call producer serializes offer/position playlists, waits for the exact noop
completion, and stops on manager death or loss of call ownership. A lost
completion fails quiet after a bounded wait rather than growing a playback queue.
Per-call workers are temporary supervisor children, not restarted orphan workers.

The applications and ecallmgr services kept their existing PIDs and restart counts.
Production-only BEAMs were checked for TEST exports/options before deployment,
loaded module hashes were compared with their files, and the existing announcement
supervisor's stored child specification was updated without restarting services.
Exact previous BEAMs and the queue schema are backed up in
`/usr/local/src/kazoo5-installer/acdc-callback-controls-deploy.V4lihZ` on this host.

Loaded module MD5 values at deployment:

| Module | MD5 |
| --- | --- |
| acdc_announcements | 191feaef770559ab763776af2e777a9f |
| acdc_announcements_sup | 99d505825d3097d666e1a3f02035a2d3 |
| acdc_queue_manager | 6bb67afad5d12f48cbcd68534bf27e57 |
| cf_acdc_member | b7a6723b5d5d1cbadcf3052e75f9d990 |
| kapi_dialplan | 7b1e01cc4a148da561f433866ff4caec |
| ecallmgr_call_command | 3249cce8ec5b117690e4a1a084a77171 |

An existing announcement worker was stopped only after its exact call was absent
from FreeSWITCH and the cluster channel lookup. The supervisor then had zero
children; no customer call or agent login was changed.

The queue schema was saved with its exact prior revision and read back. The
schema cache was flushed specifically for `system_schemas/queues`.

## Evidence and remaining gates

- Private scheduler tests: 9 groups passed; reconstructed installer baseline:
  11 groups passed, with no staged `acdc_language` module available.
- Private callback feedback tests: 14 groups passed. The opt-in per-file playback
  timeout tests passed 3 groups, including legacy behavior and no inherited
  channel playback-timeout variables.
- The 19:23 UTC isolated timing call passed SIP (caller exit 0), full-phrase PCMU
  audio verification, producer cleanup and unchanged service-PID checks. Offers
  occurred at 3.079, 18.079 and 33.099 seconds; position prompts at 11.060, 26.079
  and 41.099 seconds, followed by normal BYE/200 teardown. Full-phrase reference
  correlations exceeded 0.99999. Evidence is held in the private host directory
  `/var/log/kazoo-acceptance/20260905T192338Z`.
- That run's overall acceptance gate still **failed** because `sup -e` calls
  produced remote audit-log `FORMAT ERROR` entries. The logger assumes string
  arguments even when SUP passes Erlang terms; it also logs raw arguments/results.
  The remote logger was subsequently repaired on both nodes; the clean repeat
  below supersedes that failed run for this bounded acceptance scenario.
- The 19:35 UTC repeat **passed**, including SIP caller exit 0, full-phrase audio,
  independent schedules, no entry offer, normal teardown, producer removal,
  unchanged service PIDs, no new core dumps, and zero fresh journal/file error
  matches during the call-test window. Offers occurred at 3.113, 18.134 and 33.153 seconds; positions at 11.113,
  26.113 and 41.135 seconds. Exact-revision queue/callflow cleanup passed, with no
  agent changes or unrelated document changes. Evidence:
  `/var/log/kazoo-acceptance/20260905T193537Z`.
  The post-cleanup scan found only two informational `404 bad_identifier` entries
  from the required probes proving both deleted fixture documents are no longer
  available through Crossbar. There were no new SUP formatting errors; the
  applications/ecallmgr crash logs retained their earlier sizes and timestamps.
  This is one local timing call with no DTMF or outbound callback; it does not
  validate callback confirmation, return routing or unanswered-attempt retries.
- Earlier attempts caught a base64 configuration-reader bug, an invalid strong
  HTTP ETag cleanup assumption, and inappropriate RTP echo-pattern verification
  for a queue-audio caller. These harness issues were corrected. All temporary
  fixtures, including the retained queue from the early failed setup, were
  recovered/cleaned with exact raw CouchDB revisions and unchanged unrelated
  document/agent checks. No temporary live queue or callflow remains from them.
- Invalid/non-numeric caller ID now has bounded failure feedback, but this does
  not create a routable return destination. The user's MicroSIP callback route and
  unanswered-first-attempt retry remain separate live acceptance gates.
- Callback control-ack loops were subsequently audited and repaired as described
  below. The accepted-success playback loop received the follow-up below;
  queue-side ownership races remain separate review items. This is not proof
  for every callback phase.

## Accepted-success follow-up — approximately 20:30 UTC

`cf_acdc_member` now requires the original Call-ID, noop application, and exact
playback identifier before treating the accepted-success prompt as finished.
Original-leg hangup ends the executor without canceling the durable accepted
ticket; a bridge or foreign-controller usurp yields control. Duplicate/unrelated
events do not extend its absolute deadline. Sixteen success-loop and twenty
control-loop private tests passed against production-compatible sources.

The loaded module MD5 is `ac632898dd48fb1316b8d2c91a860c2d`. Protected prior BEAM:
`/usr/local/src/kazoo5-installer/callback-control-live-deploy.43DYFh`.
Services were not restarted. Follow-up live run `20260905T210254Z` exited zero:
digit 6 at 4.989387 seconds, complete 6.124-second confirmation before BYE
(correlation 0.999991), unanswered first return for 15.099118 seconds, then a
confirmed/bridged retry 17.980275 seconds after cancellation. The configured
minimum backoff was 15 seconds. Both agent audio directions carried 4,914
progressing PCMU packets. The busy call was released 6.621464 seconds after
confirmation (two-second explicit wait plus proof-processing overhead).
Journal/file error matches were 0/0, new cores 0, and checked service PIDs and
restart counts unchanged. This still uses legacy English audio; it does not
verify Gemini defaults. Queue-worker detach ownership races and historical
ticket reconciliation are not solved by this callflow-executor change.

## Callback control lifecycle repair — 20:13 UTC

The control-ack loops now propagate terminal events scoped to the original call,
ignore unrelated/duplicate responses without crashing or extending the deadline,
correlate the current pause capability, and resume a late registration without
abandoning its original queue member. Resume and abandon require their exact
response operation/status pairs. Twenty private lifecycle tests passed against
both the staged source and the deployable language-free baseline; production
`-Werror`, exports/imports and old-build provenance were checked separately.

Only `cf_acdc_member` was hot-loaded under the shared acceptance lock with zero
native channels. Loaded MD5 is now `1a5b20d741eadcdcb69925c42cfa3ab8`; previous
MD5 was `b7a6723b5d5d1cbadcf3052e75f9d990`. Protected source/BEAM rollback files
and unchanged-service receipts are in
`/usr/local/src/kazoo5-installer/callback-control-live-deploy.LQ48EQ`.
No applications, ecallmgr, media or agent-service restart was required.
The default integration patch and separate staged language layer reproduce the
reviewed sources byte-for-byte through forward and reverse replay. Live retry
acceptance subsequently passed in `20260905T201353Z` (exit zero): received
confirmation before server hangup, deliberately unanswered first attempt,
positive durable retry state, confirmed/bridged second attempt, strict clean-log
and unchanged-service checks. See the current acceptance status for measured
timings and the retained historical-fixture/MicroSIP/multi-node limitations.

## SUP audit repair

`sup:in_kazoo/4` now logs only module/function/arity and start/completion metadata.
Its command result, CLI output and exception behavior are unchanged. Raw arguments
and results no longer enter those two audit notices; this is not a promise to
redact deliberately requested CLI output or all command-specific logs.

Six isolated regression tests and production `-Werror` compilation passed. The
patch passed pinned-source forward/reverse replay and is applied by the installer.
Only the remote SUP BEAM was updated on applications and ecallmgr; both loaded
MD5 `20816355a52faf585ffa0cfc5e3af2f6` and retained their service PIDs/restart counts.
Previous MD5 was `a850ac9d7e4be35d27f0f5213f219c3d`; rollback files are in
`/usr/local/src/kazoo5-installer/sup-audit-deploy.tg6kAz`.
Live probes on both nodes preserved the requested CLI return value, produced
start/completion notices, and emitted neither the synthetic argument nor a
formatting error in those audit logs.
The unchanged local CLI entrypoint still uses RPC; its bundled escript will be
regenerated by the next normal build, not by a service restart for this repair.

## Voices and API portal

All 165 generated Gemini/Sulafat assets were imported under content-addressed
installer-owned IDs and downloaded/hash-verified again. Existing/custom recordings
and queue selections were not replaced. There are 145 fixed clips plus 20 Arabic
and Hebrew callback digits. This is not complete position-number coverage or
native-speaker approval; activation and removal of remaining legacy playback paths
are unfinished.

The static source-derived OpenAPI portal is live at `/apis/`; its downloadable
spec and separate planned spec return HTTP 200, `/apis` redirects with 308, and
missing assets return 404. Nginx was syntax-checked and gracefully reloaded with
its master PID unchanged. This does not deploy the unified queue editor, certify
every catalog endpoint, or establish HTTPS readiness.

The refreshed catalog has 353 paths and 648 operations. The separate planned
contract includes `GET /v2/accounts/{ACCOUNT_ID}/members/devices`, explicitly
marked not implemented. The public assets match their verified repository
manifest; no authenticated API execution is enabled in this documentation viewer.
