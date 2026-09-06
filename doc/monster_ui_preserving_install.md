# Preserving Monster UI installation

The installer builds in a new, protected source directory. It does not reset an
existing checkout, delete unselected source/apps, replace the entire web root,
or re-import existing app catalog images.

The build fingerprint includes the framework/app commit pins, local ACDC file
fingerprint, all seven framework patches, both Callflows patches including CSS,
the configuration/deployment helpers, scoped installer build functions, the
exact reviewed dependency lock hash, and actual Node/npm versions. The default
source lock is `da59e0891ebb949b5acdb81663463fcc09362ce7f956f9ed50beeafe7ecd6222`.
The original lock is checked before a narrow package compatibility patch and
the audited npm10 lock artifact are installed privately. The compatibility patch
removes the unpinned `npx npm-force-resolutions` preinstall and expresses the same
existing exact resolutions (`json5=1.0.2`, `glob-parent=5.1.2`) as native npm
overrides. Retained v3 lock provenance is
`205df23382ff832ee16354e891d369e9062935f130dec17fde901eaafab01712`;
the normalized intermediate artifact (one final LF) has SHA256
`231d4c2c0bb7e8886e0032d9d3b4d3e467ac9130d5625f67b3901cb45b99680e`.
The intermediate `b26ef562feaef876f08c532b5e1d8e875d900a61d3f457f7aad3e1ba71e72abd`
repaired nested `meow/node_modules/semver` from 7.5.1 to 7.8.5 for its `^7.3.4`
consumer. Although npm-ci succeeded, a real build exposed missing required
dependencies. The corrected lock is
`6f8e2516404ce4b86048fa3d09dbe011c1e9363460c8cd204a01f9639735d396`.
Its package paths are ordered parent-before-child: the retained migration's
child-before-parent order caused npm10 Arborist to retain a stale hoisted edge
and prune a required nested yargs. A guarded offline graph probe reproduced the
55-path pruning; changing only entry order removed that pruning. The lock also
corrects three forced glob-parent 5.1.2 dependency declarations to the installed
package's actual `is-glob:^4.0.1`, reuses the already-pinned is-glob 4.0.3 artifact
at two nested paths, and removes unused path-dirname and stale root lifecycle
metadata. No new registry artifact was resolved for these repairs.

Relative to the pinned source there are 1,135 package paths versus 1,134 in the
corrected artifact: two added, three removed, and two reviewed common-path
version/resolved/integrity changes (semver and nested is-glob). The exact audit
rejects every other artifact change. Both locks, package patch, audit helper,
installed-dependency verifier, split-build controller, explicit minifier profile
JSON/helper and phase patch affect
the fingerprint. This source audit alone is not proof of a working build.

The production build recipe uses `npm ci --ignore-scripts` in its own dependency
directory, a required installed-dependency graph check, explicit single-job
`npm rebuild node-sass re2`, native Sass/RE2 smoke checks, and the original Gulp
production tasks split across fresh processes. The verifier checks required
runtime/development and present optional dependency ranges; only the two exact
reviewed overrides are permitted. It is not a peer-compatibility/security audit.

`build-monster-production.cjs` runs prepare (copy, Sass, templates, RequireJS),
exits that process, minifies main.js then templates.js in separate processes
with the same pinned gulp-uglify factory and Vinyl paths, and finally
runs CSS/config/version/cleanup in a fresh Gulp process. No option or source-map
behavior besides the explicit profile below is intentionally changed;
minification errors stop the build.
Each child is bounded to 300 seconds and V8 heap 256 MiB. The controller accepts
only protected installer-owned source stages and refuses linked output trees;
it checks all source, Gulp/Babel, package and lock hashes before/after. Failed
intermediates remain private and cannot advance ownership or the build marker.
The original `build-prod` task is still present for comparison, but the installer
uses the bounded controller. It checks the audited lock before and after. No shared `node_modules`
is modified. A different framework/lock requires a matching reviewed package
compatibility artifact and updated audit, not merely an arbitrary hash override.
An old build marker is not dependency evidence.

The reviewed `uglify2-mangle-no-compress-v1` profile uses exactly
`gulp-uglify@2.1.2`, its nested `uglify-js@2.8.29`, and `{compress:false}`. This
supported option skips the expensive Compressor pass while retaining default
local-name mangling and code output. It does not switch minifiers, remove apps,
or ignore errors. It is deliberately **not byte-identical** to the previous
fully optimized output: constant folding/dead-code compression are not run,
so raw and compressed downloads can be larger. Exact options and engine versions
are asserted and fingerprinted; arbitrary profile knobs or versions are refused.
The helper's installed README documents `compress:false`; its pinned engine
conditionally skips Compressor and still executes default mangling/output.

Before and after each minifier child, a separate bounded pinned-parser process
verifies syntax and records global named/anonymous `define` call coverage,
literal dependency arrays, arity and lexical registration order. Shadowed local
`define` functions are excluded using lexical scope. Dynamic dependency arrays
are refused. This is a structural gate, not a proof of all runtime behavior or
every possible AMD alias. Small execution fixtures cover module loading, UMD,
shadowing, Unicode, public properties, side effects and exception ordering;
browser acceptance remains separate. Each output must pass inventory equality
before finalization. No full-optimizer size comparison is invented when that
optimizer could not finish on the same input under the host's approved cap.

## Files and configuration

`scripts/deploy-owned-monster.cjs` plans exact bounded changes, keeps private
backups/receipts, and verifies final hashes before its ownership manifest becomes
complete. The installer verifies that manifest against its expected input hash
before advancing the compatibility marker. `--verify-only monster-ui` checks
actual owned content and configuration, not just marker text.
Ownership verification also requires the receipt's web root to match the
configured root. The transport gate hashes served index.html, main.js and
config.js, including an exact HTTP 200 status, against that verified local root.
It preserves all response bytes, requests identity encoding, ignores curl user
configuration and proxies, and uses the configured public-IP Host or HTTPS
hostname/SNI with loopback resolution. HTML fallbacks, redirects, wrong bundles
and byte differences fail. The catalog readback requires exactly one row for
every selected application, so duplicate names cannot satisfy verification.

The installer stages `configure(existing, requested API/socket/branding/billing
options)` and records its exact before/after configuration hashes and those
public options. The ownership planner independently recomputes this transform
before permitting `js/config.js` to change; arbitrary staged differences or stale
source hashes fail. Unknown operator fields remain intact. The full config is
backed up before the bounded replacement, and the ownership receipt records the
transition. The standalone helper still requires byte identity unless given
this explicit configuration-change plan. Existing legacy adoption still requires
review of the exact full plan, including this config transition. This small path
does not support executable operator config hooks.

Runtime `apps/acdc/language-capabilities.json`, `/apis`, unrelated applications,
and unselected standalone app files are preserved by the owned deployment.
The existing capability and API documentation helpers retain responsibility for
their own separately validated updates. Previously embedded/preloaded apps must
remain in the new preload set: preserving their directories alone would not
preserve definitions bundled in `main.js`. Removing such an app requires a
separately reviewed standalone conversion, not a destructive rebuild.

Symlink paths/ancestors/children, unsafe hard links, foreign owners, writable
directories/files, unexpected output paths, stale plans, modified managed
targets, and generated runtime capabilities fail closed. Tree limits are
20,000 files, 20 MiB per file, and 512 MiB overall. The static allowlist was
checked against retained complete Gulp outputs (1,929 and 1,930 files).
Newly created public web directories are explicitly 0755 even with an operator's
umask 077, and deployed static files are 0644. Existing directory modes are not
silently changed. Newly created state/build roots remain private 0700. Seven
focused real-filesystem groups exercise those boundaries in addition to the
original preservation tests.

## Legacy adoption and partial recovery

Fresh empty installations and previously owned unmodified installations have
an automatic bounded apply path. A nonempty legacy installation without
`/usr/local/share/kazoo5-installer/monster-ui-owned/owned.json` deliberately stops
at the plan boundary. Preserve the newly prepared build/plan directory. Generate
a fresh `adopt_existing:true` options plan using the helper, review every exact
existing path/hash and proposed removal, then apply only its exact approval
hash. Never infer ownership from a prior marker, app name, URL, or directory.
That one-time operator review is a prerequisite, not an installer failure to
be bypassed by deleting existing files or forging a marker.

The CLI accepts root-protected 0600 JSON options/plan files:

```text
node scripts/deploy-owned-monster.cjs --plan OPTIONS.json
node scripts/deploy-owned-monster.cjs --apply PLAN.json EXACT_APPROVAL_SHA NONEXISTING_BACKUP_DIRECTORY
node scripts/deploy-owned-monster.cjs --verify STATE_DIRECTORY/owned.json
```

Save only the first result's `plan` field as `PLAN.json`; its sibling
`approval_sha256` is the exact approval. All web/stage/state paths and the
fingerprint are rechecked immediately before mutations. Adoption does not
authorize overwriting operator-owned files merely because they collide with
the selected/static scope: the explicit full-path review decides that boundary.

There is a whole-workflow directory lock and a separate activation lock. Do not
remove stale locks automatically. Individual file replacements use rename,
but the whole web tree and catalog are **not atomic**. A crash may leave mixed
files; backup receipts list completed paths. Inspect exact current hashes and
choose a guarded recovery. Never automatically rollback, adopt again, or retry
an ambiguous partial operation. An abrupt process death leaves its lock.
If content proof/ownership replacement succeeded but the final receipt write
failed, ownership can already be complete while the command reports failure;
verify actual content and preserve that evidence. Other root writers outside
these locks can race; this is not a transactional filesystem or root sandbox.
Build directories and backups are retained for diagnosis; plan their disk
retention explicitly rather than deleting operator source or evidence.

## Catalog registration

The default pinned Crossbar integration patch packages
`applications/crossbar/src/kazoo_monster_catalog.erl` through the ordinary
Crossbar source/module build. The SUP hook invokes `init_app/3` only for the
explicit selected app names. A single existing app document is returned as
`preserved` with no document or image writes. Missing targets use one
deterministic account/name ID and one absent-only save containing all image
attachments; conflicts/unavailable/unknown outcomes stop with no automatic
retry, update, image deletion, or rollback. A positive result requires saved
metadata and attachment byte readback. Existing custom API URLs are preserved;
changing them needs the separate exact-revision migration workflow.

Master account lookup reads only the configured `accounts.master_account_id`,
requires a lowercase 32-hex ID, and never discovers/persists the oldest account.
The installer's `ensure_master_account` remains the explicit bootstrap step.
Metadata/image reads verify protected paths, regular-file identity/size/mode,
and bytes across reads; only access-time changes are ignored. These checks do
not protect against a malicious concurrent root writer restoring every value.

The hook accepts only exact `created` or `preserved` SUP output, with no raw
document/error response in logs. Timeout or `created_unverified` may mean a new
document was committed and requires read-only reconciliation. Existing legacy
writers can race a separate same-name creation under another ID; no generalized
catalog name-uniqueness lock is claimed. Coordinate first-create writers. No
fallback to `crossbar_maintenance:init_apps` or its existing-image rewrite path
is allowed. Split web/apps nodes require the selected static source to be
available on the applications node or registration delegated there explicitly.

## Offline verification and remaining live gates

```sh
node scripts/test-deploy-owned-monster.cjs
node scripts/test-monster-installer-preservation.cjs
node scripts/test-monster-build-dependencies.cjs
node scripts/test-monster-production-build.cjs /absolute/monster-owned-build.STAGE/source
node scripts/test-monster-minifier-profile.cjs /absolute/monster-owned-build.STAGE/source
node scripts/verify-monster-production-artifact.cjs /absolute/monster-owned-build.STAGE/source
node scripts/test-monster-template-order.cjs /absolute/monster-owned-build.STAGE/source
node scripts/test-monster-served-proof.cjs
bash scripts/test-monster-catalog.sh
bash scripts/test-install-kazoo5-modular.sh
```

Private integration evidence: 21 real-filesystem preservation/negative groups,
10 actual extracted installer-hook groups (including config transition and exact
lock/package rejection), 9 catalog EUnit groups, and production
Crossbar replay with `-Werror`, all normal warning flags, Lager transform and
`+debug_info`. The production BEAM exports only `init_app/3` and module metadata;
it has no test exports or `kapps_util` implicit-master dependency. The modular
dry-run suite also passed with private installer logic and read-only shared
fixtures. API docs deployment-order assertions were updated to the owned path.

After integration into the current installer, all 21 filesystem and 10
installer-hook groups passed again; shell/JavaScript syntax and whitespace
checks passed. This recheck did not rerun Erlang or native builds.
The unmodified original source lock was tested with npm10 `ci` and failed its
consistency gate (glob-parent/path-dirname graph mismatches). That failure is not
waived. A capped package-lock-only probe identified the single semver repair;
its broader55-path pruning was deliberately not adopted. Final exact package
SHA`1838ddad9703350234221b5db8451b3c5d41c5c1e5cc3c7606f223fd56da873b`
and lock`b26ef562...` passed a real isolated `npm ci --ignore-scripts` on this host:
1,075 packages installed in48s, exit0, lock unchanged,24.045 CPU seconds,384MiB
memory cap, no swap,50%CPU,128tasks,300s deadline, Node heap192MiB. A second
fresh full-source stage with the current ACDC app passed the same exact CI,
the allowlisted single-job `npm rebuild node-sass re2`, and actual Sass render
and RE2 matching smoke checks under the verified resource guard. No OOM occurred.
That intermediate production Gulp build failed before task startup: npm10 omitted the
lock's nested `gulp/node_modules/yargs@7.1.2`, so `gulp-cli@2.3.0` resolved the
incompatible root `yargs@17.7.2`. The failed build/receipts are retained and this
established that CI exit zero is not build proof.
A first private launcher-path error was also retained separately and corrected
before invoking the actual pinned Gulp executable. The corrected 6f8e2516 lock
then passed real CI (1,130 packages), its complete installed required graph,
allowlisted native rebuild and real Sass/RE2 smoke checks. Two monolithic Gulp
attempts reached minifyJs but exhausted V8 heaps of 192 and 256 MiB respectively;
both exited 134 under the unchanged 384 MiB cgroup cap with zero cgroup OOM kills.
The first compressed core was retained; core dumps were disabled before the
second and its coredump record has no file. Neither failure is waived.

The split candidate passed five dependency-regression groups, eight
byte-equivalence/failure/path-safety groups, the actual 1,130-node graph check,
and all ten installer-hook/fingerprint groups under the same guard. The exact
eight groups passed again after adding Gulp/Babel input hashes. The one approved
real full split build then failed too: fresh prepare completed in 1.45 minutes,
but the independent main.js minifier exhausted its 256 MiB heap after about
59 seconds. The controller exited 1 without finalization, all exact input hashes
were unchanged, and cgroup OOM/kill counts remained zero (peak 384 MiB, 80.3 CPU
seconds overall). Its SIGABRT core record has no file. That default-compressor
split recipe failed; no heap/cap increase or automatic retry followed.

The separately approved explicit no-compressor profile passed eleven semantic,
AMD inventory, pinned-option and error groups, eight isolation/path groups, and
ten installer-hook/fingerprint groups. The last ten passed again after rebasing
the public-directory mode fix. The approved full supported-profile build then
completed all original production phases in separate bounded processes, including
both minifications, all 73 AMD registrations and final CSS/config/version output.
Its payload exited zero; its surrounding evidence wrapper exited one because it
compared the fresh templates input against a previous generated raw hash. That
failed receipt remains unchanged. The prior raw templates bytes were not retained,
so their exact equivalence and the historical cause of that difference remain
inconclusive. An installed glob-stream fixture demonstrates that identical input
files and sizes can concatenate in a different order; this is a possible mechanism,
not proof of the historical difference.

An independently reviewed current-artifact readback subsequently passed against
the actual build log and source. It verified 1,931 static files, all 19 application
directories, the expected 16 preloads, all 10 unchanged metadata documents, all
463 compiled template keys, the pinned Handlebars 4.7.7 runtime and two ACDC state
renders. Runtime configuration remained byte-identical and no runtime capability
file was generated. The artifact digest is
`636210bbdcc919fc31f66fb118a7883765100dd05ce4c82cab509b0712645caa`;
its source digest matches the completed build record. Current main.js is 3,656,802
bytes (843,551 bytes with gzip level 9), and templates.js is 2,942,853 bytes
(300,658 bytes with gzip level 9). Both exact output hashes match the successful
minifier records. These figures do not compare against a completed default
Compressor run on the same input.

The original build reached the approved 384 MiB memory cap without a cgroup OOM
or kill. The readback and ordering fixture passed under the same 384 MiB cap,
zero swap, 50% CPU and 128-task limits, with a 120-second deadline and 128 MiB
Node heap; together they peaked at 151,535,616 bytes and used 4.466 CPU seconds,
with no memory-limit event or OOM. Both the failed original wrapper receipt and
the separate passed artifact-readback receipt are retained. Validation helper
hashes are recorded separately from the actual build-time helper hashes, so a
later installer/deployment verifier change must not be presented as having built
this artifact. No live files were deployed, and browser acceptance remains a
separate gate.

The subsequent ownership-root and transport/catalog verifier changes are
verification-only changes applied after that artifact was built. Eight focused
offline served-proof groups passed in their separate candidate, including exact
bytes with NUL/trailing newlines, incorrect responses/statuses, configured Host
and HTTPS routing, and rejection before HTTP when ownership differs. The updated
read-only catalog suite also passed duplicate-name cases. Their final combined
integration still needs its own focused regression run; neither candidate test
is live browser or catalog-creation acceptance. The direct build wrapper did not
record an aggregate installer marker. The original exact source/helper hashes
and independent final installer/hook hashes remain separate evidence; no new
ownership manifest or retroactive build marker has been produced.
Inherited deprecation/security notices for the old Node-Sass, ESLint, tar and
core-js toolchain require separate maintenance work; this is no security audit.

Those earlier tests did not prove a new-host installation, browser acceptance of
their newly built artifact, native SUP missing-app creation,
or live ownership/adoption. Those gates require separate recorded results;
do not claim them merely because static or mocked tests passed.

### Fresh current build and isolated browser check — 2026-09-06 11:46 UTC

A separate fresh source stage `monster-owned-build.pfUGAT` completed its actual
production build (session `79721`, exit 0) and independent readback (`81701`,
exit 0). This current artifact has 1,931 files, 19 app directories, 16 canonical
`preloadedApps`, 10 preserved metadata documents and 465 compiled templates.
Its digest is `6cb494731de21b2d49b08856a7187825b3ce9a5330a01e765e011edd4c0de4cf`.
These figures describe the new artifact, not a rewrite of the older receipts.

Browser session `4914` exited 0 against these exact bytes, in an isolated network
namespace with every request intercepted. Actual unauthenticated boot, canonical
preloads and compiled ACDC templates passed. After boot, a clearly labelled
synthetic account fixture exercised mandatory explicit queue selection, a fresh
runtime probe before login, exactly one runtime-only POST, pending acknowledgement
and subsequent membership confirmation. A confirmed membership with paused agent
status did not overwrite the separate global-ready display. No real credentials,
backend requests, roster writes, authentication or publication were involved.
There were zero console errors, page errors, rejected routes or failed requests.
The external Google Fonts stylesheet was mocked empty; local assets were exact.

Two prior browser runs failed fixture expectations: the framework serializes a
missing synthetic auth token as the literal `undefined` header, and CSS renders
raw `ready` text as `READY`. The corrected fixture accepts that literal header
only on its exact synthetic API routes and checks both raw and visible status.
Both failed receipts remain retained; no application error was suppressed.

Final browser receipt under that private stage:
`browser-smoke.qRNbEh/receipt.json`, SHA-256
`6a8a63024639e8a19c6dbc0aa96ab13d55e7014aa20e598c2fc1d8507e5db62f`.
Root independently checked the receipt/hash and rendered confirmation screenshot.
The browser peaked at 289,480,704 bytes under the unchanged 384 MiB / zero-swap /
50% CPU cap, with no OOM events. Artifact bytes matched before and after.

This closes the current artifact's isolated boot and mocked queue-login browser
checks only. Authenticated live queue login, ringing, ownership/adoption, clean
server installation and the remaining production acceptance gates are still open.

### Reusable isolated artifact browser test

`scripts/test-monster-artifact-browser.cjs` is a separate, explicitly selected
frontend test. It serves a completed artifact directly from protected files
through browser request interception, in a network namespace isolated from the
host. It has no live-target, authentication, build, deployment, or download mode.
Do not substitute the live `test-monster-ui.cjs` or `test-monster-console.cjs`
scripts: those have different authorization and network boundaries.

Provide an existing compatible Node 20+ / Playwright / Chromium test workspace
(including Playwright's WebSocket-routing API). This does not change Monster's
Node 18 production build toolchain or lockfile. Review and pin these binaries and
the original successful build/readback evidence before running; the test does
not install tools or generate retrospective build receipts.

The only command-line option is `--inputs`, naming a root-owned private regular
JSON file. Replace the illustrative paths and `SHA256` values below with approved
absolute paths and 64-character lowercase SHA-256 values; this example is a
schema guide, not an executable input file:

```json
{
  "version": 1,
  "repo_root": "/absolute/kz5",
  "artifact_root": "/absolute/completed-build/dist",
  "build_receipt": {
    "path": "/absolute/evidence/original-build.json",
    "sha256": "SHA256",
    "format": "guarded-build-v1"
  },
  "readback_receipt": {
    "path": "/absolute/evidence/original-readback.json",
    "sha256": "SHA256",
    "format": "guarded-readback-v1"
  },
  "artifact_sha256": "SHA256",
  "toolchain": {
    "node_sha256": "SHA256",
    "playwright_root": "/absolute/browser-tools/node_modules/playwright",
    "playwright_package_sha256": "SHA256",
    "browser_executable": "/absolute/browser-tools/chrome-headless-shell",
    "browser_sha256": "SHA256"
  },
  "output_root": "/absolute/separate-browser-results",
  "require_acdc": true
}
```

`repo_root` must contain the running script. The existing `output_root` must be
protected and must not overlap the repository, artifact, input manifest,
evidence, or browser tools. Unsafe ancestors, symlinks, hardlinks, foreign or
writable paths, unexpected fields, and mismatched hashes are rejected. The test
creates a fresh private result directory; it never resets a previous result or
alters existing permissions. Invalid unsafe preflight inputs fail before output
creation; subsequent failures retain a failed or incomplete receipt.

The receipt format choices are deliberately narrow:

- `production-result` is the original object returned by
  `build-monster-production.cjs` (`production_build_completed` with its input
  hashes); `artifact-result` is the original successful object returned by
  `verify-monster-production-artifact.cjs`.
- `guarded-build-v1` and `guarded-readback-v1` accept the retained guarded wrapper
  records: correct terminal mode/status, successful child exits, stable original
  inputs/fingerprints and nonempty helper maps within each invocation, and
  readback linkage to the exact original build receipt.
  They are not arbitrary JSON pointers or a format for newly invented history.

The original compilation input hashes and any existing original fingerprint are
recorded under `original_compilation_evidence`, unchanged. Current test/helper,
input-file, toolchain, and evidence hashes are recorded separately under
`current_verification_inputs`. A direct build result without an aggregate
fingerprint remains without one; this test never writes an installer marker.
Both evidence formats must agree on the original source hash, and the supplied
artifact digest must match the readback and the actual tree before and after.
These bindings rely on caller-reviewed receipt hashes; they are not signatures
or proof against a malicious concurrent root writer.

Run the browser under the existing serialized resource guard and a separate
network namespace, with the executable Node file matching its supplied hash:

```sh
/absolute/kz5/scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 --runtime-sec 180 -- /usr/bin/unshare --net -- /absolute/browser-tools/node/bin/node --max-old-space-size=96 /absolute/kz5/scripts/test-monster-artifact-browser.cjs --inputs /absolute/evidence/browser-inputs.json
```

The script checks the exact 384 MiB / zero-swap / 50%-CPU / 128-task limits and
requires its network namespace to differ from PID 1. It starts no HTTP listener.
Every browser request is fulfilled from exact artifact bytes or an explicitly
named fixture; there is no network fallback. Service workers and WebSockets are
blocked. Unknown routes, missing assets, source-template/per-app preload
fallbacks, credentials, unexpected mutations, page errors, console errors and
failed requests fail the check, including events emitted during browser close.
Credential checks use Playwright's complete `allHeaders()` API, not its summary
headers API that can omit Cookie/security headers.

Actual unauthenticated core/auth boot must consume the main, templates,
configuration, build configuration and CSS files. The runtime preload set must
match the pinned readback and canonical `preloadedApps`. API origin/path prefix
and version come from the booted artifact, not a deployment hostname or fixed
version. HTTP(S), custom prefixes and same-origin API configuration are supported.
The initial supported configuration uses static branding
(`whitelabel.fetchFromApi:false`); custom pre-authentication APIs/remote branding
need a separately reviewed fixture contract and otherwise fail closed.

When ACDC is selected, the test removes the already-captured login DOM overlay
and inserts a clearly labelled synthetic account/agent host, without authenticating
or overriding application functions. Real compiled templates and DOM events
exercise explicit queue selection, a runtime-only probe, exactly one intercepted
Login POST, pending acknowledgement, and selected-queue membership confirmation.
The request gate itself rejects a first POST without an earlier exact selected
runtime GET; static, listing, legacy membership and preflight requests do not count.
Another configured queue remains unconfirmed. A mock paused runtime status does
not overwrite the separate global-ready display. The literal `undefined` auth
header produced by the unauthenticated framework is allowed only on those exact
synthetic API paths; no token, Authorization or Cookie is permitted. Real API
acceptance, membership, availability, ringing and call acceptance are not proven.
If ACDC is absent with `require_acdc:false`, the receipt says `not_selected`, not
passed; `require_acdc:true` rejects a build without ACDC before browser launch.
The external Google Fonts stylesheet is an explicit empty cosmetic fixture;
artifact-local assets remain unchanged.

The Node-only harness tests can run without Playwright or a browser:

```sh
node scripts/test-monster-artifact-browser-harness.cjs
```

They exercise input/evidence/path safety, original-versus-current provenance,
both receipt adapters, route and credential isolation, strict queue mutations,
version/selection handling, failure retention and guard refusal. They do not
replace running the actual browser against a pinned completed build.

The reusable source passed 23 Node-only harness groups, then its own isolated
browser run at 2026-09-06 12:19 UTC (session `64938`, exit 0), against the same
unchanged artifact described above. Its six checkpoints and request inventory
matched the earlier private run: 17 exact static requests, 10 intercepted
synthetic API requests including one Login POST, and one omitted font stylesheet;
zero console/page/route/request/WebSocket errors. The original compilation
fingerprint was retained separately from the new verifier/tool hashes. Final
browser receipt SHA-256:
`3f596f9fbe72572062c586618835143c4cb03c2b155622cf2b85fc35787484a4`.
The browser reached the unchanged 384 MiB cap with 67 memory-max events, no OOM,
and no kill. The preceding preflight failure is retained: the cached Node binary
had two hard links and was rejected before browser launch. A reviewed identical
standalone copy passed the existing single-link/hash checks; neither the original
tool cache nor the safety gate was changed. No live authentication, backend,
publication or new production build was involved.
