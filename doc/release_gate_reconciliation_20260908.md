# Current installer readiness and remaining release gates

## Current development stack: independent verification passed

On September8, the normal main entry point at source `f68cec3` passed on the
main dev server10.1.0.44:

```sh
sudo bash /opt/kz5/scripts/install-kazoo5.sh --verify-only ALL
```

Evidence66591/18787a: exit0,1m40.208s, CPU2m1.530s, peak293.1MiB. The command
ran under systemd with2GiB memory, no swap, CPU200%,512 tasks and900s deadline.
Protected log retained on the main dev server:
`/root/kz5-acceptance/main-verification-20260908-final.log`.
All nine roles passed; this check did not deploy/restart services, change
queue configuration, synthesize speech or send provider notifications.
The tested checkout already included the latest deployed progress-bar/dialog
patches and the company-copy helpers. Subsequent Git handover changes do not
change runtime modules or installer artifacts.

| Verified scope | Direct evidence from this run |
| --- | --- |
| CouchDB, RabbitMQ, HAProxy | Enabled/active services, authenticated CouchDB health, broker login/vhost/listener/plugin checks and both datastore proxy listeners |
| Kazoo apps | Enabled/active service, production BEAM gate, named running apps, scoped ACDC readiness, SUP, administrator auth and queue/agent/API endpoints |
| Prerecorded media | Installed fixed/cardinal/forwarding artifacts and prompt mappings; no generation |
| eCallMgr and FreeSWITCH | Enabled/active services, exact node link, framing, intercept inventory, Sofia/module/sound readiness; no supervisor/callback call performed |
| Kazoo Kamailio | SIP OPTIONS, dispatcher, SQLite, RPC, exact local AMQP endpoint/consumers, SBC authorization, JWT cache/journal checks |
| Monster UI | Served owned artifact/config, trusted hostname HTTPS/redirect, API JSON, ten catalog entries |
| Mobile bridge | Installed source/dependencies/config, enabled/active non-root service and registered consumer; not a provider send |

This latest read-only check is not substituted for previous fresh-install proof.
Actual normal fresh/repeated ALL48019/6236b8 and post-reboot ALL76710/8722b4 are
recorded in `fresh_host_tls_acceptance_20260908.md`. Actual SmartPBX/ACDC browser
and account-switch checks are in the dev44 HTTPS and company-copy reports.

## What separate-server installation still needs

Do not describe all topology variations as tested merely because configured
private IPs work on a single host. The measured split-host result so far is
the separate Monster UI node using pinned remote catalog authority and the
original apps server. The main dev stack is now intentionally self-contained.

| Remaining deployment case | Required acceptance, not yet established |
| --- | --- |
| Apps with remote CouchDB/HAProxy and RabbitMQ | Normal selected-role install on a distinct clean host; authenticated remote dependencies; no unintended local services; restart/reboot; native API and queue readiness |
| eCallMgr separated from apps and media | Shared reviewed cookie/broker configuration, real node discovery/event framing, inbound/callback/supervision call paths and reconnect after peer interruption |
| Media and Kamailio separated | Normal per-role installs, real registrar/dispatcher/proxy signaling, RTP in both directions, exact remote AMQP consumption and restart/reboot behavior |
| Bridge with remote TLS broker | Validated remote CA/hostname/AMQP and management transport, actual consumer settlement/retry on its own test topology, outage/reconnect behavior without duplicate dispatch |
| Upgrade with live distributed state | Matching multi-module rollout, admission/drain, preservation of membership/pause/callback ownership, rollback and absence of duplicate bridges |

Use isolated development hosts/topologies and explicit test accounts. Do not
point dev apps at production brokers/datastores, reuse production push routing,
or enable the imported Talkchief account's external behavior to fill this matrix.
Mocked/offline fixtures remain useful regressions but cannot close these rows.

## Other mandatory release gates still open

- Sustained30 concurrent calls followed by complete drain and log/resource
  checks. This is not30 calls/second and does not certify80 CPS.
- Broker/node failure, backup/restore, multi-node ownership and duplicate-call
  prevention under recovery. Previously tested isolated retries and restored
  DLQ routing do not establish all failure cases.
- Security/operations review: tenant isolation, exposure/least privilege,
  alerting, retention/disk controls, secret lifecycle and TLS renewal.
- Remaining live callback/supervision acceptance as explicitly scoped by their
  task entries; native module inventory is not an audio/privacy test.
- Exact Kazoo4 app host/release for the company-copy compatibility assessment.
  Shared writable production CouchDB remains NO-GO based on measured view/data
  changes; equal final document content does not prove write-free maintenance.

Physical FCM/APNs delivery testing was explicitly waived by the user, not passed
and not a current request for a handset. Historical dashboards/workforce reports
remain postponed for future ClickHouse work. Live dashboard work stays lower
priority than callback, immutable voice, installer and bridge completion.

## Tracking corrections

INST-03/04/05/06/12 and SEC-01 previously retained September6/earlySeptember8
wording that builds/publication/HTTPS were still pending. Their rows now reflect
the later actual deployment evidence while retaining the untested upgrade,
failure and renewal gates. INST-13 now records both measured retry/DLQ recovery
and the user's mobile-delivery waiver. This is evidence reconciliation, not
blanket enterprise certification or removal of outstanding requirements.
