# Fresh-host and HTTPS acceptance — September 8, 2026

This supersedes the external-input requests in `focused_acceptance_20260908.md`.
FWD-01–06 remains the other team's work; its uncommitted code is excluded from
the isolated remote acceptance checkout.

## Operator decisions

- Physical Android FCM / iPhone APNs delivery testing: **WAIVED / closed by
  user**, not a measured delivery pass. No real-device notification was sent.
  Existing bridge installer and isolated broker/consumer proofs retain their
  recorded scope. Provider credentials remain outside Git.
- Authorized clean target: `10.1.0.44`, initially Rocky Linux 9.8, about 23 GiB
  RAM, 287 GiB free and no Kazoo components. Credentials are not in this report.
- Uploaded private key matches the supplied certificate; trust-chain and
  hostname validation pass. Original and installed nginx key are root-owned
  0600. No private key is committed.

## Existing development host HTTPS — PASS

Normal Monster UI installer90345/4232b3 rebuilt the owned UI for
`https://kz5.talkchief.io/v2/`, preserved other assets/language capabilities,
configured nginx, verified transport and saved deployment settings.
HTTPS UI and `/apis/` return 200; HTTP redirects with 308.
Actual Chromium72297/af0738 passes anonymous UI boot, same-origin Crossbar JSON
and a browser `wss://kz5.talkchief.io/websocket` upgrade, without ignoring
certificate errors. This does not prove authenticated subscriptions or calls.
No ACDC/eCallMgr/FreeSWITCH restart was required for TLS.

```sh
sudo ./scripts/install-kazoo5.sh \
  --hostname kz5.talkchief.io --api-url https://kz5.talkchief.io/v2/ \
  --tls-cert '/root/ssl/SSL Certs_STAR_talkchief_io.crt' \
  --tls-key '/root/ssl/SSL Certs_STAR_talkchief_io.key' \
  --tls-chain '/root/ssl/SSL Certs_STAR_talkchief_io_bundle.crt' monster-ui
```

### Existing catalog HTTP-to-HTTPS migration — PASS

All ten catalog documents still specified HTTP. The existing exact-allowlist,
revision-checked migration now accepts `--https` for this known account's
`http://kz5.talkchief.io/v2/` to `https://kz5.talkchief.io/v2/` transition.
Both profiles pass 41 regression groups, including preservation, ambiguous-write
refusal, replay and C-locale Unicode JSON output. Guarded attempts failed before
writes because USER was absent and Erlang C-locale output used invalid JSON
Unicode escapes; explicit USER and UTF-8 protocol output resolved those causes.

Actual 5385/a8d9bc completed ten writes with readbacks. Protected originals:
`/var/log/kazoo-acceptance/catalog-https-20260908/receipt.json`.
Only `api_url` and `_rev` changed; other metadata and attachment stubs match.
The create-only importer still never overwrites existing entries. New installs
create catalog entries using the configured API URL. This account-specific
migration is not intended for unrelated installations.

```sh
sudo env USER=root node scripts/migrate-monster-app-api-url.cjs --https \
  --plan --receipt-dir /ABSOLUTE/NEW/PRIVATE/RECEIPT_DIRECTORY
sudo env USER=root node scripts/migrate-monster-app-api-url.cjs --https \
  --apply --receipt-dir /ABSOLUTE/EXISTING/PRIVATE/RECEIPT_DIRECTORY
```

For the completed migration, reuse its receipt for verification-only replay;
a new plan correctly rejects already-migrated URLs.

## Fresh target

Cloned a Git bundle of pushed `8fbcedf70ac7b2e8c60ac66c3fe4902b64f08eb6`;
origin is kz5 on GitHub. Acceptance adds only the focused fixes below.

**CouchDB/RabbitMQ/HAProxy installation and independent verification PASS**
92442/b97479. Data ports bind private 10.1.0.44. Separately generated database and
broker passwords are protected under `/root/kz5-acceptance/` and in the installer's
root-only deployment state, never the repository.

Fresh-install fixes in source:

1. Root umask 077 left `enabled_plugins` unreadable by RabbitMQ. Validate a
   regular single-link file and set root:rabbitmq 0640 before service start.
   Regression: `test-rabbitmq-plugin-permissions.sh`; actual broker now passes.
2. DNF's `--enabled` query exits 1 on a clean Node.js host. Query all streams and
   select `[e]`, distinguishing no selection from a repository failure.
   Regression: `test-nodejs-clean-install.sh` covers fresh/existing/switch/error.
   Actual Node 18/npm/nginx installation passes after the fix.
3. Fresh full UI minification exceeded 256 MiB V8 heap. The builder now selects
   512 MiB only with at least 1 GiB within all cgroup-v2 ancestor limits and host
   free memory; unknown/low-memory environments retain 256 MiB. Eight heap tests
   pass, and an actual 256 MiB guard still selects 256. Parser/minifier options
   are unchanged. Full fresh build subsequently passed.

Cold EPEL metadata exceeded the conservative 384 MiB local validation cap, killing
DNF, not a Kazoo service. The isolated 23 GiB target now uses bounded 2 GiB,
CPU 200%, no swap, 512 tasks and one-hour deadline. Current-host guard is unchanged.

Host preparation: cloud-init initially mapped `dev-testing` only to loopback,
incompatible with private-bound RabbitMQ distribution. `/etc/hosts` now maps it
to 10.1.0.44; original is `/root/kz5-acceptance/hosts.before`.
`/etc/cloud/cloud.cfg.d/99-kz5-hostname.cfg` preserves this mapping. This is explicit
host preparation, not silent installer DNS rewriting.

### Separate Monster UI node — PASS

Existing apps cluster stays on 10.1.0.26; UI builds on 10.1.0.44. Its API uses
the HTTPS hostname; proxy upstreams are .26:8000/v2/ and .26:5555/websocket.
Remote catalog readiness passes with pinned SSH and the deployed fixed receiver.
The protected web-node identity `/root/kz5-catalog/identity` is authorized on .26
only from .44, using `restrict` and a forced receiver command, never a shell.
`/root/kz5-catalog/known_hosts` pins the actual apps server public key.

Build 44757 completed the fresh artifact, deployment and ten remote catalog
preservations/verifications; its public-network API probe then timed out.
Private-name resolution on .44 now maps `kz5.talkchief.io` to 10.1.0.26 without
disabling certificate verification. Rerun 18195/bd6cac passed installation and
independent `--verify-only monster-ui`, including remote catalog, served assets,
proxy JSON and HTTPS API access. Existing compiled files were reused and checked.
Cross-host requests from .26 also receive HTTP 200 for .44 UI and Crossbar JSON
from its `/v2/` proxy. The .44 web page itself is private-network HTTP, not HTTPS;
it points clients to the existing HTTPS API/WSS host.

Public TCP443 from .44 to 91.99.188.145 still times out; direct private TLS works.
Neither local nftables nor firewalld shows an active filtering policy. External
reachability was asked of the user; no public firewall was changed or bypassed.
The user subsequently confirmed successful HTTPS login from their browser.

### Fresh apps attempt — FAILED prerequisite, P0

Session14757/4d3ba1 exited1 before the apps build: the checked-in five-language
cardinal adapter rejected its source plan. Apps/media/SIP/bridge services are not
yet installed on .44. Fix the source prerequisite and rerun the normal options;
do not treat the existing-host ALL pass as fresh-server acceptance.

Combined guarded regression 79188/59b65a passes heap selection, Node.js/RabbitMQ
first-install cases, both 41-group catalog migrations, modular and read-only
installer suites. Fresh apps/media/SIP/bridge roles and absent-catalog creation
remain distinct work; this is not a full fresh-stack or production certification.
