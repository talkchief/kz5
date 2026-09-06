# Callback native build readiness

This checkpoint concerns the private owned-audio candidate, not the running
FreeSWITCH installation. Its public admission gate remains hard closed. No
native artifact from these proofs may be treated as ready for installation.

## Actual PIC compilation and initial link — 2026-09-06

Guarded run `90804` compiled all fifteen complete private C translation units
into real PIC objects with the configured native flags, optimization and
`-Werror`. It then linked a private FreeSWITCH core and Sofia module. The Kazoo
module link failed, so the overall checkpoint is **failed**, not accepted.

The failure is a test-recipe normalization error: the explicit module command
omitted core dependency libraries which the normal libtool command expands
from `libfreeswitch.la`. The first unresolved direct dependency was
`curl_easy_setopt` from libcurl. The configured `mod_kazoo.la` dependency list
already includes libcurl; this does not establish a missing dependency in the
production installer. The correction must preserve that expansion, not weaken
undefined-symbol checks or substitute the installed FreeSWITCH core.

Evidence directory:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-pic-link.Rny3oG/pic-link-proof.w3xhTl`.
Receipt SHA-256:
`068976907b42f04e9acda0b48c1f39ebcf9d43c79b87dbfac2b30365258e6a41`.
All 853 unique pinned inputs and 913 lexical path identities remained stable;
the helper completed in 79.885 seconds. Its output occupied approximately 52 MiB.
The run was serialized with a 384-MiB memory cap, no swap, 768-MiB reserve,
300-second outer deadline and private network namespace. No modules were loaded,
no native artifact executed, and no services restarted.

The input set reuses pinned cached unchanged objects: 87 core, nine Sofia and
sixteen Kazoo, plus static archives and the generated Kazoo definitions object.
Eight core objects are replaced and two new owned-audio objects added; Sofia
replaces one object, Kazoo four. Thus successful linking would prove incremental
native link closure, **not** a clean rebuild or provenance of unchanged cached
objects. The prior complete real-header compilation is documented in
[the module version correction](mod_kazoo_version_namespace.md).

## Corrected library dependency expansion

Run `66262` used a new reviewed derivative which added the complete 26-operand
native core dependency-library expansion to both module links. The source,
compiler flags and strict undefined-symbol checks were unchanged. All fifteen
PIC compilations and all three links passed. The later ELF check failed because
it incorrectly expected the internal resource classifier to be a dynamic export.
The overall receipt remains failed, despite successful native links.

Source/header inspection shows `switch_ivr_owned_resource_classify` has no
`SWITCH_DECLARE` public declaration. Full-symbol inspection of the linked core
shows a defined local function, as expected with configured hidden visibility.
The public owned submit/codec-enter functions are dynamic exports. Correct
acceptance must require that distinction, not broaden production visibility to
make a test pass.

Evidence:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-pic-deps.rhqolu/pic-link-proof.EG5q5L/receipt.json`;
SHA-256 `25c4026f020b5737cffb1a25d19abe6fcf8404ba0ff6224d7ed7709789f570b4`.
All 863 input hashes/923 path identities stayed stable; elapsed time was
89.613 seconds. No native artifact executed or loaded.

## Complete corrected checkpoint

Run `22624` passed all fifteen fresh PIC compilations, three strict private
links, all three ELF metadata groups and the explicit public-versus-local symbol
checks. Sources, compile flags, link inputs and undefined-symbol requirements
were unchanged; only the incorrect classifier visibility expectation was fixed.
Both earlier failed packets remain intact.

Complete receipt:
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/native-pic-visibility.iuM1OQ/pic-link-proof.IJco3Z/receipt.json`;
SHA-256 `c4c563de93afc3686cafec076b7d48bed69b3047e69fb2ad2698c723dc684912`.
All 865 unique input hashes and 925 path identities stayed stable. Elapsed time:
88.307 seconds; retained private outputs: approximately 55 MiB.

The initial 384-MiB guard refused before starting because available memory was
below cap plus reserve. The completed run used a **lower 320-MiB cap**, keeping
the 768-MiB reserve, zero swap, 300-second outer deadline, internal deadlines and
network isolation. No tests or acceptance checks were removed to fit memory.

This closes the incremental PIC/link/ELF checkpoint only. It is not a cold
rebuild, native execution, sanitizer test or deployment. Admission remains
closed and the following source and real-call gates remain open.

## Remaining source and deployment gates

- SAY: the private candidate still returns unsupported. The actual native
  `switch_ivr_say` implementation is in `src/switch_ivr.c`, not
  `src/switch_ivr_say.c`. Owned playback needs token-scoped copied prefix
  selection without channel-global writes and an explicitly acquired/released
  say-interface lease covering the whole primitive. The legacy interface getter
  only protects hash lookup, not interface lifetime: adding an unmatched release
  to the legacy function would be incorrect. Forced shutdown/unload must also
  respect the new lease before destroying a module. Calling the unchanged
  primitive does not close this gate.
- Media lifetime: reserve the entire producer/write stack before early SDP or
  recovery mutation, RTP payload/interval/crypto changes and codec/media/session
  teardown. Frame completion alone does not prove producer-stack completion.
- Bridging: implement and verify every actual entry, handoff, end and abort path,
  with both-leg reservation and exact ticket release. Callers must propagate
  deferred/failed outcomes rather than claiming a completed bridge.
- Real media: test accepted output, continued hold, SAY fragments, key 6,
  bridge/usurp/hangup and cancellation under actual native scheduling.
- Delivery: package reviewed source and build changes into kz5's installer,
  complete fresh and distributed build/deployment acceptance, and perform the
  requested durable callback registration, spoken confirmation and unanswered
  first-attempt retry scenario.

These are release gates in P0-03 and INST-06/07, not work that a successful
compile/link can silently waive. No callback-ready or production-ready claim is
made by this document.
