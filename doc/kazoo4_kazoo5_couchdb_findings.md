# Kazoo 4/5 shared CouchDB assessment — findings in progress

Task: `COMPAT-01`. Date: September8,2026. This is **not a coexistence approval**.
Source node: production `10.1.0.10` (CouchDB3.3.2). Destination: protected,
isolated development storage on `10.1.0.44`; its installed CouchDB is3.5.2.
Only company `d8520ce3f29c5b6db692289e782c92af` is authorized for copying.
No production write, migration, restart or development connection to production
AMQP has been performed. Raw customer documents must remain outside Git.

## Measured result: do not share writable production databases yet

Actual native `kapps_maintenance:refresh_account/1` returned `ok` in the isolated
Kazoo5 node (35650/7e39fb). Before refresh, baseline and working account documents
were identical (51893/261e18). After refresh (18164/b6feda):

- **38 existing design documents changed; eight new design docs were added.**
  Existing non-design account documents did not change in this refresh step;
  none were removed. Some JavaScript differences may be formatting rather than
  semantics; the count is not a claim of38 incompatible behaviors.
- The new designs are `acdc_callbacks`, `application`, `contacts`,
  `crossbar_listings`, `emails`, `functions`, `scope_restrictions`, `websites`.
- Isolated shared databases also changed: `accounts`3→4 documents,
  `services`2→3 and `system_config`19→20 (6eb5ca). These globals were created by
  the lab's fresh native startup, **not copied from production**.

Actual baseline-versus-refreshed view GETs passed the comparison harness
16978/039f93. Both sides run the same CouchDB3.5.2 engine, separating these
definition changes from engine-version differences:

| View | Captured baseline | After native Kazoo5 refresh | Observed contract effect |
| --- | --- | --- | --- |
| `trunkstore/lookup_user_flags` | HTTP200,0 rows | **HTTP404** | Existing view removed |
| `vmboxes/legacy_msg_by_timestamp` | HTTP200,0 rows | **HTTP404** | Existing view removed |
| `users/crossbar_listing` | HTTP200,15 rows | HTTP200,15 rows | Same IDs; `features` values changed |
| `devices/crossbar_listing` | HTTP200,82 rows | HTTP200,82 rows | Exact rows match for this data |
| `callflows/crossbar_listing` | HTTP200,89 rows | HTTP200,89 rows | Exact rows match for this data |
| `queues/crossbar_listing` | HTTP200,4 rows | HTTP200,4 rows | Same IDs; additive `strategy` value field |

The two removed endpoints prove that the refreshed database does not preserve
the complete captured view API. They returned200 even though this sample had no
matching rows;404 is a different contract. Whether the **currently deployed
production Kazoo4 code** still calls these paths requires its exact source/runtime
version, requested from the operator. Equal rows for devices/callflows prove only
these queries on this sample, not all keys, edge cases or production4 behavior.

Current decision: **NO-GO for attaching Kazoo5 to writable production CouchDB
based on current evidence.** This is an interim safety decision, not completion
of all migration/API/version4 regression tests. Keep separate databases while
the remaining checks identify needed compatibility adaptations and rollout
boundaries. No production compatibility patch has been applied by this task.

Private evidence on .44 under `/var/lib/kazoo-compat/snapshots/`:

- `comparison-before-refresh.json`, SHA256
  `991fc544540f199e7e0300bf3b627741f3b40bbff6c276965fc1765f9fbd2507`.
- `comparison-after-refresh.json`, SHA256
  `84bf2bea6f46e472710f52b81de5b0d66304be6858c5481266d9ea92319dc0c3`.
- `refresh-native.log` and `view-query-comparison.json`; contain private data,
  never copy into Git or print raw responses. `query-company-compat-views.py
  --summarize-existing` emits only sanitized status/count/field-name evidence.

## Confirmed code-level isolation risks

An isolated Kazoo Erlang/AMQP zone is **not by itself a database isolation
boundary** when both versions use the same writable CouchDB databases:

1. `core/kazoo_apps/src/kapps_maintenance.erl`, `refresh/1` calls
   `kz_datamgr:refresh_views/1` before invoking database/account refresh hooks.
   `core/kazoo_data/src/kz_datamgr.erl`, `do_refresh_views/1` selects registered
   view definitions and calls `db_view_update/2`. The resulting design documents
   are database-wide, not zone-specific. A version5 refresh can therefore alter
   the views queried by version4. Which definitions actually differ in this
   company's snapshot is measured above; the code path explains why zone
   separation cannot protect those database-wide definitions.
2. `kapps_maintenance:refresh_by_classification/2` invokes `ensure_aggregate/1`
   for an account. That calls faxbox/device/account aggregation and services
   reconciliation. `ensure_aggregate_account/1` saves the account document into
   shared `accounts`. Consequently, even an explicitly account-scoped refresh
   is not restricted to writes in only its account database.
3. `kapps_maintenance:migrate/1` invokes system/config migrations and enumerates
   databases. `migrate/2` refreshes selected databases, removes deprecated
   databases from that set, migrates account config and forwarding failover,
   then invokes registered migration hooks. The broad maintenance entry point
   must never be run against production during this assessment.
4. Registered account-refresh hooks include ACDC refresh, number-services view
   updates and service-plan migration (`acdc_app.erl`, `kazoo_numbers_app.erl`,
   `kazoo_services_app.erl`). A test limited to Crossbar GETs or replacing design
   JSON would omit real maintenance effects and cannot establish compatibility.

These findings establish required test scope, not whether current version4
consumers will break. Shared/global production databases have **not** been copied
or modified. Their migration compatibility and actual version4 runtime contract
remain unverified.

## Snapshot and runtime limits

Account export26720/e97565 is verified complete:1,847 leaf revisions, stable
start/end metadata, protected .44 file
`/var/lib/kazoo-compat/snapshots/company-b05rg4rz.ndjson`. SHA256 is recorded in
the assessment plan. Monthly export55565/c9e79e is also complete:27,762 leaf
revisions across six databases, all individually unchanged during export.
Total copied:29,609 leaf revisions, exact company only. All nine main .44
services remain active (d8ffc0); imported customer data is not connected to them.

The account baseline and working restores pass79427/a9ee43 and19538/fab27e:
1,805 live documents,42 tombstones and all1,847 revisions checked via `_revs_diff`.
Restore security is intentionally restricted to the generated lab administrator;
production security metadata is retained in the immutable snapshot, not applied
as live lab access policy.

Lab runtime is `/var/lib/kazoo-compat-runtime`, dedicated `kazoo-compat` user,
separate cookies/data/logs, units `kazoo-compat-couchdb`, `kazoo-compat-broker`,
`kazoo-compat-apps`. They are not enabled at boot. A separate network namespace
with only loopback/no external routes is verified a56dfc; broker namespace
membership verifiedf8c244. Native Crossbar, ACDC, Callflow, Blackhole and database
bootstrap are verified0c2398 (OTP26). Helpers refuse host-namespace restore/RPC.
The assessment helper's hostname-selector mistake and missing AF_NETLINK allowance
were fixed; the latter is needed by OTP `inet:getifaddrs`. External networking
remains blocked by the network namespace and unprivileged service/capabilities.

Monthly restore initially failed under the lab's1GiB/256-task cap (OOM), then
with query-pool starvation after limiting only JavaScript processes. Main
services remained active; dependent lab broker/apps stopped through `BindsTo`.
No matching stored lab CouchJS core files were found (a4cc79). Corrected helper:
4GiB cap, eight JS processes/four soft, one background indexing channel/no extra
incremental channels, and serial design-document replay. This is **lab tuning**,
not production load/soak acceptance or an automatic main-stack configuration
change. CouchDB's default background indexing concurrency can amplify large
design refreshes; see [background indexing configuration](https://docs.couchdb.org/en/stable/config/indexbuilds.html).
Account-only startup success did not exercise this bulk-MODB condition.

Interrupted monthly baselines with prefixes `baseline-account/` and
`baseline-retry1-account/` remain preserved; they are **not accepted monthly
baselines**. No preexisting DB was overwritten/deleted. The accepted monthly
baseline prefix is `baseline-verified-account/` (5405/d4f304: all six match source
counts/revisions); subsequent canonical working restore also passes5405/120ead,
terminal success1m8.444s. Working databases keep canonical `account/` names for
native Kazoo. Snapshot files are now read-only/root-only0400. The lab broker/apps
are restarted after the successful import, with main stack services untouched.
Post-restore verificatione5a400 confirms Crossbar, ACDC, Callflow, Blackhole and
database bootstrap; all three lab units share the separate namespace, no default
route exists, and lab Crossbar8000 is listening. All copy/restore jobs are terminal.

The protected export uses GET-only `_changes` and exact revision/document reads;
it does not invoke source replication/checkpoint writes. It captures current
leaf revisions including conflicts/tombstones, known ancestry, attachments and
design/security metadata. It excludes `_local` checkpoints and historical
revision bodies. A live database can change during the export; per-database
start/end metadata records this limitation. See the
[assessment plan and source tools](kazoo4_kazoo5_couchdb_coexistence_plan.md).

Production CouchDB3.3.2 versus development3.5.2 is a separate version variable.
Do not attribute every runtime/query difference to Kazoo5 without isolating
that engine-version effect. This logical export/restore also does not establish
physical `.couch` file downgrade compatibility.

## Still required

- Additional view keys/edge cases, repeat-migration/idempotence and live call
  behavior under both versions; the representative API/edit tests below do
  not prove every endpoint or call feature works.
- Full system/config/global migration semantics. The selected-company native
  components tested below deliberately do not run broad `migrate/0` or `/1`.
  Synthetic lab globals are not a copy of production globals, so cannot prove
  compatibility of production authentication, billing, services or routing.
- Establish the actual production Kazoo4 source/runtime contract and replay
  compatible queries where possible. Clearly label unavailable runtime tests.
- Produce a final evidence-based GO/NO-GO with rollback/isolation requirements.

Until these checks are complete, **do not attach a Kazoo5 zone to production
writable CouchDB on the basis of this assessment**.

## Authenticated API and selected migration evidence — September8 continuation

`exercise-company-compat-api.py` authenticates natively with the copied account
API key, held only in memory. HTTP credentials and token envelopes are never
printed or returned into API-response evidence. Full CouchDB documents and API
data remain in root-only private journals. A fixed account/resource allowlist,
lab namespace checks and disabled redirects/proxies constrain all requests.
Each edit changes only an existing label, then restores it through Crossbar and
checks the readback. A journaled intent precedes mutation; ambiguous timeout
still attempts restoration. HTTP400 with unchanged original value is recorded
as a rejected edit, **not a successful edit**.

The initial reads77379/b034d6 exposed lab-only setup issues: fixture selection
included Kazoo soft-deleted documents, and minimal native lab startup had not
registered the five optional API modules that the normal installer registers.
The fixture picker now excludes `pvt_deleted`. `company-compat-rpc.escript
prepare-api` uses the normal native `crossbar_maintenance:start_module/1` path
and verifies both running and persistent autoload state (b0f8b2). This is not
evidence of a missing registration in the already-tested normal ALL installer.
Collections explicitly disable pagination to cover this bounded sample.

Before migration, actual API reads/edits90319/6cf15e:

| Resource | Collection/detail GET | Label PATCH and restore | Result |
| --- | --- | --- | --- |
| Account | 200/200 | 200/200 | Both readbacks correct |
| Users (15) | 200/200 | **400/400** | Sampled user rejected; original unchanged |
| Devices (82) | 200/200 | 200/200 | Both readbacks correct |
| Queues (4) | 200/200 | 200/200 | Both readbacks correct |
| Callflows (89) | 200/200 | 200/200 | Both readbacks correct |

Only one representative existing document per resource was edited. The counts
are collection sizes, **not counts of successful edits**. First native
authentication also added `pvt_signature_secret` to the working account.
After restoring labels, device/callflow audit fields (`pvt_auth_account_id`,
`pvt_modified`, `pvt_request_id`) changed; the queue gained `agent_order` as
well as audit updates. These are exact document differences, not a claim that
every such difference is incompatible with version4.

The rejected user PATCH identified `call_forward%2Efailover` with validation
rule `additionalProperties`. Current `call_forward.json` excludes that legacy
field and sets `additionalProperties:false`. All15 live users and9 live
devices in this sample carried a boolean legacy flag. A working list API alone
would not have exposed this edit failure.

### Selected native migration and post-migration edits

Before migration, streaming comparison20965/fd910b verified all six monthly
working databases exactly matched baseline live documents, revisions and counts.
It reads100-document pages and checks metadata stability instead of loading the
entire company history into memory. Account differences at this point were
the previously measured refresh/API effects.

The first migration invocation73724/2bcfcc failed before entering maintenance:
`kapps_maintenance:migrate/2` is private, not an exported RPC API. The helper now
uses its exported native components on the fixed seven working databases:
classification/existence preflight, `refresh/1` for each, account-config
`migrate/1`, account-selected `migrate_failover_from_forward/1`, and account-scoped
`maintenance.migrate` hooks. It never enumerates baseline/global DBs or invokes
the deprecated-database deletion step. This is a selected-component assessment,
not execution of the full global migration command.

Actual run99861/408605 returned normally. Its private log reports seven refreshes,
account-config/failover completion, two hook results and24 migrated documents;
no matching failure/warning lines were found in that captured command output.
Native functions can absorb internal errors, so the independent differences
and post-migration API tests are the stronger evidence:

- 15 users and9 devices lost the legacy `call_forward.failover` field. For23
  documents it was false. For one user it was true: an enabled `call_failover`
  object was added with its destination number preserved. This changes stored
  call-routing representation; actual version4 interpretation must be tested.
- Each of the six monthly DBs changed21 existing design documents and gained
  `call_reports`, `functions`, `presence`. No existing monthly non-design
  document changed; none were removed. The service views
  `day_summary_by_source` and `day_summary_by_date` were removed from each.
  Actual GET comparison64718/b919f6 confirms both endpoints return200 with zero
  rows in every baseline and404 in every working MODB (12 endpoint pairs).
- Across all seven DBs, baseline content hashes stayed unchanged and deleted
  document counts still matched. Comparison48886/cad73a captures exact private
  differences. Current account totals versus original baseline are38 changed
  designs,8 new designs and28 changed non-design docs (including earlier API
  effects; do not add overlapping counts from individual stages).
- Post-migration API test93347/340c36: all five representative label PATCHes
  returned200, changed-value readbacks matched, restore PATCHes returned200
  and original-value readbacks matched. All collection/detail GETs returned200;
  collection counts stayed15/82/4/89. The previously failing sampled user edit
  now succeeds. Four ordinary audit-field changes remain after this final edit
  cycle; original baseline documents remained untouched.

Over the broader interval from account refresh to the final API/migration
inspection13751/b6ddaa, synthetic lab `accounts` changed revision sequence;
`acdc`1→2 docs, `alerts`2→3, `system_config`20→29 and `system_schemas`453→454.
This interval includes native startup, API registration, authentication, edits
and migration: these counts must **not** all be attributed to migration alone.
No production global databases were copied or modified. All nine main .44
services and all three isolated lab services remained active (941cb5).

Private evidence files under `/var/lib/kazoo-compat/snapshots/`:

| File | SHA256 |
| --- | --- |
| `api-reads-1.ndjson` | `8c8516f90ca8eacb93acf1c67e6b640b2f0ba31c12224e38e010062f52465c75` |
| `api-edits-2.ndjson` | `8401053a4d4c7c05b65555c95a06a8c82d08547e585efeb18dd468636d949d7f` |
| `databases-before-migration.ndjson` | `6cd50cc73ab3e415d07b046a53613ebc3e7b69c67748f5c20a8d2eecb09523bf` |
| `databases-after-migration.ndjson` | `a21bb534804dad35cca9e3efe3344e7fe3acac12a6e17d91b0a8ed6c05bc987d` |
| `api-after-migration.ndjson` | `fe6ff97778300e213e6ad700488920047dcce7d4536769ffa3875b113584f37a` |
| `comparison-after-api-migration.json` | `53e420cb34c8e6527b51d425d2d4219107b475c56b7382a417e74b43897d1aaf` |

Also preserve `api-edits-1.ndjson` (early abort on rejected user restore; both
original labels verified unchanged) and `company-migration-native-2.log`.
`monthly-view-query-comparison.json` holds the12 real MODB endpoint comparisons.
Do not overwrite evidence paths or replay edits from an interrupted journal
without inspecting restoration state.
