# Crossbar module registration on split-role deployments

## Corrected defect

`crossbar_maintenance:start_module/1` read the effective autoload list (node,
then zone, then default) but saved it into **default** unconditionally. With a
custom node/zone list, this replaced the default used by other servers while
leaving the original override unchanged. The module could run until restart
without being added to the calling node's effective startup list. `stop_module/1`
had the same scope mismatch.

Root-owned installer patch:
`scripts/patches/crossbar-module-autoload-scope.patch`.
The normal `ensure_kazoo_sources` path applies it to the pinned Crossbar source;
no commit is made to the nested upstream checkout.

Persistence now reads the configuration category and selects the existing
owner using native precedence: node, zone, default. An explicitly empty node
list still belongs to that node. The native `kapps_config:set_node/4` writer
updates only that owner path, preserving unrelated configuration fields and
other scopes. With no category, initial registration uses default. A category
read failure does not issue a persistence write. Explicit administrator APIs
for changing default configuration are unchanged.

This correction applies to the installer's ACDC, entitlements and storage
registrations as well as ordinary SUP start/stop module commands. It does not
enable modules on every running remote node, create a new cluster, configure
storage providers or change account data. A zone-owned setting remains shared
within that zone; it is not silently converted into a node override.

## Focused evidence

`scripts/test-crossbar-module-scope.sh --baseline` compiles the pinned original
production maintenance module and invokes public start/stop calls with controlled
configuration/module-start seams. Baseline73331/f53f5a fails6 of9 cases: node and
zone starts/stops, empty node override and configuration-read failure. Three
existing default/no-op behaviors pass.

Candidate24011/6fa7fc passes all9 cases. Final66781/039b20 additionally replays
the root installer patch on clean pinned source twice, verifies exact bytes,
and passes all9 cases in13.183s. Evidence directory:
`/tmp/kazoo-module-scope.n5meSvYS` on the original development host.
The production module is compiled without TEST/export_all; dependencies and
datastore/module-start seams do not constitute live multi-node acceptance.

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 512 \
  --runtime-sec 180 -- /bin/bash /opt/kz5/scripts/test-crossbar-module-scope.sh
```

Native deployment and running/disk module parity are pending. Do not label the
current dev server fixed until those complete. The earlier storage registration
on its default scope remains valid; it did not prove custom-node behavior.
Concurrent writers changing the same module list, live zone/node failure and
reboot acceptance on separately configured hosts remain separate release gates.

Do not overwrite a live server's module list merely to create an override test.
Use isolated configuration fixtures for regression; any native multi-node test
needs an explicit scoped configuration snapshot and restoration plan.
