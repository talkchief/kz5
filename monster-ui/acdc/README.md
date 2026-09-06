# Kazoo ACDC Call Center

An open-source Monster UI application for the Kazoo 5 ACDC APIs.

The app provides:

- Queue creation, editing, deletion, live counters, and multi-user roster management.
- Round-robin, most-idle, ring-all, and ordered agent selection. Ordered mode uses
  named roster priority controls and the backend `agent_order` contract; deploy
  it only with the matching backend/schema. The non-ring-all modes
  ring one eligible agent at a time; ring-all rings every eligible responder.
  The unused legacy `ring_simultaneously` value is preserved but is not exposed
  as an effective concurrency control.
- Music-on-hold, a once-per-call pre-connect announcement, and periodic spoken
  queue position and estimated wait-time announcements, with validated prompt
  names and an optional prompt language override.
- Optional internal-extension routing through strictly app-owned `acdc_member` callflows.
- Explicit queue-selection Login, with separate pending and confirmed runtime
  queue membership. This source candidate requires the matching runtime-only
  backend; it is not yet a live-deployment claim. Login only uses an existing
  configured enrollment and does not assign rosters or log out other agents.
- Existing global logout, timed pause, and resume controls remain separate from
  selected-queue membership. Global Ready and confirmed membership do not prove
  SIP registration, endpoint ringing, or immediate queue availability.
- Current agent status and answered, missed, and total call counters.
- Current queue activity and recent ACDC call-stat records.
- Staged queue-level callback configuration plus account/queue-scoped,
  privacy-filtered callback inventory and cancellation controls. The UI never
  exposes callback creation; only a live waiting caller may register.
- Loading, partial-data, empty, validation, and retry states.
- Named-user callback authority and automatic current user/account caller-ID
  inheritance, with an optional account-owned number override. Legacy device
  authority and explicit caller-ID settings are preserved until deliberately
  changed. No technical authority IDs or caller-ID names need to be typed.
- Catalog-backed language and media selectors. System prompts require verified
  attachments; incomplete catalog responses disable affected selectors and
  preserve unavailable existing values. Roster replacement is disabled when a
  current member is missing from the complete user inventory.

The staged language selector lists English, Arabic, Hebrew, Spanish, and French,
but only enables verified installed packs. The installer imports multilingual
media; backend activation and publication of `apps/acdc/language-capabilities.json`
are not yet wired in. That artifact must only be published
after runtime verification; builds must never manufacture it. The UI checks the version 1 capability proof
and the required fixed prompt attachments. In legacy capability mode, incremental
English readiness requires 42 provenance-verified immutable Gemini projections
(32 fixed messages plus all ten recorded telephone digits)
plus 15 attached official English prompts, not name-only aliases. Internal `acdc-number-*` audio chunks are
excluded from editable media choices and per-prompt browser requests. Missing
capabilities never imply readiness; corrupt or
unreachable capability data disables language editing. Synthetic packs lacking
native-speaker review are explicitly labeled, not presented as native-approved.

The queue language selector has exactly five choices and explicitly defaults new
queues to English, with no inherit/custom prompt or voice picker. Saving a
ready selected language adopts built-in prompts, even without changing its value:
editor PATCH null tombstones remove the
queue's announcement/callback media maps and old returned-confirmation alias
before storage. No media document or attachment is deleted. Existing legacy
settings survive unrelated edits when the selected language is unavailable; an unavailable
pack is never enabled just because it was previously selected.

It uses the account-scoped Crossbar resources implemented by `cb_queues`,
`cb_agents`, `cb_acdc_call_stats`, and `cb_callflows`; it does not include mock
data. Callflows without the app's complete ownership marker and expected shape
are never modified or removed.

Queue-editor recovery keeps the form editable while its explicit reload GET is
pending, but disables Save and duplicate recovery actions until that read ends.
The replacement form uses the latest name, roster and route edits, not a draft
captured before the request. Failed reads retain the original form and pending
operation; late replies cannot replace a detached form or a newer account/view.
This source repair requires a matching rebuilt UI before deployment; previous
artifact/browser receipts do not certify these changed bytes.
The 2026-09-06 isolated source-browser regression passed all15 cases, including
deferred reloads, overlapping Save/duplicate-read prevention, failed-read retry
and stale-response suppression. Its API responses were mocked; it made zero
network requests and is not live backend or compiled-artifact acceptance.

The queue language is one of the five supported lowercase locales. New queues
explicitly select English (`en-us`); the editor does not offer a blank/inherit
choice. Historical unavailable settings survive unrelated edits. Callback configuration and
inventory/cancellation source are present but must not be deployed or described
as working until the trusted caller menu, Crossbar API, durable coordinator,
returned-caller confirmation, recovery, and live SIP/DTMF gates all pass.

The optional pre-connect selector writes the queue API's top-level `announce`
media ID or prompt name and preserves existing custom URIs. This source control must not be deployed as accepted until the
same build passes the live audible pre-connect gate.

## Build

Place this directory at `src/apps/acdc` in the pinned Monster UI checkout, then
run:

```sh
npx gulp lint --app=acdc
npx gulp build-app --app=acdc
```

This source is licensed under the Mozilla Public License 2.0.
# Source contract tests

Run the contract checks from the installed Monster UI build checkout, whose
normal dependencies include Lodash:

```sh
cd /usr/local/src/kazoo5-installer/monster-ui
node /opt/kz5/monster-ui/acdc/tests/contract.test.cjs
```

Adjust the two paths when using a different project/build root. The checks read
the repository's ACDC source and make no API writes. Running from an unrelated
directory without Lodash installed will fail dependency resolution; that is not
a live API or call acceptance result.
