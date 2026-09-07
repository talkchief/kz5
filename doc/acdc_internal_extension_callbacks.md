# Account-local extension callbacks

September7: focused four-module deployment, current-account request construction
and isolated internal1001 retry acceptance pass. The separate operator MicroSIP
1000 test and broader release acceptance remain open.

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

## Isolated native-transport retry harness

`scripts/test-acdc-callback-retry.sh` now accepts `--transport internal` in
addition to its default external mode. Internal mode uses only the existing
isolated account7807ad61761269a1ccec833dde63f621, numeric extension1001 and its
registered `acceptance1001` SIP device. The returned phone listens at
127.0.0.20:16060, with media44000. It does not replace the user's MicroSIP1000
registration or change the main account. A preflight refuses an already
registered fixture identity. Its absence check recognizes only the installed
Kamailio RPC's exact `error: 500 - AOR not found in location table` result;
arbitrary errors are not evidence of absence.

Internal mode requires a privately pinned user/flow target in the durable
callback, unchanged across both attempts. Packet gates require the native
username and dedicated localhost endpoint; external-carrier evidence fails the
internal contract and vice versa. It retains the existing single6, complete
Gemini audio before BYE, busy-agent release, unanswered first attempt, durable
backoff, completed digit1 before the agent INVITE, reciprocal bridge and media
checks. Cleanup additionally binds the internal target to the exact borrowed
user/flow IDs and returned endpoint; it cannot terminate arbitrary1001 calls.

Run under the serialized validation guard, with no other active calls:

```sh
bash scripts/test-acdc-callback-retry.sh --live --keep-fixture \
  --registration-mode entry-only --transport internal \
  --confirmation-reference /protected/verified/acdc-callback-success.ulaw
```

The first trial stopped on an overly narrow registrar preflight. The second
stopped on REGISTER timeout using127.0.0.30; both stopped before callback calls.
The revised trial uses the existing phone-side127.0.0.20 address. Later trials
proved that the early native channel can omit `sip_call_id`: the expected
outbound UUID is retained with an explicit source label, and final packet proof
must independently match it. It is not treated as an observed channel variable.

Trial `20260907T151923Z` exposed a test-phone response bug: saving `[last_Via:]`
inside the initial receive action produced an empty value, so the actual100/180
responses had no Via headers and the proxy retransmitted the INVITE. The native
unanswered scenario now explicitly extracts the second received Via occurrence,
alongside the existing first header, and preserves both in INVITE responses.
CANCEL/ACK retain their independently verified top-hop transaction. Duplicate
packet validation also rejects changes in the second Via. This follows SIPp's
[header-occurrence extraction](https://sipp.readthedocs.io/en/latest/scenarios/actions.html).
These changes are test-harness fixes, not callback runtime changes.

The corrected run `b6e938/session58987/493a66` finished exit0. Evidence directory:
`/var/log/kazoo-acceptance/20260907T152609Z`. It proves busy-agent single6 callback
registration, full Gemini confirmation before BYE, initial-call release2s after
audio proof, unanswered first native return, positive CANCEL/487/ACK settlement,
durable retry_wait and a digit1-confirmed second return reciprocally bridged to
the agent. Final packet/media, agent-ready and unchanged-service gates pass;
scoped errors0/0 and new cores0. Its fixture is retained, not fully deleted.
This fixture is still not the separate operator1000 phone test or a production
release certificate. The default external-route regression was rerun on this
same parameterized harness: `c26844/session62944/efcaac` exit0, evidence
`/var/log/kazoo-acceptance/20260907T153203Z`. Its full packet/media diagnostic,
unanswered-first retry, reciprocal agent bridge and service/log checks pass.
That route uses the isolated loopback carrier, not real PSTN, and retains its
fixture too.
