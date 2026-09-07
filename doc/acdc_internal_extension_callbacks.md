# Account-local extension callbacks

September7: focused four-module deployment and current-account request
construction pass. End-to-end internal callback/ringing acceptance remains open.

The reported MicroSIP device sent `kz5_test` as caller ID. It now has internal
caller-ID number1000, changed through Crossbar and read back (`da514d`); its
external caller-ID configuration was preserved. Account-local callflow1000
targets the same enabled user. Merely setting caller ID was insufficient:
the previous callback transport sent every destination to offnet routing.

`acdc_callback_internal.erl` resolves exact numeric extensions up to six digits
in the requested account, supporting terminal user/device callflows only.
No pattern, catch-all, voicemail, forward or carrier fallback is used after
matching an internal route. Cross-account, disabled/DND, ambiguous or changed
targets fail closed. A trusted target identity is persisted privately in the
callback reservation and resolved again for every attempt. SIP endpoints must
carry the expected account/device identity; mobile and forwarding routes are
not admitted by this path. Existing external-number authorization is unchanged.

The caller publishes native resource origination over AMQP, preserving the
existing durable READY-before-execute, cancellation, confirmation and retry
lifecycle. Native responses are validated and correlated before adaptation;
malformed payloads cannot crash the adapter. Registration and every retry still
validate the queue's configured authority and account restrictions.

Root `4be707/4261f8` passes29 internal/external-policy regression tests after
isolating ordinary call-language/privacy defaults in the offline fixture.
These tests include request shape and response correlation, not a live broker,
device registration, DTMF confirmation, voice playback or unanswered retry.
Full canonical regressions now pass87 (`03917f/d91ac3`), and all13 focused
production modules compile without TEST (`592f91/e0e1cc`), retained under
`/tmp/kazoo-callback-media-build.qg16Ob`. Current-device endpoint construction
passes the read-only probe below; real extension1000 calls remain. The OpenAPI queue POST/PATCH descriptions now
document account-local routing, target revalidation and no carrier fallback for
failed matched routes. Rebuilt documentation passes schema/negative/determinism
checks (`20052e/a78e1c`, `1b2e55/b77ce0`) and is served at `/apis`; exact served
bytes verified `8a4484`. Previous docs retained under
`/var/lib/kazoo-api-docs-backup.POLoxv`.
Do not treat this document as release acceptance.

## Focused runtime deployment

`scripts/deploy-internal-callback.cjs` promotes only `acdc_callback_internal`,
`acdc_callback_policy`, `acdc_callback_store`, and `acdc_callback_caller` from a
verified13-module production candidate. No TEST BEAMs, announcement modules,
dashboard/statistics records, services, queue configuration or rosters changed.
Preflight verifies zero live channels, exact source/dependency/artifact hashes,
old disk/runtime identity and free old-code slots. Original modules are backed
up before promotion. It never force-purges processes.

Initial by-name OTP atomic loading could not locate the new module through its
application-directory cache (`f7763d/df8a81`, `nofile`). Both attempted promotions
rolled back and verified original disk/runtime code. The corrected helper reads
exact protected files and verifies SHA-256 in the target VM before OTP's atomic
binary-cohort load; it does not reset code paths. Successful deployment:
`d116f0/6c6bb3`, backup `/var/lib/kazoo-internal-callback-deployment.i8kMw1`.
All four installed hashes and loaded MD5s match the reviewed build. This helper
is a one-off development promotion gate, not a substitute for main-SH compilation
on future nodes or a reusable arbitrary hot-upgrade system.

Read-only runtime check `8a22d5/239d62` against the reported account/queue and
extension1000 passes: current authority accepted, one native device endpoint,
valid `resource/originate_req`, `Originate-Immediate=false`. It does not write a
reservation or publish a request. Reproduce with:

```sh
node scripts/probe-internal-callback.cjs ACCOUNT_ID QUEUE_ID 1000
```

This proves directory/policy/endpoint construction on the actual configured
device, not registration reachability, SIP ringing, media, returned confirmation
or retry completion. Those remain mandatory live gates.

## External-route regression after promotion

The existing external-route fixture completed successfully after this deployment
(`170c04/session87038/7cfb8b`), with evidence retained at
`/var/log/kazoo-acceptance/20260907T144250Z`. One busy agent, single6 at about5s,
full5.491-second Gemini confirmation before caller hangup, busy-call release2s
later, unanswered first return attempt, durable retry_wait, and second-attempt
reciprocal bridge all passed. Scoped error logs/new cores were zero. This used
the isolated loopback carrier, not the new internal transport or real PSTN.
The diagnostic retained its fixture; it is not full cleanup or production
acceptance. It must not be substituted for the internal1000 live test.
