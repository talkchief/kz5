# Main development server HTTPS — September 8, 2026

## Address and login

- URL: `https://kz5-dev.talkchief.io/`
- Main host:10.1.0.44 / public46.225.31.248; repository `/opt/kz5`, kz5 master.
- Login **account name**: `KazooMaster`; username: `admin`.
- `master.dev-testing` is the account realm, not this UI's account-name field.
  The earlier credential response incorrectly treated these as interchangeable.
- Password remains in `/etc/kazoo/installer-secrets.env` on .44. Do not put it,
  session tokens, cookies, or certificate private keys in Git.
- The original `https://kz5.talkchief.io/` site was not moved. DNS for the new
  hostname already resolved to46.225.31.248; no DNS change was performed.
- The existing wildcard certificate covers this DNS name, not the IP literal.

## Deployment and fixes

Initial inspection confirmed no443 listener on .44. Prior TLS acceptance in
`fresh_host_tls_acceptance_20260908.md` concerned the original site, not .44.
The user approved the new hostname and existing wildcard certificate.

Normal deployment command (all certificate files are outside Git):

```sh
sudo env MONSTER_UI_WEBSOCKET_URL=wss://kz5-dev.talkchief.io/websocket \
  bash /opt/kz5/scripts/install-kazoo5.sh \
  --hostname kz5-dev.talkchief.io \
  --api-url https://kz5-dev.talkchief.io/v2/ \
  --tls-cert '/root/ssl/SSL Certs_STAR_talkchief_io.crt' \
  --tls-key '/root/ssl/SSL Certs_STAR_talkchief_io.key' \
  --tls-chain '/root/ssl/SSL Certs_STAR_talkchief_io_bundle.crt' monster-ui
```

The first attempt53694/f9ca92 built/activated TLS but failed during existing
master discovery. Root systemd invocations can lack HOME; OTP's distribution
authentication then crashes in `filename:basedir_join_home/1` before SUP reads
its configured cookie. Installer-generated SUP now resolves the actual user's
NSS home only when absent/empty and preserves explicit HOME (`f2e6f4a`).
Fifteen argument tests and four home/NSS cases pass, bootstrap tests pass,
and actual `env -i ... sup kapps_util get_master_account_id` passesebbe3f.

Rerun50206/267490 passed the complete normal UI installer: certificate identity
and trust, redirect308, served-owned-file hashes, Crossbar JSON, app registration,
and root-only persisted deployment settings. Only nginx restarted; no call or
database service restart was needed. Nine main services remain active.

The create-only app importer correctly preserved existing catalog documents,
but their old `http://10.1.0.44/v2/` URLs overrode the new UI API configuration.
Actual browser tests reproduced insecure requests after login. The user also
reported mixed-content/CORS failures on ACDC live/queue/stats routes. Redirects
cannot repair those browser preflights; the stored URLs must change.

`9861f4b` adds the exact reviewed `--dev44-https` profile to the existing
revision/hash-guarded catalog migration, scoped to this master and ten verified
app IDs. All41 regression groups pass in each of the three profiles, including
full-document preservation, stale-revision refusal, partial recovery, ambiguous
write handling and UTF-8 stdin-only Erlang transport. Actual24378/5329d2d writes
and verifies ten URL changes. Original documents and readbacks are protected at:

`/root/kz5-acceptance/catalog-dev44-https/receipt.json`

For this already-completed migration, replay verification uses:

```sh
sudo env USER=root node /opt/kz5/scripts/migrate-monster-app-api-url.cjs \
  --dev44-https --apply \
  --receipt-dir /root/kz5-acceptance/catalog-dev44-https
```

Do not create a new plan over already-migrated entries, substitute another
account, or use this exact-account profile on a different installation. New
installations configured with HTTPS from the outset create the correct URLs.
The generic installer deliberately does not overwrite custom existing app
catalogs; another existing deployment requires a separately reviewed migration.

## Browser checks and remaining verification

Actual Chromium55182/108dd9 verifies one deliberate wrong-account login401 with
visible error and enabled retry, followed by successful `KazooMaster` login.
All ten catalog URLs now use HTTPS. UI/API, WSS upgrade, `/apis/`, and the ACDC
live queue API200 pass without insecure requests or JavaScript errors. This
test uses private routing with normal certificate verification, not ignored
TLS errors. It does not prove calls, authenticated subscriptions, or load.

The user reached the public hostname and supplied browser traces. Direct public
connections from the original dev server time out on80/443 despite ACCEPT host
firewall rules; do not conflate that source-specific reachability result with
the verified private-route browser test or operator's external access.

A separate resize-after-dialog-close error was reproduced74294/de43b6 after the
URL migration. `monster-ui-dialog-resize-lifecycle.patch` cancels the pending
debounce on close and ignores an already destroyed dialog. The patch is part of
the normal source pipeline and build fingerprint. Actual-source before/after
tests and clean pinned-framework patch replay pass. Normal installer25232/ec4d2b
deployed `c7ecf0a` successfully in85.5 seconds with848.2MiB peak memory, reusing
persisted HTTPS settings; final owned-file, certificate, API and catalog checks
all pass. All nine main services are active afterward.

Postdeployment Chromium90351/a3c1e3 passes the deliberate wrong-account401 and
retry, correct administrator login, all ten HTTPS catalog URLs, WSS upgrade,
`/apis/`, ACDC live200, and delayed resize after dialog destruction, with zero
insecure requests or page exceptions. The master account's live response has
zero queues; the UI correctly renders its visible empty state, not a spinner.
Initial postdeployment probes failed an incorrect search-box assertion; it was
corrected to validate the API's actual queue count and corresponding UI state,
without changing application data or suppressing browser failures.

The reported `VM38 reportAllChanges/startTime` exception has not been attributed
to a shipped source file or reproduced in the clean browser. If it remains after
a fresh page load, capture its original script URL; do not silently suppress it
or claim that it was repaired by the catalog migration.

## Private evidence and recovery

### Subsequent top blue progress-line correction

The operator clarified that the thin top blue line, not the in-app spinner,
remained animated in SmartPBX and ACDC. Browser77543 and28271 confirmed
`monster.apps.core.request.counter=-1` while `.progress-indicator.active` stayed
present. Earlier acceptance did not inspect that separate global indicator and
must not be cited as proof that the top line stopped.

Source fix `2a593ee` adds
`scripts/patches/monster-ui-request-indicator-lifecycle.patch` to the normal
installer and build fingerprint. An unmatched completion can occur around the
core's subscription boundary. Counters now cannot decrement below zero; a new
request recovers any older negative state; only positive work counts activate
the indicator; draining work cancels a pending show timer. This preserves normal
overlap and background-request behavior rather than hiding the progress bar.

`scripts/test-monster-request-indicator-lifecycle.cjs` executes the actual
handlers with controlled timers, reproduces the old stuck-line failure and
checks unmatched/duplicate completion, overlapping work, background bypass,
fast completion, replacement requests, and recovery from existing underflow.
Twelve installer wiring and eleven preservation groups also pass15196/f35d93.
Normal installer81343/73a371 on .44 completes in86 seconds,849MiB peak; private
log `/root/kz5-acceptance/progress-https-install.log`. All nine main services
remain active. Postdeployment Chromium20021/2b3a50 verifies both apps after
15 seconds: counter0, inactive top indicator, no underflows, no in-app loading
elements, no page errors or failed HTTP requests. Earlier HTTPS/WSS/login/retry,
API docs, ACDC live and dialog-close assertions pass in the same run.

### Protected deployment records

On .44, retain `/root/kz5-acceptance/https-dev-install.log` (failed first attempt),
`https-dev-retry.log` (successful retry), `dialog-https-install.log` (successful
source-patch rebuild), `monster-ui.before-https.conf`,
`deployment.before-https.env`, the catalog receipt and owned-deployment recovery
stages. Certificate key files are0600 under root-only directories. Installed
settings are `/etc/kazoo/deployment.env`, root0600 and base64 values, **not a shell
file to source**. Never replace current state with an old HTTP backup as an
automatic rollback; inspect the exact stage/receipt first. Hard-refresh or use
a new browser session after catalog changes so cached app metadata is reloaded.
