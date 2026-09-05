# Installer verification checkpoint — 2026-09-05 22:32 UTC

Acceptance is incomplete. The actual, unwrapped command
`bash scripts/install-kazoo5.sh --verify-only all` ran for **52.675 seconds** and
exited **1**. Its only remaining failure was the Monster UI build fingerprint:
the deployed bundle does not match the requested source/app fingerprint. Do not
overwrite its marker or omit that check to obtain a passing result.

## Current live evidence

| Component/check | Recorded result |
| --- | --- |
| EPMD | Expected loopback listener; no wildcard listener |
| CouchDB | Enabled/active, pinned 3.5.2.1-1.el9, authenticated health check passed |
| RabbitMQ | Enabled/active, 3.13.7 with Erlang 26.2.5; ping, listener, authentication and consistent-hash plugin passed |
| HAProxy | Enabled/active; configuration and both CouchDB proxy listeners passed |
| Kazoo applications | Production-BEAM checks, expected running applications, isolated logs, SUP and authenticated Crossbar queue/agent/external-number APIs passed |
| Prompt media | 192 existing English prompt documents had attachments; this includes 17 locally generated legacy extras, not 192 pinned official recordings. All 165 immutable Gemini assets and both resolver caches' 330 mappings verified |
| eCallMgr | Enabled/active, expected applications, event/intercept support, callback cleanup permission, four-byte event framing and FreeSWITCH link passed |
| FreeSWITCH | Enabled/active; 719 speech/hold-music files, module/native API inventory, Sofia profile, stability and eCallMgr connection passed |
| Kamailio | Enabled/active; configuration, SQLite, SIP OPTIONS, AMQP, dispatcher, RPC, module and SBC ACL checks passed; no matching integration errors in its checked activation window |
| Monster UI | nginx enabled/active, but full verifier failed the bundle fingerprint |
| Separate portal diagnostics | HTTP content, same-origin `/v2/` JSON, actual language-capability route and the existing ten-app catalog passed; these do not waive the fingerprint failure |
| Public HTTPS | Connection refused on port 443; no TLS listener. Saved installer inputs have no public hostname/key configured |

The protected runtime language manifest exists, but every EN/AR/HE/ES/FR full-pack
`ready`, `position`, `wait_time`, `callback` and `native_speaker_review` flag is
false. Immutable fixed-media/cache proof and the earlier successful English
Gemini callback are separate evidence, not complete multilingual readiness.

## Bug found and bounded repair

The original live verification hung in RabbitMQ password authentication. The
installed 3.13.7 shell wrapper accepts password stdin only with exactly the
operation and username; adding `-q` disables input. Offline doubles had accepted
the wrong three-argument shape. The helper now omits `-q`, retains protected stdin
and output suppression, and uses a 30-second timeout with a five-second kill
grace. Actual authentication passed without changing any RabbitMQ user/password.

Verification was also made non-repairing: it reads only an already configured
master ID, queries the existing catalog view directly, checks already-loaded SUP
modules, opens SQLite read-only, and lists RabbitMQ plugins as the service user
through the underlying CLI. The distribution's root plugin wrapper otherwise
adjusts cookie ownership/permissions even for `list`. Installation/bootstrap
paths keep their explicitly mutating behavior.

Commit `8167379` contains this source/test checkpoint. All 32 password scenarios
passed, including exact argv, secret boundaries, failure propagation and actual
hung-double termination. The focused read-only suite passed configured-ID and
catalog negative cases and SQLite no-create checks. All nine existing installer
shell suites passed again after the repair. Bash syntax and ShellCheck
warning/error-level checks passed; the earlier full-level lint audit retained
two informational SC2015 findings rather than reporting an entirely clean lint.

## Receipts and limits

Detailed server-local receipts/logs are root-protected and are not committed:

- `/tmp/kazoo-live-readonly-audit.ThcLmj/receipt.json`: original failed all-module
  run and serial component results; captured service PIDs/restart properties and
  selected configuration-content hashes remained unchanged.
- `/tmp/kazoo-live-readonly-audit.ThcLmj/postfix.json`: unwrapped post-fix command
  at 22:31:41–22:32:36 UTC, separate portal/catalog success and HTTPS failure.
- `/tmp/kazoo-live-readonly-audit.ThcLmj/postfix-all.log`: complete protected
  post-fix verifier output, including the retained Monster failure.
- `/tmp/kazoo-live-readonly-audit.ThcLmj/rabbitmq-stdin-corrected.log`: actual
  corrected authentication probe; no broker configuration change.
- `/tmp/kazoo-live-readonly-audit.ThcLmj/regression.json`: nine post-fix shell-suite
  results. Focused password traces: `/tmp/kazoo-rabbitmq-stdin.u2mmki/`.

Post-fix verification performed no application/service restart or live
configuration repair. Ordinary authentication and diagnostic SIP OPTIONS
were used; no calls, queue/roster/media changes, provider requests or installation
were performed. This is an existing single-host verification, not a clean Rocky9
installation, reboot test, separated-role deployment, traffic-safe upgrade,
capacity test, failover test or backup restore. Other crash/security/acceptance
gates remain in [the current status](kazoo5_acceptance_status.md).

## Source portability review — read-only, not deployment proof

The pinned-source install flow imports and verifies immutable voice media before
building applications. It needs configured CouchDB and Node.js at that point,
not a local FreeSWITCH service, provider key or running SUP node. The default
ACDC patch packages the Gemini mapper and its adjacent include; the staged
language and atomic layers remain separate. Resolver activation is local to the
configured applications node: a distributed upgrade still needs verification
on every node serving media requests.

Two concrete limitations remain. The current nested ACDC/eCallMgr worktrees
contain staged layers beyond the default baseline, so the installer's strict
default-patch forward/reverse checks reject them. That protects the staged work;
it is not permission to revert it or install the experimental layers. A reviewed
pinned production checkout is needed for installer reruns.

The reviewed apps-owned manifest initializer is now integrated in installer
source. It creates only an absent protected all-false manifest under the chosen
Kazoo configuration root before building apps, with an apps-only systemd path
environment. The backend preserves explicit paths and existing legacy artifacts;
only an absent legacy path falls back to the apps-owned path. Existing bytes are
not repaired or replaced, and GET no longer persists a filesystem default.
Eleven memory-only initializer groups and custom-root/order/unit-wiring checks
pass, along with all 31 editor/path backend tests. A real-filesystem test in
`acdc-capability-filesystem.YCNy1z` verified protected creation, byte/inode-preserving
reruns, corruption retention and symlink rejection with no target changes.
The 13-scenario Gemini installer suite now exercises the new capability step
before build/restart, including failure propagation, with an explicitly isolated
node name instead of inheriting the test shell's host setup. This source
integration has not changed live manifests or restarted units.

A further pinned-source audit found only 175 official top-level English WAVs in
the selected sounds revision; 17 ignored/generated legacy extras had entered
the old manifest through a broad file scan. The source repair now derives the
inventory from that exact Git tree and reads missing imports from pinned Git
blobs, while preserving existing attached documents. The editor validates the
actual 29 immutable English Gemini records plus 12 official compatibility
phrases and three official auxiliary prompts in one 44-document batch. It does
not invent canonical aliases or assert five-language readiness.

All 31 editor/path backend tests passed after integration. The focused official
inventory tests and explicit baseline UI regression tests pass, including every
missing prerequisite and invalid immutable-provenance cases. Default patch
forward/layered/reverse replay passes with experimental layers kept separate.
The generated OpenAPI additions validate but are not yet deployed. The mapper,
editor and matching ACDC UI must be deployed together in dependency order;
current live English selection still uses the previous deployed contract.
No fresh installation, remote dependency fetch or separated-node deployment was
performed for this checkpoint.

## Subsequent clean-build failure and memory incident

A later actual private Monster dependency installation did fetch registry
metadata. Its pinned upstream lock failed `npm ci`. A reviewed native-override
package amendment plus retained migrated lock still failed a second isolated
`npm ci --ignore-scripts` on a semver dependency mismatch. Both failures are
retained; neither source-only lock audit is a clean-install pass. Live UI and
its provenance marker are unchanged.

At 23:27 a host-global OOM also coincided with new AMQP failures in both Kazoo
nodes. Read [the incident record](host_memory_incident_20260905.md); earlier
component passes are not current enterprise certification. Heavy work is now
being serialized and resource-capped while recovery is checked.
