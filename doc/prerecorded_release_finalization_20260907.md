# Prerecorded voice release finalization — September 7, 2026

This records bounded development-host evidence, not production certification.
The authoritative remaining-work register is `../PROJECT_TASKS.md`.

## Deployed runtime and publication

Pushed source `dd39d90` was fully compiled and release-assembled by the main
installer. Apps and eCallMgr are running that build. The enclosing validation
job reached its 30-minute limit during later verification, so this is **not**
a completed uninterrupted installation.

The subsequent real runtime probe (`95443/8dee1a`) verified eleven exact
production BEAM paths/hashes and loaded module MD5s, 796 media documents,
1,592 mappings, 95 position playlists, ten callback preparations/readbacks,
and 80 wait cases. It created no calls, queues, or provider requests.

Private evidence is under `/root/kazoo-prerecorded-release.F8qJut`:

- `production-beams.json`: actual compiled module identities.
- `probe-options.json`: reproducible real inputs and source/receipt pins.
- `runtime-receipt.json`: native result; SHA256
  `f0f59a60be6fb8607ff15f146e35fbdf4c2dbe51aaed2e17eee4453cfe3f7db0`.

The initial `/var/lib/kazoo` evidence location was rejected because its parent
is service-owned. Task-owned evidence was moved under root-owned parents; the
protection was not disabled.

Publication (`71766/1727f7`) used the checked-in publisher and real receipt,
retaining its installer ownership marker. The effective configuration path
is now `/etc/kazoo/acdc/language-capabilities.json`, SHA256
`198866b70bc0805b32ae8eab385355a172931e114939960c59ea1c69d1290221`.
All five languages are selectable. Full readiness and native listening approval
remain false. No same-invocation successful-build flag was fabricated.

The old explicit web-root capability file was inspected as a root-owned,
all-negative schema-1 legacy artifact and left unchanged. Only its effective
configuration reference was migrated. Installer code now handles this exact
legacy location; unrelated or reviewed custom paths are not adopted silently.

## Installer fixes

`wait_kazoo_datastore_ready` replaces the fixed five-second delay before apps
and eCallMgr startup configuration. It requires a real local driver/server pair
and a successful read-only server-info response. RPCs and the overall retry
loop are bounded; raw connection errors are suppressed. The 26 shell regression
cases and both actual warm-node checks passed. Actual eCallMgr cold restart
`34255/656bb8` subsequently passed the new gate and full native eCallMgr checks,
with zero channels before restarting. Apps cold startup remains separate.

`releasePlans()` now scopes a private conversion replay cache to a single
synchronous five-language plan. The cache is bounded to 32 MiB/1,024 entries and
cleared in `finally`. Keys include the exact resampling recipe and actual master
bytes. Returned buffers cannot mutate cache entries. All source reads, metadata,
history, QA, version checks and comparisons against actual telephony bytes still
run. No persistent cache or cached validation verdict is trusted.

Fifteen isolated cache regression groups passed. The actual all-five reference
preparation also passed and produced an input identical to the prior uncached
native proof. Full installer timing acceptance is not yet established.

## Live acceptance

Installed reference index: `/root/kazoo-prerecorded-reference.PvNvXj/index.json`,
SHA256 `588d9e5ab556ee1cc7968d6d646f0e21d2fa55c5257c307dc69dab95acd2f78a`.
Preparation read installed attachments twice and made zero Gemini requests.

English live evidence: `/var/log/kazoo-acceptance/20260907T231909Z`.
Offers arrived at 30.042/60.042 seconds; the full position-one playlist began at
45.042/75.042 seconds. Exact received PCMU, no entry/extra announcement, normal
teardown, runtime/log gates and conditional cleanup passed (`71221/06d203`).

The remaining-locale batch also exited0 (`75174/44d3e7`). All runs passed the
same audio/timing, no-entry/extra-audio, runtime/log and cleanup gates:

| Language | First offer / position (seconds) | Evidence directory under `/var/log/kazoo-acceptance/` |
| --- | --- | --- |
| EN | 30.042 / 45.042 | `20260907T231909Z` |
| HE | 30.049 / 45.049 | `20260907T232112Z` |
| FR | 30.051 / 45.051 | `20260907T232304Z` |
| ES | 30.065 / 45.065 | `20260907T232456Z` |
| AR | 30.046 / 45.046 | `20260907T232647Z` |

Second offers and positions occurred30seconds after the corresponding first
ones. This verifies the complete position-one playlist and offer-six recording,
not every numeric value, live wait-time, or every callback response.

See `acdc_five_language_live_audio_acceptance.md` for the serial test commands.
Post-build callback retry `1297/784164` subsequently passed: key6 after five
seconds with an agent busy, full Gemini success audio before BYE, two-second
wait then release of the busy agent, unanswered first return, durable retry_wait,
second return accepted with key1, and reciprocal native bridge. Runtime/log
and teardown checks passed. Evidence is
`/var/log/kazoo-acceptance/20260907T232852Z`; isolated internal1001 fixture
retained deliberately. This does not prove physical operator1000 acceptance.

UI build/deployment and `/apis` publication succeeded in `73828/bc2596`, but
the overall installer stopped at CSV Onboarding's empty-icon catalog field.
The first npm attempt had OOMed; bounded heap/download concurrency allowed
the successful build retry. Catalog fix deployment and normal installer retry
are tracked separately. Actual authenticated unified editor/API plus extracted
deployed AMD language functions pass `59484/322097`, with all five choices
enabled and210media entries; zero queue writes/provider requests. An initial
probe incorrectly looked for unbundled app.js rather than production main.js.
Native listening, live wait-time and full installation acceptance remain open.

## September 8: UI installer completion

Normal `bash scripts/install-kazoo5.sh monster-ui` completed with exit0
(`44420/6ef89a`). It reused the verified owned production build, preserved and
verified all ten selected app catalog registrations, verified the served index,
main bundle and config, checked same-origin Crossbar JSON, enabled/started
nginx, and saved deployment settings through the normal installer path.

The blocker was a valid `icon: ""` in CSV Onboarding metadata. The helper now
treats empty icon as absent, retaining screenshot name/type/size/duplicate
checks and preservation of existing documents. The fix is carried in the
Crossbar aggregate plus exact prior-state transition patches. Twelve catalog
tests, production compilation and all87 source-transition cases passed before
deployment. The first new malformed-null test accidentally removed the field
using kz_json:set_value; literal construction corrected that fixture without
removing cases or relaxing production validation. A stale81-case suite total
was updated to87; the complete suite was rerun successfully.

Only the stateless catalog helper was compiled/deployed for this continuation;
no whole-node restart or long-lived FSM migration was needed. Exact loaded
MD5 and absence of TEST exports were checked. Old application/release BEAMs
are recoverable under `/root/kazoo-catalog-deploy.Q6EBiJ`. New BEAM SHA256:
`79528cf9362e9742c74b62bb079f091e5372fa316da59400258c066e2db19a95`.
The first private deployment preflight used code:check_old_code instead of
the erlang BIF and refused before any write; that preflight was corrected.

This is a successful normal UI component installation on the development
host. It is not proof of an uninterrupted apps/eCallMgr build, clean-server
installation, separate-server deployment, TLS, or production certification.
