# Atomic ACDC answer selection

Status: source-level regression tests only. A coordinated FreeSWITCH module
deployment and the true simultaneous-answer live acceptance remain required.

The isolated live strategy test found that three agents answering together could
all be disconnected before any `CHANNEL_BRIDGE`. FreeSWITCH 1.11.3's ordinary
`intercept_unbridged_only` checks `CF_BRIDGED`, but `uuid_bridge` establishes media
asynchronously. Another intercept can replace the pending partner in that gap.
Separately, an originate success response can arrive before the actual bridge;
ACDC must not treat the first such response as the winning media leg.

## Protocol

1. Ecallmgr routes ACDC agent originates to `kz_intercept:<member-call-id>`.
   Generic non-ACDC intercept remains unchanged. ACDC cannot opt into takeover
   using `Intercept-Unbridged-Only=false`; malformed member IDs fail closed.
2. The module verifies live same-account channels, a nonempty agent identity,
   and an exact `Member-Call-ID` equal to the target. A mutex reserves the target
   before invoking core intercept. Only one agent may enter the asynchronous
   bridge window. Other agents receive `LOSE_RACE` on their own legs only.
3. ACDC retains one acceptance candidate per selected process, then matches the
   accepted `Agent-Call-ID` to a same-account caller `CHANNEL_BRIDGE`. Either
   event order is supported, including a losing agent's acceptance arriving first.
   Only the matching winner is handled; only other agents receive cancellation.
   The same candidate join protects native callbacks.
4. A media `LOSE_RACE` clears a losing agent to its requested availability without
   incrementing failure counts, unsolicited logout, or customer-call wrapup.
   The agent also validates the full bridge event's account and own leg; hearing
   the shared caller's bridge to another agent cannot falsely mark it answered.

## Claim lifetime and failure handling

Each target owns one fixed-size claim in its session memory pool. There is no
global UUID registry, retry allocation growth, timer-based winning decision, or
per-session callback pointer. A random owner nonce distinguishes delayed destroy
events from a later session reusing the same UUID. Duplicate execution by the
same owner is a no-op. Intercept failure or an exact owner `CHANNEL_DESTROY`
releases the claim; target destruction frees its storage automatically.

A failed `session_locate` is **not** proof of death: FreeSWITCH uses a fallible
read try-lock. Cleanup with an unavailable target therefore fails closed rather
than granting another claim. If that destroy event cannot be applied, the claim
remains reserved until the target ends. No other caller or arbitrary UUID is
terminated to recover it. Module shutdown disables new claims and unbinds the
global destroy listener synchronously; active-call module reload is unsupported.

After a real ordinary-call bridge, delayed retry/ring/connection timers cannot
start a second originate or cancel the live partner. If selected-agent acceptance
is still missing after 15 seconds, the worker records an error and keeps the
actual call alive without claiming successful handling. Native callbacks retain
their existing bounded proof/reconciliation lifecycle.

## Validation and deployment

The Erlang atomic changes remain explicit supplemental patches. The existing
native `mod-kazoo-atomic-intercept.patch` is now included in the default installer
source aggregate; its 21-case offline installer/source regression passes, but
this is not evidence of a new runtime deployment. See
[the installer reconciliation](mod_kazoo_version_namespace.md#atomic-intercept-installer-reconciliation--2026-09-06).
The reproducible source order is:

1. Apply the installer's current `mod-kazoo-kz5-integration.patch` in the pinned
   module tree. It already includes `mod-kazoo-atomic-intercept.patch`; do not
   apply that supplemental patch a second time. Independent replay uses the
   original thirteen patches followed by the unchanged atomic-intercept patch.
2. Apply `scripts/patches/acdc-kazoo5-integration.patch` to pinned ACDC, then
   `scripts/patches/acdc-atomic-answer-runtime.patch`. The independently staged
   `acdc-language-runtime.patch` is optional for atomic answering; to reproduce
   all current source, apply it between the baseline and atomic patch. Its
   files do not overlap the atomic layer.
3. Apply `scripts/patches/ecallmgr-kazoo5-integration.patch` to pinned Ecallmgr,
   then `scripts/patches/ecallmgr-atomic-answer-runtime.patch`.

`scripts/refresh-kazoo-integration-patches.cjs --check` verifies forward replay,
exact source bytes and reverse replay for these Erlang layers. `--write` keeps
the language patch unchanged and preserves the pre-staged versions in default
baseline aggregates; it never silently promotes language/atomic work into the
installer. Production deployment still requires the ordering and idle-call
gate below.

- `bash scripts/test-mod-kazoo-intercept.sh` executes the production app with a
  deterministic FreeSWITCH boundary, including 100 three-thread answer races in
  the pending-bridge window, ownership, nonce replay, duplicate execution,
  bounded allocations, failed intercept, and shutdown.
- `bash scripts/test-acdc-strategies.sh` tests selected-process/media-leg joining,
  losing acceptance first, duplicates, wrong account/call, timer isolation,
  missing proof, native callback joining, and loser availability.
- `bash scripts/test-acdc-callback-queue.sh` and
  `bash scripts/test-ecallmgr-originate-reconcile.sh` cover compatibility.

Deploy the patched `mod_kazoo` before the new Ecallmgr originate beam. The queue
record gained a private bridge-proof field, so use the coordinated zero-call
node restart, not a hotload into existing queue workers. Module-only compilation
is sufficient; a full FreeSWITCH rebuild is unnecessary. Re-run the isolated
live strategy harness after deployment; unit tests do not prove real media.
