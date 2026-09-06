# Private typed SAY checkpoint — 2026-09-06

Not deployed or callback-ready. Both public SAY admission and the global
owned-audio lane remain closed. The prior fifteen-unit link result does not
cover this new derivative.

Working source directory:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-say-scope.MfDQMl`.

The root candidate implements strict numeric WAV fragments, whole-list
validation before playback, and copied language-scoped paths bound to the
active audio token, input args and owner thread. External PLAY classification
is not broadened. The typed wrapper does not call legacy `switch_ivr_say`,
change channel language/sound-prefix variables, invoke TTS, or execute English
`file_string` expressions. Telephone digits are handled in order without
depending on the missing Spanish telephone SAY callback. AR/HE remain on the
separate recorded-numeric-assets path; this does not certify Gemini coverage.

The parallel loader candidate adds a protected interface lease and shutdown
fences; its review and lifecycle tests are separate open acceptance work.
The integrated wrapper still needs cancellation, stale/foreign-token,
module-unload, full native link and real audio tests before installer packaging.

## Validation tools and completed checks

The user explicitly authorized installing missing tools. Rocky 9 packages
`libasan-11.5.0-14.el9.x86_64` and `libubsan-11.5.0-14.el9.x86_64` were installed
from AppStream: 584 kB download, approximately 1.6 MB installed. The transaction
added only these two packages. No Kazoo service was restarted; all eight selected
services remained active afterward.

Reproduce these development-only dependencies on the matching Rocky build host:

```sh
dnf install -y --setopt=install_weak_deps=False libasan libubsan
```

They are validation runtimes, not new requirements for every production module
server. The original sanitizer run `746cf9` failed at link because these
libraries were absent. After installation, `a81ab7` passed the actual pure C
leaf/list/path fixture with `-fsanitize=address,undefined`, leak detection and
halt-on-error, under a 320-MiB memory cap, 768-MiB reserve, zero swap and isolated
network namespace. This is sanitizer coverage of that helper only, not the
FreeSWITCH process or module lifetime.

Earlier fixture runs exposed a `currency/and.wav` length error in the new
helper and an incorrectly counted prefix length in the test. Both were fixed;
`40c923` passed without sanitizers before the successful sanitizer rerun.

Tested resource source SHA-256:
`15c64a9392de3e70f9baada056c383eda0a6792998dbca64314e8478ccb52410`.
Fixture SHA-256:
`925ce4252644115922ade6b24f47ed7f34c02db03427abd5e8f71b4e94ada824`.

`fcc723` passed preliminary syntax checks of the complete resource, owned-audio
and play-say translation units using real configured headers and native flags
including `-Werror`. This was not a frozen dependency-pinned build proof,
loader compilation, linking, executable test or deployed callback test.

Subsequent run `e2a605` passes all four complete translation units, including
the frozen loader candidate. Independent review identified two completion
issues, now corrected in the private root candidate: dispatch must not return
native SUCCESS after the final validity/zero-output check downgraded completion;
and each individual prompt fragment must send audio rather than borrowing a
positive count from an earlier digit. These corrections compile but still need
the specific empty-fragment and cancellation regression tests. Loader
lease/shutdown fault-injection fixtures are being prepared separately.

## Completion regressions and incremental link

Run `6f88de` passes an ASan+UBSan fixture containing the exact private
`owned_complete` function and the actual play/dispatch completion blocks.
It covers zero-output PLAY/SAY, positive output, last-moment validity failure,
preserving native failure, refusing cleanup while SAY scope/output remains
active, wrong-thread/stale-token cleanup, and a successful fragment followed by
an empty fragment. Dependencies are doubles: this is not full native playback,
XML, module shutdown or RTP coverage.

Evidence: `native-say-scope.MfDQMl/completion-proof.3puwUd/receipt.json`.
SHA-256: `a7c5e0537a2209cd6f0cb75843fb5559a21786b316ae7ac0c44c75a97d1d9cf1`.
Run `4ab578` additionally passes two negative controls: removing dispatch's
completion downgrade and permitting an unchanged per-fragment frame count
each causes its intended assertion to fail. Compilation/sanitizer failures
are not accepted as a successful negative control.
Evidence: `native-say-scope.MfDQMl/completion-negative.EyqM4B/receipt.json`.
SHA-256: `1c901b95940581409643e9ec7f7b55b7ddfb16fd58395db63057089b3797e333`.

Run `5de233` now passes four complete fresh PIC compilations (owned audio,
resource validation, play-say and loader), three strict incremental core/Sofia/
Kazoo links, and required new exported-symbol checks. It retains hashed
unchanged objects/archives from the earlier accepted link checkpoint; linker
LOAD inputs are checked and neither module may import an old FreeSWITCH core.
This is not a cold rebuild or native execution.

Evidence: `native-say-scope.MfDQMl/say-link-proof.CR1U3M/receipt.json`.
SHA-256: `268bc7e22f6d026857053a30d4b5c638ee70f423cbe587281768fd31cd9c9538`.
The first attempt correctly rejected the changed `/etc/ld.so.cache` after the
authorized sanitizer installation. The cache was reviewed and explicitly
re-pinned; no existing source/library pins were relaxed. A subsequent attempt
stopped at two previously unlisted APR declaration headers newly selected by
the complete loader TU. Those headers were read and explicitly pinned before
the successful rerun. All source, cached-object and selected dependency checks
remain enabled. No live library was replaced, loaded or restarted.

## Loader fault scenarios

After full review of the extractor, dependency doubles, tests and runner,
guarded run `610fd9` passes all eight groups/39 leaf scenarios in both plain and
ASan+UBSan modes. The runner checks 108 selected compiler/tool dependencies and
its source pins before/after execution. The cap was 320 MiB with a 768-MiB
reserve, zero swap, 60-second outer deadline and separate network namespace.

Evidence: `native-say-scope.MfDQMl/loader-lease-proof.jWyEMH/receipt.json`.
SHA-256: `e2aec9212b984db9d14eeaf00c9d663cac85973d1502470bc5f5428c85ed09be`.

Coverage includes balanced leases, full registry/serial exhaustion, acquisition
and release lock faults, poisoned cleanup, foreign-thread/stale/duplicate/ABA
release, normal/forced unload refusal, every admitted unload exit, and both
remove-before-shutdown and failure-before-reinsertion races against global drain.
The real extracted shutdown admission/drain prefix waits for active loads,
unloads and owned SAY leases. Its destructor tail is a counted local effect,
not actual native destruction. Recursive global shutdown remains unsupported:
the fixture proves it self-waits rather than returning unsafe success, then
uses a fixture-only escape. It does not make that misuse responsive in production.

The root source/test snapshot is recorded in private `say-root-inputs.sha256`
and was rechecked unchanged afterward. Full native session/module teardown,
language-module fragment playback, real callback retries/DTMF and installer
packaging remain open. No readiness/admission switch was enabled.
