# Test-phone process identity guard

The optional receive-only fixture supervisor must not signal an unrelated task
after Bash reaps a SIPp child and Linux reuses its PID. A numeric PID and `kill
-0` are not ownership proof.

The spawning Bash records `/proc/PID/stat` field22 (kernel start ticks) and
requires the process to be its direct child. It captures this with builtins,
before launching another helper; no SIP credentials or command line are read.
The new `scripts/phone-process-identity.py` opens a Linux pidfd **before**
validating the saved start ticks and supervisor PPID. INT/KILL is delivered
only using `signal.pidfd_send_signal` on that descriptor. PID reuse after the
check cannot redirect the signal. There is no numeric-PID signal fallback.

Observation results are intentionally distinct:

- `alive`: exact saved child identity, nonterminal descriptor.
- `dead`: saved PID has vanished, or exact child is terminal/zombie.
- `foreign`: present PID has different birth identity or parent.
- `unknown`: absent captured identity, unsupported API/kernel, permission,
  malformed observation, or other inability to prove ownership.

Only `alive` plus the existing exact loopback contact counts as registered.
Only `dead`, existing fixture ownership, global zero calls and another fresh
`dead` check permit an individual phone restart. `foreign`/`unknown` do not
authorize signals or replacement. Missing contact never authorizes killing a
live phone. Cleanup keeps its existing five-second INT grace period and only
sends KILL via the validated descriptor; it avoids an unbounded `wait` on an
unproven task. Existing queue/roster/login/pause and call cleanup gates are
unchanged. Systemd still owns lifecycle cleanup of its service cgroup.

## Packaging and support

Ship the Python helper next to `run-live-test-agents.sh`. The separate optional
`install-live-test-agents.sh` checks its presence and pidfd capability before
writing the unit; supervisor startup repeats the gate before state/API/phone
work. The main Kazoo installer already installs `python3` as a common package.
This fixture additionally needs Python exposing `os.pidfd_open` and
`signal.pidfd_send_signal` and a supporting Linux kernel. The actual read-only
self-pidfd probe, not a version-string guess, controls admission. Unsupported
Python/kernel installations fail closed;
there is no fallback to Bash kill. This does not add a dependency to ordinary
Kazoo call handling or automatically start the fixture service.

## Validation and activation boundary

Run the pure mocked tests:

```sh
python3 -I scripts/test-phone-process-identity.py
bash scripts/test-live-test-phone-identity.sh
bash scripts/test-live-test-phone-recovery.sh
bash scripts/test-live-test-agent-control-bind.sh
```

The Python suite mocks every proc/pidfd/signal operation. Shell suites mock
SIP, contacts, statuses, process identity and signals; no live calls or service
changes occur. The existing `test-live-test-agents.sh` monitor mock was updated
to the new identity boundary, but that complete suite includes a SIPp parse
invocation and must not run during a no-live-action window.

This is source protection, not live activation proof. The currently parsed
Bash supervisor cannot acquire these new arrays/functions merely because the
file changes. Any future renewal requires its separately reviewed exact
ownership, zero-call, roster-preservation and service-lifecycle gates. Do not
use a normal restart of the old supervisor as a way to install this protection.
