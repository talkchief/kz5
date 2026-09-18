#!/usr/bin/env bash
# Offline regression for the kazoo-kamailio configuration start guard. An
# invalid configuration must fail once, visibly, with the parser's own error,
# and must not restart-loop (4,367 restarts on September 18, 2026). Uses the
# real Kamailio parser on private copies when it is installed. Nothing under
# /etc is changed and no service is touched.
set -Eeuo pipefail
umask 077
kg_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
kg_installer="$kg_root/scripts/install-kazoo5.sh"
kg_guard="$kg_root/scripts/kazoo5-kamailio-config-guard.sh"
kg_work=$(mktemp -d /tmp/kazoo-kamailio-guard.XXXXXX)
trap 'rm -rf -- "$kg_work"' EXIT
kg_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { kg_pass=$((kg_pass + 1)); printf 'PASS: %s\n' "$*"; }

bash -n "$kg_guard"; bash -n "$kg_installer"
fake() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$kg_work/$1"; chmod +x "$kg_work/$1"; printf '%s' "$kg_work/$1"; }
KAZOO_KAMAILIO_CHECK=$(fake ok 'echo "No errors found"; exit 0') bash "$kg_guard" >/dev/null 2>&1 || fail 'a valid configuration was refused'
status=0
out=$(KAZOO_KAMAILIO_CHECK=$(fake bad 'echo "ERROR: Invalid configuration file x!"; echo " 0(12) CRITICAL: <core> [core/cfg.y:4122]: yyerror_at(): parse error in config file local.cfg, line 137"; exit 1') \
    bash "$kg_guard" 2>&1) || status=$?
[[ $status == 78 ]] || fail "invalid configuration exit $status, expected 78"
[[ $(wc -l <<<"$out") == 1 ]] || fail 'the refusal must be exactly one line'
grep -Fq 'parse error in config file local.cfg, line 137' <<<"$out" || fail 'the parser detail is missing'
grep -Fq 'systemctl reset-failed kazoo-kamailio' <<<"$out" && grep -Fq 'KAMAILIO_PUBLIC_SIP_IP' <<<"$out" || fail 'the remedy is missing'
status=0; out=$(KAZOO_KAMAILIO_CHECK=$(fake silent 'exit 3') bash "$kg_guard" 2>&1) || status=$?
[[ $status == 78 ]] && grep -Fq 'no parser detail' <<<"$out" || fail 'a silent check failure must still refuse'
pass 'valid configuration starts; invalid refuses with exit 78, one line, parser detail and remedy'

unit=$(sed -n '/write_file 0644 \/etc\/systemd\/system\/kazoo-kamailio.service/,/^EOF$/p' "$kg_installer")
grep -Fxq 'ExecStartPre=/usr/local/libexec/kazoo5-kamailio-config-guard' <<<"$unit" || fail 'unit lacks the configuration guard'
grep -Fxq 'RestartPreventExitStatus=78' <<<"$unit" || fail 'unit would restart-loop on an invalid configuration'
grep -Fxq 'Restart=on-failure' <<<"$unit" || fail 'runtime crashes must still restart'
# prepare creates the runtime directory the check needs, so it must come first.
[[ $(grep -n 'ExecStartPre' <<<"$unit" | head -1) == *kazoo-kamailio-prepare* ]] || fail 'prepare must precede the guard'
grep -Fq 'kazoo5-kamailio-config-guard.sh' "$kg_installer" || fail 'guard is not installed'
grep -Fq "would restart-loop on an invalid configuration" "$kg_installer" || fail 'verification does not require the no-loop setting'
pass 'unit runs the guard after prepare, never restarts on exit 78, still restarts on crashes; installer verifies both'

config=/etc/kazoo/kamailio
if [[ -x /usr/sbin/kamailio && -f $config/kamailio.cfg && -f $config/local.d/00-kazoo5-installer.cfg ]]; then
    copy() {
        mkdir "$kg_work/$1"; cp -a "$config/." "$kg_work/$1/"
        sed -i "s#$config#$kg_work/$1#g" "$kg_work/$1/local.d/00-kazoo5-installer.cfg"
        sed -i -E '/^#!(define|trydef) (MY_EXTERNAL_IP|SIP_EXTERNAL_PORT|ALG_EXTERNAL_PORT|WITH_EXTERNAL_LISTENER)/d' "$kg_work/$1/local.d/00-kazoo5-installer.cfg"
        fake "check-$1" "cd '$kg_work/$1' && exec /usr/sbin/kamailio -c -f '$kg_work/$1/kamailio.cfg' -m 64 -M 16 -x tlsf -w /tmp -A MY_LOCAL_IP=127.0.0.1 -A LOCAL_IP_ARG"
    }
    KAZOO_KAMAILIO_CHECK=$(copy good) bash "$kg_guard" >/dev/null 2>&1 || fail 'the installed configuration was refused by the real parser'
    checker=$(copy outage); printf 'listen=UDP_SIP advertise 198.51.100.7:5060\n' >> "$kg_work/outage/local.cfg"
    status=0; out=$(KAZOO_KAMAILIO_CHECK=$checker bash "$kg_guard" 2>&1) || status=$?
    [[ $status == 78 ]] || fail "the September 18 configuration gave exit $status"
    grep -Fq "could not resolve 'UDP_SIP'" <<<"$out" || fail "the refusal does not name the real cause: $out"
    pass "real parser: installed configuration starts; the September 18 lines refuse naming 'UDP_SIP'"
else
    printf 'SKIP: Kamailio or its installed Kazoo configuration is absent; parser checks not run\n'
fi
printf 'All %d Kamailio configuration guard groups passed\n' "$kg_pass"
