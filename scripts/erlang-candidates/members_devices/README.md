# Members/devices regression fixtures

The implementation is now in `applications/crossbar/src/modules/cb_members.erl`;
this directory retains only tests and the constrained read-only acceptance harness.
The source/API is deployed; see `doc/members_devices_acceptance.md` for exact live
evidence and remaining limits. It adds no user/device writes, SIP calls, roster
changes, presence updates or cached online flags.

Implemented endpoint: `GET /v2/accounts/{ACCOUNT_ID}/members/devices`.

- Member-based pagination includes users with no devices: `page_size` defaults
  to 25 and is capped at 100. An opaque, account-bound `cursor` continues from the
  last user ID. This is a live listing, not a cross-page database snapshot.
- `items` contains safe user identity/name/enabled fields and nested safe device
  ID/name/type/enabled fields. No SIP credentials, SIP usernames/realms, contacts,
  network addresses, tokens, full raw documents, or queue membership are returned.
- `count`, `has_more`, and `next_cursor` describe the current member page;
  `total_members` is null rather than an invented full-account count.
- One bounded user view page plus one device catalog query (maximum 1,001 rows)
  is performed. At more than 1,000 account devices, the response explicitly marks
  device inventory and every member's devices incomplete, with null counts and
  empty device lists. It never labels those empty lists a complete inventory.
- One correlated cluster registrar **detail** request supplies registration
  evidence. Only AOR and expiry are retained internally. Contact/Path/Call-ID and
  other detail fields are discarded. The existing collector's complete-peer and
  part-count checks must already be deployed on the core API and registrars.
- `online` means a currently unexpired registration (or Kamailio's permanent
  binding sentinel), not proof of reachability or successful calling. `offline`
  requires complete registrar evidence and no current binding. Timeout, incomplete
  peers/parts, missing or invalid expiry, non-registration authentication, external
  device realms, and non-registerable device types produce `unknown` with a reason.
- Expiry is evaluated at response observation time. Output times are Unix epoch
  milliseconds. Numeric expiry is exposed where available; permanent/unavailable
  expiry is null. `enabled` remains separate from registration: disabling a device
  does not prove its existing binding has already disappeared. Cluster clocks must
  be synchronized for reliable expiry comparison.
- `registration_snapshot` includes start/observation timestamps, completeness,
  source, and expiry availability. Responses use `Cache-Control: no-store`.

## Integration contract

1. Package `cb_members.erl` as a Crossbar plugin and compile with the normal
   production warning flags. Include `cb_members` in its generated application
   module list and persisted Crossbar module-start list.
2. `api_util` now treats `members` as a built-in custom route, preserving the
   existing configured custom-route list without any database rewrite. The
   actual-parser regression verifies `/members/devices` stays with `cb_members`
   whether or not the configured list also contains `members`.
3. Preserve existing authorization. The candidate requires authenticated exact
   account routing and re-evaluates global/module stop decisions and `allowed_scopes`
   for members, users, and devices GET resources. Restricted-token and cross-account
   behavior still require real runtime acceptance; mocked tests are not that proof.
4. Confirm `crossbar_listings/by_type_id` is deployed and the registration
   correlation/sequence patches are active cluster-wide. No new CouchDB view or
   writable schema is needed.
5. Review this bounded inventory policy before claiming suitability for accounts
   with more than 1,000 devices. A per-member device continuation API is a future
   expansion, not a capability hidden by this candidate.

Source evidence for expiry units: Kamailio `usrloc/ucontact.c` stores `expires`
as absolute `time_t` (`0` is permanent); `sqlops/sql_api.c` converts DB1_DATETIME
to an integer; deployed `registrar-query.cfg` detail puts that value in `Expires`.
The summary SQL has no expiry predicate, so summary presence alone can include a
binding awaiting registrar cleanup.

## Offline validation

```sh
bash scripts/test-members-devices-candidate.sh
```

The runner compiles with actual production warnings, then compiles TEST-only
exports into a temporary private directory and runs memory-only EUnit. It never
loads a live Erlang node, changes shared source/ebin, or performs an HTTP request.

## OpenAPI and read-only live acceptance

`openapi-overlay.cjs` re-exports the source-hashed OpenAPI3 contract and standalone
`buildSpec()` preview from the main generator. Calling it alone does not write
the main or planned published catalog.
It documents optional/omitted null values, members with zero devices, partial
device inventory, status/expiry branches, authorization gates, and custom routing.

```sh
node --test scripts/erlang-candidates/members_devices/contract.test.cjs
```

After root has reviewed and deployed the endpoint, root may run the separately
armed harness against the known MASTER31-user baseline:

```sh
node scripts/erlang-candidates/members_devices/live-readonly.cjs \
  --allow-authentication-only /var/log/kazoo-acceptance/PRIVATE_RUN_DIRECTORY
```

The directory must already be root-owned0700. The harness reads only existing
protected MASTER credentials and uses ordinary `user_auth`; that authentication
is its sole allowed HTTP write. All subsequent requests are exact allowlisted
GETs against local Crossbar and the fixed MASTER account. It cannot create a
user/device, change a roster, or mint a new broader-scope principal/token. It checks
anonymous and malformed/different-account cursor failures, all31 users across
pages, zero-device users, device associations/types, fresh milliseconds/no-store,
no credential fields, and unchanged before/after catalogs.

The private0600 receipt contains counts, checks, observation timestamps and hashes,
never credentials, auth headers, raw user/device documents or registrar contacts.
A partial registrar result is explicitly recorded as incomplete, with unknown
statuses; a contract PASS does not imply registrar availability. The independent
live reference is the existing correlated **summary** status API. Exact detailed
expiry is source/unit-tested and checked for consistency in the new response,
not independently proven by summary. Restricted-token authorization and SIP call
reachability remain outside this harness's coverage. No live harness execution
is part of the offline tests above.
