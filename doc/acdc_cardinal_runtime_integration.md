# Prerecorded position runtime integration

Source candidate, not deployment or audible acceptance evidence.

The first complete cardinal pack is English. `acdc_cardinal_media.erl` resolves
the exact 31-role map emitted by `import-acdc-gemini-cardinals.cjs` and shared
immutable media-document verifier. An explicit installed-byte verification by
the importer is still required: runtime metadata checks do not hash audio.
`acdc_cardinal_prompts.erl` supplies the tested numeric grammar, not native SAY,
digit spelling or a provider request. A positive position up to 999999999 uses
at most 14 number PLAY fragments plus its framing.

`acdc_announcements.erl` keeps raw media field presence separately from merged
legacy defaults. During worker initialization it resolves callback audio first,
then English position audio. All deadlines retain their original monotonic start;
the existing separate callback initial delay and repeat interval are unchanged.
No position interval performs datastore reads. Events remain bound and the
manager monitored during preflight; existing event-drain checks run before any
playlist is enqueued. Synchronous datastore calls retain their existing Kazoo
timeouts; this change does not claim a new absolute preflight time bound.

Missing, duplicate or wrong cardinal identities, invalid metadata, lookup errors,
or unavailable account-override checks fail closed. Only position announcements
are disabled; callback and wait-time settings remain independent. English cannot
fall back to SAY when the verified pack is missing. Deploy/import the pack before
activating this module. Disabling position audio is deliberate incomplete-pack
behavior, not an assertion that silent position announcements meet acceptance.

Explicit prefix/suffix settings are preserved, including stock-looking IDs.
Account-scoped legacy/canonical prefix, suffix and combined-intro recordings keep
priority. Built-in framing uses the separately approved current-position intro;
its transcript and WAV pins must also match the compiled existing fixed map.
Customized framing continues to use account-scoped prompt resolution while the
English number itself uses only immutable prerecorded PLAY paths.

## Validation commands (root execution required)

- `bash scripts/test-acdc-cardinal-media.sh`: private production/test compilation,
  metadata/pack coverage, bounded PLAY composition, invalid position/locale,
  source stability, custom framing and independent announcement clocks.
- `bash scripts/test-acdc-callback-announcements.sh`: real worker timers and
  cancellation, combined PLAY-only English position/callback playlists, existing
  supervisor/event cleanup checks. Private output only.
- Existing `applications/acdc/test/acdc_announcements_tests.erl` now expects
  English prerecorded playback and mocks media preflight for its timer case.
- Keep the pure grammar parity suite and immutable importer suite as distinct
  gates. Unit fixtures do not establish audible/live behavior.
- `node scripts/test-install-acdc-cardinal-pack.cjs`: adapter control-flow
  fixture for plan/no-write, map identity, import then separate verification,
  ambiguous errors, final map drift and invalid receipts. No CouchDB/provider.

The main installer's existing 210-asset import now runs the separate checked-in
cardinal adapter afterward. It compares the emitted map with the tracked header,
performs create-only import and separate final byte readback, and writes only a
separate `/usr/local/share/kazoo5-installer/acdc-cardinal-media.json` receipt.
It inherits the configured CouchDB child environment, so no local FreeSWITCH or
provider key is required. `--plan` makes no database connection. This English
hook is required for the new runtime but does not claim all-language readiness.

## Remaining language and release work

FR/ES/HE/AR continue their pre-existing position behavior in this English slice;
this is not five-language completion. The catalog already defines all grammars
and exact roles. Preserve 31 successful English recordings, 25 Spanish cardinal
recordings, and two verified provider-free whole-word Spanish reuse identities.
Resolve the remaining catalog roles once, including separate approved Hebrew and
Arabic intros, then emit reviewed per-locale immutable maps before enabling each
runtime path. All five pure grammars are now ported and pass73240 parity cases
(`926abd/1ea276`); grammar coverage does not imply complete recorded assets.

Never synthesize from queue/account creation, editing, installation, service
startup or live calls. Once generated, WAVs and provenance remain in kz5. Full
release still requires all five complete packs, voice/listening review, live
position and callback captures, installer import/readback, fresh deployment and
regression tests. No dashboard module or statistics record migration belongs in
this focused deployment.
