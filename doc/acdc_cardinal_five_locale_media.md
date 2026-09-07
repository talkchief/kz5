# Five-locale cardinal media preflight — source preparation

Root offline validation `0d2bfe/session53173/b60ebe` passed all12 focused EUnit
groups and production/TEST compilation with warnings treated as errors.
Private artifacts: `/tmp/kazoo-cardinal-media.i32h6k`; unchanged input digest
`f24f44cb84aaec3fcdac7c8736aab50bdb063b52cc7b45b43d12a8b1271319ae`.
The generated catalog/intro oracle and synthetic five-locale metadata tests are
not installed audio, listening approval or runtime activation.

`acdc_cardinal_media.erl` now recognizes exactly `en-us`, `es-es`, `fr-fr`,
`he-il` and `ar-sa` in its preflight seam. It requires the complete selected
catalog inventory: 31, 53, 161, 131 or 208 roles respectively. Missing, extra,
duplicate or substituted selected-locale roles fail before frame resolution or
document reads. A combined map can contain the other supported locales, but
only the requested locale is selected or read. Invalid aliases and nonbinary
language values fail explicitly.

The production `prepare/3` still uses the unchanged `CARDINAL_ASSETS` header,
which contains EN31. It therefore cannot admit another locale until real complete
maps are deliberately integrated. No other-locale audio tuple or compiled map
was fabricated. The announcement dispatcher still selects this path only for EN;
it was not changed. This source change does not establish five-language runtime
readiness or remove the remaining legacy nonEN dispatch behavior.

## Interfaces and verification

`prepare_with/6(Language, Account, Media, Assets, Read, Frame)` retains its
existing signature. It verifies the selected inventory against independently
listed catalog roles, resolves framing once, and verifies each document against
the exact immutable tuple with `acdc_gemini_prompts:verified_asset/2`. The returned
context contains same-locale direct system-media paths, preserving the pure
compositor's cardinal roles. Its injected `Frame` is trusted application code;
the seam is exported only in TEST builds.

`frame_with/5(Language, Account, Media, IntroAssets, Read)` is a new TEST seam
used internally by `frame/3`. Its introduction contract is the locale's exact
canonical ID, transcript hash and telephony WAV hash from the approved release
importer. EN retains `CARDINAL_EN_INTRO`; ES/FR use their existing current-position
intro; HE/AR require the separately authored
`acdc-cardinal-intro-v1-current-position-number`. The target intro identity must
occur exactly once. A duplicate with different hashes is still rejected. The
selected tuple and returned document must agree before builtin playback.

`frame/3` currently supplies the unchanged fixed210 `GEMINI_ASSETS` inventory.
Future integration must explicitly supply the verified new HE/AR intro tuples;
their absence cannot resolve to an old introduction or another language. The
new introductions are not implicitly added to the fixed210 map or inventory.

Configured prefix/suffix recordings and account introduction overrides retain
their existing precedence. When both frame components are builtin, the combined
intro lookup still checks for account overrides. For HE/AR only, the exact
`unsupported_gemini_prompt` result from `default/4` means its account lookup
succeeded with no override and its fixed-map lookup lacks the newly versioned
ID. Only then can the independently pinned and document-verified new intro play
directly. Account lookup errors, missing media, unexpected IDs and other error
results fail closed. Custom framing remains an explicit customer choice and
does not claim immutable voice or text verification for that customer recording.

`playlist/3` continues to reject invalid/zero queue positions and out-of-range
numbers. The underlying cardinal catalog/compositor still includes zero and the
whole 0..999999999 range; a queue position starts at one. Before producing a
playlist, every required role must exist and every numeric path and builtin
frame path must be in the requested locale's system-media directory. Malformed
contexts, SAY commands, foreign-language prompt tuples and foreign numeric paths
return no playlist. There is no digit spelling, speech synthesis, native SAY,
partial numeric speech or language fallback in this module.

Runtime document metadata verification remains distinct from the importer's
downloaded-WAV byte verification and from actual native listening. This change
does not claim that a metadata read has independently hashed remote audio bytes.

## Prepared tests and remaining work

The focused test launcher exports the pure JS catalog's role identities and
importer's intro pins to a retained private Erlang fixture. EUnit compares every
locale's inventory and intro declaration to those independent authoring sources;
it does not duplicate the production inventory logic as its oracle. Synthetic
tuples/documents then exercise all five complete inventories, full-number
boundaries and maximum playlists, same-locale selection from combined maps,
missing/extra/duplicate/wrong-locale roles, malformed frames, bad metadata,
missing or substituted intro tuples/documents, account-lookup failures and
preserved custom overrides. Original EN and independent announcement-clock
regressions remain. Synthetic tuples are not actual media, release maps or
native playback evidence.

These changes were source-reviewed only while serialized authoring was active.
No tests, builds, guard commands, provider calls, credentials, imports or
deployment were run by this task. Root must run the focused media test launcher
in its guarded window before relying on these prepared regressions.

Remaining integration is concrete: finish the actual five-locale role assets,
verify/import their immutable tuples and new HE/AR intros, integrate complete maps
and the intro inventory, then change the announcement dispatch/preflight
boundary together. Preserve callbacks' independent scheduling and customer
overrides. Actual distributed playback, cancellation, completion, bridge safety
and honest listening evidence remain release work. The required release still
covers all five locales with one female prerecorded voice per locale; nothing
here narrows that requirement. All ACDC work remains in `kz5`.
