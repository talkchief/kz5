# Built-in queue voice release — September 7, 2026

## Current evidence

All required position recordings are saved: EN31, HE131, FR161, ES53, AR208,
584 roles total. These are reusable cardinal components, not one recording per
possible queue position. Existing fixed210 callback/digit/wait-time recordings
remain separate. Two new HE/AR position introductions bring the complete unique
media inventory to796 documents, with1592 mappings across the two native caches.

Root source preflight `f0be7f/session70038/eb0909` passes actual five-locale
plans, WAV/hash/resampling/provenance checks and exact independently stored map
readback. No CouchDB/provider/runtime operation occurred. Its resolution is
412 original recordings +170 separate-model recordings +2 reviewed Spanish
whole-word aliases. Runtime and listening readiness remain false in this receipt.
Check PROJECT_TASKS.md for subsequent regression/deployment/live acceptance.

Actual main-SH media installation and separate final verification now pass
`96ba63/session31524/e25b08`: all584 cardinals,210 fixed assets and both new
introductions are installed. This is796 unique media documents; EN/FR/ES intros
are already part of fixed210. Final source/byte/revision verification receipts:

- `/usr/local/share/kazoo5-installer/acdc-cardinal-media.json`, SHA256
  `a629cbb24bd4ed2ae235adc72002419fb0affd1deb267fe12cfe371116e052bd`.
- `/usr/local/share/kazoo5-installer/acdc-gemini-media.json`, SHA256
  `294fd51eb3cb4d7de42b0bc4dfdcba1a8ccd548c5a63b888d470d56508a91f9e`.

The final cardinal receipt is `VERIFY_ONLY`,584 verified, exact five locale
counts and every intro verified. No provider request was used. Runtime mapping,
coherent code deployment, SIP playback and listening approval remain separate.

## Frozen source inputs

- Original pack: `scripts/assets/acdc-gemini-cardinals-20260907`.
- Original manifest SHA256:
  `9c97120495c327a66644330d222ae7d4705402c40b1f97b6696a486e4a5d0398`.
- Authoring approval SHA256:
  `452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5`.
- Saved model trials: `scripts/assets/acdc-gemini-cardinal-model-trials-20260907`.
- Final59-receipt index SHA256:
  `b6c4e2a2ef515be72d378a239086b4421992a095447003c1c397c925d98c1e51`.
- Spanish alias file: `scripts/acdc-cardinal-reuse-es-20260907.json`, SHA256
  `f1338ba60bbb360a91491fcf3be0d161ca25ff267a2f7ec32c2faacc49ca1b6d`.
- HE/AR intros: `scripts/assets/acdc-gemini-cardinal-intros-20260907`.

The original ledger remains unchanged, including failed attempts. It is not
rewritten as a successful2.5 generation history. Separate recordings retain
actual `gemini-3.1-flash-tts-preview` provenance; both use Sulafat. There are171
additional model requests,170 accepted recordings and one retained diagnostic
failure. Final read-only recovery plan `d5f2f4/467d44` has zero missing roles and
zero proposed provider requests. Do not regenerate successful audio.

## Runtime/build integration

`acdc_cardinal_prompts.erl` composes numbers without TTS/SAY. All five exact source
maps are mandatory compile inputs to `acdc_cardinal_media.erl`. Missing media
disables position audio, never falls back to robotic or another-language audio.
Position and callback clocks remain independent. Existing account media is not
deleted or overwritten; standard queue defaults use this shared built-in pack.

| Locale | Roles | Map SHA256 |
| --- | ---: | --- |
| EN |31|`290ce69c163729cf567d2353982066f0518d42045a89b4dfc2125953494c5406`|
| HE |131|`62a9fcd109fd5d6d8965572b2b45e3b0da536b31b5c44ac89ca097f2c0daa16a`|
| FR |161|`70bb7e7767c2c8c26fd4375607de762d6131897bf852457d2e64774b27f54166`|
| ES |53|`a53cc14203f0cb8f5d9558a36314547757bf24fb81fd9f017ececfcf55ee5267`|
| AR |208|`06798759f618ea4bf04ed32c9694c85bc8b48307d005a1dbc13e0c9cb515050b`|

EN map is `applications/acdc/src/acdc_cardinal_map.hrl`; the other four are
`applications/acdc/src/cardinal_maps/acdc_cardinal_<locale>.hrl`.
The AR source file SHA256 is
`5e4566e9fc62619e15764c3f0918ea82f566604f51c214c8e5e0e9db60ce2bc9`.

## One installer, no online synthesis

`bash scripts/install-kazoo5.sh kazoo-apps` owns dependency/build/import and
service setup. Its `install_acdc_language_packs` first plans fixed210 and the
complete584 cardinal inventory before any media database effect. It creates
only versioned owned documents, independently rechecks installed bytes, and
stores separate fixed/cardinal receipts under
`/usr/local/share/kazoo5-installer/`. Cardinal receipts include exact final intro
revisions, not just an availability boolean.

After applications start, the fixed mapping helper and separate
`refresh-acdc-cardinal-mappings.cjs` activate/check only their exact owned IDs.
`--verify-only kazoo-apps` never repairs caches. No global media flush, custom
recording overwrite, queue/account mutation or provider call is part of this
voice import. CouchDB may be remote. New accounts/subaccounts reuse system-media
defaults; they do not invoke Gemini or require a Gemini key.

The authoring tools are release-maintenance tools only. They must never run in
the installer, account creation, queue editor or call path. Missing artifacts
must fail source preflight, not trigger synthesis. Technical source completeness,
installed bytes, cache activation, live playback and listening quality are
separate evidence; do not convert one into another readiness claim.
