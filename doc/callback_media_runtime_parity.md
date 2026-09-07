# Callback media runtime parity — September 7, 2026

The eight focused callback media modules already match current canonical source
on the apps node. This supersedes older blanket statements that this particular
cohort still needed deployment. It does not certify queue settings, actual WAV
playback, the full dependency set, eCallMgr/native behavior or the UI.

Root full canonical test `fada33/fee8c1` passed all87 tests, including feedback,
menu, returned caller, independent announcement clocks and success ownership.
Input digest remained
`5bcd7e76678f42988001ad768c391fd272401d2ec8b6d4b48eab975a73759ea8`.
The private network-isolated run used192MiB/512MiB reserve/600-second deadline.
Expected killed-worker supervisor reports came from the test fixture, not the
live service. No test installed BEAMs or placed calls.

## Reproducible focused build

```sh
bash scripts/run-kazoo-validation.sh \
  --memory-mib 128 --reserve-mib 512 --runtime-sec 120 -- \
  /usr/bin/unshare --net /usr/bin/bash \
  /opt/kz5/scripts/build-callback-media-candidate.sh
```

The builder compiles only the eight named modules, without TEST, and retains
source/dependency checksums, artifact hashes, exports/imports/BEAM MD5 metadata
and a terminal receipt. It never installs or loads candidate code. Prepared
local dependencies are pinned inputs, not fresh-build or external-host proof.
Root `760395/afb084` passed; retained output:
`/tmp/kazoo-callback-media-build.68ghEg`.

Root disk comparison `7b9401/fcf084` found all eight installed executable MD5s
equal to the fresh build. Read-only metadata RPC `0ad7ce` independently confirmed
the actual loaded modules on `kazoo_apps@kz5-testing`, with no old-code slots:

| Module | Fresh, installed and loaded BEAM MD5 |
| --- | --- |
| acdc_gemini_prompts | a7a0587aad759a83ceb57c4d85162171 |
| cf_acdc_member | 88409de7b996146f4b79d7a0a9f31f8d |
| acdc_callback_caller | 24e1b2ea416f93c8d24474658ad41c21 |
| acdc_announcements | 3741a4c92d98e3c44cb0e3f3cefb2a86 |
| acdc_announcements_sup | 99d505825d3097d666e1a3f02035a2d3 |
| acdc_callback_menu | d0fd907a7bce337b184e78da75405510 |
| acdc_language | b02a67629ea9001aae5acc10ccf6d6dc |
| kapi_acdc_callback | 44423e51e0f3e0291e25c859e74b181c |

MD5 here is Erlang executable-code identity, not a security signature or a claim
of byte-identical compile-info metadata. Artifact SHA-256 files are retained
separately. Loaded paths resolve under `/opt/kz5/applications/acdc/ebin`.

## Next actual-call gate

The existing offer harness passed prepare-only (`8d4b3b/70b363`): no API writes,
reference fetch or SIP traffic. Its historical reference capture still fetches
legacy canonical IDs, whereas the current built-in callback offer emits exact
versioned Gemini media paths. Do not arm that harness and misinterpret the
wrong audio reference as a platform failure. An explicit immutable-reference
mode is being prepared; preserve legacy tests and exact fixture cleanup.

Next: validate installed Gemini reference bytes, inspect actual scoped queue
settings and media dependencies, then test offers over hold and the requested
key6/confirmation/unanswered-first-attempt/retry scenario. Existing numeric
caller validation remains intact. Do not require completion of the experimental
native RTP rewrite unless actual normal-path evidence establishes the need.
No service restart, provider request or live-call test accompanied this check.
