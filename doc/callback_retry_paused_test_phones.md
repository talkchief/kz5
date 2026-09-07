# Callback retry diagnostic with MASTER test phones paused

The default retry diagnostic requires all five named services active and running.
An explicit `--allow-paused-master-test-phones` option permits only
`kazoo-live-test-agents.service` to be **loaded, inactive, dead, with MainPID 0**.
It does not accept a missing, failed, activating, deactivating, or partially
stopped helper. The four call services—apps, ecallmgr, FreeSWITCH and Kamailio—
must still be loaded, active, running, with positive process IDs.

This is a memory-conscious development-test scope, not a production readiness
shortcut. The helper runs the MASTER account's receive-only test phones. The
retry diagnostic registers its own isolated-account agent and launches its own
SIPp answer endpoint at `127.0.0.20:15100`; it does not depend on those MASTER
phones. Historical fixture ownership restrictions remain unchanged.

The harness never stops or starts that helper, and never changes MASTER accounts,
devices or enrollment. The coordinating operator must verify zero native calls,
stop the helper when appropriate, and restore its prior service state after the
diagnostic, including after failure. Restoration is a separate required receipt;
it is not claimed by the diagnostic itself.

Example extra options on the existing guarded live retry command:

```text
--registration-mode entry-only --allow-paused-master-test-phones
```

`retry-service-before.txt`, `retry-service-after.txt`, and
`retry-service-scope.json` preserve the exact service inventory, load/active/sub
states, process IDs and restart counters. Before/after equality is mandatory,
including for the paused helper. The final packet receipt records the paused
limitation explicitly: isolated-tenant callback success is not proof that the
MASTER phones were available. This option changes no callback/media/durability,
five-second entry, retry/backoff, native ownership, log, core-dump or teardown gate.
