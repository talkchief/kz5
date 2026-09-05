# Exact Monster app API-URL migration

This is a reviewed, **one-time ten-document migration**, not app discovery or
an automatic installer action. No ownership marker exists in these app docs.
The exact account, ID/name pairs and old/new URLs are hard-coded in both the
controller and RPC bridge. A matching name or URL alone never grants write
authority. On 2026-09-05 at 20:26:31 UTC, all ten reviewed documents were
migrated and read back successfully. The protected receipt is
`/var/lib/kazoo/monster-app-api-url-plan-20260905-v2/receipt.json`; it contains
private snapshots and must not be committed. No unrelated fields changed.

The public runtime configuration and nginx `/v2/` route now use the same HTTP
origin. A real CLI regression also covers restrictive installer umask `077`:
the published `config.js` must explicitly retain public read mode `0644`.

Scope: master account `302ae5a70c403124f764cbc54229cfcd`, encoded DB
`account%2F30%2F2a%2Fe5a70c403124f764cbc54229cfcd`.

| App | Reviewed document ID |
| --- | --- |
| accounts | 6fd9207e022cedcc3b1c9493b1bf7b20 |
| acdc | 9ed4c13921516bb1d2afb9f1874290a3 |
| callflows | f607173df478e2654a7aa28b219c1a72 |
| csv-onboarding | 747e264204ec61bae44a47fe8bc24532 |
| fax | 1468daf86a7ec165af980daaf908bfdd |
| numbers | f3248fe1214da79cb5d089614bf22651 |
| pbxs | ee30412619e9e4d922c99467db8a5268 |
| voicemails | f61021d214b6e7e8d3a41429133ea99b |
| voip | f9a82ad18cf17c9a73b836ff0feba33f |
| webhooks | b94a5cff43467f9e0755aa2f7e9d560e |

Only `api_url` changes from `http://91.99.188.145:8000/v2/` to
`http://kz5.talkchief.io/v2/`; CouchDB advances `_rev`. HTTP is intentional for
the currently authorized target, not an assertion of TLS availability. A later
HTTPS migration requires a new reviewed scope and original-document snapshots.

## Plan, review, apply

Prerequisites: root, Node 18+, existing Erlang/escript and repository Jiffy,
local `kazoo_apps@LOCAL_HOST` running with reachable loopback distribution,
and the protected installed `/etc/kazoo/.erlang.cookie`. The controller never
prints its contents or passes the cookie/document body in argv. The bridge is
a short-lived local client; no module is installed on the running node.

Choose a new private directory whose parent already exists. Do not reuse an
existing plan directory for `--plan`:

```sh
node /opt/kz5/scripts/migrate-monster-app-api-url.cjs --plan \
  --receipt-dir /var/lib/kazoo/monster-app-api-url-plan-20260905

# After reviewing the ten plan metadata lines and the private receipt:
node /opt/kz5/scripts/migrate-monster-app-api-url.cjs --apply \
  --receipt-dir /var/lib/kazoo/monster-app-api-url-plan-20260905
```

No flags/`--help` makes no connection. `--plan` makes document reads only; it
does create the local protected receipt. `--apply` is the only write mode.
The RPC target is restricted to the local Kazoo apps node. There is no URL,
account or allowlist override. `--cookie-file` accepts another protected local
cookie path without exposing its contents.

Each plan snapshots the **entire raw JSON representation returned from
`kz_datamgr:open_doc`**, its SHA-256, original CouchDB revision, and canonical
full-document hash. This is not a hash of HTTP wire headers/formatting. Snapshots
may include private custom fields: keep `receipt.json` root-owned `0600` and its
directory `0700`; do not paste or commit it. The script refuses symlinks,
hard-linked receipt files, permissive modes, unknown identity/type/account,
conflicts, non-stub attachments, custom/prechanged API URLs and malformed data.
It also refuses a public `id` field: `kz_datamgr` would remove that field on
save, violating the preservation contract.

Before any writes, all ten current documents must still match their snapshot
revision and raw hash. Immediately before each save, the Erlang bridge checks
them again and constructs the update directly from the original Erlang object,
preserving attachment stubs and all unrelated fields. It calls exact-revision
`kz_datamgr:save_doc` with change notices enabled. It does not use `ensure_saved`,
`update_doc`, `init_apps`, image replacement, bulk save or direct CouchDB PUT.
Read-back verifies the committed revision and equality of every unrelated field.

## Partial commits and recovery

The ten-document operation is **not atomic**. A protected, fsynced `in_flight`
receipt is persisted before each remote save. A received successful save
acknowledgement is checkpointed before the separate read-back. File replacement
uses a private atomic rename and directory fsync. Stdout reports only reviewed
app name/ID, status, revision and hashes; bridge errors never render raw responses,
document bodies, cookies or stack traces.

- A completed receipt can be replayed. Only its recorded committed revision,
  target URL and unchanged full document permit a no-op; a matching target URL
  by itself is rejected.
- After an acknowledged save followed by read-back failure, replay verifies
  that committed revision without writing it again, then handles remaining
  unchanged planned apps.
- A save timeout, conflict/error response, lost response or crash before the
  acknowledgement checkpoint leaves `uncertain`/`in_flight`. Automatic replay
  stops, even if the target URL is visible. An administrator must establish
  external commit evidence and explicitly review recovery. Do not edit receipt
  states to manufacture ownership, roll back blindly, or refresh revisions.
  No automatic rollback, retry, lease takeover or deletion is provided.
- A changed snapshot or edited committed document fails closed. Prior committed
  rows are retained; no remaining app is overwritten using a newer revision.
- The exclusive `migration.lock` prevents concurrent helper runs. A killed
  process can leave it behind. Confirm the original process is dead and review
  the durable states before manually removing that exact stale lock; removing
  a lock does not resolve an uncertain write.

Keep the receipt for audit/replay. The helper does not delete it or silently
revert successful rows. After root applies the migration, separately verify
the same-origin nginx proxy and inspect the browser's actual API requests.

## Offline checks

```sh
node /opt/kz5/scripts/test-monster-app-api-url-migration.cjs
```

Tests use fake document storage and private scratch receipts, plus the bridge's
pure self-tests compiled with warnings as errors. They do not read a real
cookie, start distributed Erlang or access Kazoo/CouchDB/SIP. They cover exact
scope, all-field/attachment preservation, stale revisions/hashes, unknown target
documents, partial commits, lost replies/checkpoints, acknowledged-save recovery,
receipt modes/locks/symlinks, and stdin-only subprocess metadata.
