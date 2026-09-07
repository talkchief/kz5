# Single-key callback live acceptance — September 7

**PASS, isolated English callback flow.** Root run `d26b83/0fcc7e` exited0;
protected evidence is `/var/log/kazoo-acceptance/20260907T131946Z`.
No Gemini request, media regeneration or core-service restart was used.

## Verified behavior

- One agent was already bridged to a first conversation. A second caller
  entered the queue and pressed **only6**,4.995seconds after answer. The strict
  packet check rejects an additional registration1 or repeated6.
- Durable callback registration preceded the complete installed English
  Sulafat confirmation recording. All5.491seconds arrived before server BYE;
  correlation0.999993, missing phrase samples0. This is exact audio delivery,
  not independent transcription or subjective listening certification.
- The first conversation remained bridged through that confirmation. The
  harness waited2seconds after its proof/setup work before releasing it;
  measured release was7.204seconds after phrase completion, not exactly2seconds.
- The first returned call was deliberately unanswered for15.967seconds, then
  cancelled. Durable `retry_wait` was verified. The second returned INVITE arrived
  0.922seconds after its durable due time (configured backoff15seconds) and was answered;
  returned-call confirmation1 preceded the agent INVITE by1.112seconds.
- The exact caller/agent pair formed a reciprocal native bridge. PCMU media
  was received in both directions (4913packets each), both agent conversations
  completed, and agent readiness returned.
- Core call-service states, PIDs and restart counts were unchanged. Final log
  checks reported0new file/journal errors and0new cores. Observed minimum host
  available memory was640944KiB. This was not a load/capacity test.

The source fix is in master0b26789. Only `acdc_callback_menu` was promoted:
loaded/disk module MD5 `f2395173bdf3183659ac45fc0b7fa6c5`, with old code released.
Deployment receipt/baseline rollback copy:
`/tmp/kazoo-single-key-deployment.LKf1lf` (`cd4e17/6fbfad`). Full canonical87,
reducer17, wrapper22, strict retry80/audio79, service-scope27 and deployment
control-flow7 tests are separate supporting evidence, not substitutes for SIP.

## Scope and restoration

The exact fixture is tenant-local and routes fictional numbers through a
loopback carrier, not PSTN or production phones. Its historical unresolved
documents were retained unchanged; full cleanup acceptance is explicitlyfalse.

The separate MASTER30-phone helper was paused to admit the test while preserving
the512MiB memory reserve. The test supplied its own isolated agent. Its receipt
explicitly records this limitation; the four core call services remained active.
After test exit, root verified zero native channels and restored the helper:
`7268a4/898117`, active/running PID1980329. Apps, ecallmgr, FreeSWITCH, Kamailio,
CouchDB, RabbitMQ, HAProxy and nginx were all active.

## Still open

The user's invalid `kz5_test` callback caller-ID configuration is separate and
was not silently changed. Configure an authorized dialable return destination
or explicitly allow alternate-number collection; do not weaken validation.
Actual30-second independent offers, real hold music, all-five-language playback,
complete prerecorded position composition, matching OpenAPI portal publication,
fresh/distributed installer acceptance and wider release gates remain open.
Gemini stays one-time authoring only; reuse all successful checked-in WAVs.
