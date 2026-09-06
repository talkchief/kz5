# Real owned-child PIDfd acceptance checkpoint

On 2026-09-06, the helper passed 12 real-kernel checks in 0.819 seconds against
**three newly spawned synthetic Python children only**. The receipt was
collected at 00:49:25 UTC. No SIPp, existing process target, system service,
manager, Erlang node, API, queue or agent state was used or modified.

A final rerun with bytecode generation explicitly disabled passed the same 12
checks in 0.868 seconds; receipt collected at 00:51:55 UTC. It created and reaped
three new synthetic children. Across both runs, six children were created and
all six reaped; no long-running fixture was touched.

Tested helper SHA256:
`1d78865580b2532e5d2fefa58ae96de64bcec4a1b3559690b7280c8a1af8f5b6`.
The private test used a byte-identical copy of the promoted shared helper,
not a mock or altered syscall implementation. The default test invocation
was also checked and created no child processes.

| Real check | Result |
| --- | --- |
| Exact live child identity | `alive` |
| Wrong start ticks: check, INT, KILL | All three `foreign`; child remained alive |
| Wrong parent: check, INT, KILL | All three `foreign`; child remained alive |
| Exact INT through helper pidfd | `sent`, child exit `-2` (SIGINT) |
| Exact KILL through helper pidfd | `sent`, child exit `-9` (SIGKILL) |
| Both signalled children after reaping | `dead` |
| Third child exited normally after a one-byte parent instruction | Exit `7`, then `dead` |

All three children were reaped and their descriptors closed. The complete
nonsecret private receipt is
`/tmp/kazoo-pidfd-owned-child-acceptance.Op9HZP/receipt.json`.
The final bytecode-safe receipt is
`/tmp/kazoo-pidfd-owned-child-acceptance.Op9HZP/receipt-bytecode-safe.json`.

## Explicit opt-in reproduction

```sh
# Safe default: description only; does not spawn a child or send a signal.
python3 -B -I scripts/test-phone-process-owned-children.py

# Real signals, but only to three synthetic children this harness creates.
python3 -B -I scripts/test-phone-process-owned-children.py --live-owned-children
```

The test accepts no PID, account, service or helper-path argument. Target PIDs
come only from its new Popen handles. Children self-expire after eight seconds;
each helper invocation has a deadline and cleanup uses owned pidfds/Popen
handles. Failed assertions never authorize switching to an existing process.
The harness emits a bounded nonsecret JSON receipt and exits nonzero on failure.

This proves real local pidfd identity checks and INT/KILL delivery for the
tested helper bytes. It does **not** force kernel PID reuse, establish rolling
SIP-service safety, or activate this code inside the existing Bash supervisor.
PID-reuse timing is covered separately by the mocked descriptor-race tests.
Any live supervisor renewal still requires its own reviewed status-preserving
activation procedure; no restart was performed for this checkpoint.
