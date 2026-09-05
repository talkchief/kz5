# Bridge application-variable compatibility

The pinned Kazoo FreeSWITCH 1.11.3 core recognizes `%[...]` scoped variables,
but not the `/[...]` application-variable prefix emitted by this Kazoo bridge
builder. Consequently `kz_bridge` received `/^[app_uuid=...]<...>[...]kz/...`
unchanged; originate could not see the leading ultra-global `<...>` variables
and misinterpreted their comma-separated fragments as channel types. This
produced `CHAN_NOT_IMPLEMENTED` and no outbound agent leg.

Simply changing `/` to `%` would remove the bad prefix but would not preserve
event correlation: the pinned `switch_core_session.c` reads and removes
`app_uuid` and `app_uuid_name` before processing scoped variables.

The compatible builder now emits, in this exact order:

```text
kz_multiset ^^!app_uuid=<generated-UUID>!app_uuid_name=bridge
kz_bridge <existing-channel-variables>[existing-leg-variables]kz/device@account
```

The first application sets both one-shot event variables atomically. The next
application consumes them together when producing bridge execute/completion
events. No intervening application may be inserted. UUIDs are restricted to
32 hexadecimal characters or standard hexadecimal UUID form; empty values and
delimiter/newline injection are rejected. An absent UUID does not invent or
set correlation. Empty endpoint dialstrings are rejected. Existing quoted
JSON variables, endpoint variables, and endpoint separators are unchanged.

Run `bash scripts/test-ecallmgr-bridge-compatibility.sh` for isolated command
ordering, correlation, injection, empty endpoint, and variable-preservation
regressions. These are not proof of a successful live bridge. After coordinated
deployment of `ecallmgr_fs_bridge.beam`, rerun the isolated direct-call and
monitor acceptance tests and check the actual bridge UUID and both call legs.
No FreeSWITCH module rebuild or restart is needed for this source fix.
