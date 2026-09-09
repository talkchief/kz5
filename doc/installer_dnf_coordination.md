# DNF metadata refresh contention

The final empty-data installation exposed a long package-lock wait after
compilation and SUP validation. The owner was the OS's standard
`dnf-makecache.service` (`/usr/bin/dnf makecache --timer`), not a package
installation. The background job eventually failed on its own and released the
lock; no process was killed and the first installer attempt was not restarted.

`dnf_transaction` in `scripts/install-kazoo5.sh` now pauses an active metadata
timer for its transaction, checks the cache service's exact command before
stopping it, and restores the timer's previous active state on success/failure
or ordinary termination signals. It never changes the timer's enabled state.
Stops and restoration have60s limits. Other package-manager owners are never
terminated: `exit_on_lock=True` makes contention fail promptly instead of waiting
indefinitely behind an unknown transaction. The operator can retry once that
transaction finishes. SIGKILL cannot run shell cleanup; if the installer itself
is forcibly killed, check and restore the previously active metadata timer.

The wrapper covers normal package installs and Node.js module mutations.
The full installer holds one pause across installation and configuration
persistence, including nested media/package functions. Peer install1 exposed
that pausing/restoring for every individual call exhausted the timer's systemd
start limit (`Result=start-limit-hit`) despite successful package transactions.
The failed receipt remains `/var/lib/kazoo5-install-lab/apps-peer-install-1.log`.
The corrected batch boundary preserves the timer with only one stop/start for
ten nested package calls. Standalone helper use still acquires its own guard.
Ten tests execute the real helper with private adapters: active/inactive
cache, nonstandard/multiple command refusal, package failure, cache-stop failure, timer
restoration failure, dry-run, nested batches and resolved-config persistence.
No real OS service is touched by those tests. The corrected full peer installation
passed on source `9764bc2`, receipt
`/var/lib/kazoo5-install-lab/apps-peer-install-2.log`; the metadata timer was
active/enabled with Result=success after normal installer completion.
Native helper validation passed in `kz5-cold-kazoo-apps` using the committed
helper (`33254c0`, installer SHA256
`96a56bc5115d8512535f4b782e1f8c3c131f06821478009cc09aafae2e077f8c`).
With the real metadata job started immediately before the helper, its explicit
pause message was observed; `dnf_install --cacheonly bash-completion` completed
successfully and the timer remained active/enabled afterward. The package was
already installed: this tests actual coordination and DNF invocation, not a new
RPM download. A prior inactive-job native invocation passed too. The corrected
helper is on main44 in `/opt/kz5`; no applications rebuild is required for this
installer-only change. The final cold first install ran its original `e8e3a46`
functions and passed without this intervention after the cache job ended itself.
