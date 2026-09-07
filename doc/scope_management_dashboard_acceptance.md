# Scope-policy management prerequisite for live dashboard isolation

This work supports restricted-user tests of the live queue summary/detail. It
does not implement history, callback playback, voices or workforce reporting.

## Defects and source ownership

The first real policy preflight (`592766`) returned404 before any write, while
the same administrator could read the isolated account. The upstream Crossbar
default and effective configuration contained `cb_scope_retrictions`, not the
implemented `cb_scope_restrictions`.

Enabling that module unchanged would expose policy management to ordinary
same-account users unless another token restriction vetoed access. Its native
resource had no local administrator guard. The root-owned required patch
`scripts/patches/crossbar-scope-management-guard.patch` therefore:

- Corrects the default spelling.
- Normalizes only the exact legacy alias after existing module-version removal,
  preserving unrelated effective entries and existing deduplication behavior.
- Restricts all five collection/selected GET/PUT/POST/DELETE validators to native
  account administrators or superadmins, before policy/schema/view access.
- Exports production capability `management_guard_version/0 = 1` so UI-only
  installer invocations cannot accidentally register an old unguarded backend.

Global authentication, hierarchy and token restrictions still run first and
are unchanged. This is an intentional tightening of management access, not a
grant of cross-account permissions. No policy is assigned or altered by the
registration helper. Crossbar remains a pinned nested dependency; commit the
root patch, never its nested Git metadata. ACDC remains directly tracked in kz5.

## Evidence and limits

The installer registration helper passes22 mocked groups (`66cc53`/`cea08b`),
including old-capability refusal, unavailable readbacks, preserving custom
entries, effective-override failures and read-only verification. Existing native
Blackhole registration tests still pass37 groups (`e08f24`/`941a97`).

The final source fixture passes all7 groups (`bcc947`/`c5cf88`), with11 production
modules compiled with warnings as errors and no TEST/export_all. Evidence/build:
`/tmp/kazoo-scope-management.PqePbc`. The same final fixture against pinned old
source fails5 groups and passes the2 unchanged administrator paths
(`8594f1`/`20731f`, `/tmp/kazoo-scope-management.9QeQ1d`). Replay, repetition,
reversal, mismatched-source refusal and disjoint aggregate-patch checks pass.
Earlier fixture runs had a missing list bracket and incomplete mocked config/
error-formatting functions; they are not counted as regression passes.

These tests use real context/user-role logic with controlled datastore/schema/
view/config seams. They do not prove full HTTP authorization, JWT expiry,
restricted dashboard isolation, cluster failover or production capacity.

## Deployment and acceptance tools

- `scripts/deploy-scope-management-guard.sh --tested-build BUILD`: explicit
  development-only deployment of the guarded resource and config modules, with
  source pins, zero-call checks and before/after31-agent/roster snapshots.
- `scripts/verify-scope-management-runtime.cjs BUILD`: verifies actual installed
  bytes and loaded module MD5s, capability and installer registration. It uses
  the actual root account home for SUP, never credentials in arguments/output.
- `scripts/test-crossbar-revision-live.cjs`: separately armed localhost-only
  policy create/update/stale-delete/weak-delete/current-delete probe. A protected
  journal is persisted before every write. Ambiguous responses retain the
  fixture without destructive retries. It creates no users or fixture JWTs.
- `scripts/test-crossbar-revision-live-offline.cjs`:15 passing controlled
  transport/journal/scope groups (`7a1a9f`).

The first deployment (`e45b88`/`ac69c0`) verified module bytes but failed wrapper
registration because the sanitized child environment lacked the real root home.
Evidence/backup: `/tmp/kazoo-scope-deployment.mOZUf3`. The fallback restored the
old config module and restarted apps, retaining the guarded policy module to
avoid re-exposing old behavior if a corrected name had been persisted. All
services checked afterward were active. Root home was then restored in the
wrapper using `getent passwd 0`; the direct isolated-environment reproducer
failed without it and passed with it.

The corrected deployment (`209651`/`1e3fc6`) passed. Receipt/backup:
`/tmp/kazoo-scope-deployment.rwm5y2`. Runtime verification confirms installed
bytes, actual loaded MD5s, capability1 and running/effective registration. Only
apps restarted; the exact queue roster and all31 agent states were unchanged.

Actual full-route probe (`7c9f07`/`47ce1f`) subsequently passed all3 checks:
stale If-Match412 with unchanged document, weak If-Match412 with unchanged
document, and current If-Match DELETE200 followed by independent absence.
Journal: `/tmp/kazoo-crossbar-revision-http.zRwU7L/run3/journal.json`.
One exact owned unreferenced policy was soft-deleted; no fixture JWTs were issued.
This proves the administrator route, not ordinary-user rejection or the live
dashboard permissions matrix. Corrected offline probe passes15 groups (`f6d5fb`).

Earlier run2 (`04b8c5`/`2dcefb`) is deliberately retained after a harness error:
native POST replaces public fields while retaining private fields; sending only
the changed marker omitted the original token restrictions. The probe now sends
the complete intended public document and its mock models replacement. Retained
unreferenced policy `api:revision-dcf9ca6fb0821f0d5c3a07740192a451` belongs to
isolated account `7807ad61761269a1ccec833dde63f621`. Its pending-update journal is
`/tmp/kazoo-crossbar-revision-http.zRwU7L/run2/journal.json`. Do not refresh the
revision and automatically delete this ambiguous fixture. The protected token
files beside these journals must never be printed or committed.

Do not restore the old unguarded policy module on fallback. If guarded bytes or
the prior config cannot be restored safely, the deployment helper leaves apps
stopped and prints the backup location for explicit recovery.

Restricted-dashboard fixture admission remains closed until full-route cleanup
and token-lifecycle gates in [queue_live_isolation.md](queue_live_isolation.md)
are met. Native scope-policy reads return a view array; their view ETag is not a
document revision. Capture strong revisions from write envelopes and verify
absence independently. Never delete an assigned scope policy while its issued
tokens can still authenticate.
