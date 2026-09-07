# Mobile bridge development installation — September 7, 2026

The modular installer now installs the bridge as an enabled, running service.
This is a development broker-readiness result, not production/mobile delivery
acceptance. No notification was published or sent during these checks.

## Installation and evidence

Latest OAuth transport deployment `3f5035/session60404/aa39ab` passes main SH;
release `5d3745fd54bc8297f586c8ebb9c8e917de410957d9f02b6c04070c75997b5afa` is
enabled/active with registered consumer PID301642, zero automatic restarts.
All103 bridge tests and installer dispatch pass `325b4d/c536f1`. Independent
main-SH verification plus the15 OAuth cases in the new venv pass
`67c5ba/a1b50e`. OAuth session reuse, request connect/read bounds, redirect
rejection and decoded64KiB body cap are deployed; total deadline and delivery
acceptance are not. See `push_bridge_oauth_deadline.md`. Previous releases
remain. Production and provider notifications were untouched.

Operator clarification rechecked September7: the configured FCM service-account
and APNs keys were already retrieved read-only from production10.1.0.28 using
the protected SSH credentials. No additional production retrieval or mutation
was needed. Independent main-SH verification `8c6713/session38308/7f467d`
passed protected configuration, locked dependency versions, deployed source
and broker-consumer readiness. Passive readback `676802` confirmed active/running
and zero automatic restarts. This did not contact either push provider, validate
provider permissions, or send a mobile notification.

FCM session-pool deployment `01728e/session59026/abcc83` passed through the
main SH. Current release is
`/usr/local/lib/kazoo-push-bridge/releases/c36d971f6f8a1630af942cc1e8b7ee51c3adced67d6d124c500caea329a04db2`.
Each FCM send exclusively leases one reusable session; total sessions are capped
at WORKERS. Shutdown defers all session closing until active sends finish.
All88 bridge tests and installer dispatch pass `0f958e/5f962f`, including nine
real pinned-Requests/fake-adapter tests. Enabled/active PID259472 with registered
local consumer and automatic restarts0 (`46b546`). Previous release retained;
no production change, broker-binding change or provider push. OAuth refresh and
whole-operation time bounds, durable recovery and real delivery remain open.
The independent `--verify-only push-bridge` phase in `5a5172/b0c93a` also
passed before the next voice-authoring process started in that guard.

Earlier focused FCM source deployment: `515d94/1f29eb` passed through the main
SH, using all18 hash-locked dependencies and the existing protected config.
It adds redirect rejection before Requests redirect/body processing and closes
streamed responses without reading them. Six real pinned-Requests/fake-adapter
tests pass (`be4d36`); all79 prior tests plus installer dispatch pass
(`a6ee6e/73b78f`). New release
`/usr/local/lib/kazoo-push-bridge/releases/8b6eb7b60923ba295b0ecc074c0ebf78835bbaa201360211fb87c7bb29745d23`
is enabled/active with consumer PID111917 and automatic restarts0 (`82056a`).
The prior release remains on disk. All eight core services remain active.
This made no provider calls and did not change production or AMQP topology.
Independent main-SH `--verify-only push-bridge` also passed (`3c03ae/324540`).

```sh
sudo bash scripts/install-kazoo5.sh push-bridge
sudo bash scripts/install-kazoo5.sh --verify-only push-bridge
systemctl status kazoo-push-bridge.service
```

- Main installer run `d789ab`, session46947, terminal `55d3b0`: exit0.
  Rocky9 provisioned Python3.11 plus dependencies; all18 pinned bridge packages
  installed with wheel hashes verified, `pip check` and exact-version checks pass.
- A dedicated non-root `kazoo-push-bridge` account owns the running process;
  root owns release code. The service is enabled and active, `Type=notify`;
  readiness reports an actually registered AMQP consumer. Initial PID49686,
  `NRestarts=0`, observed in `d6a984`.
- Separate main-SH verification `d6a984/c0c60f`: exit0, exact source/unit bytes,
  dependency/configuration checks and consumer status pass.
- `b5fb19`: installed SDKs load the configured FCM service account and production
  plus sandbox APNs signing keys as the service user in an isolated network
  namespace. No credential values, provider JWTs or payloads are printed.
- Repeat main-SH installation `77bcab/1adade` passed, reusing the same release
  and dependency environment and restarting only the selected bridge service.
- Current network-isolated regression run `f1da0f/d65ad4` passes79 Python tests
  (8 configuration,19 runtime,14 settlement,23 APNs transport,15 service),
  installer selection/dry-run checks and13 cardinal installer adapter cases.
- Independent passive broker inspection `b24480/025319` confirms one consumer
  and zero ready messages on the isolated queue. Bridge PID53666 after the
  intentional repeat-install restart, automatic restarts0; all eight checked
  Kazoo/data/web services remain active.

## Protected configuration and production boundary

The operator authorized read-only retrieval from production10.1.0.28. SSH used
existing pinned host keys and credentials from the root-only key file. Its
bridge remained enabled/active/running with PID1226 before and after retrieval.
No production unit, broker, queue, package or process was changed.

Private source copies are in `/var/lib/kazoo-mobile-import.1AUqMO` (root0700).
The unit copy there contains secrets: do not print or commit it. Local deployed
provider files and JSON are in `/etc/kazoo-push-bridge`, root:service-group0750,
with only validated files0640. Source originals remain protected separately.
The one-off private migration helper is not part of the reusable deployment.
For new nodes use the tracked example and documented protected configuration.

The copied **production AMQP URL was deliberately not used**. This development
instance uses local RabbitMQ and a separate `kazoo5-mobile-acceptance` topic
exchange/durable queue, binding `acceptance.only`. It cannot steal production
messages and does not yet receive ordinary native `pushes` traffic. Do not
claim mobile integration is finished because this idle consumer is ready.

## Required next acceptance

1. Reboot, remote broker and failure/recovery acceptance. Repeat installation
   and its controlled bridge restart now pass on this development host.
2. Finish bounded durable retry/dead-letter/expiry and failure recovery. Current
   uncertain-delivery exit78 requires manual recovery; it is not high availability.
3. Complete OAuth refresh/total deadlines and AMQP TLS controls. FCM sessions
   now have tested exclusive leases bounded by worker count. Redirect/body
   controls remain tested in the expanded nine pinned-Requests
   adapter tests (`be4d36`); no provider was contacted. Validate real
   pinned HTTP/2 behavior, APNs initialization recovery and worker shutdown.
4. Use an explicitly designated test mobile device/token with the correct app
   and environment; verify native Kazoo payloads, provider acceptance, phone
   ringing, registration and answered calls. No test device is inferred from
   provider credentials or production configuration.
5. After acceptance, configure the development native exchange/binding; keep
   production queues and consumers separate. Never commit populated secrets.
