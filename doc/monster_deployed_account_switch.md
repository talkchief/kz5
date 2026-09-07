# Deployed Monster: optional native account switch

Verified on 2026-09-07: root3e50c7 passed16 offline groups; actual default browser
74850 passed7 checks and switched browser69219 passed10 against the newly built
and deployed `monster-owned-build.nUolDS` artifact. Receipts:
`/tmp/kazoo-monster-live-deployed.w8N0gc/receipt.json` and
`/tmp/kazoo-monster-live-deployed.tE4KRo/receipt.json`. Both recorded zero console,
page, HTTP and blocked-scope errors. Switched acceptance included home overview
ACK and disposal ACK before target, native account selection, target summary/detail,
and return home after target unsubscribe. This extends the deployed harness. It does not
originate calls, provision users/queues, impersonate a user, or demonstrate
restricted-principal isolation or natural-call rendering.

## Scope and normal controls

Existing same-account invocations are unchanged. `KAZOO_TEST_ACCOUNT_ID` and
`KAZOO_TEST_QUEUE_ID` remain the dashboard target. Optional
`KAZOO_TEST_LOGIN_ACCOUNT_ID` defaults to the target; a different explicit ID
enables account switching. `KAZOO_TEST_LOGIN_ACCOUNT_NAME` selects the normal
login company name and falls back to legacy `KAZOO_TEST_ACCOUNT_NAME`, then
`KazooMaster`. Credentials still come from the existing protected master-admin
file; no token or account state is injected into the page.

Switching additionally requires `KAZOO_TEST_LOGIN_QUEUE_ID`: one explicit,
lowercase 32-hex queue ID belonging to the login account. There is no guessed
queue or automatic inventory selection. The reviewed master queue is
`6729981c1d697e88aa31921eb6bad2da`; root must provide and confirm the intended
scope. Same-account mode still requires only its original target account/queue.

The initial switch-mode route is the normal `#apps/acdc`, not `#apps/apploader`
(which is not a loadable application route). Initial ACDC dashboard bootstrap
may send exactly one subscribe for the pinned **home account plus home queue**.
Target or other home queue subscriptions are denied during this phase. The
actual home overview must pass the application's snapshot validator, contain
only that pinned queue, and belong to the login account's active acknowledged
overview controller. The native same-connection reply must correlate to that
exact request, with `subscribed: [homeBinding]` and
`subscriptions: [homeBinding]`.

Next the harness clicks the normal **Queues** tab. A fresh subscribe is no
longer admitted. The home controller must be disposed, the home account must
still be selected, and the exact navigation-triggered unsubscribe must receive
`unsubscribed: [homeBinding]` with `subscriptions: []`. Only then does the home
admission window close permanently and the target-account window open. No new
home subscription commands are allowed afterward, including during restoration.
Duplicate or stale home request records cannot satisfy these ACK gates or a
target ACK gate. Request IDs cannot be reused on the same native connection;
the connection has a 200-request lifetime bound as well as bounded pending work.
These are observed native subscription replies, **not broker readiness**.

Only after home disposal and its ACK does the harness click the native topbar
account toggle and exact target-ID row. Both picker openings require the real
visible toggle to advertise `aria-disabled="false"`; no Common-module presence
heuristic or state injection replaces the Core readiness gate. If absent from the initial children page,
it types the ID and presses Enter in the native account browser. It waits for
initial list readiness first: the framework requires a non-Enter keyup to attach
its global-search link, so `fill()` followed only by Enter is insufficient.

The browser itself issues authorized GETs for children, account search and the
selected account. Successful selected-account GET, unchanged original login
account, target current account, visible masquerading state and ACDC's actual
target account are required. A failed account GET cannot be accepted merely
because the framework invoked its continuation callback.

Normal masquerading retains the administrator's existing token. It is distinct
from `auth.triggerImpersonateUser`, which is not used. Existing HTTP write guards
still permit only one `PUT /user_auth`; all other HTTP writes remain blocked.
Native queue-live commands are restricted to the explicit home window above,
then the target account only. Frames are forwarded unchanged to the actual
native connection, without fabricated ACKs or responses. No new authentication
authority is created.

The target company rerenders the retained **Queues** tab. The harness clicks
**Dashboard before waiting for its grid**, then preserves the original target
overview/detail proof: target-scoped snapshot/controller, one initial detail
GET, real detail subscribe ACK followed by a GET before periodic reconciliation,
and exact selected unsubscribe/disposal. Home wire records cannot increment
target ACK counters, even if two tenants use the same binding text.

After target detail verification, the existing normal Queues-tab navigation and
correlated selected unsubscribe ACK must finish before the native home-account
control is clicked. ACDC preserves the selected Queues tab during its normal
rerender, so original/current/app account must be restored and **no** live
controller may remain and the selected tab must still be **Queues**. On failure,
the ephemeral context closes; no persistent
logout, browser-state save or destructive rollback is performed.

## Artifact pins and proposed invocation

In switch mode the lazy served
`apps/common/submodules/accountBrowser/accountBrowser.js` must match the explicit
`KAZOO_TEST_EXPECT_ACCOUNT_BROWSER_SHA256` and the before/after deployed-file pins.
Its served hash is mandatory even though `common` is preloaded. The common CSS
is also pinned; any observed response must match those bytes. Main/templates and
the original deployed-artifact requirements remain mandatory.

For the reviewed `monster-owned-build.Fd3cY7` artifact, account-browser source and
deployed bytes both have SHA-256
`181c6df9a2673be24bb785c9668896ed6685bef08e88bc62d99fc40dcac7c7c7`.
Recheck the actual artifact for subsequent builds; do not substitute source
files into a deployed browser run.

Example environment additions to the existing root-reviewed live browser command:

```sh
KAZOO_TEST_LOGIN_ACCOUNT_ID=EXPLICIT_MASTER_ACCOUNT_ID
KAZOO_TEST_LOGIN_ACCOUNT_NAME=KazooMaster
KAZOO_TEST_LOGIN_QUEUE_ID=EXPLICIT_MASTER_QUEUE_ID
KAZOO_TEST_ACCOUNT_ID=EXISTING_ISOLATED_ACCOUNT_ID
KAZOO_TEST_QUEUE_ID=EXISTING_ISOLATED_QUEUE_ID
KAZOO_TEST_EXPECT_ACCOUNT_BROWSER_SHA256=181c6df9a2673be24bb785c9668896ed6685bef08e88bc62d99fc40dcac7c7c7
```

Use the previously reviewed compatible Node 20+ / Playwright installation and
actual deployed main/templates hashes. Root owns serialized resource admission
and any development-service restoration window. Do not use an isolated network
namespace for the actual live browser invocation.

The bounded offline command is:

```sh
node scripts/test-monster-live-deployed-scope.cjs
```

The sixteen offline groups exercise actual harness helpers with a controlled
page, including home admission phases, wrong account/queue, malformed or stale
ACKs, retained Queues tab, source ordering and default same-account behavior.
They read no credentials or live
services. It is not execution of Monster's account-switch framework. Actual
default and switched browser runs remain separate acceptance gates. Receipt
additions are fixed stage/category names and booleans, never IDs, names, tokens,
HTTP bodies or raw frame/exception diagnostics. The safe fixed browser-error
classification remains; the temporary RequireJS/Postal registry diagnostics
were removed. No new browser or offline test was executed while preparing this
revision; root owns the serialized guarded validation and current asset pins.

Source references: Fd3cY7 `src/apps/core/app.js` lines 327–340, 414–565;
`src/apps/common/submodules/accountBrowser/accountBrowser.js` lines 138–169,
189–196, 492–505; `src/apps/auth/app.js` lines 418–421, 2066–2072;
`src/js/lib/jquery.kazoosdk.js` lines 28–37. The lazy account-browser file is
also present byte-identically under the deployed web root. Tracked
`monster-ui/acdc/app.js:175` preserves the selected tab during rerender.
