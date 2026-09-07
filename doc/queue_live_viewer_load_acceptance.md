# Live queue viewer load acceptance

This is read-only **idle dashboard viewer** acceptance, not a call-capacity,
browser-rendering, reconnect, broker-failure or production-readiness claim.

## Reproducible harness

- `scripts/test-queue-live-load.cjs`: real HTTP selected-queue snapshots and
  native Blackhole queue subscriptions; existing protected authentication token.
- `scripts/test-queue-live-load-offline.cjs`: controlled-clock transport faults
  with the real response and event validators. No network or credentials.

The live command requires `--allow-load`, one exact account and queue, literal
loopback API/WebSocket endpoints, an absolute installed `ws` module path and a
root-owned0600 token file. It refuses redirects, unsafe token files and missing
arming. Do not put a token in the command line, repository or report.

Bounds:1–30 viewers,500ms minimum start spacing,15-second polling, one in-flight
GET per viewer,30–180 seconds with the entire cohort established,8-second
WebSocket stage deadlines and an overall deadline. Frames, payloads and socket
work are bounded. The shared acceptance lock must stay owned. Cancellation
stops HTTP/socket work; successful completion requires every subscription and
unsubscription ACK to match the requested queue. No login, fixtures, call
control, service operation, reconnect or event publication is performed by
the repository harness.

Every snapshot must validate the actual public DTO, no-store response, selected
scope, fresh call/agent observations and complete source consensus. Empty rows
alone are not an idle readiness proof. Partial/unavailable/stale results fail
the test rather than being treated as zero occupancy.

Example (replace scoped IDs and private paths with validated local values):

```sh
bash scripts/run-kazoo-validation.sh --memory-mib 128 --reserve-mib 512 --runtime-sec 150 -- \
  /usr/bin/node /opt/kz5/scripts/test-queue-live-load.cjs \
  --allow-load --account ACCOUNT_ID --queue QUEUE_ID \
  --api-url http://127.0.0.1:8000/v2 \
  --ws-url ws://127.0.0.1:5555/websocket \
  --token-file /private/acceptance-token \
  --ws-module /absolute/installed/node_modules/ws \
  --clients 2 --duration-seconds 30
```

Run the offline suite first; begin real acceptance with2 viewers and increase
only after the preceding run is terminal and passes. Preserve sufficient memory
for running telephony services. A refused resource guard is not a test pass.

## September7 evidence

- Offline `c3b213`/`5709e0`:14 groups PASS under128MiB cap/512MiB reserve and
  isolated network namespace. Covers30-client stagger/full-cohort timing,
  transport/ACK faults, scope rejection, stale/incomplete/active-call refusal,
  cancellation, lock loss, pending HTTP deadline and redacted receipts.
- Actual2 viewers `026802`/`3ff190`: PASS,30,001ms full cohort,6 valid fresh
  snapshots,2 subscribe and2 unsubscribe ACKs, zero errors, partial or incomplete
  snapshots. HTTP p50=62ms, p95/max=939.59ms. Zero natural invalidations occurred.
- Actual10 viewers `4e2352`/`10fc96`: PASS,30,001ms full cohort,30 valid fresh
  snapshots,10 subscribe and10 unsubscribe ACKs, zero errors/partial/incomplete
  snapshots. HTTP p50=57.39ms, p95=112.97ms, max=830.83ms.
- Actual30 viewers `91df3e`/`e967fb`: PASS,30,001ms full cohort,91 valid fresh
  snapshots,30 subscribe and30 unsubscribe ACKs, zero errors/partial/incomplete
  snapshots. HTTP p50=57.38ms, p95=106.23ms, max=1,002.42ms. No natural events
  occurred in either larger cohort; event handling under load is not proved.
- Extended30 viewers `2fbd95`/`90d1e4`: PASS,180,000ms full cohort,391 valid
  fresh snapshots,30 subscribe and30 unsubscribe ACKs, zero errors/partial/
  incomplete snapshots. HTTP p50=56.21ms, p95=97.5ms, max=969.67ms. No natural
  invalidations occurred. This three-minute sample is not long-duration soak.

All four jobs are terminal. Post-run check: all nine scoped services active,
zero FreeSWITCH calls. Application error.log remained160,320 bytes on inode581964
and crash.log remained48,653 bytes on inode581963 from the check during the
10-viewer run through completion of the extended run. This proves no additions
to those two files in that interval, not an audit of every logging destination.
No services were stopped or restarted, and no queue/agent mutation was issued.

Private evidence directory: `/tmp/kazoo-live-viewer-acceptance.HVcF2T`.
`run.cjs` authenticates once per run using existing protected installer settings,
keeps the returned token only in memory and invokes the same exported harness
with real transports/validators. It does not synthesize server responses.
Receipts contain aggregate counters and latency only; private settings are not
copied into this document or Git. No service was stopped for these runs.

At this checkpoint the live harness SHA256 is
`cb67b0441b9e360b1a026f601c26bb1cd7b84ecbbdd43fc5b1b4533671033dfe`,
and offline harness SHA256 is
`a9a095329c6dbcb3f9ee4cdf271818d5dc4b8d8f760e1b8c2955c6b0fc9fbc8e`.
The offline receipt also pins its imported transport/validator source hashes.

Remaining: sustained soak, natural call/event load,
cross-node behavior and failure/backpressure acceptance. Passing this short
idle cohort does not establish an SLA or support30 concurrent calls.
