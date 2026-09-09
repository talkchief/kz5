# Fresh SUP archive failure and bootstrap discovery

The independent empty-data campaign found a real packaging defect, not a failed
account creation. Cold apps attempt2 returned success from protected native
account creation and saved a master account. Discovery then failed because the
fresh `sup` archive raised `undefined function props:get_value/2` (exit127).
The authenticated account view contained one account and system_config already
contained its master ID. No second account was created to fix this.

The SUP Makefile did not explicitly stage Kazoo helper BEAMs as archive
prerequisites, and cleanup could run alongside archive creation with parallel
make. Mandatory `kazoo-sup-archive-order.patch` adds explicit staging and serial
ordering within this small package; repeated builds refresh the embedded helpers.
Direct `escript` builds now compile first. Other module builds remain parallel.

`verify-sup-archive.escript` examines the actual archive, requires exactly one
copy of each required module, validates BEAM exports and executes the packaged
`props:get_value/2` without distribution or cookies. The normal installer runs
this before installing the CLI/creating an account, so a broken archive cannot
be mistaken for a datastore/bootstrap problem. `test-sup-archive-order.cjs`
reproduces the old missing-helper archive and checks corrected parallel/repeated
Makefile ordering using private compiler/archive adapters and real BEAM contents.
Full native package rebuild/deployment verification is still required.

The cold lab may resume a failed post-create install only when its original
empty baseline is retained, system_config names a valid master ID and the sole
account exactly matches that ID and the fixed cold fixture realm. Original
failed attempts remain failed; a successful retry is not relabeled first-install
success. This prevents a diagnostic or retry from silently adding another master.
