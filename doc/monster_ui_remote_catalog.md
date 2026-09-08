# Standalone Monster UI catalog registration

Implemented in the modular installer. The receiver is installed on the dev apps
node and its actual local protocol/read-only/preserve paths passed on September
8. Pinned loopback SSH also passed. Fresh-catalog creation and deployment on a genuinely separate server remain
acceptance gates; do not equate the local receiver test with split-host proof.
No production bridge host or credential is involved.

## Why this exists

An app's deployed JavaScript is not its cluster catalog entry. The current
create-only import contract is `sup kazoo_monster_catalog init_app NAME PATH API`.
Crossbar's account `apps_store` PUT installs an already-published catalog app; it
does not publish metadata and screenshots. This transport runs the existing
importer on the applications node without sharing a CouchDB password or Erlang
cookie with the web node.

Local `ALL`, or a UI install with an existing local running applications node,
continues using the existing local SUP workflow. Explicit remote settings select
remote registration. A standalone UI install with neither authority now fails
preflight. `MONSTER_UI_REGISTER_APPS=false` is an explicit assets-only choice,
not a claim that cluster catalog integration was completed.

## Required operator inputs

Install or update the apps role from the same reviewed kz5 release first:

```sh
sudo ./scripts/install-kazoo5.sh kazoo-apps
```

That role installs the fixed helper
`/usr/local/libexec/kazoo5-monster-catalog`, its protected local configuration
`/etc/kazoo-monster-catalog.json`, and an ownership receipt at
`/var/lib/kazoo-monster-catalog/installed.json`. It does not install/enable SSH,
create an SSH user, copy a private key, modify authorized keys, or grant sudo.

On the web node, provide all five required settings and optionally the port:

```sh
sudo env \
  MONSTER_UI_CATALOG_SSH_HOST=apps1.example.net \
  MONSTER_UI_CATALOG_SSH_USER=catalog-installer \
  MONSTER_UI_CATALOG_SSH_PORT=22 \
  MONSTER_UI_CATALOG_IDENTITY_FILE=/root/catalog-ssh/identity \
  MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE=/root/catalog-ssh/known_hosts \
  MONSTER_UI_CATALOG_MASTER_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  KAZOO_API_URL=https://ui1.example.net/v2/ \
  KAZOO_API_UPSTREAM=http://apps1.example.net:8000/v2/ \
  KAZOO_WEBSOCKET_UPSTREAM=http://apps1.example.net:5555/websocket \
  ./scripts/install-kazoo5.sh monster-ui
```

Replace the example master ID with the target cluster's **already configured**
master account ID. It is not discovered from account age or created by the
receiver. The SSH hostname is an independent, explicit apps-node destination;
it is never inferred from an API, proxy, or websocket URL.

Identity and known-hosts files must be regular, single-link, root-owned 0600
files below protected root-owned directories, with absolute ASCII paths without
spaces. Pin the verified server key out-of-band; this installer does not trust
`ssh-keyscan` output or accept a new key on first connection. Non-default ports
require the matching `[host]:port` known-hosts entry. Encrypted SSH identities
requiring a prompt or an agent are not supported by this noninteractive path.

The SSH principal must already be authorized to execute this **fixed command**:

```text
/usr/bin/sudo -n -- /usr/local/libexec/kazoo5-monster-catalog --receive
```

For least privilege, the operator should provision a dedicated SSH principal,
disable PTY/forwarding, force that exact receiver command, and grant only its
exact noninteractive sudo invocation. Do not grant the `--install-receiver`
subcommand or an arbitrary shell. This trust setup is an explicit administrative
prerequisite, not something inferred or broadened by the installer. Existing
root administration may also run the fixed sudo command if already authorized.

Only connection identifiers and protected file **paths** enter the installer's
root-only saved deployment settings. Private key bytes do not enter Git,
deployment state, packet contents, process arguments, or diagnostics. Updating
the helper source requires updating the apps role first: receiver and sender
must have the same SHA-256 source identity.

## What installation and verification do

1. Resolve local, remote, or explicitly disabled registration before effects.
   Missing/partial authority fails before package or UI deployment work. Unsafe
   authority files fail early; full ancestor/link checks and host-pin lookup
   precede the remote check and every UI mutation.
2. On the remote path, install the SSH client dependency and make a read-only
   readiness/master/module/catalog-view check before Node installation, UI source
   staging, web-root publication, nginx changes, or restarts. This requires the
   applications node, local SUP, and initialized catalog view to be ready.
3. Build/deploy the selected UI assets through the existing owned-asset workflow.
4. Send exactly one allowlisted app's public metadata and referenced images at
   a time to the fixed receiver, over stdin. No tar extraction, source checkout,
   arbitrary RPC, arbitrary remote path, or caller-controlled command exists.
   Metadata is limited to 256 KiB, individual images to 5 MiB, screenshots to ten,
   total image bytes to 16 MiB, and framed JSON to 24 MiB per app.
5. The receiver checks the explicit master before creating its protected pending
   target and public input stage, checks again before existing SUP `init_app/3`,
   and checks master, unique catalog entry, and expected public API afterward.
   `created` and `preserved` are the only accepted importer outcomes. The existing
   backend validates the schema and verifies newly created metadata/attachments.
   Existing entries and customized images are never overwritten. An existing
   entry with a different API URL fails verification and needs a separately
   authorized migration, not silent correction.
6. Success removes only the exact staged files/directories from that operation.
   Unknown/timeout/conflict/readback failures retain an exact pending target and
   stage for operator inspection. Another installer invocation refuses that
   pending target instead of automatically retrying or rolling back.

`--verify-only` does not install dependencies, stage/upload assets, create
receiver configuration, acquire a pending target, call importer SUP, create
catalog records, or change services. It only checks selected catalog entries on
the explicit master via the fixed receiver. Missing SSH/helper prerequisites
cause failure. Dry-run does not connect remotely or create a catalog entry.

The RPC is read-only and uses the apps node's existing local `erl_call` as the
`kazoo` service user. SUP reads the local protected config; its cookie is not
forwarded by SSH. The read-only path checks importer exports from its BEAM file
without loading the module. Child output is bounded to 16 KiB while draining. Each receiver
invocation has a 120-second deadline; the sender bounds its SSH child to 125
seconds. Command output is never included in failure diagnostics.

Master checks do not claim an atomic transaction with concurrent privileged
changes to the cluster's master-account configuration. Do not change that
configuration while running catalog installation. Existing catalog creation
still uses its deterministic create-only conflict handling.

## Interrupted-operation recovery

On the explicit apps node, inspect the exact pending directory
`/var/lib/kazoo-monster-catalog/pending-MASTER-APP/stage.json`. Its referenced
stage has a private receipt naming the master, app, API, and packet hash. The
public subtree contains only the attempted app's metadata/images, never SSH or
database secrets. A `verified.json` file indicates readback completed but local
cleanup may have been interrupted; absence does not prove the create failed.

Use the read-only verification path and inspect the exact catalog record before
authorizing a retry. Never delete or overwrite the catalog entry as automatic
rollback. After reconciling the outcome, an operator may remove that operation's
exact owned stage/pending directory. No broad recursive cleanup is provided.
No existing unrelated path or changed installed receiver is adopted: changed
ownership/hash receipts fail closed and require explicit recovery.

## Verification and remaining acceptance

Offline fixtures:

```sh
python3 -B -I scripts/test-monster-catalog-transport.py
bash scripts/test-monster-catalog-routing.sh
```

The 19 transport tests and extracted installer routing fixtures passed, along
with installer smoke, modular-role, read-only and deployment-persistence suites.
An actual RPC check exposed a missing newline after the Erlang input form;
that was fixed and regression-tested before receiver deployment.

These execute actual packet validation, framing, file ownership checks,
create/preserve driver branches, exact cleanup, uncertain-outcome retry refusal,
SSH command construction, child-output/deadline handling, and installer routing
against private filesystem and process/RPC doubles. They never connect to SSH,
start SUP/erl_call, mutate a broker, or act as live schema/database proof.

Actual dev receiver evidence (`18673/066c23`) passed readiness, selected ACDC
catalog verification, wrong-master rejection and the real SUP `preserved`
branch. A before/after hash of the complete catalog document (including revision
and attachment metadata) was unchanged; the exact temporary stage was removed.
No apps/web services were restarted. The first helper-only invocation omitted
installer preflight and safely rejected empty node settings before file creation;
the normal preflight plus helper installation passed (`91394/fda2b3`).

Pinned loopback SSH acceptance (`16602/47fb93`) then exercised the real
installer's remote routing through a temporary SSH daemon on127.0.0.1:22229
with a forced receiver command and generated test-only keys. It passed ten
`preserved` importer outcomes and twenty remote catalog checks. Wrong host key,
master and receiver source hash were rejected. No pending stages remained.
The daemon stopped and its exact temporary configuration/keys were removed;
the normal SSH service/configuration was not touched. Apps/eCallMgr/nginx PIDs
were unchanged (`09b781`). This is transport integration proof, not a second
machine or absent-catalog creation proof. Receiver reinstall also passed with
matching source/installed SHA-256
`faa59f49c0ec2072537e241eba6a32dd48ffae3a0d71cf555b7d186072d326b3`
(`a9e7ef`).

Remaining: use authorized isolated apps/web boundaries with actual pinned SSH/SUP:
wrong master/version/host key fails before UI changes; absent selected entries
create once; a second install preserves document revisions and attachments;
verify-only has no writes; a deliberately interrupted create refuses blind
retry. Finally prove authenticated browser catalog/icon reads from a genuinely
separate UI host with no local apps/SUP. Loopback SSH is not the separate-host
release gate, and offline doubles are not proof of live Erlang/database behavior.
