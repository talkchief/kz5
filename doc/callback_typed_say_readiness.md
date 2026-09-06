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
