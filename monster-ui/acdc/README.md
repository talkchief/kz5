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
- Agent login, logout, timed pause, and resume controls.
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
but only enables verified installed packs. Automatic multilingual import,
backend activation, and publication of `apps/acdc/language-capabilities.json`
are not yet wired into the installer. That artifact must only be published
after runtime verification; builds must never manufacture it. The UI checks the version 1 capability proof
and all 29 fixed prompt attachments. Internal `acdc-number-*` audio chunks are
excluded from editable media choices and per-prompt browser requests. Missing
capabilities allow only the existing verified English fallback; corrupt or
unreachable capability data disables language editing. Synthetic packs lacking
native-speaker review are explicitly labeled, not presented as native-approved.

It uses the account-scoped Crossbar resources implemented by `cb_queues`,
`cb_agents`, `cb_acdc_call_stats`, and `cb_callflows`; it does not include mock
data. Callflows without the app's complete ownership marker and expected shape
are never modified or removed.

The announcement language is a lowercase BCP 47 locale such as `en-us`. When
it is blank, ACDC retains the incoming call/account prompt language and Kazoo's
system prompt default is English (`en-us`). Callback configuration and
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
