# Private live-dashboard backend production build

`scripts/build-live-dashboard-backend.sh` prepares a new protected
`/usr/local/src/kazoo5-installer/live-dashboard-backend.*` directory. It builds
all production ACDC modules and all Blackhole modules, including every consumer
of the changed Blackhole context header. The existing
`scripts/test-acdc-production-compile.sh` is a narrower compile check: it has no
Blackhole/.app assembly and removes its temporary output, so it is not reused as
a deployment artifact builder.

Root must review the frozen script and run it serially under the resource and
network guard. Command:

```sh
cd /opt/kz5
/usr/bin/bash scripts/run-kazoo-validation.sh --memory-mib 256 --reserve-mib 768 --runtime-sec 300 -- /usr/bin/unshare --net /usr/bin/bash /opt/kz5/scripts/build-live-dashboard-backend.sh
```

Allow roughly 1–3 minutes and 256 MiB for the two serial production compilations;
the guard remains authoritative and may refuse admission. No service pause is
performed by the script. Source copies/BEAM output are small relative to the
existing cached dependencies, which are read-only and not copied or fetched.

The runner uses the actual app Makefiles and `make/kz.mk` full-source
`ebin/PROJECT.app` recipe, with `KAZOO_FORCE_RECOMPILE=1`, `-j1`, normal production
warning flags and `-Werror`. It deliberately does not invoke `compile`,
`compile-direct`, `all`, `deps`, `apps`, `json`, `depend`, clean or test targets:
even compile-direct also formats JSON and can invoke extra prerequisites.
Make includes, local app source/header inventories and .app templates are
copied into the private stage; generated dependency rules are never copied or
included. Make environment overrides are cleared. Explicit source lists cover
ACDC production source and Blackhole top-level/nested production source. Only
`src/ci` property/API-client fixtures are excluded, as in the existing ACDC
production proof; those source bytes remain pinned. No TEST/PROPER source branch
is requested. Source-declared .app versions are retained explicitly rather than
copying possibly stale/test-contaminated runtime .app files or guessing a version.

Before compilation, `.app.src` consultation also checks that Erlang resolves
both selected application directories to the private stage. No application
BEAM is loaded. After compilation, `beam_lib` inspects every output for exact
module count, source path, no TEST/PROPER/export_all flags or test exports. The
new .app module lists must exactly match the freshly compiled modules, and the
source-declared versions must agree. This is metadata inspection, not an
application startup or functional test.

Retained evidence includes original/staged source and cached dependency hashes,
before/after source inventories, exact make argv, compile/metadata logs, each
artifact hash, module counts/versions, and a fail-closed receipt even on failure.
The runner does not rebuild dependencies or prove their runtime behavior. It
does not execute tests, fetch packages, load modules, publish API/UI artifacts,
restart services, or overwrite any existing source/ebin/config/runtime path.
Only a fully successful receipt with stable inputs yields candidate production
artifacts; deployment, ABI cutover and live acceptance remain separate root-owned
steps.

September7 root96554 passed:74 ACDC and30 Blackhole production modules, complete
application inventories and stable inputs. Candidate artifacts are retained at
`/usr/local/src/kazoo5-installer/live-dashboard-backend.pPXUZc`.
Root11614 activated those two ebin directories with controlled apps/ecallmgr
restarts; previous directories remain recoverable under
`/tmp/kazoo-live-rollout.OYdOqh/{acdc,blackhole}-ebin.before`.
Root65638 passed real authenticated HTTP snapshots, anonymous/wildcard rejection,
native subscribe/unsubscribe and one scoped invalidation followed by a refetch.
The invalidation was deliberately emitted through `acdc_dashboard_events:changed/2`;
it was not a call-state transition test. Initial subscription failed because the
old persisted Blackhole autoload list omitted the new module; native maintenance
added/persisted only `bh_queue_live`, preserving the other entries. UI deployment,
broader permission/reconnect/call-state acceptance and the installer upgrade
automation remain separate. Later source changes require another build.
