# Network hardening checkpoint — 2026-09-05

This is a scoped repair, not a complete firewall or external penetration-test
certificate. No application, media server or fixture service was restarted.

## Test-phone control containment

The 30 existing SIPp 3.7.7 fixture phones bound SIP/RTP to loopback but exposed
their unauthenticated UDP control sockets on `0.0.0.0:8888–8917`. The inspected
host nftables/iptables rulesets were empty. Provider firewall state and Internet
reachability were not tested, so a public bind alone is not an external-access
proof. The installed SIPp source confirms that control commands have no sender
authentication and that `-ci` selects the control bind address.

After verifying all 30 exact socket/PID/executable/systemd-unit identities, a
single owned nftables table was added atomically:

```nft
create table inet kazoo_sipp_control_guard {
    comment "kazoo5 reviewed SIPp fixture control containment"
    chain input {
        type filter hook input priority -10; policy accept;
        iifname != "lo" udp dport 8888-8917 counter drop comment "block non-loopback fixture control only"
    }
}
```

Post-checks confirmed the same 30 phones and socket identities. The rule changes
only non-loopback inbound UDP to that reviewed range. SSH, SIP, RTP, other
tables and the default policy are untouched. No control datagram was sent to
an actual phone. A zero counter does not establish external reachability.
Protected review material is in
`/usr/local/src/kazoo5-installer/sipp-control-containment.bfubon`;
the applied rule-file SHA-256 is
`16978ac16cd4c2d19029c9a599eed698a2767294ecd6a6dc2cfd4c30cd85fe59`.

This runtime guard is not reboot-persistent. The repository's persistent-phone
and deregistration commands now explicitly bind control to `127.0.0.40` using
`-ci`; the zero-call parser test uses `127.0.0.41`. The mock-only regression
`scripts/test-live-test-agent-control-bind.sh` passes persistent startup and all
30 deregistration invocations without changing SIP/RTP arguments. Existing
running shells do not adopt edited functions; the source fix takes effect on
the next coordinated service start. No roster or agent statuses were changed.

If rollback is required, inspect `nft -a list table inet
kazoo_sipp_control_guard` and confirm the table still has only the reviewed
chain/rule before deleting that exact table. Never flush the ruleset or remove
unrelated rules. Removing it before the phones restart with loopback controls
would restore the observed host-level exposure.

## Post-incident fixture recovery — 2026-09-06

The separately reviewed zero-call fixture recovery at 00:12–00:14 restarted only
the stalled test-phone supervisor. All 30 phones now have verified loopback SIP,
RTP and control listeners; their one-agent roster and statuses were preserved.
At 01:30 UTC the same supervisor PID still reported 30/30 registered phones.
The narrow runtime rule remains in place. The process-identity signal hardening
committed in `ebb50e1` has not been activated inside that already-running shell;
its owned-child acceptance is not a supervisor-renewal claim.

## Still open

Other public listeners require an explicit deployment network policy, not an
automatic blanket block: Crossbar 8000, Blackhole 5555, media/Pivot proxies
24517/34512, fax 19025/30950, Kamailio registrar 7000 and metrics 9494, and
FreeSWITCH SIP 11000. Public binds do not by themselves prove authentication
bypass; SIP authentication/ACL behavior must be tested separately.

At inspection, Erlang distribution/EPMD, RabbitMQ, CouchDB and FreeSWITCH event
sockets were loopback-bound. HTTPS still has no 443 listener because the
matching private key has not been provided. SELinux enforcement, provider
filtering, separated-host access rules and comprehensive security acceptance
remain unverified or incomplete.
