# Carrier / SBC ACL maintenance commands

## Operator summary

Whitelisting a carrier is one command and may be run from any Kazoo node:

```sh
sup ecallmgr_maintenance allow_carrier NAME CIDR true   # cluster default (recommended)
sup ecallmgr_maintenance allow_carrier NAME CIDR        # only the ecallmgr node(s) that run it
sup ecallmgr_maintenance carrier_acls true              # list cluster defaults
sup ecallmgr_maintenance remove_acl NAME true
```

`true` stores the entry in the cluster default, so every current and future
ecallmgr node receives it. Without it the entry is stored for the executing
ecallmgr node only; a node with its own `acls` section no longer follows later
changes to the defaults. Prefer `true` unless a carrier must reach one media
controller only.

The `trusted` list is applied by ecallmgr when it classifies an inbound call;
SIP reaches FreeSWITCH through Kamailio with an authorization token. FreeSWITCH
is sent only the `freeswitch` and `authoritative` lists, so
`fs_cli -x "acl IP trusted"` answers `false` by design and is **not** a test of
carrier whitelisting. Use:

```sh
sup -n ecallmgr -e ecallmgr_fs_acls trusted_acls
```

## Defect — September 17, 2026

`sup` addresses the applications node unless `-n ecallmgr` is given. That node
carries `ecallmgr_maintenance` but runs no ecallmgr. A node-scoped command was
therefore stored under `kazoo_apps@HOST`, a section nothing reads, and then
crashed reloading FreeSWITCH:

```
Command failed: {'EXIT',{noproc,{gen_server,call,[ecallmgr_fs_nodes,{connected_nodes,false}]}}}
```

The listing on that same node showed the entries, so the operation looked
successful while the carriers stayed untrusted.

## Correction

Required installer patch `scripts/patches/ecallmgr-acl-command-forwarding.patch`
(fetched `ecallmgr`, applied after the integration patch). Every ACL command —
`allow_carrier`, `deny_carrier`, `allow_sbc`, `deny_sbc`, `remove_acl`,
`carrier_acls`, `sbc_acls`, `acl_summary`, `reload_acls`, `test_carrier_ip`,
`test_sbc_ip` — first checks whether `ecallmgr_fs_nodes` runs locally. If not,
it executes itself on every connected node that does; that node's output returns
to the operator's terminal. With no reachable ecallmgr node it writes nothing
and prints the `sup -n ecallmgr` form. Behavior on an ecallmgr node is unchanged.

## Verification

`bash scripts/test-ecallmgr-acl-forwarding.sh` rebuilds the pinned module plus
the patch and runs three groups in a private network namespace, the third with
**two real distributed Erlang nodes**: no ecallmgr anywhere writes nothing and
explains itself; an ecallmgr node runs locally; a node without ecallmgr forwards
node-scoped and default-scoped commands, stores nothing locally, stores under
the ecallmgr node's own name remotely and relays the remote output. `--baseline`
(unpatched pinned module) fails. Installer base/modular/deployment/read-only/
production-BEAM suites pass with the patch registered.

Native repair on main44 the same day, before the patch was deployed: the three
operator carriers were added as cluster defaults on the ecallmgr node, resolve
in its effective trusted list, and the three misplaced `kazoo_apps` copies were
removed. Deployment of the patch itself is recorded in `PROJECT_TASKS.md`.
