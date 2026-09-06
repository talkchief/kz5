# Installer source-fetch failure handling

The main installer's `sync_git` helper now explicitly stops on failed directory
creation, initialization, remote setup, fetch, checkout, clone or fast-forward.
For full commit pins, it also checks the resulting HEAD against the requested
commit. No forced checkout/reset was added; conflicting local source edits are
preserved and require operator resolution.

## Reproduced bug

Guarded local-fixture run `72775` reproduced a false-success path in the previous
helper: a missing commit on a fresh repository caused fetch and checkout errors,
but the helper reached its unconditional `return 0` when invoked conditionally.
Bash disables implicit `errexit` inside a function whose result the caller tests.
The correction uses explicit error handling instead of relying on that setting.
This was a helper-level reproduction, not evidence that a deployed installation
had used the wrong source revision.

Failed receipt: `/tmp/kazoo-git-sync.cxoOvj/receipt.json`, SHA-256
`f1ac2329cdce258e86273cfbbcb007145ca6d36f12c69338b0a2af46f12da0f9`.
The corrected initial seven-case run `81072` passed; receipt:
`/tmp/kazoo-git-sync.4WFjKg/receipt.json`, SHA-256
`bf3b1f5207339075702feb2e946640c9650a649b64c81a0fef4dfa9a99c88f5e`.

Expanded run `79712` passed all ten cases and then the main installer smoke
(syntax, pins, aliases, modular selection, security gates, ALL dry-run and error
paths), within the unchanged 384-MiB cap and private network namespace. Complete,
input-stable receipt: `/tmp/kazoo-git-sync.4Y5jI7/receipt.json`, SHA-256
`975df5d4b1897458d4ebf85a988c495635343d3610880da55f3a9888e3522738`.

## Reproducible check

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 384 --reserve-mib 768 \
  --runtime-sec 90 -- /usr/bin/unshare --net -- /usr/bin/node \
  /opt/kz5/scripts/test-installer-git-sync.cjs
```

The test extracts the actual helper and uses actual Git against a new private
local repository. It does not replace Git with a mock, source the full installer,
access GitHub, use credentials or touch live checkouts. It covers exact pinned
checkout, repeat installs with tracked/untracked edits, failed fetch on existing
and fresh repositories, successful retry, failed/successful branch clone,
conflicting upgrade, clean upgrade and no-write dry-run. Inputs are hashed before
and after and receipts distinguish interrupted/failed runs from completion.

A failed initial fetch can leave the newly initialized repository as a retryable
artifact; no source-install success is reported and no automatic deletion is
performed. Existing-repository fetch may update Git metadata before a conflicting
checkout fails; this is not an atomic Git transaction. Network authentication,
remote availability and clean/distributed-server installation remain separate
acceptance requirements.
