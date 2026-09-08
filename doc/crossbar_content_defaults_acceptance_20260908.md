# Crossbar collection content types and optional app overrides

## Normal installer, independent ALL and isolated browser/log checks passed

Main `/opt/kz5` used source `ec2ec69` for this build. Unit
`kz5-crossbar-content-completionfix-20260908.service`, observer74822, is
terminal success (`09fb22`, `2cde08`), PID0/inactive. Protected log:
`/root/kz5-acceptance/crossbar-content-completionfix-20260908.log`.
Same normal apps/eCallMgr command and2GiB/CPU200%/3600s bounds as below; no HOME
override or skip-build. Actual runtime12m3.090s, CPU15m53.050s, peak378.4MiB.
Compilation/release, SUP completion, apps/eCallMgr activation, configured
applications, authenticated APIs, prerecorded inventory/mappings/capabilities,
FreeSWITCH connection/framing and final selected-role validation all passed.
Documentation-only updates were subsequently fast-forwarded to08b2bc7 on main.
The old51560/98460 jobs remain terminal failures, not active observers.

Loaded callback exports were independently confirmed in the restarted apps node
(`83083/dabfb9`, `038973`): all five added arities are present. Actual HTTPS
browser76601/52c6e4 passes Talkchief selection,15 users/82 devices/4 queues/89
callflows, SmartPBX,4 ACDC cards, no captured page/request errors, and inactive
global indicator.30 test agents remain logged out after restart (`30550/8ddddf`).

The first browser log baseline overlapped independent ALL verification. It
counted one INFO `generating error401` line (`a0ffd5`), not the old callback
undef or missing override errors. Exact request correlation524fcb identifies
unauthenticated `GET /v2/?` from127.0.0.1; source `verify_kazoo_apps` deliberately
uses this JSON health probe and accepts HTTP4xx (`911047`). Repeat the isolated
browser/log gate after the ALL verifier is terminal; do not change the matcher
or claim this mixed window had zero matched lines.

Independent ALL44779/9328d0 failed Kamailio's activation-history check. All three
ERROR records are at16:50:06 (`04c8ab`), the already documented first broken
negative SIP registration fixture; no later integration ERROR was found by that
readback. Sourceae87595 fixed that fixture and its subsequent functional run
passed. With zero calls independently read back, development Kamailio was
restarted (`04c8ab`) to validate a fresh corrected activation. No journal records
were deleted, matcher changed, or previous failure retroactively marked passed.

Read-only ALL retry64780/fe58e6 passes, all nine components, unit
`kz5-content-verify-all-fresh-20260908` terminal/PID0 (`d99514`). Runtime1m40.245s,
peak244.9MiB; log `/root/kz5-acceptance/content-verify-all-fresh-20260908.log`.
Isolated HTTPS browser79330/e6baef passes the same complete company/UI checks;
fresh file/journal matches are both0 (`b50240`) using the unchanged matcher.
No calls remain. Baseline directory:
`/var/log/kazoo-acceptance/main44-ui-content-isolated-20260908`, since1788892632.
This closes the observed missing callback/optional override error paths for the
tested browser flows; it does not certify every Crossbar endpoint.
Next:30+5 call acceptance with browser activity, without concurrent installer
health probes. Original failures and mixed-window informational401 remain above.

Native installed SUP with a clean environment and no HOME successfully locates
the running Crossbar module (`b0f05b`). Legacy release-wrapper cookie-output
regression also passes on main (`57cdbf`); that wrapper's code is now synced,
but systemd services use the separate dev-start scripts. SUP completion test
logs are preserved under `/root/kz5-handoff/crossbar-content-20260908/`, with
independent matching SHA readback57cdbf/6e4845. No service or provider call was
made by that isolated wrapper test. Required post-install checks remain below.

## Historical second installer failure: completion generator

Source `38cbb03` was used by unit
`kz5-crossbar-content-localbuild-20260908.service`, observer98460; it is now
terminal exit2, PID0/inactive (`c6f73d`, `120609`). Log:
`/root/kz5-acceptance/crossbar-content-localbuild-20260908.log`.
Same normal apps/eCallMgr command, missing-HOME environment and resource bounds
as the first run. It successfully assembled the actual full Kazoo release and
passed production-BEAM checks. The next `make sup_completion` helper independently
started a named node and failed on missing HOME (`76fa65`), before service
restart. Apps/eCallMgr remained their original active PIDs2174/2175.

`kazoo-sup-completion-local-build.patch` removes distribution from that local
BEAM-inspection helper and is wired into normal core source preparation. Actual
make target regression reproduces failure before89595/cec126 (`e2dd67` confirms
the matching auth/HOME reason), then passes85746/463d65. Expanded regression
70253/f26aa0 also proves pinned fresh/repeat/reverse/conflict installer replay,
valid Bash output and maintenance/syslog_level/kapps entries. Its earlier replay
fixture inherited BASH_ENV and emitted shell startup warnings; the final fixture
uses an explicit clean environment and matching source executable mode.
The second failed build's crash report is root0600 at
`/root/kz5-acceptance/sup-completion-build-failure-20260908.dump` (`e0ecb1`).
No call data was deleted. The installer-invoked release and completion helpers
are now both local; the remaining named scripts found by the source scan are
separate lint/docs/xref tools, not invoked by this deployment path.

After success: establish a fresh backend log baseline; run the authenticated
company browser check; require no fresh file/journal errors; independently verify
all nine services, then run the30+5 load gate with browser activity included.
No deployment/browser/capacity pass is claimed until the next normal retry and
its subsequent acceptance checks succeed.

## Findings and source fix

The combined browser/call acceptance produced seven `undef` diagnostics for
content-type callbacks and one missing apps-store document error. The original
30+5 call run is retained as failed at its log gate; see
`main44_call_acceptance_20260908.md`. Its SIP/RTP counters are not changed.

Commit `7344fa1` adds explicit default-context callbacks for apps-store
collection/item, voicemail collection/item, and directory collection. These
paths use the default JSON representation; individual directory PDF and raw
voicemail audio handlers are unchanged. It also distinguishes an absent optional
apps-store override (`not_found`) from other datastore failures. Absence retains
inherited permissions, logs only at debug, and performs no GET-time creation.
Existing blacklist enforcement and real datastore-error logging are retained.
No shared binding exception logger or acceptance error matcher was weakened.

Crossbar is an upstream dependency: the durable change is
`scripts/patches/crossbar-optional-content-defaults.patch`, applied from the
normal `scripts/install-kazoo5.sh` source preparation. No commit was made to the
nested Crossbar checkout. ACDC remains ordinary tracked kz5 source.

## Offline evidence

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 512 \
  --runtime-sec 180 -- /usr/bin/bash /opt/kz5/scripts/test-crossbar-optional-content.sh
node scripts/test-crossbar-optional-content-patch.cjs
```

- Baseline `24423/0946ad`: six failures, three passes; five missing callback
  exports and the optional-document error reproduce on the old source.
- Patched `94716/63cef2`: all nine cases pass. Five production modules compiled
  with `-Werror`, Lager transform and no TEST/export-all options. Public
  callbacks and real context/JSON/document helpers are used. Catalog/datastore,
  node/service and whitelabel reads are controlled; this is not HTTP/native
  CouchDB proof. Diagnostics use real transformed Lager with an in-memory sink.
- `7a0528`: exact pinned upstream archive, actual installer helper, fresh and
  repeat application, byte equality with local source, reverse application and
  atomic refusal of conflicting input. Installer wiring and shell syntax pass.
- `79541/9421a3`: broader installer syntax, aliases, modular paths, security,
  pins, ALL dry-run and error regressions pass; not a live deployment claim.

## First deployment failed before activation

Main dev `/opt/kz5` fast-forwarded to `7344fa1` (`5999/780ad4`); zero calls
verified before starting the normal apps/eCallMgr installer. No source changes
should be synced to this checkout until the build is terminal.

- Unit: `kz5-crossbar-content-deploy-20260908.service`
- Observer: session `51560`, terminal exit2 (`d0471a`); PID0/inactive.
- Protected log: `/root/kz5-acceptance/crossbar-content-deploy-20260908.log`
- Command: `env USER=root KAZOO_MAKE_JOBS=2 bash /opt/kz5/scripts/install-kazoo5.sh kazoo-apps ecallmgr`
- Bounds: 2 GiB memory, zero swap, CPU200%,512 tasks,3600s deadline.

Compilation completed, but `build-dev-release` failed starting Erlang's auth
process: `filename:basedir_join_home/1` cannot resolve a missing HOME in this
systemd invocation (`801d9a`). The release escript started a fixed distributed
node `kazoo_relx` although assembly has no RPC/node dependency. Neither apps
nor eCallMgr was restarted; both original service PIDs remain active. This is
a failed installer run, not a deployment pass. Its generated crash report was
moved from `/opt/kz5/erl_crash.dump` to
`/root/kz5-acceptance/crossbar-content-build-failure-20260908.dump`, mode0600,
for recovery/diagnostics; no data or call records were deleted (`e64940`).

Source correction removes `-sname` from `scripts/build-release.escript`, keeping
assembly local without setting/reusing HOME or loading a cookie. Runtime node
configuration is unchanged. `test-release-build-nondistributed.cjs` runs the
real escript/relx with HOME absent and checks non-distributed execution and a
generated boot file. Baseline reproduces the auth failure (`65991/7e1016`,
`53b856`). The first patched run assembles successfully but the new test used
the wrong output path (`20753/ef5964`); native output is under the release-name
subdirectory (`fa3160`). This assertion was corrected before deployment.
Corrected native test `48279/483f67` passes: real assembled boot file, HOME
absent, no distributed node, no cookie created. The normal installer retry
will retain the same missing-HOME environment to exercise the source fix.

Only prerecorded artifact import/verification is used: no Gemini generation or
provider notification. Required after the corrected normal installer succeeds:
source/runtime readback; authenticated browser/API checks with a fresh log
baseline; all-nine-service verification; then the full30+5 capacity/log gate.

Before/after Crossbar EUnit logs and input hashes were copied to the main host
under `/root/kz5-handoff/crossbar-content-20260908/{baseline,current}/`, mode0600
inside0700 directories. Independent SHA256 comparison matches both copies;
the original machine is not needed to retain these test reports.

## Separate public HTTPS finding

Explicit no-proxy HTTPS to `46.225.31.248` from the original public source
`91.99.188.145` timed out (`82603/b28204`). Simultaneous captures show three
outgoing SYNs on the source interface (`14427/140b7c`) and no matching packets
arriving on the destination public interface (`79883/fcbcd8`). Private-route
HTTPS browser checks pass. Nginx listens on443 and the inspected host input
policy accepts traffic; no firewall settings were changed.

This localizes the observed failure before destination Nginx, but does not prove
public unreachability from every client. The operator has been asked whether a
cloud firewall/allowlist intentionally restricts the source. Confirm intended
exposure and upstream routing/filtering; do not blindly open firewall policy.
