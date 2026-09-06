# Gemini runtime regression suite

Run from a prepared Kazoo checkout containing the directly tracked ACDC source, compiled Erlang dependencies and the checked-in Gemini voice assets:

```sh
bash scripts/test-acdc-gemini-runtime.sh
```

The suite is offline. It copies the ACDC source tracked in `kz5` into a private directory and reverses the retained language patch to reconstruct the **historical media compatibility baseline**. It verifies reverse applicability of the baseline patch for the media modules and header it compiles, and records hashes of the bundled inputs and every projection patch. Agent/queue FSM changes are covered by the source suites and do not need to match historical patches for these media tests to run. `ACDC_REF` records upstream provenance; no nested repository or network fetch is required. This suite does not validate all bundled media/language behavior, install media, or change application BEAMs. Use the source unit/strategy, agent recovery and language suites for current source coverage.

Production modules are built with `-Werror +warn_missing_spec` and the Lager parse transform, separately from `-DTEST +debug_info` builds. Their imports and exports are checked so a staged `acdc_language` module or TEST-only entry point cannot slip into the production artifact. The private test VM removes code paths containing the staged language BEAM and uses a test-only storage stub.

The 62 tests cover all165 exact immutable asset mappings, custom/legacy account overrides, missing and tampered imports, prepared AR/HE telephone-digit order, gated incomplete language defaults, preserved legacy custom paths, queue-locale media lookup, real prompt-URI idempotence, periodic announcement scheduling and real timers, manager loss, cancellation/backpressure, callback protocol, truthful error feedback, and accepted-callback success lifecycle. Deliberately killed temporary test workers produce expected supervisor reports. They are not live-service crashes.

For a quick replay/map/production-compilation check without the longer EUnit cases:

```sh
bash scripts/test-acdc-gemini-runtime.sh --replay-only
```

An optional `--project-root /path/to/kz5` supports packaging and testing from another working directory. The runner does not clone or fetch missing dependencies; it requires the bundled source and retained compatibility patches, not a separate ACDC Git checkout or locally resolvable upstream commit. It snapshots the default patch and rejects a result if the parsed ACDC provenance pin, aggregate patch, verified asset map, runner or compiled test source changes during the run. Asset manifest/audio QA runs again at the final check. Unrelated installer settings do not change those actual replay inputs. Small offline freshness tests cover changed pin/patch/map/test inputs, malformed pins and missing files. Temporary archives and test BEAMs are removed on exit.

## Deterministic map

```sh
node scripts/generate-acdc-gemini-map.cjs --check
```

The map generator uses repository-relative source assets and the existing strict importer to verify their bytes. `--output /path/to/table.hrl` can check an isolated replay. `--generate --output /new/path/table.hrl` creates a new file only; it never overwrites an existing table. The original generated header is intentionally retained for exact byte compatibility with the frozen165-asset table.

These tests establish source-level/offline regression coverage, not complete production or native-speaker approval. English default numbers and legacy custom playback still depend on native numeric speech; newly generated non-English callback defaults remain gated until auxiliary/numeric completion. Real SIP/audio/log/cleanup acceptance is a separate deployment gate.

Do not copy `scripts/test-fixtures/gemini-runtime/kz_datamgr.erl` into any application source or runtime directory. It is intentionally confined to this suite.

After recovery merge `8548b98`, session `93794` independently passed all 62
historical tests, map, production checks and final freshness on 2026-09-06
12:40:29–12:44:54 UTC. It used the documented 900-second allowance with
384 MiB memory, zero swap and 50% CPU; systemd recorded 174.1 MiB peak.
This supersedes the incomplete 120-second invocation for full-suite acceptance,
not its retained failure record. See `doc/acdc_agent_recovery.md` for the input
hash and the distinction between historical projection and live native media.

## Resource-capped current-source receipt — 2026-09-06

On the live small host, run the offline suite only through the serialized
guard after checking the maintenance/workload window:

```sh
bash scripts/run-kazoo-validation.sh --runtime-sec 900 -- /usr/bin/bash /opt/kz5/scripts/test-acdc-gemini-runtime.sh
```

The 00:05–00:09:46 run passed all 62 tests, production compilation/export/import
checks, exact 165-asset map and final input freshness. Default patch SHA256 was
`0d1b87addc16ca631069a1da5b535fdb7240577c314856cd4c166d6412d5d3e3`.
Systemd recorded 181 MiB peak and 2m10.071s CPU under a 384 MiB memory cap,
zero swap and a half-core quota. Observed cgroup OOM counters were zero.

The preceding capped rerun was cancelled by one test's ten-second outer EUnit
budget during mock compilation. That test now allows thirty seconds for setup
and execution; its inner playback deadlines, timing assertions and production
timeouts are unchanged. The failed run is not counted as a pass. This remains
offline source evidence, not post-incident live callback or capacity acceptance.
