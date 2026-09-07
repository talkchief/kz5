# eCallMgr native atomic-intercept compatibility gate

Upgrade native `mod_kazoo` on every configured FreeSWITCH server **before**
deploying eCallMgr's atomic-answer aggregate. The bridge action now requires
`kz_intercept` for ACDC agent legs; it deliberately has no non-atomic fallback.
A successful source patch replay or BEAM build does not prove that native
application is installed on a local or remote media server.

Main SH `verify_ecallmgr_atomic_media` follows the existing configured-node
connection verification. It uses the same `freeswitch_nodes_to_manage` scope,
expands bare hosts to `freeswitch@host`, and rejects malformed, duplicate or
oversized inventories before any RPC. An empty scope reports compatibility
**unverified**, rather than claiming a media server was checked. It does not
discover additional nodes, register one, or assume a local `fs_cli` executable.

For each node, a checked-in, protected read-only Erlang script requests only
`freeswitch:api(MediaNode, show, <<"application as json">>)` through eCallMgr.
The decoded inventory is bounded to1MiB/4096rows, requires object rows and unique
keys, and must contain exactly one application named `kz_intercept`, owned by
`mod_kazoo`. Missing, duplicate, wrong-owner, malformed and unreachable results
all fail closed with a fixed token. Malformed response bytes are not logged by
the JSON decoder. SUP has a15-second RPC timeout and a20-second local outer
timeout per node; the native API has its existing timeout. No automatic retry,
alternate node, notification, account write or call is performed.

This is an installation/verification gate, **not startup dispatch admission**.
Fresh eCallMgr must connect before the remote check is possible. A failed check
does not stop already running processes or undo a deployment. Use a controlled
development window and media-first deployment ordering; a future production
admission policy would require separate implementation and acceptance.

Root-run offline validation:

```sh
bash -n scripts/install-kazoo5.sh scripts/test-ecallmgr-atomic-media.sh
bash scripts/test-ecallmgr-atomic-media.sh
```

The fixture evaluates the actual Erlang file with the real JSON implementation
and a synthetic FreeSWITCH API, then exercises the extracted shell gate with
stubbed SUP responses. It retains private evidence and checks source stability.
It performs no native API request and does not establish actual compatibility.
Actual main-SH verification must separately pass against each configured node.
