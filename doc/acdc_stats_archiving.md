# ACDC statistics and restart persistence

The statistics collector archives agent statuses and completed calls to CouchDB.
Only an individual successful document acknowledgement marks the exact in-memory
snapshot as archived. A failed or missing acknowledgement remains retryable;
cleanup does not remove unarchived rows. A conflict is acknowledged only after a
fresh read proves the database already contains that same snapshot. A conflicting
different document is retained as pending and logged, never silently overwritten.

On orderly shutdown, the collector snapshots both ETS tables before releasing
them, saves agent statuses first, and waits for completion. The
`acdc.stats_shutdown_flush_ms` setting defaults to 10000 milliseconds and is bounded
to 100–12000 milliseconds. Its supervisor gives the collector 15000 milliseconds
to terminate. Timed-out work is killed before the owner returns; no shutdown
writer is left reading destroyed tables. Latest persisted statuses are read by
the existing agent startup recovery path.

This is not a durable local outbox. A database outage, forced process kill, power
loss, or an incomplete shutdown flush can still lose unpersisted in-memory data
when the whole service and ETS heirs stop. Such failures are logged explicitly as
incomplete/timeout, not reported as successful persistence or healthy agents.
Preserving unsaved status across that failure requires a separately designed
durable outbox. Do not count zero/unavailable agent statistics as queue readiness.

For first deployment, load the new collector, agent-statistics, and archive helper
modules before stopping the old application, or explicitly persist current agent
statuses beforehand. Simply copying new files and stopping an old loaded module
still executes its old shutdown callback.

Isolated regression coverage: `bash scripts/test-acdc-stats-archive.sh`. It tests
partial/failed saves, safe conflict retries, snapshot freshness, cleanup retention,
bounded shutdown, exact key updates, and latest-status recovery through the
existing database lookup after runtime state is cleared. It is not a live restart
or database-outage acceptance test.
