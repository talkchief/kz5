# Bounded validation on a live Kazoo host

`scripts/run-kazoo-validation.sh` is an opt-in resource guard for trusted,
foreground build/test commands. It is not automatically inserted into the
installer and does not repair or restart any existing service. Deploying the
helper does not authorize a workload during an incident or maintenance hold.

Defaults are a 384 MiB hard memory cap, no swap, 50% of one CPU, 128 tasks and
a 900-second service runtime. The default admission reserve is 768 MiB, so
MemAvailable must be at least 1152 MiB before the default workload can start.
On a small no-swap host, refusal is an intentional outcome, not a reason to
skip the guard.

Only these numeric options are accepted before the required `--`:

| Option | Default | Allowed range |
| --- | ---: | ---: |
| `--memory-mib` | 384 | 128–384 |
| `--reserve-mib` | 768 | 512–4096 |
| `--runtime-sec` | 900 | 10–1800 |

The reserve is a headroom check, not reserved RAM. Service growth or unrelated
commands outside the guard can still exhaust the host. Choose a lower allowed
reserve only after measuring current host conditions; never infer safety just
because the command is admitted. One approval does not authorize parallel
unguarded workloads.

## Examples

Run only after the live-work hold is explicitly released:

```sh
sudo /usr/bin/bash scripts/run-kazoo-validation.sh -- /usr/bin/true
sudo /usr/bin/bash scripts/run-kazoo-validation.sh -- /usr/bin/bash -c 'exit 37'
sudo /usr/bin/bash scripts/run-kazoo-validation.sh --runtime-sec 600 -- /usr/bin/bash scripts/test-acdc-queue-editor.sh
```

The wrapper requires an absolute executable. Arguments after `--` are kept as
distinct arguments; they are not reconstructed through `eval`. It preserves
literal dollar bytes across systemd's ExecStart expansion by encoding each
command-argument dollar as `$$` exactly once, including the worker script.
This does not expand or import caller variables; a payload shell can evaluate
its own script normally after systemd restores those literal bytes. It preserves
the physical working directory. Only fixed local-system manager options are
used: user managers, remote hosts, containers, scope units, alternate runners
and arbitrary unit properties cannot be selected through wrapper options.

Caller environment variables are not implicitly forwarded. The systemd client
and the worker start with minimal environments. The worker's home is the actual
UID 0 account home from `getent passwd 0`, verified as a protected root-owned
directory; it is never taken from the caller's environment. This preserves
Erlang/SUP network-kernel initialization without forwarding caller startup flags
or credentials. For explicit nonsecret
runtime flags, use a bounded command such as:

```sh
sudo /usr/bin/bash scripts/run-kazoo-validation.sh -- /usr/bin/env NODE_OPTIONS=--max-old-space-size=256 /usr/bin/node scripts/test-example.cjs
```

Existing protected credential files may be read by a trusted test script where
the task authorizes it. Do not put passwords, API keys, cookies or tokens in
command arguments or `env KEY=value` arguments. The wrapper neither echoes
argv nor uses it as the transient unit description, but process listings and
privileged systemd ExecStart metadata can expose argv. Workload output is
passed through and may itself contain sensitive data; existing redaction and
root-only receipt rules still apply.

## Serialization and fail-closed checks

The single fixed lock is `/run/kazoo-validation/validation.lock`. Its directory
must be a nonsymlink root:root directory with mode 0700, below a protected
root:root `/run`. The lock must be a nonsymlink, empty regular file, root:root,
mode 0600, with one hard link. Missing paths are created narrowly with those
modes; insecure existing objects are refused, never repaired, truncated,
deleted or replaced. Metadata parsing uses the C locale.

The launcher takes a nonblocking preliminary lock and checks the real
`/proc/meminfo` MemAvailable against cap plus reserve. It then starts one local
transient service. Inside that service, a separate `flock` parent holds the
same nonblocking lock for the foreground command's lifetime. The worker checks
memory admission again under that lock. This closes the launch race: racing
launchers can create small bounded guard services, but only one payload is
admitted. A failed launch or disconnected/killed client does not remove the
lock inode or unlock a surviving service's lock.

Before executing the payload, the worker verifies its actual unified cgroup
membership is the expected unique `system.slice/kazoo-validation-*.service`
and reads the effective `memory.max`, `memory.swap.max`, `memory.oom.group`,
`cpu.max` and `pids.max`. Missing controllers, changed limits, a different cgroup, malformed
MemAvailable, insufficient memory or a busy lock cause refusal. There is no
direct-execution fallback.

The unit also sets `LimitCORE=0` and verifies both soft and hard core-file limits
before executing the payload. This confines the change to validation processes;
it does not change global coredump policy or discard earlier crash evidence.
The workload's failure status and diagnostics are still retained. It is not a
promise that the system's crash handler will emit no journal metadata.

The unit uses OOMPolicy=kill with verified memory.oom.group=1, fixed accounting and hard
limits, a 15-second start timeout, 10-second stop timeout, KillMode=control-group,
SendSIGKILL=yes, no delegation and a read-only cgroup filesystem. Its independent
RuntimeMaxSec remains in effect if the client disappears. The client is also
bounded to runtime plus 45 seconds, with a further 10-second forced-kill bound.
The wrapper returns the systemd-run/client exit status without turning failed,
timed-out or OOM-killed runs into success. A busy/admission/usage refusal returns
75/69/64 respectively; local prerequisite or security failures are nonzero too.

This is not a sandbox or an authorization boundary. A trusted root command can
contact the system manager, change host state or deliberately escape resource
controls. Do not run untrusted commands or daemonizing/detached workflows, and
do not use this helper to grant broader task authority. Existing services are
not stopped to manufacture headroom. If the client is lost, inspect only the
named validation unit and its bounded lifetime; do not remove the shared lock
file or restart unrelated services.

## Validation status

`scripts/test-run-kazoo-validation.cjs` sources the helper in isolated shells
and substitutes fake launch/lock commands for orchestration tests. It checks
exact argv, fixed unit properties, exit propagation, launch refusal, numeric
bounds, no diagnostic argv echo, two admission locations and service-owned
lock command structure. It separately checks parsers, effective-limit failures
and protected lock metadata using only private synthetic filesystem fixtures.
It makes no actual systemd calls, creates no cgroups and runs no workload.

Mock tests and Bash/ShellCheck checks do not certify this host's systemd
enforcement. Before a real build, the operator must first verify a harmless
success command, exit-37 propagation, actual effective cgroup properties and
serialized overlap refusal. Do not intentionally exhaust memory to test this
on the live host. Clean-host/distributed deployment and workload compatibility
remain separate acceptance gates.

### Harmless host smoke, 2026-09-05 23:55 UTC

The reviewed helper passed actual default-limit smoke checks on the running
systemd 252 host: `/usr/bin/true` exited 0, an explicit `exit 37` propagated 37,
and the worker read 402653184-byte memory.max, zero memory.swap.max,
memory.oom.group=1, pids.max=128 and cpu.max=50000/100000. A synthetic caller
environment marker was not forwarded. An owned eight-second sleep held the
global lock; another run was refused with 75 both before and after the launching
systemd-run client was terminated. The client returned 143, the service kept its
lock, and a subsequent run succeeded after the finite service ended. No existing
service was changed and no validation workload remained afterward.

The first smoke failed before unit creation because this installed systemd-run
does not accept a separate MemoryOOMGroup property. The compatible implementation
retains OOMPolicy=kill and additionally checks actual memory.oom.group=1 before
payload execution; no memory limit or proof was relaxed. The original failure
and subsequent success are retained in the protected receipt directory
`/var/log/kazoo-validation-smoke.2QVSR8`, including `summary.json`. No intentional
OOM or resource-exhaustion test was run. This demonstrates harmless host
enforcement, not suitability or completion of any heavy build/test workload.

### Follow-up, 2026-09-06

An actual harmless worker verified soft and hard core limits of zero. The
callback retry at `20260906T003353Z` then failed during isolated fixture setup,
before any SIP calls, because the previous minimal environment omitted the
account home required by Erlang authentication startup. Fixture setup had
already performed isolated configuration writes, so this was not a successful
callback test or a no-write run. The failure evidence is retained under
`/var/log/kazoo-acceptance/20260906T003353Z`.

The guard now restores the verified account home. Its 74 mock cases include
rejection when that home cannot be verified and proof that a caller-supplied
home does not enter the worker environment. The resource caps are unchanged.
A guarded read-only `sup -e code which stepswitch_maintenance` subsequently
exited 0 and returned the installed module path. The initial follow-up probe
without `-e` reached Kazoo but failed because SUP passed a binary instead of
the atom required by `code:which/1`; that probe is not counted as a pass.
Bash syntax and ShellCheck also passed. Callback behavior itself requires the
separate live scenario receipt.

### Literal-argument correction, 2026-09-06 09:01 UTC

The installed systemd 252 client has no `--expand-environment` switch. Its
manager expands ExecStart variables even inside an argument intended for
`bash -c`. A harmless synthetic reproduction confirmed the previous wrapper
emptied `${KAZOO_ARGV_LITERAL_8D1F}`, removed the standalone
`$KAZOO_ARGV_LITERAL_8D1F` argument and collapsed `$$` to `$`. Consequently,
shell-local variables in an inline URL could disappear before the shell ran.
The wrapper now escapes dollars in every ExecStart command argument once;
manager decoding restores exact worker and payload bytes. Unit options,
environment isolation, admission checks, service-owned locking and caps are
unchanged.

The corrected actual systemd path preserved all 14 synthetic arguments,
including empty, whitespace, multiline, percent, quoted and dollar cases.
The same worker confirmed memory.max=134217728, memory.swap.max=0,
memory.oom.group=1, pids.max=128 and cpu.max=50000/100000 under the selected
128 MiB cap. A separate guarded inline shell produced the exact synthetic URL
`http://127.0.0.1:5984/synthetic`. Both commands exited 0 with empty stderr;
no application services, credentials, HTTP/RPC or SIP were used. The protected
actual receipt is
`/usr/local/src/kazoo5-installer/validation-argv-preservation.0msw8a/actual-proof.yb8Y0b/summary.json`.

The expanded 75-case mock suite passed under a 384 MiB cap and a 60-second
runtime bound. Its earlier 10-second guarded attempt timed out before emitting
an assertion result; that failed attempt is retained, not counted as a pass.
PID1 reported RuntimeMaxSec expiry for
`kazoo-validation-84927b9d-e166-4989-b651-8e428d8042eb.service`. Bash syntax,
Node syntax and ShellCheck passed for the candidate; byte-identical source
promotion also passed syntax and scoped diff checks. The private promotion
receipt records the original/fixed hashes and both test outcomes.
