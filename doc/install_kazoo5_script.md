# Kazoo 5 modular installer for Rocky Linux 9

`scripts/install-kazoo5.sh` is the single deployment entry point for a
standalone component, a distributed Kazoo topology, or an all-in-one host. It
installs dependencies, writes configuration, installs a named systemd service,
enables and starts that service, and runs component-specific acceptance checks.
It is designed to be safely re-run.

This repository checkpoint is not a production-ready certification. Consult
[the current acceptance status](kazoo5_acceptance_status.md) before deploying:
some packaged source fixes have passed isolated tests but still await live
rollout/acceptance, and the additional announcement languages are unfinished.

The parent repository deliberately ignores downloaded upstream component
trees. Their modifications are shipped as installer-applied patches, including
complete `acdc-kazoo5-integration.patch`, `crossbar-kazoo5-integration.patch` and
`ecallmgr-kazoo5-integration.patch`; the installer applies one aggregate per
overlapping source stack so reinstallation does not fail on superseded hunks.
Feature patches alongside them are historical review/test provenance, not an
additional stack to apply manually. After developing in those component trees,
run `node scripts/refresh-kazoo-integration-patches.cjs --write`, then `--check`
and the relevant tests before committing the parent repository. This makes the
changes available from a fresh clone instead of only on the current server.

After a successful installation, the script saves deployment inputs in
`/etc/kazoo/deployment.env`, owned by root with mode `0600`. This includes
remote endpoints and their credentials. Explicit environment variables and
command-line options override saved values. The file contains base64-encoded
values, not shell code; do not source it. Base64 is not encryption: protect
this file and keep it out of version control. `KAZOO_DEPLOYMENT_CONFIG` selects
a different state file. Verification and dry runs do not rewrite it.

## Requirements

- Rocky Linux 9 using systemd. Other RHEL-derived distributions are not yet
  covered by this installer's repository and live-service tests.
- Root privileges and outbound HTTPS access to the official package and source
  repositories.
- A stable hostname. Use an FQDN that resolves on every node in a distributed
  installation; Erlang node names depend on it.
- UTC time with a synchronized clock.
- At least 10 GiB free while compiling an all-in-one test installation. The
  merged Rocky 9 guide recommends roughly 120 GiB for a production all-in-one
  host so there is room for database and log growth; that is capacity planning,
  not the installer's temporary build footprint.

The compiler sources are cached under `/usr/local/src/kazoo5-installer`. They
can be removed after a successful installation and `--verify-only` run; the
installer downloads them again if a future rebuild is required.

## Commands

List the selectable modules:

```sh
./scripts/install-kazoo5.sh --list
```

Review the full resolved path without changing the host:

```sh
sudo ./scripts/install-kazoo5.sh --dry-run ALL
```

Install and test every component on one host:

```sh
sudo ./scripts/install-kazoo5.sh ALL
```

Install any exact subset:

```sh
sudo ./scripts/install-kazoo5.sh couchdb rabbitmq haproxy
sudo ./scripts/install-kazoo5.sh kazoo-apps ecallmgr
sudo ./scripts/install-kazoo5.sh freeswitch kamailio monster-ui
```

Validate services without changing the installation:

```sh
sudo ./scripts/install-kazoo5.sh --verify-only ALL
```

The canonical names are `couchdb`, `rabbitmq`, `haproxy`, `kazoo-apps`,
`ecallmgr`, `freeswitch`, `kamailio`, `monster-ui`, and `ALL`. The aliases
`apps`, `kazoo_apps`, `monster_ui`, and the requested `kamaialio` misspelling
are accepted.

## Installed versions

The defaults are the selected Kazoo 5 integration set. Native service checks
and API tests are distinct from answered SIP/RTP and capacity acceptance;
passing the former does not establish production readiness. Core, Crossbar, eCallMgr, ACDC,
media/configuration sources, and frontend apps use immutable commit hashes
inside the script; the remaining Kazoo applications follow the project's
source manifest. A fresh clone's ignored source trees are fetched before
patches and generated-source build steps run.

| Component | Installed default | Why |
| --- | --- | --- |
| Erlang/OTP | `26.2.5` from EPEL | Matches this tree's `make/erlang_version` (`26.2`) |
| CouchDB | `3.5.2.1-1.el9` | Current official EL9 package selected for this installer |
| RabbitMQ | `3.13.7` | Latest tested 3.13 line compatible with OTP 26 and Kazoo 5 |
| FreeSWITCH | `1.11.3` | Current selected upstream release; built with Kazoo `mod_kazoo` |
| FreeSWITCH config | Kazoo config release `5.5.1` commit | Uses the `kazoo-freeswitch` wrapper |
| Kamailio | `6.1.4` | Official Kamailio RPM plus official `kamailio-kazoo` module |
| Monster UI | source tag `5.5.13` | Upstream package metadata still displays `4.3.0`; this is separate from the Kazoo backend version |
| HTMLDOC | `1.9.23` | Pinned source build for Kazoo fax document conversion |
| ACDC | pinned `kazoo-community/kazoo-acdc` revision | Integrated, compiled, started; queue/agent APIs and 15 upstream unit tests checked |

The Kazoo backend is built from the Kazoo 5 source tree. Its development
build metadata currently reports `master.0`, not a numbered stable release.
FreeSWITCH 1.11.3 builds and passes the native service/link checks on Rocky 9
with the pinned Sofia-SIP, SpanDSP, `mod_kazoo`, and 2600Hz configuration.
The Sofia build includes Kazoo's split routing semantics: `sip_proxy_uri`
selects the registrar proxy, while a distinct `sip_route_uri` remains an
optional initial SIP route. Without that compatibility, current eCallMgr
location dialstrings try to resolve the opaque account ID as a DNS domain and
registered-device calls fail before an INVITE reaches Kamailio.
Answered-call compatibility and capacity must also pass the SIP/RTP suite.
Moving an individual package to a newer major line
without moving the whole compatibility set is not considered an upgrade.

## Services and acceptance checks

| Selection | Enabled service | Installer acceptance gate |
| --- | --- | --- |
| `couchdb` | `couchdb.service` | exact RPM version and authenticated `/_up` response |
| `rabbitmq` | `rabbitmq-server.service` | exact RabbitMQ/Erlang versions, broker ping, listener, Kazoo user, consistent-hash plugin |
| `haproxy` | `haproxy.service` | config parser plus both CouchDB proxy ports |
| `kazoo-apps` | `kazoo-apps.service` | Erlang apps, Crossbar JSON API, ACDC DB/app, master account, SUP |
| `ecallmgr` | `kazoo-ecallmgr.service` | Erlang app and configured FreeSWITCH nodes |
| `freeswitch` | `kazoo-freeswitch.service` | version, CLI, Sofia SIP profile, process stability, `mod_kazoo`, SpanDSP, ecallmgr link when local |
| `kamailio` | `kazoo-kamailio.service` | config, SIP OPTIONS, RPC, established AMQP transport, queue when RabbitMQ is local, SQLite, dispatcher, SBC ACL |
| `monster-ui` | `nginx.service` | production files, app metadata/catalog, API JSON, HTTP or verified HTTPS response |

The stock `freeswitch.service` and `kamailio.service` units are disabled when
their Kazoo wrappers are installed.

Kamailio 6.1.4's stock `kamailio-kazoo` module does not export the per-zone
`amqpc` XAVP used by the newer registrar configuration's early availability
guard. The installer explicitly disables that unsupported guard; otherwise it
drops every REGISTER even while AMQP is connected. This does not disable SIP
authentication: REGISTER still uses `kazoo_async_query`, and AMQP send errors
or timeouts fail closed. Verification checks the live setting, established
Kamailio-to-RabbitMQ transport, and the broker consumer queue when RabbitMQ is
local.

That config revision also names the stock module's optional AMQP-header
argument `REGISTRAR_AMQP_FLAGS` and defaults it to numeric `2048`. The
installer removes that optional final argument from registrar publish and
asynchronous-query calls. Supplying even an empty string invokes the stock
module's `key=value;...` header parser, so omission is required to prevent
malformed-header errors on registration events.

Kazoo 5's dialplan fetch definitions use a multi-prefix channel-variable
serializer. The pinned upstream `mod_kazoo` source does not implement that
field type. It also skips live-channel enrichment when a dialplan fetch
already contains `Unique-ID`, which is the normal inbound-call case. The
installer applies both compatibility patches before building the module.
Together they preserve `Account-ID`, endpoint, and authorization channel
variables in FreeSWITCH route requests; without them authenticated calls
time out with `NO_ROUTE_DESTINATION` because the account database is
undefined. The same compatibility layer implements Kazoo 5's multi-prefix
and contains event-filter comparisons, which the public module otherwise
silently treats as different comparison types.

The public pinned module also does not provide the private `kz_deliver_event`
or `kz_intercept` dialplan applications selected by newer eCallMgr source.
The installer configures eCallMgr to use FreeSWITCH's supported built-in
`event` and `intercept` applications—the behavior used before those
optimizations were added—and verifies both exact nested settings after startup.
The same public module is missing the `kz_originate` and
`kz_originate_cancel` APIs required by the pinned eCallMgr. A build-time
compatibility patch supplies those APIs, preserves quoted channel-variable
values instead of passing them through FreeSWITCH's destructive first parser,
and supports cancellation by the Kazoo request UUID. Installer verification
requires both APIs to be registered.

Callback recovery also uses the scoped `kz_originate_reconcile` API and its
eCallMgr AMQP request/response adapter. Status and cancellation require the
originate UUID, original request ID, and caller call ID to match; every eCallMgr
node reports its own result and contradictory, duplicate, incomplete, or timed
out evidence remains unknown. The FreeSWITCH table is intentionally in-memory:
after a FreeSWITCH restart an older originate is unknown, which fails closed and
does not authorize a replacement call. This hook narrows the uncertainty window
but is not a claim of exactly-once calling across media-server restarts.

Kazoo 5 also adds a boolean synchronization field to the `command` and
`commands` C-node requests. The public module predates that wire format. Its
compatibility patch accepts both the legacy three-element and current
four-element tuples, validates the boolean, and honors `true` by executing the
event immediately; `false` retains the private-event queue behavior. A
separate reply-completeness guard returns `badarg` instead of ever emitting a
truncated Erlang distribution term when a request handler rejects input.

Event streams use four-byte length framing on both eCallMgr and each managed
FreeSWITCH node. Two-byte framing cannot represent events larger than 65,535
bytes and can corrupt or drop the larger channel events produced by real call
flows. The installer persists `ecallmgr.tcp_packet_type = 4`, restarts eCallMgr
once only when that value changes so its sockets inherit the setting, and
verifies the negotiated value through every configured FreeSWITCH node.

Audio-fork commands remain optional and unsupported by this public build:
`kz_audio_fork_start`, `kz_audio_fork_stop`, `kz_audio_fork_pause`, and
`kz_audio_fork_resume` require a separately licensed or explicitly selected
module. The installer does not silently substitute an unrelated media module.
This does not affect core SIP, ACDC queue, bridge, or transfer operation.

## Distributed example

CouchDB's own cluster cookie is separate from the Kazoo/FreeSWITCH cookie.
The installer preserves the existing CouchDB cookie in
`/opt/couchdb/.erlang.cookie` (owner `couchdb`, mode `0400`) and removes its
`-setcookie` argument so local process listings cannot disclose it. It also
restricts `vm.args` to mode `0640`. Conflicting or ambiguous existing cookie
sources fail closed without replacing either credential. Use
`sudo kazoo-couchdb-shell` for a protected-file authenticated remote shell;
the upstream `remsh` helper expects an explicit cookie argument.
CouchDB HTTP verification credentials are sent on curl's standard input,
not in its process arguments. These controls do not replace network isolation
or encryption between distributed nodes.

Bindings default to loopback for safety. Set a private interface address and
strong credentials when a standalone CouchDB or RabbitMQ host must accept
other Kazoo nodes.

An all-in-one loopback deployment generates a 96-character Erlang cookie once
and preserves it in `/etc/kazoo/.erlang.cookie` with mode `0600`. For a
distributed deployment, generate the cluster cookie once, securely provision
that same root-only file on every applications, eCallMgr, and FreeSWITCH host,
then run the installer. Independent servers intentionally do not invent their
own cookies because they would be unable to authenticate to one another. An
explicit `KAZOO_COOKIE` is also accepted, but a protected file avoids shell
history and process-argument exposure.

```sh
# db1.example.net (10.20.0.11)
sudo KAZOO_COUCHDB_BIND=10.20.0.11 \
  KAZOO_COUCHDB_USER=kazoo \
  KAZOO_COUCHDB_PASSWORD='replace-with-a-strong-secret' \
  ./scripts/install-kazoo5.sh couchdb

# mq1.example.net (10.20.0.12)
sudo KAZOO_RABBITMQ_BIND=10.20.0.12 \
  KAZOO_RABBITMQ_USER=kazoo \
  KAZOO_RABBITMQ_PASSWORD='replace-with-a-strong-secret' \
  ./scripts/install-kazoo5.sh rabbitmq

# apps1.example.net
sudo KAZOO_COUCHDB_HOST=db1.example.net \
  KAZOO_COUCHDB_USER=kazoo \
  KAZOO_COUCHDB_PASSWORD='replace-with-a-strong-secret' \
  KAZOO_AMQP_HOST=mq1.example.net \
  KAZOO_RABBITMQ_USER=kazoo \
  KAZOO_RABBITMQ_PASSWORD='replace-with-a-strong-secret' \
  KAZOO_ERLANG_DIST_IP=10.20.0.13 \
  ./scripts/install-kazoo5.sh kazoo-apps ecallmgr

# media1.example.net
sudo KAZOO_AMQP_HOST=mq1.example.net \
  KAZOO_RABBITMQ_USER=kazoo \
  KAZOO_RABBITMQ_PASSWORD='replace-with-a-strong-secret' \
  KAZOO_ERLANG_DIST_IP=10.20.0.15 \
  ./scripts/install-kazoo5.sh freeswitch

# On apps1, register and require the new media node.
sudo KAZOO_COUCHDB_HOST=db1.example.net \
  KAZOO_COUCHDB_USER=kazoo \
  KAZOO_COUCHDB_PASSWORD='replace-with-a-strong-secret' \
  KAZOO_AMQP_HOST=mq1.example.net \
  KAZOO_RABBITMQ_USER=kazoo \
  KAZOO_RABBITMQ_PASSWORD='replace-with-a-strong-secret' \
  KAZOO_FREESWITCH_NODES='freeswitch@media1.example.net,freeswitch@media2.example.net' \
  ./scripts/install-kazoo5.sh ecallmgr

# Back on media1, enforce the end-to-end connection gate.
sudo KAZOO_AMQP_HOST=mq1.example.net \
  KAZOO_RABBITMQ_PASSWORD='replace-with-a-strong-secret' \
  KAZOO_ERLANG_DIST_IP=10.20.0.15 \
  KAZOO_REQUIRE_MEDIA_CONNECTION=true \
  ./scripts/install-kazoo5.sh --verify-only freeswitch

# sip1.example.net
sudo KAZOO_PUBLIC_IP=10.20.0.14 \
  KAZOO_AMQP_HOST=mq1.example.net \
  KAZOO_RABBITMQ_PASSWORD='replace-with-a-strong-secret' \
  ./scripts/install-kazoo5.sh kamailio

# ui1.example.net
sudo KAZOO_API_URL=http://apps1.example.net:8000/v2/ \
  ./scripts/install-kazoo5.sh monster-ui
```

With `KAZOO_REQUIRE_MEDIA_CONNECTION=auto` (the default), a FreeSWITCH-only
host validates its native media service but delegates both the remote eCallMgr
link and the Sofia SIP profile that eCallMgr loads dynamically. When a link is
present, or when a local eCallMgr is installed, both the link and Sofia profile
are checked strictly. Set `KAZOO_REQUIRE_MEDIA_CONNECTION=true` for the final
distributed end-to-end gate.
Likewise, a standalone Kamailio or Monster UI node delegates cluster-wide ACL
or app-catalog changes when no local Kazoo applications node is available.

Open only the needed private-network ports between roles: CouchDB `5984`,
RabbitMQ `5672`, Crossbar `8000`, Erlang distribution `4369` plus the configured
distribution range, FreeSWITCH's `mod_kazoo` C-node listener `8031`, and SIP/RTP
ports required by your deployment. FreeSWITCH's event socket `8021` remains
loopback-only and does not need to be exposed. The installer does not disable
SELinux or the firewall.

`KAZOO_AMQP_URI` can configure Kazoo applications and Kamailio directly.
FreeSWITCH's Kazoo wrapper accepts only the split `KAZOO_AMQP_HOST`,
`KAZOO_AMQP_PORT`, `KAZOO_RABBITMQ_USER`, `KAZOO_RABBITMQ_PASSWORD`, and
`KAZOO_RABBITMQ_VHOST` settings. When FreeSWITCH is selected, the installer
rejects a URI that differs from those split settings instead of silently using
a different broker.

## SUP and ACDC

Selecting `kazoo-apps` installs `/usr/local/bin/sup` and Bash completion. The
wrapper reads the protected installed Kazoo configuration directly without
putting the cookie in a world-readable script, environment, or process
arguments. Commands such as these are then available:

```sh
sup kazoo_maintenance syslog_level debug
sup kapps_controller running_apps
sup kapps_config get kapps_controller kapps
sup -n ecallmgr ecallmgr_maintenance list_fs_nodes
```

ACDC is part of the default `KAZOO_APPS_LIST`. The installer fetches its pinned
community repository, applies the OTP 26 compatibility fix, compiles it with
Kazoo, persists it in `kapps_controller.kapps`, and verifies both the running
application and the `acdc` CouchDB database.

The staged callback integration adds durable queue-position metadata, a
correlated caller pause/register/resume/abandon menu, bounded returned-caller
DTMF-1 confirmation, account-owned authority/caller-ID checks, normal
stepswitch routing, callback visibility/cancellation APIs, and fail-closed
multi-node recovery. It defaults off. The isolated suites and production build
pass, but the aggregate runtime has not yet passed the complete live callback
and restart-recovery gates, so this documentation does not mark it production
validated.

When a queue has a top-level `announce` media ID or URI, ACDC now interrupts
the caller's hold media, plays that announcement once, and waits asynchronously
for its terminal call-control event before offering the call to an agent. The
queue FSM remains responsive to caller hangup and maximum-wait expiry during
playback, continues safely after a playback error or bounded timeout, preserves
the incoming call's language, and does not replay the announcement when an
agent attempt is retried.

The default Monster UI bundle also includes the project-owned **Call Center**
app from `monster-ui/acdc`. Its local source is content-hashed so edits force a
new production build. It is registered in the administrator app catalog and
supports child-account masquerading, queue CRUD, multi-agent rosters,
login/logout/pause/resume, current queue/agent statistics, and up to 20 recent
call records from the last 24 hours. Queue edits use PATCH to preserve fields
not exposed by the form. Partial roster failures are visible and retries do
not create duplicate queues. `MONSTER_UI_APPS_LIST` can explicitly deselect it.
The installer writes the selected API URL into both UI configuration and ACDC
metadata; it does not leave browser requests pointed at localhost.

Compatibility patches also reject malformed authentication tokens without
internal exceptions, preserve legacy-token fallback, and avoid logging raw
malformed tokens. Run `scripts/test-crossbar-auth.sh` for the 16 isolated
authentication regression tests, including invalid signatures/headers and
successful-claims propagation.

If no Kazoo master account exists, `kazoo-apps` creates one. Generated initial
credentials are stored only in `/etc/kazoo/installer-secrets.env` with mode
`0600`; the installer never prints the password. Account creation is sent as a
base64-safe Erlang expression over `erl_call` standard input, with the protected
Kazoo runtime cookie, so names and passwords never enter child-process argument
vectors. Reruns validate that this is a root-owned regular file and restore the
stored realm, administrator username, and password for the authenticated ACDC
acceptance check.

## Important environment settings

| Setting | Default |
| --- | --- |
| `KAZOO_COUCHDB_HOST` / `KAZOO_COUCHDB_PORT` | `127.0.0.1` / `5984` |
| `KAZOO_COUCHDB_BIND` | `127.0.0.1` |
| `KAZOO_AMQP_HOST` / `KAZOO_AMQP_PORT` | `127.0.0.1` / `5672` |
| `KAZOO_RABBITMQ_BIND` | `127.0.0.1` |
| `KAZOO_HAPROXY_BIND` | `127.0.0.1` |
| `KAZOO_PUBLIC_IP` | primary IPv4 route source address |
| `KAZOO_ERLANG_DIST_IP` | `127.0.0.1`; set the node's private IP for distributed ecallmgr |
| `KAZOO_API_URL` | `http://<primary-ip>:8000/v2/` |
| `KAZOO_FREESWITCH_NODES` | none; comma-separated nodes when remote |
| `KAZOO_REQUIRE_MEDIA_CONNECTION` | `auto` |
| `KAZOO_DEPLOYMENT_CONFIG` | `/etc/kazoo/deployment.env`; root-owned `0600` saved settings used by safe reruns |
| `KAZOO_MAKE_JOBS` | detected CPUs, capped at 2 to limit memory/disk pressure |
| `KAZOO_MIN_BUILD_FREE_MB` | `4096` hard preflight floor for build-heavy selections |
| `MONSTER_UI_REGISTER_APPS` | `auto` |
| `KAZOO_WEBSOCKET_UPSTREAM` | `http://127.0.0.1:5555/websocket`; set the remote Blackhole endpoint on a standalone UI server |
| `MONSTER_UI_WEBSOCKET_URL` | `auto`; preserve an explicit endpoint or use the browser origin's `/websocket` proxy |
| `MONSTER_UI_REMOTE_BRANDING` | `auto`; preserve an explicit setting, otherwise use local branding without whitelabel API probes |
| `MONSTER_UI_BRAINTREE` | `auto`; preserve an explicit setting, otherwise enable only when a Braintree API endpoint is configured |

Run `./scripts/install-kazoo5.sh --help` for the complete interface. Version
and source-ref variables are overrides for controlled testing; change them as a
compatibility set and re-run all acceptance checks.

### Optional browser integrations

The installer preserves existing static public source `src/js/config.js` settings,
including custom integrations, instead of resetting them to upstream defaults.
Keep persistent custom settings in that source file under the Monster UI build
directory; edits made only to generated live `js/config.js` are not imported
automatically and will be replaced by a rebuild. Executable
configuration hooks that cannot be preserved as static settings fail explicitly.
The generated same-origin socket URL chooses `ws` on HTTP and `wss` on HTTPS;
nginx forwards the exact `/websocket` path to Blackhole. A standalone UI host
must set `KAZOO_WEBSOCKET_UPSTREAM` to its reachable Kazoo apps server. HTTPS
upstreams use certificate verification. `MONSTER_UI_WEBSOCKET_URL` also accepts
`same-origin`, `disabled`, or an explicit `ws://`/`wss://` endpoint. Malformed,
missing, or mixed-content socket configuration does not start a retry loop.

Remote branding and Braintree can each be explicitly enabled or disabled with
`true` or `false`. Local branding uses the bundled/custom local logo and favicon;
a missing remote profile no longer causes additional logo/icon API failures.
Disabled Braintree does not query customer/payment endpoints, but manual billing
contact editing remains available. No payment processor is provisioned.

Google Maps loads only with an explicitly configured `api.googleMaps.apiKey`
and uses the asynchronous loader. Optional E911 ZIP autofill additionally needs
`api.googleMaps.geocoding: true`; manual emergency-address forms remain available
without Maps. Webphone startup requires a valid `api.socketWebphone` endpoint.
The installer does not manufacture third-party keys or pretend an absent
webphone/payment backend is operational.

When ACDC is selected, an absent `apps/acdc/language-capabilities.json` receives
an explicit negative `backend_mode: "legacy"` state. This avoids a missing-file
request without claiming the staged multilingual backend is ready. English
still requires the complete legacy media catalog; other languages remain
disabled until independently verified. Existing valid readiness artifacts are
preserved; unsafe or malformed artifacts fail installation rather than being
overwritten. See [language packs](acdc_language_packs.md).

Focused browser/configuration regressions:

```sh
node scripts/test-monster-runtime-config.cjs
node scripts/test-monster-websocket-config.cjs
node scripts/test-monster-optional-integrations.cjs
node scripts/test-monster-branding-billing.cjs
sudo node scripts/test-acdc-language-capability-state.cjs
```

`scripts/test-monster-console.cjs` is a deployment-specific Playwright gate for
this server's protected MASTER account. It tests login, billing, an unsaved
queue form, unsaved Callflows drag/drop, and authenticated WebSocket events.
It permits authentication but blocks other API writes and unconfigured external
integrations; it is not a generic fresh-host smoke test or call-audio test.

## Tests

The fast, non-mutating installer tests cover syntax, aliases, modular
dependency selection, multi-media-node parsing, the `ALL` path, and invalid
input:

```sh
./scripts/test-install-kazoo5.sh
./scripts/test-install-kazoo5-modular.sh
sudo ./scripts/test-install-kazoo5-deployment.sh
./scripts/test-install-kazoo5-cookie.sh
./scripts/test-install-kazoo5-couchdb-security.sh
./scripts/test-install-kazoo5-bootstrap.sh
./scripts/test-install-kazoo5-production-beams.sh
./scripts/test-acdc-call-wait.sh
./scripts/test-acdc-callback-store.sh
./scripts/test-acdc-callback-menu.sh
./scripts/test-acdc-callback-menu-integration.sh
./scripts/test-install-kazoo5-logging.sh
./scripts/test-install-kazoo5-prompts.sh
./scripts/test-kazoo-log-redaction.sh
./scripts/test-kazoo-stacktrace-redaction.sh
./scripts/test-ecallmgr-cnode.sh
./scripts/test-acdc-unit.sh
```

Run Erlang tests through the isolated scripts above. Do not run `make eunit`
or `make compile-test` in a source tree used by running services: those targets
can overwrite production modules and dependencies with test-only behavior.
The installer inspects BEAM compile definitions before and after its production
build, removes only identified generated test artifacts within the project,
and refuses an unreadable/corrupt module or a failed scan. The regression suite
also checks valued `TEST` macros and rejects paths escaping the project.

Callback storage tests are foundation tests, not proof of a working callback
telephone workflow. Live queue acknowledgement, preserved ordering across a
restart, outbound routing, caller DTMF and agent audio remain separate gates.

Stacktrace logging retains module/function/arity and line locations, but does
not print function argument values. Endpoint exception frames can contain whole
SIP device and call documents; those are not safe diagnostic payloads. This
protection does not redact arbitrary caller-supplied log messages or certify
that every log source is free of sensitive data.

The callback telephone fixture can be prepared without traffic, then run only
in a coordinated maintenance window after the aggregate ACDC runtime is active:

```sh
sudo ./scripts/test-acdc-callback-calls.sh --prepare-only
sudo ./scripts/test-acdc-callback-calls.sh --live
```

The live script temporarily assigns only `+12025550100` and `+12025550101`,
creates an exact-prefix account-local resource to `127.0.0.30:16060`, and
restores the saved queue document during cleanup. One caller registers a
same-number callback with DTMF 6/1; a later sentinel stays queued while the
returned local-carrier leg confirms with DTMF 1 and bridges agent 1002. The
simulated carrier is loopback-only and the numbers are reserved fictional-use
numbers, so no PSTN call can leave the host.

The live lifecycle test creates a uniquely named temporary child account and
queue, verifies its ACDC worker and APIs, then deletes those exact test fixtures:

```sh
sudo ./scripts/test-acdc-live.sh
# Storage-only callback persistence/race probe in that temporary account:
sudo KAZOO_TEST_CALLBACK_STORE=true ./scripts/test-acdc-live.sh
# After HTTPS is configured, test the same lifecycle through nginx:
sudo KAZOO_TEST_API_URL=https://kz5.talkchief.io/v2/ ./scripts/test-acdc-live.sh
```

The live acceptance suite is built into the deployment command:

```sh
sudo ./scripts/install-kazoo5.sh --verify-only ALL
```

ACDC's Crossbar modules (`cb_queues`, `cb_agents`, `cb_acdc_call_stats`) and
Monster UI's `cb_external_numbers` dependency are started and added to
Crossbar's persisted autoload list. When master credentials
are available, acceptance also logs in through Crossbar and reads the queue
and agent collections. The unit suite runs in an isolated temporary directory
and does not replace production Erlang beams. These checks do not substitute
for a real SIP endpoint/trunk call acceptance test for a production deployment.

`scripts/test-monster-ui.cjs` additionally checks browser sign-in and authenticated
app loading, failing on JavaScript errors or unexpected HTTP failures. It uses
Playwright with Node.js 20 or newer in a separate test workspace; it does not
change Monster UI's pinned Node.js 18 build toolchain. Set
`KAZOO_PLAYWRIGHT_MODULE` to that workspace's Playwright module path and
`KAZOO_TEST_UI_URL=https://kz5.talkchief.io/` to test the public HTTPS site.
The script reads the protected master credentials file without logging them.

For internal SIP and ACDC load acceptance, provision a dedicated tenant without
touching existing customer users:

```sh
sudo ./scripts/test-kazoo-call-provision.sh
sudo ./scripts/test-kazoo-call-provision.sh --agent-status logout --agent-range 1:30
sudo ./scripts/test-kazoo-call-provision.sh --agent-status login --agent-range 1:5
sudo ./scripts/test-kazoo-call-provision.sh --agent-status verify --agent-range 1:5
```

The default fixture has caller extension `1001`, 30 distinct agent
users/devices on `1002` through `1031`, and queue `2000`. The queue callflow
uses `acdc_member`; each endpoint has its own SIP credential and user callflow.
Generated IDs and credentials are reusable base64 values in the root-owned
`0600` file `/etc/kazoo/acceptance-secrets.env`. The provisioner never prints
those secrets and does not configure PSTN routes or email. Agent count can be
set from 1 through 30 when creating or expanding the fixture.

Validate the protected fixture and SIPp scenarios without sending traffic,
then run the single-call functional gate before the staged capacity gate:

```sh
sudo ./scripts/test-kazoo-calls.sh --prepare-only --no-install-deps
sudo ./scripts/test-kazoo-calls.sh --live --functional --no-install-deps
sudo ./scripts/test-kazoo-calls.sh --live --stress --no-install-deps
```

The functional gate keeps its agent logged out until the caller is observed in
queue, then registers the endpoint, starts its answering SIP user agent, and
logs the agent in. The stress gate requires answered-call and bidirectional-RTP
success at 1, 5, 10, 20, and 30 simultaneous calls; the 30-call stage is held
for a continuously verified three minutes and also verifies five excess queued
callers. Calls are established at two per second: it measures simultaneous
answered calls, not new calls per second, and does not use PSTN. On the
reference 2-vCPU host, a separate 35-call one-second burst produced dialplan
route-response timeouts after 2.5 seconds (20 calls in one second passed); that
measured burst limit must not be reported as a 35-CPS capability.

## HTTPS for Monster UI and the API

Supply a certificate covering the public hostname, its matching unencrypted
PEM private key, and the issuer's intermediate bundle (unless the certificate
file already contains the full chain). The hostname must be a valid DNS name
with at least two labels; IP-address certificates are not supported by this
mode. For this host:

```sh
sudo ./scripts/install-kazoo5.sh monster-ui \
  --hostname kz5.talkchief.io \
  --tls-cert '/root/ssl/SSL Certs_STAR_talkchief_io.crt' \
  --tls-chain '/root/ssl/SSL Certs_STAR_talkchief_io_bundle.crt' \
  --tls-key /root/ssl/talkchief.io.key \
  --api-url https://kz5.talkchief.io/v2/ \
  --api-upstream http://127.0.0.1:8000/v2/
```

Replace the key path with the actual matching key. A certificate or chain alone
cannot enable HTTPS. The installer checks hostname coverage, expiration, trust,
and key matching before changing nginx. It stores the key as root-only `0600`
under `/etc/nginx/kazoo-tls`, enables TLS 1.2/1.3 on port 443, redirects HTTP,
and proxies `/v2/` to Crossbar. Monster UI uses the HTTPS API URL to avoid mixed
content. For a separate UI host, set `--api-upstream` to the applications
server's private Crossbar URL. DNS must point to the UI host and TCP 443 must
be reachable. Supply renewed certificate files and rerun `monster-ui` to renew;
external certificate issuance and renewal are not automated by this mode.

## Diagnostic retention

Selecting `kazoo-apps` automatically imports missing official English-US system
prompts plus the generated English-US callback prompts into CouchDB and verifies
that every required document has audio. The current English-US import is 191
media documents: 175 official prompts and 16 deterministic callback prompts.
Existing prompt attachments are preserved. Selecting `freeswitch` also installs
the pinned English-US local speech and hold-music files without overwriting existing files.
`KAZOO_SOUNDS_REF` pins the shared `2600hz/kazoo-sounds` checkout. This default
does not install every language; additional languages require their own import.

The applications and eCallMgr nodes use separate Lager roots under
`/var/log/kazoo/kazoo_apps` and `/var/log/kazoo/ecallmgr`. Normal files are in
each root's `log/` subdirectory, retaining five 10-MiB archives per stream.
Separate roots prevent two Erlang VMs from rotating the same file. Node
directories are `kazoo:kazoo` mode `0750`; new file diagnostics are private.
Each node keeps its most recent `erl_crash.dump` in its own root, capped at
100 MiB and ten seconds of dump generation. Preserve that file separately
before another crash if it is needed for investigation.

FreeSWITCH uses native 10-MiB size rotation with five archives per profile.
The historically named `kazoo-debug.log` defaults to `info` and higher; the
error stream includes warnings and higher. `/var/log/freeswitch` is restricted
to `freeswitch:freeswitch` mode `0750`, and new service files use a `0027`
umask. Previously collected debug logs may contain sensitive call information
and must not be published. Existing diagnostic files are not deleted during
this migration. Test-run captures are separately protected under
`/var/log/kazoo-acceptance`; retain only those needed for investigation.
