# Account language for forwarded-call confirmation

Assessment date: **2026-09-08**. Task group: **FWD-01–06** in
[PROJECT_TASKS.md](../PROJECT_TASKS.md).

**Feasible with moderate implementation effort.** Kazoo already supplies a
confirmation audio file to FreeSWITCH for the forwarded destination. The
change can reuse that mechanism, account persistence and the existing account
API. The main work is consistent selection across four code paths, preserving
existing accounts, packaging five recordings, and testing actual call behavior.
There is no identified need to redesign call routing or replace the confirmation
engine. This source assessment cannot establish zero operational risk.

The user subsequently authorized implementation and added Spanish and French.
The final scope is EN/HE/AR/ES/FR. Implementation, packaged audio and focused
source tests, development installation and API/browser acceptance pass. See [implementation evidence](call_forward_confirmation_acceptance.md).

## What the source establishes

The stock English transcript is: “This is a forwarded call. Press 1 to accept,
or hangup to ignore.” It appears in the local installer sound checkout at
`/usr/local/src/kazoo5-installer/kazoo-sounds/kazoo-core/en/us/prompts.txt:103`.
That checkout contains the corresponding English WAV and several other
languages, but no Hebrew or Arabic `ivr-group_confirm.wav`.

The setting is **not exclusively system-wide in the underlying architecture**.
The standard prompt name is shared, but its resolver supports account media
overrides and language. The existing general account language can affect other
prompts, so it is too broad for this dedicated preference. The current call's
language and an endpoint's language also need not be the same.

| Source | Finding and implementation implication |
| --- | --- |
| [kz_endpoint_v5.erl](../core/kazoo_endpoint/src/kz_endpoint_v5.erl), `maybe_set_confirm_properties/1` | With `require_keypress`, sets `Confirm-Key=1`, a 7000 ms read timeout, and `Confirm-File` from `kapps_call:get_prompt(Call, <<"ivr-group_confirm">>)`. Replace only the file-selection expression. |
| [kz_endpoint_v4.erl](../core/kazoo_endpoint/src/kz_endpoint_v4.erl), same function | Separate legacy implementation with the same prompt choice. It must receive the same preference behavior. |
| [kz_directory_cfwd.erl](../core/kazoo_directory/src/kz_directory_cfwd.erl), `call_forward_confirm_properties/5` | Native directory forwarding instead uses `kzd_endpoint:get_prompt/2`. Emits a 3000 ms read timeout and play count 3. Preserve these existing values. |
| [kz_directory_failover.erl](../core/kazoo_directory/src/kz_directory_failover.erl), confirmation properties | The fourth selector serves failover forwarding and needs the same account preference. |
| [kapps_call.erl](../core/kazoo_call/src/kapps_call.erl), `get_prompt/2,3`; [kzd_endpoint.erl](../core/kazoo_documents/src/kzd_endpoint.erl), `get_prompt/2` | Pass call/endpoint language and account identity into media resolution. |
| [kz_media_util.erl](../core/kazoo_media/src/kz_media_util.erl), `get_prompt/3,4`, `prompt_language/2`; [kz_media_map.erl](../core/kazoo_media/src/kz_media_map.erl) | Support account overrides, localized media and default-language fallback. General overrides are controlled by `media.support_account_overrides`, defaulting to true in source. Do not toggle this global setting for the new feature. |
| [ecallmgr_fs_xml.erl](../applications/ecallmgr/src/ecallmgr_fs_xml.erl), `kazoo_var_to_fs_var/2` | Already resolves `Confirm-File` to a media path and emits `group_confirm_file`. No new switch command is needed. |
| [accounts.json](../applications/crossbar/priv/couchdb/schemas/accounts.json); [cb_accounts.erl](../applications/crossbar/src/modules/cb_accounts.erl) | Account schema and existing GET/PATCH/POST provide the storage/API seam. The preference is implemented through the tracked Crossbar installer patch. |

The endpoint wrapper defaults to v5 outside tests, while its test configuration
selects v4; testing the wrapper alone would miss the normal v5 implementation.
Source inspection establishes the four selectors, not which one serves a
particular live account. No live account documents or loaded configuration were
queried, and no forwarded call was placed during this assessment.

FreeSWITCH documents `group_confirm_file` as the audio played to the destination
while awaiting confirmation. Its locally available originate source also
compares collected digits to the confirmation key and has a playback-error
hangup path. A broken media reference can therefore affect call delivery;
asset readiness matters. [FreeSWITCH channel variables](https://developer.signalwire.com/freeswitch/reference/channel-variables/).

## Recommended account behavior

Add an optional, account-only object, provisionally:

```json
{
  "call_forward_confirmation": {
    "language": "he-il"
  }
}
```

Supported explicit values are `en-us` (English), `he-il` (Hebrew), `ar-sa`
(Modern Standard Arabic), `es-es` (Spanish), and `fr-fr` (French).
The field is separate from the forwarding destination/enabled settings and
the general account `language`. It does not enable forwarding or keypress
confirmation. It is used only when the selected forwarding rule already
requires confirmation, including the failover path that uses this prompt.

| Account state | Proposed behavior |
| --- | --- |
| Preference absent | Execute the current prompt resolver unchanged, preserving existing language and custom-media behavior. Do not migrate all accounts to a new English recording. |
| EN, HE, AR, ES or FR explicitly selected | Use that account's selected built-in recording for the forwarded destination, regardless of caller, user, device or queue language. |
| Existing account-specific recording | Keep its document and bytes. Explicitly adopting a built-in language takes precedence for this prompt; clearing the preference restores the existing resolver. |
| New account or sub-account | Reuse the installed shared assets. With no explicit preference, retain existing default behavior. There is no new parent-to-child cascade in this first version. |
| Preference changed during a call | Already-created legs retain their selected prompt. Subsequent forwarded legs use the new value after normal cache invalidation, without a service restart. Measure and document propagation during acceptance. |

One small shared media helper should resolve the preference using the account
that owns the forwarding endpoint/rule. Confirm account identity at each call
site; do not infer ownership from caller ID, destination number, or the signed-in
reseller. Keep the original resolver as the unset/error fallback at each site.
Use existing cached account reads and change notifications, with bounded error
handling and explicit cache tests. Avoid adding a core dependency on ACDC.

For explicit built-in selection, resolve a versioned, feature-specific system
media document rather than overwriting or repointing `ivr-group_confirm`.
This follows the existing prerecorded-media approach while keeping this feature
independent of queue voice settings. Verify the exact selected asset before
accepting a preference change and before enabling a release on every serving
node. If a runtime lookup later fails, log the failure and attempt the existing
prompt resolver while retaining the confirmation requirement. Do not unset
`Confirm-Key`, silently auto-connect, or attempt online synthesis. If media
delivery itself fails after resolution, the existing call-failure behavior
still applies; no transparent recovery is claimed.

## API and OpenAPI plan

**Reuse `GET` and `PATCH /v2/accounts/{ACCOUNT_ID}`.** A separate service or
dedicated mutation endpoint is unnecessary for one account preference. The
custom frontend and MonsterUI should use the same contract and account ID.
These routes exist today; the following field and reset semantics are proposed.

```http
PATCH /v2/accounts/{ACCOUNT_ID}
X-Auth-Token: <runtime token>
Content-Type: application/json

{"data":{"call_forward_confirmation":{"language":"he-il"}}}
```

GET returns the persisted field in the normal account `data` object. Use PATCH
for this setting to preserve unrelated account fields. The existing POST path
validates a submitted account document and preserves private fields; it is not
a substitute for a narrowly scoped PATCH with a partial account body.

Proposed reset request:

```json
{"data":{"call_forward_confirmation":{"language":null}}}
```

Implement and test reset normalization explicitly: remove the stored language
and empty feature object before account schema validation/storage. Do not assume
Crossbar's merge semantics already delete nulls. Omission in PATCH means no
change; malformed values and unsupported locales are rejected. The persisted
schema contains only supported strings, and the PATCH request schema separately
documents the deletion marker.

Check permissions on the server for changes to this preference, including
creation, PATCH and full-document POST/reset. Permit account administrators and
properly authorized account-management principals with the required tenant and
token scopes. Generic [cb_simple_authz.erl](../applications/crossbar/src/modules/cb_simple_authz.erl)
includes same-account/ancestor authorization, so an admin-only UI is insufficient
proof of restricted-user protection. Preserve the preference on unrelated
updates and prevent older full-document clients from accidentally clearing it;
make reset an explicit operation for this new field. Test unchanged GET-to-POST
round trips as well as changed values.

During implementation, update the canonical account schema/accessors, handler
validation, and a source-reviewed account overlay in the existing
[build-api-docs.cjs](../scripts/build-api-docs.cjs) pipeline. Document auth,
envelopes, locale enum, unset/default/reset behavior, asset-unavailable errors,
permission failures, not-found/conflict responses, and a custom-frontend fetch
example. Preserve existing account operations and their schemas. Regenerate and
validate the catalog, then publish matching `/apis` assets with the backend/UI
release. This assessment does not add an unimplemented field to the live spec.

## MonsterUI plan

Add **Forwarded-call confirmation language** to **Callflows → Account Settings**.
Offer English / עברית / العربية / Español / Français and a short explanation that the choice controls
the message heard by the forwarded recipient before pressing 1. Represent an
unset preference as “Current behavior”; opening or saving unrelated settings
must not silently opt the account into a new recording. Provide a reset control.

Keep the existing per-user/device “require keypress” option separate. The local
SmartPBX forwarding editor supports ordinary forwarding and failover, and its
checkbox is inverted into `require_keypress` when saved. Preserve that behavior.
An optional read-only note there can point administrators to Account Settings;
do not add competing per-user language preferences.

The inspected Monster sources are in the installer checkout:
`/usr/local/src/kazoo5-installer/monster-ui/src/apps/callflows/app.js`
(`renderAccountSettings`, `bindAccountSettingsEvents`) and
`views/accountSettings.html`, plus
`src/apps/voip/submodules/users/users.js`. These are source seams, not an assertion
that the currently served bundle has identical bytes. The repository directly
bundles ACDC; the other apps are fetched at pinned revisions by
[install-kazoo5.sh](../scripts/install-kazoo5.sh), `sync_monster_ui_sources`.
Ship the change as a tracked installer-applied patch with build-input tracking,
localization strings and focused UI checks. Editing only the installed bundle
would not survive rebuilds.

Use an isolated PATCH/save action for the new preference and refresh account
state after success. Check the existing full-account Save flow for stale data
so it cannot overwrite the new choice. Preserve pending form edits, account
switching, restricted-user visibility, error handling, and native Hebrew/Arabic
labels. The implemented follow-up also supports the main Update button: include
a changed language in the account POST, omit an unchanged selection, retain the
form on success, and show visible fallback section/field labels with left-aligned
options as requested by the user. Deploy
the selector only after backend and all five media choices pass readiness.

## Audio plan

Google's current TTS documentation lists English, Hebrew and Arabic and lists
Sulafat among its voices. The project already has Gemini authoring and WAV
packaging tools. This supports feasibility; it does not certify a new recording's
translation or pronunciation. [Gemini speech generation](https://ai.google.dev/gemini-api/docs/speech-generation#supported-languages).

Recommend generating **five recordings once during release preparation**, then
switching the account's reference when its language changes. The user's idea of
generation on each change is possible, but adds provider availability, waiting,
retries and credentials to settings changes without improving a fixed message.
The prebuilt approach also follows the project's existing queue-audio practice.
Authoring made five provider requests; no provider credential is needed for installation or use.

Use the same message meaning in all five languages: identify a forwarded call,
press 1 to accept, hang up to ignore. Select one consistent voice, review the
translations and listen to every complete recording. Package immutable PCM16
mono masters and 8 kHz telephony WAVs with transcripts, model/voice provenance,
hashes and duration/clipping checks. Confirm the authoring model is available
when generation begins. Import shared media create-only and verify byte readback
and playback references on apps/media/eCallMgr nodes. Never overwrite customer
recordings or require generation during installation, account creation or calls.

## Work sequence, risk and acceptance

| Task | Deliverable | Completion evidence |
| --- | --- | --- |
| FWD-01 | Assessment and concrete design | This document; implementation subsequently authorized. |
| FWD-02 | Account schema, permissions, resolver and all four integrations | Direct v4/v5 and directory tests; absent preference preserves existing outputs; explicit selection changes only the confirmation file; API persistence/reset and cache tests. |
| FWD-03 | EN/HE/AR/ES/FR prerecorded assets and installer support | Reviewed speech; exact media bytes/readback; repeat install and missing/corrupt-asset rejection; operation without a Gemini key. |
| FWD-04 | Account-level Monster selector | Save/reload/reset, unchanged-form, stale-save, account-switch, restricted-user and RTL checks against the compiled UI. |
| FWD-05 | API/OpenAPI/custom-frontend contract | Actual handler validation agrees with request/response examples and generated schemas; matching catalog publication. |
| FWD-06 | Controlled call acceptance and rollback | Tests below on isolated accounts, then a designated physical cellphone route. |

A provisional estimate is **3–5 engineering days** for implementation,
integration and controlled development acceptance, assuming available test
destinations and voice review. External listening/scheduling and broader cluster
acceptance can extend that. This is a planning estimate, not a measured delivery
commitment. Basic implementation is small; verification across routing paths
and installer-owned UI/media accounts for much of the work.

Acceptance must establish:

- EN, HE, AR, ES and FR play to the forwarded recipient; a different account's selection
  and the incoming caller's language do not change that result.
- Correct key 1 connects exactly once; wrong key, no key, mobile voicemail,
  rejection and caller hangup do not produce an unintended bridge. Compare
  timing/repetition to each path's existing behavior rather than changing it.
- Ordinary forwarding, failover, and applicable simultaneous ringing retain
  caller ID, early-media behavior, answer ownership and cleanup. Direct calls
  without forwarding/confirmation and ACDC callback prompts remain unchanged.
- New calls observe setting changes after cache invalidation on every serving
  node; in-progress legs are stable. No restart is needed for a preference edit.
- Existing custom overrides, absent settings, reset, unavailable account/media
  data, and unauthorized/cross-account/expired-token writes behave as documented.
- Complete HE/AR audio and DTMF work on a designated real cellphone route, with
  native listening review separate from format checks and synthetic call tests.

Roll out assets and backend first with every account initially unchanged, then
the UI and matching documentation. Enable one isolated account per locale and
run the call cases before broader adoption. Record the previous account value
and build/media identities. Roll back that account through the explicit reset
or restore its prior value; retain existing media and previous backend/UI builds.
Do not change the global prompt to activate or roll back this feature.

The unresolved risks are media delivery failures, missed routing paths, stale
account settings and unintended changes to confirmation behavior. The design
limits them through explicit account adoption, existing call control, immutable
assets and reversible settings. Until the acceptance evidence exists, describe
this as a feasible design with controlled risk, not a risk-free deployed feature.
