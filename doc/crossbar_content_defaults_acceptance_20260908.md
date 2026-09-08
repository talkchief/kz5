# Crossbar collection content types and optional app overrides

## Current job: normal installer retry is active

Source `38cbb03` is on main `/opt/kz5`. Unit
`kz5-crossbar-content-localbuild-20260908.service`, observer98460, PID289461
is verified active (`921c45`, `3ff30e`). Log:
`/root/kz5-acceptance/crossbar-content-localbuild-20260908.log`.
Same normal apps/eCallMgr command, missing-HOME environment and resource bounds
as the first run. Do not restart it on observer timeouts, and do not sync new
Git revisions into the compiling checkout. The latest documentation may be
pushed separately; sync it only once this unit is terminal.

After success: establish a fresh backend log baseline; run the authenticated
company browser check; require no fresh file/journal errors; independently verify
all nine services, then run the30+5 load gate with browser activity included.
No deployment/browser/capacity pass is claimed for this active retry.

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
