# Dispatcher reload bookkeeping repair

Status: reviewed configuration deployed on 2026-09-05 at 20:11 UTC; the installer
Kamailio verification passed after startup. A clean callback rerun remains a
separate gate. OPTIONS probing and the acceptance log gate remain unchanged.

## Observed failure

Kamailio RPM `6.1.4-0.el9.centos` logged the primary destination UP at
19:46:34.763 UTC. A repeat media advertisement at 19:46:34.787 logged an INSERT
at 19:46:34.788, followed by dispatcher reload at 19:46:44.801. An OPTIONS
callback failed to update its destination at 19:46:44.806. The new destination
generation was UP at 19:46:54.765.

The installer changed every `$sqlrows(exec)` expression to literal `1` because
the stock SQLite driver lacks the affected-row capability. This is incorrect
for the dispatcher's `INSERT ... WHERE NOT EXISTS`: successful execution can
change zero rows. The pre-reload destination was already loaded and active,
so the repeat advertisement did not justify reloading it. A real SQLite test
of the pinned INSERT confirms first execution changes one row and repetition
changes zero. The matching SQLOps source distinguishes query success from
affected-row support. [Kamailio 6.1.4 SQLOps implementation](https://github.com/kamailio/kamailio/blob/6.1.4/src/modules/sqlops/sql_api.c#L115)

The matching upstream `dispatch.c`, not the older local source checkout,
contains the reported error at line 4523. Loading destinations creates new
internal identifiers; OPTIONS From-tags carry those identifiers. A reply to a
probe from the prior generation cannot match the newly loaded destination,
even when its URI is unchanged. The source mechanism plus the observed ordering
supports the stale-probe explanation; no matching SIP capture was taken for
this startup event. [Kamailio 6.1.4 dispatcher implementation](https://github.com/kamailio/kamailio/blob/6.1.4/src/modules/dispatcher/dispatch.c#L4451)

## Scoped fix

The pinned configuration patch changes only `dispatcher-role-5.7.cfg`:

- Immediately after successful dispatcher INSERT or DELETE, SQLite reads
  `select changes()` through the same process-local `exec` connection. Zero
  does not request a reload or log a false insertion/removal. Other DB drivers
  retain native `$sqlrows(exec)`. Failed or invalid count reads are explicit
  errors and retain a reload request because the preceding DML succeeded.
- The timer consumes its dirty bit before `ds_reload()`. A concurrent writer
  during loading therefore leaves another reload pending. A negative reload
  result re-arms the bit for the existing timer, with an error log.

The installer applies the patch before copying config, exempts this file from
the old constant-row rewrite, and defines `KZ_DISPATCHER_SQLITE_AFFECTED_ROWS`
only in its generated SQLite config. Deploy both candidate files together.
The SQL statements, destination selection, probe settings, SIP authorization,
listeners and error counters are not changed. SQLOps `sql_pvquery` uses its
named connection and returns an execution status independently of the selected
value. [Kamailio SQLOps documentation](https://www.kamailio.org/docs/modules/6.1.x/modules/sqlops.html#sqlops.f.sql_pvquery)

## Private validation

Run without SIP/API requests, live writes or service reloads:

```sh
node scripts/test-kamailio-dispatcher-reload.cjs
node scripts/test-kamailio-registered-source-credentials.cjs
```

The dispatcher suite checks pinned forward/reverse replay, installer
idempotence, refusal of unknown operator edits, exact changed-route scope,
real SQLite positive/zero row counts, count failures, extracted reload-branch
behavior under concurrent writes and failure/retry, and both preprocessor
branches with the installed `kamailio -c` parser. It reproduces both old
lost-dirty cases before checking the fixes. Parsing does not start listeners,
connect to a DB or execute a reload. These are not live runtime acceptance tests.

## Remaining gate

This removes duplicate-advertisement reloads and lost dirty-bit updates; it
does not fix stock dispatcher behavior when a **genuine membership change**
reloads while an old-generation probe is outstanding. There is no C/RPM patch,
probe suspension, log suppression or replacement of old identifiers by URI.
Other callers of dispatcher reload and partial-load semantics also remain
outside this two-fix scope.

## Live deployment checkpoint

Root verified the exact old and new configuration hashes, an empty native call
inventory, and only the existing receive-only test phones. Deployment used the
shared acceptance lock, a consistent SQLite backup and a full configuration
parse before restarting only `kazoo-kamailio`. Protected rollback material is
in `/usr/local/src/kazoo5-installer/dispatcher-live-deploy.TPGcL3`.

The new Kamailio PID is `3019351`, automatic restart count zero. The native
dispatcher reports the existing media destination `AP`. The unmodified
`--verify-only kamailio` gate passed SIP OPTIONS, AMQP transport/consumer queues,
dispatcher discovery, SBC authorization, SQLite integrity, RPC/module checks
and the since-startup runtime-error scan. This verifies this startup, not the
remaining genuine-membership-change race or a completed callback test.
