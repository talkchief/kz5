# Company members and device status

Implemented endpoint: `GET /v2/accounts/{ACCOUNT_ID}/members/devices`.
Use an existing account-scoped `X-Auth-Token` over HTTPS. Never put tokens in URLs.
The local deployment currently lacks HTTPS; do not expose authentication over
the public HTTP connection as a substitute.

`page_size` defaults to25 and accepts1–100. Follow `data.next_cursor` while
`data.has_more` is true. Each member includes safe identity fields and owned
device IDs, names, types, enabled state and registration evidence. Only
`owner_id` associations are expanded: unassigned devices and additional
shared-device/hotdesk users are not assigned invented ownership.

`online` means a currently unexpired/permanent SIP registration, not proof of
successful calling. `offline` requires complete evidence of no current binding;
incomplete/invalid registrar evidence produces `unknown`. This is separate from
ACDC login, availability and office presence. Observation and expiry timestamps
are Unix milliseconds; responses use `Cache-Control: no-store`.

The account device catalog is bounded to1000 devices. Larger catalogs are
explicitly incomplete; empty device lists in that case do not mean zero devices.
Member pagination cannot retrieve those omitted devices. A device-continuation
API and shared/hotdesk expansion remain future work. The registrar detail cap
of10000 rows is checked after collection, not an AMQP transport-memory bound.
The current installer uses case-insensitive registrar identities; case-sensitive
AOR deployments are not supported by this endpoint. Stable registrar discovery,
synchronized clocks and complete correlated peer/part responses are prerequisites;
cluster churn/partition completeness has not been certified.

## Live checkpoint — 2026-09-05

Protected receipt: `/var/log/kazoo-acceptance/members-devices-live.bVNePd/`.
The existing MASTER-admin read-only test passed:

- All31 members and31 devices, across two pages;30 online and1 offline at the
  recorded observation time. These counts are not a promise about later status.
- Anonymous access, malformed queries and different-account cursors rejected.
- Fresh/no-store timestamps and stable independent registrar-summary comparison.
- User/device catalogs unchanged; only ordinary authentication wrote a token.

There were no device-less members in this live account. That branch is covered
by offline tests, not fabricated live evidence. Real restricted-token access,
unauthorized cross-account principals and multi-node failure cases still need
live acceptance. Three additional auth-matrix groups cover global/module stops,
conflicting allows and per-resource scope checks in memory.

Production source SHA256:
`4f83a0e8d60d49f1ebe336f035f4e0a1fb7d3c46bd632cfa61be8a20645c8cc0`.
Deployment backup: `members-devices-deploy.MC5Ry3` under the installer build
directory. The built-in `members` route preserves existing custom-route config,
and `cb_members` is registered and persisted in Crossbar autoload. Its module is
included in the generated application manifest and installer API checks. Loading
the module/parser required no service restart and did not change crash-log stats.

OpenAPI is generated from the source in `scripts/api-docs-members-devices.cjs`
and included in the main `/apis/` catalog, not the planned spec. The specification
does not itself certify live authorization, load, TLS or failover readiness.
