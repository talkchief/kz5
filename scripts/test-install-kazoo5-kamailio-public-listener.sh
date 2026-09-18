#!/usr/bin/env bash
# Offline regression for KAMAILIO_PUBLIC_SIP_IP. Runs the installer's real
# functions and, when Kamailio and its installed Kazoo configuration exist,
# Kamailio's own configuration check on a private copy. Nothing is bound,
# written under /etc or restarted.
set -Eeuo pipefail
umask 077
pl_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
pl_installer="$pl_root/scripts/install-kazoo5.sh"
pl_work=$(mktemp -d /tmp/kazoo-kamailio-public-listener.XXXXXX)
trap 'rm -rf -- "$pl_work"' EXIT
pl_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { pl_pass=$((pl_pass + 1)); printf 'PASS: %s\n' "$*"; }
function_body() { sed -n "/^$1() {\$/,/^}\$/p" "$pl_installer"; }

bash -n "$pl_installer"
settings() {
    (
        die() { printf '%s\n' "$*" >&2; exit 1; }
        ip() { printf '2: eth0    inet 198.51.100.7/32 scope global eth0\n'; }
        DRY_RUN=${2:-false} KAMAILIO_PUBLIC_SIP_IP=$1
        eval "$(function_body kamailio_public_listener_settings)"
        kamailio_public_listener_settings
    )
}
[[ -z $(settings '') ]] || fail 'an unset option must generate nothing'
expected=$'#!define MY_EXTERNAL_IP 198.51.100.7\n#!define SIP_EXTERNAL_PORT 5060\n#!define ALG_EXTERNAL_PORT 7000\n#!trydef WITH_EXTERNAL_LISTENER'
[[ $(settings 198.51.100.7) == "$expected" ]] || fail 'generated settings differ'
if settings 203.0.113.9 >/dev/null 2>&1; then fail 'an address not assigned to this host was accepted'; fi
[[ $(settings 203.0.113.9 true) == *'MY_EXTERNAL_IP 203.0.113.9'* ]] || fail 'dry run must not inspect host addresses'
pass 'explicit external listener settings; unset generates nothing; unassigned address refused'

grep -Fq 'KAMAILIO_AMQP_WORKERS KAMAILIO_PUBLIC_SIP_IP' "$pl_installer" || fail 'option is not persisted'
grep -Fq '$(kamailio_public_listener_settings)' "$pl_installer" || fail 'settings are not written to the installer-owned file'
verify=$(function_body verify_kamailio)
grep -Fq 'verify_kamailio_public_listener' <<<"$verify" || fail 'verification omits the public listener'
grep -Fq "'^listen=(UDP|TCP|TLS)_[A-Z_]+'" <<<"$verify" || fail 'verification does not reject listener macros in local.cfg'
grep -Fq "must differ from the primary listener address" "$pl_installer" || fail 'duplicate primary address is not refused'
pass 'option persisted, written to the installer file, verified, and local.cfg macro lines rejected'

listener() {
    (
        die() { printf '%s\n' "$*" >&2; exit 1; }
        log() { printf '%s\n' "$*"; }
        ss() { [[ $* == *-lun* ]] && printf '%s\n' "$PL_UDP"; [[ $* == *-ltn* ]] && printf '%s\n' "$PL_TCP"; return 0; }
        KAMAILIO_PUBLIC_SIP_IP=$1
        eval "$(function_body verify_kamailio_public_listener)"
        verify_kamailio_public_listener
    )
}
both=$'UNCONN 0 0 198.51.100.7:5060 0.0.0.0:*\nUNCONN 0 0 198.51.100.7:7000 0.0.0.0:*'
PL_UDP=$both PL_TCP=$both listener 198.51.100.7 | grep -Fq 'PASS Kamailio public SIP listener' || fail 'bound listener not accepted'
if PL_UDP='UNCONN 0 0 10.1.0.44:5060 0.0.0.0:*' PL_TCP=$both listener 198.51.100.7 >/dev/null 2>&1; then fail 'missing UDP listener accepted'; fi
if PL_UDP=$both PL_TCP='' listener 198.51.100.7 >/dev/null 2>&1; then fail 'missing TCP listener accepted'; fi
[[ -z $(PL_UDP='' PL_TCP='' listener '') ]] || fail 'unset option must verify nothing'
pass 'verification requires UDP and TCP on both ports and is silent when unset'

config=/etc/kazoo/kamailio
if [[ -x /usr/sbin/kamailio && -f $config/kamailio.cfg && -f $config/local.d/00-kazoo5-installer.cfg ]]; then
    check() { (cd "$1" && /usr/sbin/kamailio -c -f "$1/kamailio.cfg" -m 64 -M 16 -x tlsf -w /tmp \
        -A MY_LOCAL_IP=127.0.0.1 -A LOCAL_IP_ARG 2>&1); }
    prepare() {
        mkdir "$1"; cp -a "$config/." "$1/"
        sed -i "s#$config#$1#g" "$1/local.d/00-kazoo5-installer.cfg"
        sed -i -E '/^#!(define|trydef) (MY_EXTERNAL_IP|SIP_EXTERNAL_PORT|ALG_EXTERNAL_PORT|WITH_EXTERNAL_LISTENER)/d' "$1/local.d/00-kazoo5-installer.cfg"
        sed -i -E '/^listen=/d' "$1/local.cfg"
    }
    prepare "$pl_work/good"
    settings 198.51.100.7 >> "$pl_work/good/local.d/00-kazoo5-installer.cfg"
    out=$(check "$pl_work/good") || { printf '%s\n' "$out" | tail -5; fail 'generated settings do not pass the Kamailio configuration check'; }
    for socket in 'udp: 198.51.100.7:5060' 'tcp: 198.51.100.7:5060' 'udp: 198.51.100.7:7000' 'tcp: 198.51.100.7:7000'; do
        grep -Fq "$socket" <<<"$out" || fail "configuration check omits $socket"
    done
    # The September 18 outage: a listener macro in local.cfg precedes its definition.
    prepare "$pl_work/outage"
    printf 'listen=UDP_SIP advertise 198.51.100.7:5060\n' >> "$pl_work/outage/local.cfg"
    if out=$(check "$pl_work/outage"); then fail 'a listener macro in local.cfg unexpectedly parsed'; fi
    grep -Eq "could not resolve 'UDP_SIP'|parse error|syntax error" <<<"$out" || fail 'unexpected failure for the outage form'
    # Nested $def() defaults are not expanded by this Kamailio: the switch alone fails.
    prepare "$pl_work/implicit"
    printf '#!trydef WITH_EXTERNAL_LISTENER\n' >> "$pl_work/implicit/local.d/00-kazoo5-installer.cfg"
    if check "$pl_work/implicit" >/dev/null 2>&1; then fail 'implicit external defaults now parse; the explicit definitions can be revisited'; fi
    pass 'real Kamailio check: generated form binds four public sockets; outage form and implicit defaults are rejected'
else
    printf 'SKIP: Kamailio or its installed Kazoo configuration is absent; parser checks not run\n'
fi
printf 'All %d Kamailio public listener groups passed\n' "$pl_pass"
