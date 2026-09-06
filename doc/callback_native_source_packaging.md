# Native callback source packaging handoff

Read-only inventory taken 2026-09-06. This is a packaging plan, not native
playback/deployment acceptance. Do not copy private build trees or cached objects
into kz5. Current canonical callback telephone readback uses recorded digits in
all five locales; the historical private SAY mapping is not canonical.

## Reproducible baseline

Use local pinned Git objects, not the installed working tree:

- FreeSWITCH `ef32e205295e29f034f1453ad245ba5efb07b94a` (1.11.3), plus the existing
  `freeswitch-mod-sofia-thread-lifecycle.patch`,
  `freeswitch-mod-sofia-kazoo-proxy-uri.patch` and
  `freeswitch-module-load-shutdown.patch`.
- mod_kazoo `0878e13e02db5db7bde765d61a9453b3cf279399`, plus the current kz5
  aggregate. Its atomic-intercept reconciliation includes the unchanged tracked
  patch SHA256 `dc64c100e6ad0d07956aa897e6897b892f827e8f32fe42a9480bca93feea3aad`.
- Preserve installer pins Sofia-SIP `ad36ac8f755308e8b87f98a505e83d4e408e5cc3` and
  SpanDSP `8f1e1646bdec99eac5fd2cd92c35563f736b9b89`. Normal bootstrap/configure/
  libtool dependency expansion remains authoritative; the earlier hand-written
  incremental link command's missing library operands were fixture corrections,
  not evidence that the installer needs ad-hoc extra linker flags.

The inspected installed mod_kazoo source had atomic interception but still used
the old `VERSION` macro. It is not identical to the current kz5 baseline. Its
extra `remove_kz_dptools()` call belongs to atomic interception, not an unrelated
local modification to discard. The tracked atomic patch was previously missing
from installer preparation; that bounded reconciliation is documented separately.

## Exact overlay map

All private paths below are relative to
`/usr/local/src/kazoo5-installer/callback-owned-audio.EeqmMW/`.
Targets are relative to the FreeSWITCH tree, except the mod_kazoo rows, which are
relative to `src/mod/outoftree/mod_kazoo/`.

| Target(s) | Source directory/file |
| --- | --- |
| `src/switch_ivr_owned_audio.c`, `src/include/switch_ivr_owned_audio.h` | `native-ei-dispatch.S4NXF3/`, same basenames; includes the read-only snapshot addition |
| `src/switch_ivr_owned_resource.c`, `src/include/switch_ivr_owned_resource.h` | `native-say-scope.MfDQMl/`, same basenames |
| `src/switch_ivr_play_say.c` | `native-say-scope.MfDQMl/switch_ivr_play_say.c` |
| `src/switch_loadable_module.c`, `src/include/switch_loadable_module.h` | `native-say-loader-busy.XKamzX/`, same basenames; retains the later busy-unload fix |
| `src/switch_core_media.c` | `native-normal-codec.nZYBwT/switch_core_media.c` |
| `src/switch_apr_queue.c`, `src/include/switch_apr.h` | `native-passive-ready.jpGiQK/`, same basenames |
| `src/switch_core_codec.c`, `src/switch_core_event_hook.c`, `src/switch_core_session.c`, `src/switch_ivr.c`, `src/switch_pcm.c`, `src/switch_rtp.c` | `native-write-extractor.DmBWMY/source/src/`, same basenames |
| `src/mod/endpoints/mod_sofia/mod_sofia.c` | `native-write-extractor.DmBWMY/source/src/mod/endpoints/mod_sofia/mod_sofia.c` |
| root `Makefile.am` | `native-write-extractor.DmBWMY/source/Makefile.am`: retain only the two owned C sources and two installed-header additions; discard its unrelated final-newline deletion |
| mod_kazoo `kazoo_dptools.c` | `native-version-tu.RAKTfm/mod-kazoo/kazoo_dptools.c`: adds exact hold begin/end around existing endless playback |
| mod_kazoo `kazoo_node.c` | `native-ei-dispatch.S4NXF3/mod-kazoo/kazoo_node.c` |
| mod_kazoo `kazoo_queue_audio_wire.c`, `.h`, `kazoo_queue_audio_dispatch.c`, `.h`, `kazoo_queue_audio_guard.h` | `native-ei-dispatch.S4NXF3/mod-kazoo/`, same basenames |
| mod_kazoo `Makefile.am` | `native-ei-dispatch.S4NXF3/mod-kazoo/Makefile.am`: adds wire and dispatch C translation units |

Before the in-progress signal/RTP work, this is eighteen FreeSWITCH overlay
targets and eight mod_kazoo targets relative to the corrected installer baseline.
An upstream-based aggregate also retains the baseline Sofia files and atomic
intercept header/cleanup: twenty FreeSWITCH and twenty-one mod_kazoo target files.
Recalculate those inventories when accepting subsequent owner-frozen changes.

Key inspected SHA256 values (not a final aggregate freeze):

- normal media: `9c0a94afac58b6ef225ac0b1c21dd0b97698c9ff054f5acd251ca8f83fa51fed`
- EI-owned audio C/header: `b38bd41c9fa8c53de2638b20796fbd38ec719318c768a702b42b4830255208b7` /
  `2bc743e51334701be3a6655c5647e24d0ba8f28915a9e7fd1bb923fbd6a68aa3`
- EI node: `00890fb9fbc0f1625a7ecf8fc713ee1642b7e01b5ce05f291ec3d030e681d181`
- passive queue C/header: `3cf0d9330c45a78d43d9fab8b9aacc71de592533d679c1518c0fc3c52b1b6cb0` /
  `cfe585434fdf5e4a7d33396622f5901d11af2950b4f6dbb705020682ff6ee773`
- later loader C/header: `302762c23e9735c3c222d07b8252d397f8a24e1de780de60842fcd57fd3c5b61` /
  `cf166c9c7d74f4785f7114ae27b9466ac3d65898b185a985df30f3a5a85c4953`

## Resolve variants before packaging

- Use one canonical `src/include` tree. The normal-media TU proof selected the
  older codec-fence owned header; EI dispatch adds snapshot to the later SAY
  header. Both private `switch.h` copies are byte-identical to native baseline
  and are include-routing shims, not new product headers. The copied
  `switch_core_event_hook.h` is also unchanged and needs no patch.
- RAKTfm `kazoo_api.c`, `kazoo_fetch_agent.c` and `kazoo_ei.h` only carry the
  already-tracked version namespace fix. Do not duplicate them as callback work.
  Its `kazoo_intercept.h` and `mod_kazoo.h` are supplied by the corrected baseline.
- Do not combine the superseded `native-lifecycle.ZCgpTZ` event executor/guard C
  files with the newer EI dispatcher. The new wire decoder needs the guard
  header's types, not the old executable guard/lifecycle implementation.
- `native-pic-visibility.iuM1OQ/link-plan.json` (SHA256
  `688e484763eb8e70d55675b378dc1e5df8e380873b5471ddce2773b3574345ce`) and the later
  SAY relink retain old media, queue and EI-node objects; the SAY relink also
  predates loader-busy. They are historical receipts, not the current link recipe.
- The native agent owns in-progress `native-signal-fence.ChqP6i`; root owns the
  next RTP derivative. Obtain their explicit source freeze and merge onto this
  map before producing an aggregate. Do not infer acceptance from file existence.

## Bounded executable delivery plan

1. Archive the two exact local Git refs into fresh disposable roots. Apply the
   kz5 baseline patches, including atomic interception. Hash every selected
   source before and after copying; reject symlinks, unknown paths and drift.
2. Resolve the table into one reviewed source/header tree. Commit small upstream-
   based aggregate patches and a relative-path/SHA256 manifest in kz5, plus the
   genuinely new source/header files if maintained separately. Do not commit
   generated headers, objects, libraries, configure output or private proof trees.
3. Add protected installer clean/current/previous transitions, finite target
   inventories and aggregate digests in the build fingerprint. Overlapping loader
   and module patches require whole-state preflight, not individual reverse
   checks after later patches have rewritten their contexts. Test fresh, repeat,
   existing namespace/intercept states and no-mutation rejection cases.
4. Port the focused proof drivers to repository-relative source inputs; keep
   retained historical receipts historical. Replay from local pinned Git without
   network, verify exact resulting bytes/reverse application, then run actual
   bootstrap/configure/normal build in a fresh root without cached native objects.
   Verify dependency-selected headers, exported/local symbol distinctions and
   core/Sofia/Kazoo link closure against the same new core.
5. Keep owned admission and transport ownership hard closed while packaging.
   Native producer/mutation lifetime, normal codec/SRTP output, both-leg bridge
   reservation and actual callback acceptance remain separate technical work;
   user authorization already permits development deployment/restarts once that
   bounded implementation is ready. No new permission blocker is implied.
