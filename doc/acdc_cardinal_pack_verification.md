# Prerecorded cardinal pack verification

Status: offline authoring prerequisite implemented and tested, September 6,
2026. No cardinal recordings were generated, imported or deployed by this work.
The complete language/callback release and production goal remain open.

## Tools and contract

- `scripts/acdc-cardinal-catalog.cjs`: pure five-language, full-range grammar
  and584 contextual recording roles. Linguistic/intro approval remains separate.
- `scripts/acdc-cardinal-pack.cjs`: provider-free manifest/WAV verification;
  never generates, imports, reserves a request or activates runtime readiness.
- `scripts/test-acdc-cardinal-pack.cjs`: reproducible offline regression harness.

The verifier enforces the exact catalog, transcript/context hashes, bounded
request ledger and immutable successful attempts. An indeterminate REQUESTING
attempt cannot become an implicit retry. It validates PCM16 mono24kHz masters
and8kHz telephony files, actual bytes, saved measurements and technical QA.
It rejects unsupported paths, symlinks, hardlinks, unsafe modes and changed files.

Matching duration and separate hashes do not establish a master/telephony
relationship. Successful verification replays a fixed local SoX14.4.2 recipe
against the master and compares the resulting PCM bytes with the telephony
payload. Conversion is high-quality resampling only: no trim, padding, gain or
random dither. `RESAMPLING` exports the exact recipe for the later authoring
tool. SoX receives a fixed executable/argument list, clean environment, bounded
stdin/stdout and deadlines. No provider credentials or network are used.

Declared transcript/delivery/intro/listening reviews are not authenticated
reviewer identities. Approval acceptance requires an independently pinned
approval-set hash; listening claims bind the exact locale asset set. Intro
audio is outside this pack and is explicitly **not verified** here. Technical
QA does not prove speech accuracy, natural delivery, runtime readiness or
provider provenance. The584 cardinal roles remain separate from the210 existing
callback assets and must not widen callback-only completeness checks.

## Test evidence

Guarded offline session52469 exited0: **13 groups /2,542 assertions**, all584
roles and1,168 synthetic WAVs. A same-duration900Hz telephony file, independently
rehashed to look internally consistent, was correctly rejected against its
500Hz master at both entry and complete-pack validation. Tests also exercise
SoX failure/version/argument/environment handling, retries, approval binding,
catalog mutation and filesystem rejection. Synthetic speech-free fixtures are
not language or listening approval.

Receipt: `/tmp/acdc-cardinal-pack-proof.lZXrt9/receipt.json`

SHA-256: `0d9f02f7749c43894bda2283bb2cd985728c8672f7d5a14289b68643a34c9740`

Source pins remained stable:

| File | SHA-256 |
| --- | --- |
| `scripts/acdc-cardinal-pack.cjs` | `a53f1ff78c55ab941a5bf3a7ba9a5525161a580e03573e42cde18287ffe20328` |
| `scripts/test-acdc-cardinal-pack.cjs` | `20d557bb9895405c801ab5bd103ea05b6d37658ba6bd47c060697fd415e46456` |

Run only after obtaining the serialized validation window:

```bash
bash scripts/run-kazoo-validation.sh \
  --memory-mib 128 --reserve-mib 768 --runtime-sec 60 -- \
  /usr/bin/unshare --net /usr/bin/node \
  /opt/kz5/scripts/test-acdc-cardinal-pack.cjs
```

The bounded one-time generator now exists at
`scripts/generate-acdc-gemini-cardinal-pack.cjs`; its initial offline proof passed
12 groups / 173 checks (root39271). See the [cardinal design](acdc_prerecorded_cardinal_design.md)
for that receipt and [current authoring readiness](acdc_cardinal_authoring_readiness.md)
for the next source correction and exact approval workflow. Next: finish the
finite transcript/intro review, author missing artifacts once, verify/listen,
implement create-only import and normal recorded playback, then deploy and
perform actual five-language call acceptance. Installation, queue editing and
future account creation must never invoke Gemini.
