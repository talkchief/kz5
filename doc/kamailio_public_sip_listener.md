# Kamailio public SIP listener

## Why

The installer binds Kamailio to `KAZOO_PUBLIC_IP` only (on dev44 the private
`10.1.0.44`). Carriers and phones that send SIP to a second, public address of
the same host get no answer. On September 18, 2026 seven lines such as

```
listen=UDP_SIP advertise 46.225.31.248:5060
```

were added by hand to `/etc/kazoo/kamailio/local.cfg`. `kamailio.cfg` reads
`local.cfg` and `local.d/00-kazoo5-installer.cfg` **before**
`listener-defs.cfg`, which is where `UDP_SIP` and the other listener names are
defined. There they are unresolvable words (`could not resolve 'UDP_SIP'`), the
configuration check fails and the SIP edge stays down: 4,367 restarts.

## Option

```sh
sudo KAMAILIO_PUBLIC_SIP_IP=46.225.31.248 ./scripts/install-kazoo5.sh kamailio
```

The value is persisted in `/etc/kazoo/deployment.env`. It must be an IPv4
address **assigned to this host** and different from `KAZOO_PUBLIC_IP`. The
installer writes, into its own `local.d/00-kazoo5-installer.cfg`:

```
#!define MY_EXTERNAL_IP <address>
#!define SIP_EXTERNAL_PORT 5060
#!define ALG_EXTERNAL_PORT 7000
#!trydef WITH_EXTERNAL_LISTENER
```

which adds UDP and TCP listeners on ports 5060 and 7000 next to the private
ones. All three values are explicit because this stock Kamailio 6.1 does not
expand the nested `$def()` defaults the upstream configuration relies on; the
switch alone is a parse error. Verification requires all four sockets and now
also refuses any `listen=<MACRO>` line in `local.cfg`.

A 1:1 NAT address that is not on the host needs the advertise listeners
(`MY_PUBLIC_IP`, `WITH_ADVERTISE_LISTENER`, `WITHOUT_DEFAULT_LISTENER`) instead.
That form is not implemented and the installer refuses such an address rather
than creating a listener that cannot bind.

## Exposure

A public SIP listener is scanned within minutes. dev44 has no host firewall
(`firewalld`/`nftables` inactive) and the `ANTIFLOOD`/`RATE_LIMITER` roles are
not enabled. Carrier calls are authorized by the ecallmgr trusted list
(`doc/ecallmgr_acl_commands.md`), and registrations by SIP authentication, but
restrict ports 5060/7000 to known carrier and customer ranges at the provider
firewall wherever possible. This is an operator decision recorded as open.

## Verification

`bash scripts/test-install-kazoo5-kamailio-public-listener.sh` passes four
groups: generated settings and refusals; persistence/wiring/verification text;
listener verification against controlled socket tables; and, with the installed
Kamailio, the real configuration check on private copies — the generated form
yields the four public sockets, while the outage form and the switch-only form
are rejected. Installer base, modular, deployment and read-only suites pass.
