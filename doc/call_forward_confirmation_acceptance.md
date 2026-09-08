# Account-level forwarded-call confirmation language

Development implementation, September 8, 2026. The user authorized implementation
after assessment and added Spanish and French to the original English, Hebrew
and Arabic scope. The normal development installer, deployed API, simulated calls and browser
checks pass. The UI is ready for testing. Feature branch:
`feat/account-forward-confirmation-languages`; merging is left to the user.

The account field is `call_forward_confirmation.language`. Supported values are
`en-us`, `he-il`, `ar-sa`, `es-es`, and `fr-fr`. An absent preference preserves the
existing prompt resolver, including account/custom media and call/endpoint
language. Explicit selection uses an immutable shared recording. Other account
language, forwarding enablement, confirmation digit, timeouts and routing remain
unchanged. New legs use the selected preference after normal cache invalidation.

The existing account API exposes the preference:

```http
PATCH /v2/accounts/{ACCOUNT_ID}
X-Auth-Token: <runtime account token>
Content-Type: application/json

{"data":{"call_forward_confirmation":{"language":"he-il"}}}
```

Use `language:null` to remove the preference. Omission preserves it on PATCH and
full POST, including older clients. Changes/reset require an account admin,
account API-auth principal or system admin within existing tenant/token scopes.
Invalid input returns 400, forbidden changes 403, and failed selected-media
readiness 503. Stored/read data never contains the reset null.

MonsterUI: Callflows → Account Settings → Misc → Forwarded-call confirmation.
The dedicated Save language button sends this preference through PATCH, with
the standard MonsterUI request metadata.
The main Update button saves a changed language together with the other account
fields in the existing account POST, keeps the form open and confirms success.
An unchanged selection is omitted to preserve a newer value from another client. The
compiled bundle and the read-only `/apis/` developer catalog ship through the
normal installer. The OpenAPI account PATCH includes five examples, reset and
a custom-frontend JavaScript example.

## Source and packaging

- `scripts/patches/kazoo-call-forward-confirmation.patch`: account accessor,
  shared media resolver and all four endpoint/directory selectors.
- `scripts/patches/crossbar-call-forward-confirmation.patch`: schema, validation,
  authorization, omission preservation and explicit reset.
- `scripts/patches/monster-ui-call-forward-confirmation.patch`: actual Callflows
  app, account template and native language labels.
- `scripts/call-forward-confirmation-pack.cjs` and
  `scripts/assets/call-forward-confirmation-20260908/`: five masters, five 8 kHz
  PCM16 WAVs, provenance and pinned Erlang map. The normal installer validates
  sources, creates missing versioned documents only, verifies exact bytes and
  refuses conflicting/tombstoned/corrupt media. No synthesis during installation,
  account changes or calls.

Exactly five initial Gemini requests succeeded with Sulafat. Adding ES/FR
preserved all original EN/HE/AR bytes and generation attempts. Audio durations:
EN 6.531 s, HE 8.291 s, AR 8.331 s, ES 7.051 s and FR 6.251 s. Format, hashes, clipping,
silence and duration checks pass. Authoring manifests remain unchanged by runtime
tests; their `native_speaker_review` and `runtime_verified` fields are not release
certifications. Operational evidence is recorded here separately.

Authoring credential location for future maintainers: `/root/key.key`, protected
as a root-owned mode-0600 file and already used for ACDC WAV generation. Reuse the
Gemini-specific credential reader in `scripts/generate-acdc-gemini-samples.cjs`;
never copy the key value into source, documentation or logs. The five completed
recordings are shipped in Git. A fresh deployment needs no Gemini credential or
online synthesis; merge this branch into the release and use the normal installer.

## Completed checks

`bb9c13`: a clean export of committed Git objects at `d6bcde5` contains the five
masters, five telephony WAVs, manifest, compiled asset map, three patches and
installer integration. With networking disabled and credential/provider helpers
set to fail if invoked, the exported pack validates all five recordings and the
compiled map, imports five documents into an empty media fixture, reads back exact
bytes and creates zero documents on repeat import. Credential reads and provider
calls are both zero. This checks the committed feature payload and import path;
the actual full development installer result is recorded below. The private
receipt is `git-release-verification.json` in the feature acceptance work directory.

`24649/d164a4`: production compilation and seven focused Erlang groups pass.
Both endpoint v4/v5 and directory forwarding/failover select all five assets;
other confirmation variables are equal to baseline. Tests cover absence/custom
fallback, disabled keypress, account ownership, malformed media, authorization,
omitted fields, reset, positive fresh attachment checks and corrupted-byte 503.
Installer smoke and modular suites pass in the same guarded run.

`02bd01/77379`: five-locale authoring/resume/import test passes with synthetic
responses and no provider access. Create-only/repeat imports, preflight identity
conflicts, tombstones and WAV tampering are covered. The expanded UI fixture
passes all five choices, reset, duplicate click, error, stale account, restricted
user and RTL cases against the actual patched AMD app. Its baseline includes
the existing Callflows patch, which repairs upstream German JSON.

`78129/6b0b6e`: focused API schema checks and full generated OpenAPI validation
pass: 358 paths, 653 operations, 509 schemas, 1653 references. Deterministic rebuild
and tamper detection pass. A first generation attempt caught an inline upstream
schema incompatibility; using named account POST/PATCH schemas lets the existing
OpenAPI normalizer process both correctly. No failing artifact was published.

## Operator extension 1000 calls

The user confirmed this host cannot place real calls and authorized the account's
internal extension 1000. It resolved to the existing enabled MicroSIP device,
without changing its registration, forwarding or account settings.

The first direct-contact attempt timed out through NAT. A proxy attempt lacking
Kazoo AOR headers was rejected. Adding the normal AOR/invite-format headers to
the local proxy route reached the registered phone. No routing configuration was
changed to resolve these diagnostic dial-string errors.

| Locale | Call UUID | Server confirmation |
| --- | --- | --- |
| EN | `6d66d5ed-0b4b-4abf-a8a1-f13cea6011d1` | Press 1 accepted; user identified English |
| HE | `f17b0e25-c845-46a5-b9da-aeec14bae904` | Press 1 accepted; user identified Hebrew |
| AR | `95faa044-849d-4604-9a5a-5cfc76140545` | Press 1 accepted; user identified Arabic |
| ES | `af227d07-c925-48cc-b930-a65cf4f86f90` | Press 1 accepted |
| FR | `19c598a1-1279-42c3-9ffe-283a9db7c9e7` | Press 1 accepted |

These calls used FreeSWITCH's real group confirmation with the packaged WAVs
and a success tone after 1. They establish phone delivery and confirmation for
the recordings, separately from the account resolver/API deployment. They are
not a claim of a cellphone/PSTN forwarding test, native-speaker certification,
or every forwarding/failover/simultaneous-ringing combination.

Private working/rollback evidence: `/opt/kz5-fwd-implementation.530stmvg`.
Existing affected BEAMs/application inventories were copied to `pre-deployment`
before the normal installer began. Zero FreeSWITCH channels were verified.
Session 64656/94b843 completed the normal apps/eCallMgr/MonsterUI installation
with exit 0. Five media documents were created and read back with exact expected
bytes. Compilation, production BEAM inventories, service restarts/readiness,
media checks, owned UI deployment and the final installer verification passed.
The build used the existing 384 MiB cap, 512 MiB reserve and 3600 s deadline.
The source freeze is released.

The live HTTPS `/apis/openapi.json` was fetched with certificate validation and
matched the generated file byte-for-byte (5737db). SHA256:
`58d138b5b952c13e691fc6f6446fd91d929a0644b8c7e559e3ec2288e7e39349`.
It includes five locale examples, reset and the custom-frontend JavaScript sample.

The first live fixture hit the existing login rate limit and cleaned up both
test users. The fixture now backs off on authentication HTTP 429; no server
limit changed. A second run passed the administrator/invalid/restricted cases,
but its API-key lookup used the wrong response-envelope assumption. Using the
existing read-only `/accounts/{ACCOUNT_ID}/api_key` endpoint corrected the
fixture. Both failed fixture runs restored the preference and removed their
exact tagged test users. The corrected API and call cases completed in session62675; its final browser
launch failed because system Node18 is below the retained Playwright minimum.
All 20 API/call checks were recorded before that tool failure. Recovery in
97688/35cca2 restored the original preference and deleted both tagged users.
No application change was needed for these fixture issues.

## Deployed API, call and browser results

Twelve live API checks pass: administrator save/GET for all five languages,
invalid/extra field rejection without mutation, restricted-user change/reset
rejection, account API-auth principal access, unrelated PATCH preservation,
older full POST omission preservation, explicit reset removal and isolation
from the master account/general language. No account API key was rotated.

Eight local synthetic SIP cases pass against the running account resolver,
eCallMgr media URL resolution and real FreeSWITCH group confirmation. Each
positive case saved its locale through Crossbar, observed the new preference
through the normal eCallMgr account cache, received the complete prerecorded
phrase in continuous PCMU RTP and accepted digit 1. No cache flush was used.

| Locale | Received/reference waveform correlation | Press 1 |
| --- | --- | --- |
| `en-us` | 0.999992937 | Accepted |
| `he-il` | 0.999992800 | Accepted |
| `ar-sa` | 0.999994919 | Accepted |
| `es-es` | 0.999993491 | Accepted |
| `fr-fr` | 0.999994441 | Accepted |

EN wrong digit 2, no digit and recipient hangup all prevented connection; each
also received the complete expected prompt. These use a local synthetic SIP
recipient and bounded originate duration, not a physical cellphone or voicemail
service. Routing/keypress/timing equality across the four source selectors is
covered by the Erlang tests. Every real-world forwarding/failover/simultaneous
ringing combination and formal native-speaker certification remain outside this
development-server acceptance.

Browser session76280/888524 exited 0 with seven checks: the actual deployed
Callflows app renders all five choices with no automatic save, and saving HE,
AR, ES, FR, EN and reset each sends one successful PATCH and persists after
leaving/reopening Account Settings. No browser page errors, HTTP errors or
unexpected writes occurred. The fixture uses the existing Node22 runtime,
waits for masquerade navigation to settle, returns through the normal Back
button and allows exactly the preference plus framework `ui_metadata` on PATCH.
Earlier browser fixture runs exposed those timing/metadata assumptions; no
product-code change was required. The original confirmation preference was
restored; normal framework request metadata is retained.

Final readback e4c006 confirms 20 API/call checks, seven browser checks, restored
preferences, both tagged users deleted with their private credentials removed
from the final receipt, zero FreeSWITCH channels, and active apps/eCallMgr/nginx.
The browser image was inspected at `confirmation-settings.png` in the private
working directory. Source/offline checks and the successful normal deployment
precede this live evidence; no extra rebuild was run merely to refresh results.

## Developer handoff

Branch: `feat/account-forward-confirmation-languages` in `talkchief/kz5`.
The feature is delivered through tracked installer patches because upstream
core/Crossbar checkouts are pinned nested source repositories. The feature
worktree is `/opt/kz5-fwd-review`; unrelated fresh-server/TLS work in the shared
root index is excluded. The user will merge the branch.

UI: hard-refresh, open **Callflows → Account Settings → Misc → Forwarded-call
confirmation**, choose a language and press **Save language**. The general
account language remains independent.

Live documentation: <https://kz5.talkchief.io/apis/>. Downloadable specification:
<https://kz5.talkchief.io/apis/openapi.json>. See account GET/PATCH/POST and
`ForwardedCallConfirmation`. PATCH examples cover all five locale codes and
null reset; the JavaScript example is suitable for the other frontend.

## UI follow-up: labels, alignment and Update

The user reported missing dropdown/section labels, right-aligned language text,
and the main Update button closing without applying a newly selected language.
The final control has a semantic section heading, an associated visible label,
left-aligned 320 px selector and native language labels. Its title/label/status
strings have English fallbacks when a locale entry is absent. The default option
is short enough to display in full.

Both Save language and Update work. Save language retains the scoped PATCH.
Update includes the preference only when the dropdown changed, saves account
fields through one POST, refreshes the saved preference and stays on the form
with confirmation. If another frontend changed the preference and this dropdown
was untouched, Update omits the field and displays the newer server value.
Errors preserve the pending selection; duplicate saves and stale-account
callbacks remain guarded.

Actual formatter/handler regression tests passed b649a8. The first header
revision exposed an incorrect global `self` reference in the formatter during
browser acceptance; it was corrected to the app instance and covered directly.
The corrected normal MonsterUI-only installer92313/fb92d5 exited 0 with owned
bundle, catalog, HTTPS and final deployment verification. No backend code or
recording changed for this follow-up.

Deployed browser97471/06800e exited 0 with ten checks: header, associated label,
computed left alignment/320 px width; Update save, visible form and reopened
persistence for all five languages and reset; dedicated PATCH save; preservation
of a newer API preference; and visible labels with locale entries deliberately
absent. The inspected image `confirmation-settings-updated.png` shows Arabic
aligned left. Final readback d7d5c3 confirms the full test account settings were
restored, no browser errors/unexpected writes, zero channels and active services.
