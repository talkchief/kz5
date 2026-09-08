# Browser validation on the retained development server

Run from **10.1.0.44:/opt/kz5**. These optional tools are for trusted development
acceptance, not a production service and not a dependency of a Kazoo stack role.
They replace the original server's temporary Node/Playwright/browser paths.

```sh
cd /opt/kz5
sudo bash scripts/setup-kazoo-browser-tests.sh
sudo bash scripts/run-dev44-company-browser.sh
```

Setup supports Rocky Linux 9 x86_64 only. It installs missing browser OS libraries
and, if absent, distribution Node/npm as bootstrap tools. A private Node22.23.2,
Playwright1.62.1 and its Chromium151.0.7922.34 headless shell are installed below
`/usr/local/lib/kazoo5-browser-tests/`. The npm lock pins package integrity;
Playwright pins the browser revision. No Gemini, GitHub or login key is required
to download them. No package lifecycle script runs. System Node is not replaced
and Kazoo services are not restarted. A version/DOM smoke test must pass before
switching the managed `current` symlink. Failed staging and prior releases are
retained for diagnosis/recovery; a repeat with the same lock runs the smoke test
without downloading. Setup uses an exclusive lock and refuses unmanaged paths.

The browser runs without Chromium's sandbox as root, solely for this existing
trusted development acceptance workflow. Do not use it to browse untrusted sites.
The smoke page blocks network requests. Run actual acceptance in a resource-bounded
unit (e.g. MemoryMax512M, MemorySwapMax0, CPUQuota100%, TasksMax256,
RuntimeMaxSec240, LimitCORE0); the launcher also has a180-second timeout.

The tracked company test reads protected local installer settings, logs in as
the development master admin, and inspects the copied Talkchief account,
SmartPBX and ACDC. It checks collection counts, UI errors, HTTPS requests,
the blue loading indicator, five language options and distinct announcement
interval controls. Queue editing is select-and-cancel only; copied-company
mutations are blocked in the test. It does not place calls or enable copied
users/devices. No credentials or browser session artifacts are written to Git.
HTTPS is certificate-verified but deliberately mapped to10.1.0.44, so this test
does not establish public-IP routing. It is not an actual Save, restricted-token,
new-account inheritance or full production acceptance test.
