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
Seven tests execute the real helper with private adapters: active/inactive
cache, nonstandard command refusal, package failure, cache-stop failure, timer
restoration failure and dry-run. No real OS service is touched by those tests.
Native helper validation is pending; do not infer it from the ongoing earlier
installer process, which already loaded its original shell functions.
