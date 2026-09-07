# Restricted queue-live acceptance — explicitly armed development test

## Current admission decision — September7

**Full17-case matrix PASS:** root resume `573eb1`/`0d57c2` completed every case
listed below with4 real nonadmin tokens. The existing SdiLT6 ledger records all
17 checks and `matrix_passed: true`. This is HTTP/native socket authorization
proof, not restricted-browser, load, cross-node, delivery or revocation proof.

The shared-lock invocation was corrected:
`flock -n 3 COMMAND` interprets `3` as a filename, not a descriptor. It created
an empty `/opt/kz5/3` during the first run; that file is retained as
`/var/log/kazoo-queue-live-isolation-SdiLT6/incorrect-lock-file`. The helper now
acquires inherited fd3 in descriptor mode and retains it in its waiting child.
The41-group/180-rejection-check suite (`407a4a`/`eb685f`) includes real competing
flock/release/reacquisition on a private inode and under-lock ledger freshness.
The successful resumed live run used this corrected lock.

`--mode resume` is explicit and one-shot, restricted to an otherwise completely
created/unchanged fixture whose only unverified user is `no_roster`. It rechecks
all public hashes/ownership, user revisions, empty owned queue roster and all3
known token identities before requesting the last login. Queue GET intentionally
has no strong revision because it enriches the document with roster data;
scope GET is a view. An initial resume (`bef681`) stopped before login on the
mistaken queue-revision expectation; the fixture and test now model this native
contract. Original write revisions remain unchanged for conditional cleanup.

For a prior uncaptured login, resume additionally requires
`--retain-ambiguous-login` and durably sets BOTH `cleanup_hold` and
`resume_attempt.ambiguous` before token issuance. Cleanup refuses either marker
without any HTTP or deletion. A fresh verified token does not prove an unknown
older token revoked. SdiLT6 remains retained under this hold; no extra resources
were created by resume. Do not remove the hold to force cleanup. Future definite
captured native429 responses can be resumed explicitly without this unknown-
issuance hold, but never with an automatic retry loop or relaxed rate limits.

Live execution `5a8685`/`7099e9` stopped during the fourth fixture login, after
creating the owned dormant queue,4 policies and4 nonadmin users. The first3
tokens passed native identity/expiry verification. The log records PUT/user_auth
HTTP429 at07:42:19 (request `4c8055cb0759f99f06053218ec5bbdde`); the original
harness did not journal the failing response status/correlation, so its last
login remains pending. There was no retry or cleanup. Protected ledger:
`/var/log/kazoo-queue-live-isolation-SdiLT6/ledger.json`. Never print its tokens or
passwords. Known-token expiry guard ends2026-09-07T08:43:19Z; unresolved login
ambiguity separately blocks automatic cleanup.

Separate read-only probes using the3 verified tokens pass5 HTTP cases
(`5da95c`/`e071a8`) and5 native WebSocket cases (`a9bf71`/`716240`): allowed exact
queue, denied same-company other queue, denied foreign-company queue, denied
missing stats, denied missing selected-queue read. HTTP replies used exact
stage-specific denial assertions; WebSockets required exact native ACK/error
shapes. These probes do not mark the full17-case matrix passed, establish the
missing-roster case, or prove cleanup. Existing customer agent state was not
changed and no calls were originated.

Root opened explicit `--allow-fixture-writes` admission after reviewing deployed
P0-19/P0-20 revision safety, deployed P0-21 role guard/registration, and actual
scope-policy HTTP stale/weak/current revision checks. This is not a claim that
the matrix or cleanup has passed. The corrected fixture passes33 groups and149
rejection checks (`5dadd0`/`f05ea0`), source SHA
`f7ef55d517e76356ad3b78e92cff035e1022c502f6c4a8f581f62e794eb407db`.
Both modes still require explicit arming before protected inputs or network
access; cleanup requires every token's finite expiry plus60 seconds and actual
401 before deleting any owner or policy. No global token TTL changes.

Owned queue PUT now omits public `id` and adopts the server UUID only after
strict ID/ownership/dormant-queue checks, recording it before readback. Unknown
creation is retained and never retried. HTTP403 data is validated against exact
native shapes by matrix case: token denial `{cause: "access denied by token
restrictions", message: "forbidden"}`, hierarchy denial `{message: "forbidden"}`,
or resource denial `{}` with message `queue_live_resource_forbidden`. Additional
payloads, incorrect messages/codes and infrastructure failures still fail.

The hard-closed text below records historical decisions and is superseded by
this section. Do not run this fixture on an older backend lacking those fixes.

Latest checkpoint, September7: the offline fixture now passes28 groups and79
explicit rejection checks (`caacb6`/`9ff5b9`), source SHA
`e5ae0b3ad57ab36b261a6a0b0ffc8e89e8af0863f51b7c3ed540b4d0528c651b`.
P0-19/P0-20 are deployed. P0-21 guarded scope-policy registration is also
deployed (`209651`/`1e3fc6`), and the separate administrator HTTP revision probe
passes all3 checks (`7c9f07`/`47ce1f`). This supersedes the earlier404/registration
blocker below; see `scope_management_dashboard_acceptance.md`. The restricted
matrix itself has not run. Its optional owned denied-queue setup still needs
safe server-generated ID adoption before admission; native default PUT ignores
public onboarding IDs. Do not change global onboarding settings for the test.
Expiry-plus-actual401 and ambiguous-write retention remain mandatory.

`scripts/test-queue-live-isolation.cjs` is an explicitly armed development-only
fixture, separate from the successful administrator wire smoke. Its offline
fixture is `scripts/test-queue-live-isolation-offline.cjs`; root47083 passed19
offline groups and42 rejection checks against source SHA
`9d8089daf117ef630c30c009db1de01962e598a7a5dc844d17d5264b5291ed61`.
This includes unconditional live-admission rejection, not proof of atomic
native cleanup or a live permissions matrix. Both public `run`
and `cleanup` modes are now unconditionally closed at the start of `main`, before
any API access, secret/ledger read, lock acquisition or file write; no CLI flag or
environment override opens them. No fixtures were created and no live matrix
has run. Offline exports remain testable. It never invokes the broader call-monitor harness,
services, SUP, a provider, call origination or roster/status mutation.

The existing `/etc/kazoo/acceptance-secrets.env` was checked by key names and
file metadata only: root-owned regular `0600`, with isolated tenant/queue/agent
identities and SIP credentials. It does not contain web login credentials.
`/etc/kazoo/monitor-acceptance.json` was absent. MASTER-in-child-account requests
cannot substitute for a real restricted principal.

## Narrow fixture and API contract

The harness reuses `baseState` from `test-channel-monitor-live.cjs` only as a
pure isolated-tenant identity validator. It uses an explicitly supplied protected
admin-token file for setup/readback/cleanup, never for matrix requests. It acquires
the existing `/etc/kazoo/monitor-acceptance.lock` with a positive child handshake
before API access; do not run concurrently with isolated call acceptance.

It creates four uniquely marked `priv_level: user` web users, each with a unique
owned scope restriction. No existing user or account-wide restriction is edited.
The optional `--create-owned-denied-queue` creates one marked dormant queue with
no roster/callflow and `enter_when_empty: false`; otherwise an explicit existing
second queue in the acceptance tenant is required. The canonical acceptance queue
is the positive target. Explicit existing foreign account/queue IDs are read-only
negative targets; no resource in that foreign account is changed.

Native APIs and corresponding source:

- `PUT /accounts/A/scope_restrictions` creates an `api:`-prefixed identity;
  `GET /accounts/A/scope_restrictions/ID` returns an exact-key **view array**, not
  a single object. The harness requires exactly one marked matching policy and
  no continuation. See `cb_scope_restrictions.erl:105–171` and the account
  `scope_restrictions/crossbar_listing` view.
- `PUT /accounts/A/users` creates marked users with `scope_restrictions: [ID]`.
  `PUT /user_auth` uses their own username/password digest and isolated realm.
  `cb_user_auth.erl:354–375` puts that scope identity in the signed token.
  The harness verifies account, owner, method, scope and finite expiry against
  actual `GET /token_auth`, not by trusting locally decoded JWT claims alone.
- Policies contain exact acceptance-account queue GET rules: `/`, `live`,
  `stats`, `Q`, `Q/live`, `Q/roster`; acceptance-account agent GET is allowed so
  the selected roster can be projected. All other resource rules are empty.
  Own-token GET is allowed for authentication verification. Three independent
  policies omit respectively `stats`, `Q`, or `Q/roster`; no policy is changed
  after login, avoiding stale-policy fixtures masquerading as current policy.
- `scope_restrictions.json` places `token_restrictions` outside its `properties`
  member. Exact persisted-policy readback is therefore mandatory: a successful
  create response alone is not proof that the intended policy survived.

## Positive and negative matrix

The 17 proposed checks use genuine isolated users:

| Case | HTTP | Native Blackhole |
| --- | --- | --- |
| Allowed user, canonical queue | Detail 200 with exact account/queue and no-store | Exact subscribe/unsubscribe ACK |
| Same user, second existing queue | 403 | `queue_live authorization denied` |
| Same user, foreign account/queue | Overview and detail 403 | Authorization denied |
| Same binding with foreign account | — | Authorization denied |
| Cursor explicitly selecting denied queue | 403; no snapshot disclosure | — |
| Missing underlying stats or queue read permission | Detail 403 for each | Authorization denied for each |
| Missing roster read permission only | Detail 403 | Hint subscription allowed: hints contain no roster |
| Positive controls after negatives | Detail 200 | Exact subscribe/unsubscribe ACK |

Each WS case uses a fresh native socket and correlated request IDs. Busy,
rate-limited, binding-unavailable, malformed or missing replies do **not** count
as authorization-denial passes. A WS denial's data must be exactly
`{"errors":["queue_live authorization denied"]}`, without subscription or other
payload fields. HTTP 401/404/503 do not substitute for the expected
restricted-principal 403, whose native data must be exactly `{}`. Sentinel data,
even alongside an error, fails the proof. No event is injected; naturally received hints
must have the exact account/queue and closed wire shape. This is not delivery,
reconnect, revocation, full lookahead-boundary or call-transition coverage.

## Cleanup hazard and retained fixtures

Production `cb_token_restrictions.erl:172–230` does not simply trust a restrictions
object embedded in a token. It merges current account/system policy with the
owner's selected scope documents. `crossbar_util.erl:1033–1062` returns undefined
when the user read or scope view fails, or when no policy is found. Native
`get_priv_level/2` also falls back to the configured default if its owner read
fails (`crossbar_util.erl:982–989`). Thus removing a scope **or its owning user**
can remove the intended per-user restriction while an existing signed token may
still authenticate from native identity/cache state. This is a policy-loss
fail-open risk relative to the intended scope, not a claim that all remaining
account/hierarchy/route authorizers are bypassed. It affects live HTTP and native
queue-live authorization because both use these Crossbar bindings. No runtime
reproduction or fix of this legacy policy behavior is claimed here.

The proposed harness would retain **both users and policies**, plus its owned denied
queue, after the matrix. `MATRIX_PASS_FIXTURE_RETAINED` describes only the matrix.
Cleanup is a separate explicit mode, allowed only after every issued token's
finite expiry plus 60 seconds and an actual `/token_auth` **401** for every token.
A 403 is a policy decision, not invalidation proof. No deletion occurs before all
tokens meet that gate. Then exact ownership/content readback and the recorded
strong revision are required in the offline model; `DELETE` carries `If-Match`,
and absence is read back (empty exact-key view for scope policies). **This is not
an atomic native CAS guarantee.** Root source review found that the pinned
`crossbar_doc.erl:641–660` refreshes the current DB revision on default soft-delete
after Cowboy checked `If-Match` against the previously loaded document. A
concurrent change can therefore be deleted despite the harness's earlier
ownership/content/revision check. The harness's lack of revision refresh does
not prevent the server's refresh. Live admission remains hard closed until an
atomic owned-cleanup path is implemented and proven; neither offline fixture
success nor an HTTP precondition alone opens that gate. Ambiguous outcomes are
still retained without automatic retries or destructive rollback.

P0-19 now has an installer-owned source candidate preserving the validated
revision. Nine controlled groups, ten private-Cowboy HTTP cases and isolated
native primary CouchDB checks pass; the pinned baseline reproduces the overwrite.
The CouchDB check also exposed P0-20 single hard-delete false success, now fixed
in a second installer-owned candidate and verified against real primary CAS.
Both changes are now **deployed** with exact runtime checks and unchanged31-agent
state; see `/tmp/kazoo-revision-deployment.19HpQo` and the latest
[handoff](../PROJECT_HANDOFF.md). The first separate full-route policy probe
stopped before writes because the native scope-policy API returns404: effective
autoload uses the upstream `cb_scope_retrictions` typo. Correct registration and
its management authorization need review before enabling that endpoint.
Controlled HTTP adapters and data routing/
cache/publication seams do not prove the full deployed API authorization path,
cluster behavior or token invalidation. Source ownership, reproduction,
evidence and remaining gates are in
[the soft-delete guidance](crossbar_soft_delete_revision.md).

Ordinary `cb_user_auth:put/1` calls `crossbar_auth:create_auth_token/2`
(`cb_user_auth.erl:308`), so no request TTL is forwarded. The native three-argument
helper accepts the `expiration` option (`crossbar_auth.erl:297–315`; its type
comment says `expiration_timestamp`), but invoking that would be a different
minting path. The harness neither invents a `user_auth` expiration field nor
changes system/account TTL. `DELETE /token_auth` only deletes a legacy token DB
document; it is not used as a claimed JWT revocation mechanism. Native user-only
identity-secret rotation exists but is outside this acceptance harness.

### User-only rotation audit — not an implemented cleanup shortcut

Source review identified `PUT /accounts/A/users/U/auth` with
`data.action=reset_signature_secret` in `cb_auth` and the owner-specific
`kz_auth_identity:reset_secret/1` branch. Missing the user context instead selects
an account-level secret. Do not substitute `/auth` or `/accounts/A/auth`, rotate
existing users, or infer authorization to do so from this note.

Even exact user rotation is insufficient on its own:

- `kz_auth:include_identity_sign/1` can omit `identity_sig` when identity signing
  fails; the identity verifier has a permissive unmatched-token branch. User
  rotation cannot revoke every otherwise valid JWT. Any future proof must
  validate the exact Kazoo issuer/account/owner/signature/finite-expiry claims
  in memory and exclude device-bound tokens; never print tokens or claims.
- Kazoo identity lookup uses `open_cache_doc`; remote caches and in-flight
  authorization can lag behind a successful write. Generic already-authorized
  Blackhole sessions differ from the queue-live adapter's fresh authorization
  on subscription/delivery. No cluster-wide instant revocation is established.
- This auth action mutates during validation, before later HTTP preconditions;
  an `If-Match` header is not a proven CAS guard for secret rotation.
- A future revocation test needs actual old-token401 plus a successful unrelated
  control request, and fresh/existing queue-live rejection after bounded worker
  drain on every serving node. Authentication/storage outage is not revocation
  evidence. Keep mutable policies until all issued tokens meet the proven gate.
- Datastore debug paths can log full changed documents; do not dump raw logs or
  claim this operation is credential-free logging.

No secret rotation, key access, token issuance or live fixture was performed for
this audit. The existing expiry-plus401 requirement and unconditional admission
closure remain unchanged.

## Deferred execution proposal — do not run

After the atomic-cleanup blocker is resolved and a new source review explicitly
opens admission, the intended procedure would create a root-owned `0700` directory using
`mktemp -d /var/log/kazoo-queue-live-isolation-XXXXXX`, then run the source-reviewed
tool under the serialized resource guard with explicit existing endpoints and
protected admin-token file. Do not use a network namespace that removes access
to those live endpoints. These retained placeholder arguments are not executable
acceptance instructions for this hard-closed checkpoint:

```sh
node scripts/test-queue-live-isolation.cjs --mode run --allow-fixture-writes \
  --run-dir /var/log/kazoo-queue-live-isolation-XXXXXX \
  --acceptance-file /etc/kazoo/acceptance-secrets.env \
  --admin-token-file /absolute/protected/admin-token \
  --api-url http://127.0.0.1:8000/v2 \
  --ws-url ws://127.0.0.1:5555/websocket \
  --ws-module /absolute/existing/node_modules/ws \
  --foreign-account FOREIGN_ACCOUNT_ID --foreign-queue FOREIGN_QUEUE_ID \
  --create-owned-denied-queue
```

The eventual `--mode cleanup` would use the same run directory, protected inputs and
endpoints; the foreign/denied scope options are taken from the ledger. The ledger
contains protected credentials/tokens and must remain outside Git. It is saved
and fsynced before each write and after readback. Lost requests remain explicitly
pending. Output contains only fixed diagnostic codes, counts, receipt path and
cleanup timing, never tokens, passwords, names, server payloads or raw errors.
Individual requests/ACKs are bounded to 8 seconds, the session to 180 seconds;
HTTP bodies and WS inputs retain the existing smoke's small limits. No production
or complete-isolation acceptance is asserted by source preparation/offline tests.
