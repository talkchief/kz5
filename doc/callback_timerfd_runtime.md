# Callback RTP timing — captured runtime evidence

September 9, 2026. CALLBACK-RTP-01 remains open. Callback registration,
unanswered-first retry and the second agent bridge worked in this isolated case;
the strict returned-audio timestamp gate still failed. No production timer,
FreeSWITCH source, voice asset or acceptance threshold was changed.

## What is now proved

The single instrumented run is retained at
`/var/log/kazoo-acceptance/20260909T012606Z` on development server10.1.0.44.
The exact returned RTP SSRC and before/after timestamps match runtime probes:

| RTP timestamps | timerfd expirations | extra RTP clock | packet arrival interval |
| --- | --- | --- | --- |
| 4160 -> 4960 | 5 | 80 ms | 119.991 ms |
| 5120 -> 5440 | 2 | 20 ms | 20.004 ms |

Both timer reads returned8 bytes, timer_next returned success, tick/samplecount
advanced by the expiration count, and get_next_write_ts copied that samplecount
to the transmitted timestamp and returned marker1. The packet marker is also1.
This establishes the actual timerfd-to-RTP transition, not just an offline model.
It does **not** establish why the write timer accumulated these expirations or
justify forcing linear timestamps or disabling timers globally.

The complete4.331-second EN recording matches the ordered payload with
correlation0.999995 and no packet sequence loss. Digit1 arrived1.046532 seconds
after prompt completion, within the saved three-second response window. The
fixture's timeout was conditionally restored15->3->15. Later aggregate log/core
and agent-readiness gates were not reached after the strict audio failure.
Native negative confirmation-expiry remains a separate unverified case.

## Exact jobs and evidence

- Diagnostic dependency installation: `kz5-callback-trace-tools-main44-20260909`,
  terminal success; bpftrace0.24.2 and GDB installed, no FS restart.
- Probe dry-run:26a5ec, exit0, attaches/detaches with zero calls.
- Trace: `kz5-callback-rtp-trace-main44-20260909b`, observer77276; stopped after
  the case, TRACE_END and child exit0. Log:
  `/root/kz5-acceptance/callback-rtp-trace-main44-20260909b.log`.
- Callback: `kz5-callback-rtp-case-main44-20260909`,12150/f70fca, terminal exit1
  in3m55.362s,75.4MiB. Log:
  `/root/kz5-acceptance/callback-rtp-case-main44-20260909.log`.
- Offline exact correlation:63911/bdbdb0, exit0. Receipt:
  `callback-timerfd-correlation.json` inside the retained run directory.
- Post-case945a50:zero calls. b4dbe5:apps/eCallMgr/FreeSWITCH active.

SHA256 pins:

- Loaded FreeSWITCH library: `9acb516070fb516767faef3a8f2ab521b9fdf8fe9763ce8333fc25ec3743f3f5`.
- Trace log: `afb8b2e2dfaf8bef6e47b146f466db007d54408f9b80b2167598ab7039cc4441`.
- Returned capture: `d42a93e8b76544d43b021cba2332f6f9305e93c3194cabe9c2b397f61d66a455`.
- Immutable EN WAV: `4ad5798a81aac354568322250d723ad8cd63a789793255c3584c20486a3bcfb3`.

## Diagnostic source and limits

`scripts/test-fixtures/trace-callback-timerfd.cjs` verifies the designated dev
address, native PID, zero calls at entry, exact mapped library inode/path and
pinned source hashes. File-only GDB derives field offsets; it never attaches
to or stops FreeSWITCH. The companion `.bt` traces only numeric timing metadata.
The runner bounds attachment to5–300seconds. Use a private bounded service/log
and the existing independently locked callback fixture. It is an opt-in
diagnostic, not an installer dependency or permanent service.

The first idle probe run was stopped because `-k` logged normal missing-map
lookups. The instrumented case used default warnings, but produced2,070 map
cleanup warnings (503,176-byte total log). These are recorded explicitly in the
correlation receipt. The committed probe initializes/reset its per-frame map
entries to prevent those warnings; that cleanup revision was not used for this
call. Instrumentation overhead has not been quantified: this is causality
evidence, **not a performance or uninstrumented playout acceptance**.
Trace observer77276/d10b1f is terminal success (4m44.982s,61.4MiB); the
cleanup revision also passed a zero-call attach/detach dry-run after explicit
map-value type corrections. No second call was made to exercise that revision.

`correlate-callback-timerfd.cjs RUN TRACE_LOG` recomputes the existing payload,
SIP and bridge diagnosis, then requires one exact runtime event for every
returned timestamp gap. It refuses to overwrite its additive receipt and
never reclassifies the original strict failure. No account writes/provider
requests occur in offline correlation.

Next focused action: inspect the returned-prompt playback transition that delays
the timer read, especially the120ms packet interval immediately before speech
and the subsequent two-expiration read. Preserve this captured proof; do not
repeat the same callback without a specific new observation or candidate fix.
