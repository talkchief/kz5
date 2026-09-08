# Focused callback, bridge and installer acceptance — September 8

This record distinguishes deployed behavior, actual acceptance and remaining
release gates. Start with `../PROJECT_HANDOFF.md` and `../PROJECT_TASKS.md`.
No Gemini generation occurs in any of these acceptance commands.

## Installer validation window

The normal apps/eCallMgr installer from pushed `9642413` compiled the release,
restarted apps, passed datastore readiness and verified 796 media documents in
both runtime maps. The outer validation unit stopped it at its 1800-second
deadline on September 8 at 00:59:06 UTC. Session4728 exited1 (b741fb); journal
f5c7d5 records `timeout`. This is not a complete installer pass.

`run-kazoo-validation.sh` now permits an explicit `--runtime-sec 3600` for the
next authorized full build. Default900, memory128–384MiB, CPU50%, no swap,
task128 limit, protected global lock and memory admission are unchanged.
The private92-case regression suite passed48334/9b13b6 and repository rerun
53441 passed. Actual short unit e2026b confirmed RuntimeMaxUSec=1h, CPU500ms
per second, selected256MiB cap, swap0 and tasks128 while executing the12-case
DLQ regression suite successfully. A full installer rerun is still required.
See `validation_resource_guard.md`. Do not increase a running job's timer or
restart merely because a tool observation timed out.

## Registered mobile consumer

New reproducible acceptance entry point:

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 256 --reserve-mib 512 \
  --runtime-sec 300 -- \
  /usr/local/lib/kazoo-push-bridge/current/venv/bin/python -B -I \
  /opt/kz5/scripts/accept-push-bridge-consumer.py \
  --run-isolated-local-consumer-proof
```

This is root-only and creates a random UUID-local RabbitMQ vhost/user on
127.0.0.1. It never loads production bridge credentials or contacts providers.
It uses the actual `BridgeRuntime.run`, registered consumer, freshness logic,
thread pools and owner-thread settlements; only provider results are synthetic.

Actual session83390/9d4620 passed. Protected evidence:
`/var/log/kazoo-acceptance/kz5-retry-proof-db017d0e-c514-4bbe-8874-296d8a0d69fe/receipt.json`.
Independent readback2d7db8 confirms:

- One consumer registration; zero work-queue Basic.Get calls.
- Synthetic503 then200 gives broker delivery counts0,1 and two dispatches.
- A companion message is acknowledged before the delayed retry is requeued.
- Exhaustion gives counts0,1,2, exactly three dispatches and unchanged DLQ body.
- Work/DLQ queues are empty after consumer shutdown; source pins are stable.
- Both generated broker resources are removed; zero provider calls.

The repository suite21449/6e9d43 passed10 consumer tests,9 unbound-DLQ tests
and10 baseline retry-harness tests. Offline tests are not broker acceptance.
This result does not prove mobile delivery, broker restart, filled-DLQ behavior,
remote AMQPS, production routing, automatic recovery or exactly-once delivery.

## Temporarily unavailable dead-letter route

Initial actual test40711/644081 failed with `recovery_deadline`, not a guard
timeout. Receipt:
`/var/log/kazoo-acceptance/kz5-retry-proof-1617a68a-3c0a-45ae-a6e3-c6b566ff5ab8/receipt.json`.
It confirmed the single publish, permanent rejection, missing route for5133ms,
and restored route, but no readback within60seconds. Both temporary resources
were removed and all consumed sources remained unchanged. Do not report this
as message-loss proof or successful recovery.

Installed RabbitMQ3.13.7 `rabbit.app` sets
`dead_letter_worker_publisher_confirm_timeout=180000` milliseconds. The pinned
[worker source](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbit/src/rabbit_fifo_dlx_worker.erl#L333)
buffers unroutable messages and schedules another attempt using that interval.
Rebinding alone does not cause immediate delivery. The revised test uses240s
recovery, an absolute300s case budget and10s channel RPC bounds. It changes
neither broker configuration nor production code. All12 revised offline tests
pass cf725c and repository e2026b, including a simulated180s retry and rejection
of a lost message despite empty ready counts. Actual revised proof52763/f08152
PASS; protected receipt:
`/var/log/kazoo-acceptance/kz5-retry-proof-209af0aa-e241-441e-9b65-5e30b9a6438a/receipt.json`.
Readback ac566a confirms exact retained-body recovery174934ms after route
restoration, one confirmed publish and synthetic dispatch, no republish,
stable sources and cleanup of both generated resources. No provider calls,
full-DLQ, broker-restart or exactly-once claim.

## Explicit callback language acceptance

`test-acdc-callback-retry.sh` now accepts `--language` with exactly `en-us`,
`he-il`, `fr-fr`, `es-es` or `ar-sa`. It changes the existing isolated fixture
queue's announcement language only when explicitly selected, verifies readback,
and binds the full confirmation audio proof to a matching installed WAV.
Inherited language overrides are cleared. Unknown/repeated locales, wrong
account, changed reference hashes and custom callback media are refused.

Scope stays account7807ad61761269a1ccec833dde63f621, queue2000, internal
caller1001 and agent1002. No MASTER/PSTN calls. Busy-agent, key6, complete
confirmation before BYE, two-second release delay, unanswered first attempt,
persisted retry and accepted second native bridge checks remain mandatory.
The retained fixture is not a full cleanup acceptance claim.

The private eight-group locale suite39167/c43f5e passed. Its first run exposed
a test loader incorrectly evaluating a shebang inside `new Function`; the
loader now strips only the first shebang line. No runtime code was affected.
Repository suite53441/32d30a passed92 guard cases,8 locale groups,88 retry
groups,13 cleanup groups,79 registration-audio cases,96 packet cases and27
service-scope cases. Live non-English retry evidence is recorded separately;
these tests alone do not establish live passes.

For one explicit locale at a time, create a fresh protected reference directory
and capture the installed WAV. Example for Hebrew (all commands run inside the
normal validation guard with a600-second outer bound):

```sh
callback_reference_dir=$(mktemp -d /var/log/kazoo-acceptance/gemini-reference.XXXXXXXX)
node scripts/test-fixtures/callback-gemini-reference.cjs capture "$callback_reference_dir" he-il
node scripts/test-fixtures/callback-gemini-reference.cjs verify "$callback_reference_dir/acdc-callback-success.ulaw" he-il
bash scripts/test-acdc-callback-retry.sh --prepare-only --language he-il \
  --registration-mode entry-only --transport internal \
  --confirmation-reference "$callback_reference_dir/acdc-callback-success.ulaw"
bash scripts/test-acdc-callback-retry.sh --live --keep-fixture --language he-il \
  --registration-mode entry-only --transport internal \
  --confirmation-reference "$callback_reference_dir/acdc-callback-success.ulaw"
```

Use matching locale arguments everywhere. Capture reads authenticated local
system_media and checked-in artifacts; it never generates audio or writes the
database. Prepare-only makes no API writes or SIP calls. Live setup modifies
only the previously authorized owned fixture, whose queue is intentionally
retained afterward. The original saved configuration remains available to the
guarded fixture cleanup tool; unresolved historical callbacks are not rewritten.
An omitted `--language` preserves existing queue language, not an implicit reset
to English. Select `--language en-us` explicitly to restore the diagnostic queue
to English. Normal accepted callback conversations remain up for their existing
100-second media/teardown observation; a connected call is not yet a test pass.

### Live retry results

| Locale | Evidence directory under `/var/log/kazoo-acceptance` | Result |
| --- | --- | --- |
| EN | `20260907T232852Z` | Prior-build PASS1297/784164 |
| HE | `20260908T010737Z` | PASS8443/53f15d after current apps rebuild |
| FR | `20260908T011230Z` | PASS15515/f1b8d1 after current apps rebuild |
| ES | `20260908T011714Z` | PASS37303/93b8d4 after current apps rebuild |
| AR | `20260908T012152Z` | PASS56725/d5de4c after current apps rebuild |

HE independent readback4593c5 identifies the immutable Hebrew success asset,
exactly one observed registration digit6, complete reference audio, durable
retry_wait and two attempts with15s retry policy. Retained fixture and native
listening/complete-response limitations still apply.

### Returned-call audio diagnostic, not accepted

The separate `callback-returned-reference.cjs` and
`assert-callback-returned-audio.cjs` helpers have passing private and repository
synthetic groups (49743/eda7d6 and38329/92034c). HE reference capture50498
passed against the checked-in and installed returned-confirmation WAV; receipt
`/var/log/kazoo-acceptance/returned-reference.UVWkwpIi/reference.json`, SHA256
`4c0024b567b660049b18663281d8ea6af8a408f06d7a83a014c5c36c19baf693`.
Actual offline replay failed its strict RTP coverage gate. Read-only diagnostic
79134/7eacd4 measured a160-sample gap inside the matched42648-sample phrase;
correlation0.999992 alone does not establish every sample was received.
No supplemental PASS was written and no original evidence was changed. This
does not reverse the separate successful registration/retry checks, but full
returned-recording delivery remains unproven. Native listening and persisted
language continuity also remain separate from waveform correlation.

## Separate-host installer gates still open

Passing installation on this already-provisioned development host does not
prove fresh deployments. Remaining work includes fresh-clone/empty-cache Rocky9
roles and ALL, full FreeSWITCH native build, saved-settings replay, reboot and
actual remote DB/broker/media integration. Explicit media connectivity must be
required in split-host acceptance rather than relying on the installer's auto
mode or an empty configured FreeSWITCH list.

Standalone Monster UI currently delegates catalog registration when no local
apps node exists; remote Kamailio delegates ACL/discovery without local
eCallMgr. Those manual boundaries need review against the requested automatic
separate-host workflow, not a blanket installation-success claim. See
`install_kazoo5_script.md` and `monster_ui_preserving_install.md`.

Matching TLS private-key, remote AMQPS and designated Android/iPhone delivery
evidence remain absent. Dashboards stay postponed. Older dated installation
snapshots may describe superseded ACDC ownership/intercept/UI failures; they
are historical evidence, not the current open-bug list.
