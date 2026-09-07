# Callback offer: explicit thirty-second acceptance

The development harness now has an opt-in `--gemini-30` profile. It reuses the
installed immutable EN callback offer; no Gemini request or new recording is
made by the test. The normal `--gemini` and legacy profiles retain their prior
3/18/33-second schedules.

```sh
bash scripts/test-acdc-callback-offer-calls.sh --prepare-only --gemini-30
bash scripts/test-acdc-callback-offer-calls.sh --live --gemini-30 \
  --runtime-md5 ROOT_VERIFIED_LOADED_SCHEDULER_MD5
```

Run through `scripts/run-kazoo-validation.sh`, with no other guarded work.
The live harness requires the existing isolated acceptance account and loopback
SIP endpoints, no active calls, an exact loaded scheduler MD5, and the exclusive
acceptance lock. It creates only a marked temporary queue and extension2098
callflow. It never changes agent status or dials the master account/PSTN.

The queue has callback offer initial delay30 and interval30. Its separate generic
announcement interval remains15, but position and wait-time announcements are
disabled. The caller waits76seconds without pressing a key. Packet analysis
requires complete installed audio at30 and60seconds (+/-1second), rejects extra
offers (including45seconds), verifies quantified quiet audio before29seconds,
and requires continuous captured RTP, exact negotiated peer/dialog and normal
SIP teardown. Existing zero-capture-loss, service identity/restart, log, core and
conditional exact-revision fixture-cleanup checks remain.

This proves callback-offer scheduling with position playback disabled. It does
not prove concurrent position/MOH audio, key6 registration, returned-call retry,
other languages or production capacity; those have separate acceptance gates.

Offline validation `5639ab/session20396/d1d8e7` passed49 synthetic SIP/RTP
groups,33 fixture/ownership/Couch-CAS groups, scenario tests and shellcheck.
Thirty-second negatives cover early/extra/missing/wrong-time audio, partial
speech before the deadline, packet loss, wrong duration and invalid profiles.
Prepare-only/live-runtime inspection `31b03c/session75863/b9b3f5` passed with
zero calls and loaded scheduler MD5 `3741a4c92d98e3c44cb0e3f3cefb2a86`.
Live acceptance `2d290a/session16292/db354d` finished exit0. Evidence is retained
at `/var/log/kazoo-acceptance/20260907T162617Z`. Full5.171-second offer audio was
received at30.054 and60.054seconds, correlation0.999993 for each. Pre-offer
observation through29seconds contained zero energetic windows (34ms initial
no-RTP startup gap is explicitly not counted as observed silence). No extra
offer occurred. The call ended normally at76.006seconds, with complete captured
RTP. Service/restart, worker teardown, zero fresh scoped errors and core gates
passed. Final cleanup conditionally soft-deleted only the two marked temporary
documents and verified unrelated documents unchanged; zero agent-status edits.
