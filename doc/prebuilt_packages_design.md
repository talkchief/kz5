# Pre-built packages per module (design)

Status: **design, not implemented** (September 20, 2026). Requested by the owner: build
once, then deploy each stand-alone module from Jenkins to a server of choice without
compiling there.

## What is compiled on every host today

| Module | Today | Time on a 4-core host |
| --- | --- | --- |
| CouchDB, RabbitMQ, Kamailio, HAProxy | upstream RPMs + the installer's configuration | minutes |
| Kazoo (`kazoo-apps`, `ecallmgr`; ACDC is one of the applications inside `kazoo-apps`) | fetched at pinned refs, 134 patches applied, compiled, release assembled | 12-25 min |
| FreeSWITCH with `mod_kazoo`, sofia-sip, spandsp | cloned, 4 patches, compiled into `/usr/local/freeswitch` | 15-30 min |
| Monster UI with the ACDC app | npm build | 5-10 min |

So "pre-built" means three artifacts. Everything else is already a package.

## Principle

`scripts/install-kazoo5.sh` stays the only installation entry point and keeps doing all
configuration, secrets, units, migrations and verification. A package replaces **only the
compile step** of a role, and only when it provably is the same thing the host would
have built. Otherwise the installer builds from source exactly as today.

## Artifacts

Built by a Jenkins job `kz5-build-packages` on a Rocky Linux 9 x86_64 builder, per commit:

| Artifact | Content | Identity (must match on the target) |
| --- | --- | --- |
| `kz5-kazoo-<id>.tar.zst` | the built tree: `deps/`, `core/`, `applications/` with their `ebin/`, generated sources, `_rel/` | repository commit, the six pinned component refs, `scripts/patches/MANIFEST.sha256` digest, Erlang/OTP version, OS release, architecture |
| `kz5-freeswitch-<id>.tar.zst` | `/usr/local/freeswitch`, the sofia-sip and spandsp libraries it links, the installer's build marker | `freeswitch_build_fingerprint` (already in the installer), OS release, architecture |
| `kz5-monster-ui-<id>.tar.zst` | the built `dist/` with the ACDC app | `MONSTER_UI_REF`, apps list, repository commit of `monster-ui/acdc` |

Each artifact carries `manifest.json` (identity fields, file list with sha256) and the
build publishes `SHA256SUMS`. No secrets, no host settings and no configuration are
inside a package: cookies, passwords, addresses and certificates are always produced
on the target by the installer.

## Installer change

One new input, `KAZOO_PREBUILT_DIR` (default: none). In `build_kazoo`,
`build_kazoo_freeswitch` and the Monster UI build:

1. compute the identity the host would build;
2. if a package with exactly that identity is in `KAZOO_PREBUILT_DIR` and every file
   matches its sha256, unpack it and record `prebuilt: <artifact>` in the build snapshot;
3. otherwise build from source, as today (or, with `KAZOO_REQUIRE_PREBUILT=true`, refuse,
   so a production deploy can never silently compile for half an hour).

The existing gates stay in force on a pre-built tree: `verify_kazoo_production_beams`
(no TEST-compiled beams), the build snapshot, the patch manifest, the FreeSWITCH marker,
every role's verification and the stack health check.

## Jenkins

- `kz5-build-packages`: checkout, offline suites, build the three artifacts on the builder
  through the installer's own build functions (not a second build recipe), archive them
  with `SHA256SUMS`.
- `kz5-remote-install` gains `PACKAGES_BUILD` (which build's artifacts to use). The
  wrapper copies the matching artifacts to the target next to the source bundle and sets
  `KAZOO_PREBUILT_DIR`. Modules are offered as the owner groups them:

| Choice in Jenkins | Installer components | Packages used |
| --- | --- | --- |
| Database | `couchdb` (+ `haproxy` when it fronts a cluster) | none (RPM) |
| Message broker | `rabbitmq` | none (RPM) |
| SIP edge | `kamailio` | none (RPM) |
| Media | `freeswitch` + `ecallmgr` | FreeSWITCH, Kazoo |
| Applications + UI + API | `kazoo-apps` + `monster-ui` | Kazoo, Monster UI |

ACDC is part of the applications node, not of the media pair: a media server needs no
ACDC code, and the ACDC application ships inside the Kazoo package.

## Why tarballs with a manifest and not RPMs

An RPM per module would duplicate what the installer already converges (users, units,
configuration, migrations) and create a second source of truth for it. The artifact is
deliberately dumb: bytes plus identity. It can be turned into RPMs later without
changing the installer contract.

## Proof required before it is called done

- offline: identity mismatch (commit, ref, patch digest, OTP, OS, arch) falls back to a
  source build or refuses under `KAZOO_REQUIRE_PREBUILT`; a tampered file is refused; a
  package never contains a cookie, a password or `/etc/kazoo`;
- native: build the packages once; install `media` and `applications` on bare Rocky 9
  servers from Jenkins without a compiler run; compare the installed beams and
  FreeSWITCH modules byte for byte with a from-source install of the same commit; run the
  call campaigns on the package-installed stack.
