# The installer's forced rebuild raced with itself

## Failure

Private lab, `apps-peer-install-27` (source `fd8a86d`, September 18, 2026), **FAIL**,
log retained at `/var/lib/kazoo5-install-lab/apps-peer-install-27.log`:

```
compile: warnings being treated as errors
src/kz_auth_listener.erl:13: behaviour gen_listener undefined
make[1]: *** [Makefile:44: kazoo_auth] Error 2
```

The guest kept running its previous runtime (the failure is in the build step, before
any service is touched; stack health `failures=0` afterwards). Installs 26 and 28 of
the same guest, and every other install that day, passed: the failure depends on timing.

## Cause

The installer compiles with `KAZOO_FORCE_RECOMPILE=1`, because artifact mtimes are not
proof of current source. `core/Makefile` builds `kazoo_stdlib`, `kazoo_amqp` and
`kazoo_data` serially first and then visits every core application, those three
included, in its parallel pass; the installer likewise builds `webhooks` before the
parallel applications pass. "Forced" applied to every visit, so `kazoo_amqp` was
recompiled a second time *while* its dependents compiled. `erlc` rewrites a beam in
place; a dependent that loads `gen_listener.beam` in that instant sees no behaviour,
and OTP 26 reports that as a warning, fatal under `-Werror`. The earlier
"build webhooks first" step had the same hole for `skel` and `gen_webhook`.
The run that failed had the host busy with a 100-call soak, which widened the window.

## Fix (`8800b2b`)

- `scripts/install-kazoo5.sh` generates one build identifier per build
  (`<UTC time>.<pid>`) and passes it to its three forced passes. It is never taken
  from the environment: a reused identifier would find old stamps and skip the rebuild.
- `make/kz.mk`: with `KAZOO_FORCE_BUILD_ID`, an application's forced rebuild leaves
  `ebin/.kazoo-forced-<id>` (older stamps removed); a later visit in the same build
  finds it and is an ordinary incremental make. No identifier: every visit is forced,
  as before. A failed compile leaves no stamp.

## Evidence

- `node scripts/test-kazoo-force-recompile.cjs` (real `erlc`, extracted rules, 21
  commands): forced once per identifier and beams untouched on the second visit, forced
  again with a new identifier, always forced without one, no stamp after a failed build.
- `node scripts/test-ecallmgr-current-build.cjs`: one identifier shared by the three
  passes, format checked, never inherited, failure at each stage still stops the install.
- Native, `apps-peer-install-28` (`8800b2b`) **PASS**: `src/gen_listener.erl` compiled
  once (twice in install 26), `gen_webhook.erl` once (three times in install 26).
