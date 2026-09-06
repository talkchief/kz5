# Announcement mailbox fairness

Source fixed and privately tested on 2026-09-06; not deployed.

`acdc_announcements` previously used `receive ... after Wait` even when the
monotonic deadline had elapsed. Erlang consumes matching queued messages before
an `after 0` clause. A sustained backlog could therefore postpone the playback
timeout or a scheduled offer indefinitely. Its pre-playback event drain also
had no event-count bound.

The worker now services elapsed deadlines before receiving another message.
Before preparing/sending audio, each event drain handles at most 256 matching
events. If another matching event remains, it exits normally rather than play
past an unchecked bridge, usurp or hangup event. The supervisor's existing
`temporary` policy means no automatic replacement worker is created. No global
media flush, caller hangup, queue membership change or callback write is added.

This deliberately favors the timeout once a pending playback deadline expires,
even if a matching completion is already queued. The event budget applies per
drain (preparation calls it twice), not to wall-clock execution, total mailbox
memory or selective-receive scanning through unmatched messages. Native media
ownership and cancellation are separate, unresolved requirements.

## Evidence and reproduction

Run from the kz5 root with the existing Erlang dependencies:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 320 --reserve-mib 768 \
  --runtime-sec 60 -- /usr/bin/unshare --net -- \
  /usr/bin/bash scripts/test-acdc-callback-announcements.sh
```

Before the production fix, the existing nine tests passed but two added
regressions failed: an expired worker consumed all 128 unrelated queued messages
instead of exiting immediately, and the pre-playback drain returned after
consuming all 1,024 events rather than stopping at the safety limit.

After the fix, all 12 tests passed, including the new exact-256-event boundary
and correlated-completion case. The runner also compiled the production
announcement worker, supervisor and queue manager with `-Werror`, without TEST,
before compiling private test BEAMs. Existing cases exercise real worker timers,
separate/combined schedules, readiness, terminal events and temporary-supervisor
lifecycle. Media publication and event bindings are mocked; this is not a live
audio test. Supervisor `reason: killed` reports are expected fault injections in
that isolated Erlang VM, not live Kazoo crashes.

## Deployment and installer scope

The corrected module is tracked directly in `applications/acdc` in kz5. The
installer includes bundled ACDC in `make apps` and does not apply the historical
external ACDC patches over it. No nested ACDC Git repository is involved.

Coordinated deployment remains required. In particular, this change does not
fix the separate endless-hold playback queue blockage or certify the observed
30-second callback offer and key-6 confirmation. The installer also still needs
content-aware stale-BEAM detection (INST-12); timestamp-based rebuilding alone
is not proof that a deployed module matches its current source.
