# Built-in Gemini callback offer: September 7 acceptance

Scope: one isolated local EN-US queue call using the installed immutable
`acdc-callback-offer-6` Gemini WAV, silence hold, positions disabled, no DTMF.
This does not certify callback registration/confirmation/retries, real music on
hold, other codecs, all languages or full-position composition.

## Fresh complete live runner PASS

Root `c88ff7/d9b680` exited0, evidence
`/var/log/kazoo-acceptance/20260907T120840Z`. Complete offers began at
3.069/18.089/33.069s and finished at8.240/23.260/38.240s, each with0.999993
correlation against that run's verified reference. No early offer, zero capture
drops, complete received PCMU and normal46.011s teardown. Startup gap29.277ms
is reported separately from15,766 observed quiet entry samples.

The fresh run also passed service PID/restart-state comparison, announcement
worker cleanup, fresh journal/file error checks and no-new-core checks.
Exact conditional fixture cleanup then passed; zero agents changed and
unrelated account documents unchanged. No service was restarted and no provider
was contacted. This closes this specific EN offer-over-silence acceptance slice,
not the separate key6/retry/other-language or production-release gates.

Reference PCMU hash for this run:
`8856a894869a83ce119004869c3de97bd93e594e605be82d50d173edd29b87e6`.
Its receipt binds the immutable WAV and converted reference used for this run.
The converted PCMU hash is per-run evidence, not the immutable source-WAV hash.

## Source and isolated checks

`scripts/test-acdc-callback-offer-calls.sh --gemini` verifies all42 selected
English callback assets and their actual installed Couch attachments against
the source importer/runtime map. It rereads the exact offer revision before
using its complete5.171-second PCMU reference; canonical legacy aliases are
not accepted as substitutes. The existing legacy mode remains separate.

Root32 fixture groups and36 audio groups plus scenario checks passed
`667209/ac6781`. Final startup-boundary audio suite passes40 synthetic groups
`07f6f7/cc3e7f`; the subsequent retained-PCAP step in that network namespace
refused the host's negotiated media IP, so that step is not a playback failure.
The retained-file checker was rerun in the host namespace, without any network
request, to verify the local interface identity (`6071a3/ff00b0`).

The checker requires zero capture drops, complete received RTP coverage, the
exact negotiated peer/dialog, normal teardown, exactly three complete phrases
and schedule tolerance of one second. It examines speech energy before the
earliest permitted offer onset. Up to100ms before first RTP is reported as a
startup gap, never called observed silence; longer gaps/late capture fail.
Synthetic tests reject truncated/extra early phrases and confirm that normal
34ms startup does not defeat this check. Capture buffer is bounded8MiB.

## Actual captured call: audio verified

Evidence: `/var/log/kazoo-acceptance/20260907T120047Z`.
Root live run `41b9e8/93643f` finished the call and passed exact conditional
cleanup with zero agent changes and unchanged unrelated account documents.
Its original20ms startup check was too strict for the actual33.624ms startup.
Rechecking the retained zero-drop capture using the corrected, regression-tested
checker passes (`6071a3/ff00b0`):

| Offer | Start after queue entry | Complete end | Correlation |
| --- | --- | --- | --- |
| 1 | 3.114s | 8.285s | 0.999993 |
| 2 | 18.114s | 23.285s | 0.999993 |
| 3 | 33.114s | 38.285s | 0.999993 |

Call duration46.012s; exact received PCMU; no early offer; full audio coverage;
normal SIP teardown. The first two seconds contain15,732 observed samples,
zero energetic windows and a separately reported33.624ms pre-RTP gap.
Reference PCMU SHA256:
`736d17b8f5f7b2844e0571e8a9477d49e0d37d4666aeaa1ef76e5baaea68272d`.

This actual call does not prove the full live runner's post-audio service/log
gates: the original failed startup assertion skipped those later checks.
A fresh complete runner pass is a separate checkpoint. No Gemini request is
made by the harness or by normal playback.

## Earlier rejected attempts retained

- `20260907T115400Z`: no queue/SIP created; Couch returned multipart attachments
  to a JSON parser. Explicit `Accept: application/json`, content-type validation
  and fixed body-free parse errors corrected the reference fetch.
- `20260907T115817Z`: call and conditional cleanup completed, but6 kernel
  capture drops make absence evidence inconclusive. Not accepted. Increasing
  the bounded capture buffer did not weaken the zero-drop gate.

All test accounts/resources are isolated from the user's normal queue. Failed
and successful evidence remains private under `/var/log/kazoo-acceptance/`;
credentials, SIP captures and customer data are not copied into Git.
