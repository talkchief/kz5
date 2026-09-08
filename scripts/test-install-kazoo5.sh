#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail
export KAZOO_DEPLOYMENT_CONFIG=/tmp/kazoo5-installer-tests-no-saved-deployment
export KAZOO_CONFIG_DIR="/tmp/kazoo5-installer-test-config-$$"
export KAZOO_COOKIE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly INSTALLER="$SCRIPT_DIR/install-kazoo5.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash -n "$INSTALLER"
grep -Fq 'NODE_OPTIONS=--max-old-space-size=192 npm_config_maxsockets=2 npm_config_jobs=1' "$INSTALLER" || \
    fail 'Monster UI dependency installation must bound npm heap and download concurrency'
grep -Fq 'npm ci --ignore-scripts --no-audit --no-fund' "$INSTALLER" || \
    fail 'Monster UI dependency installation must preserve locked, script-free npm ci'
output=$($INSTALLER --list)
grep -Fxq couchdb <<<"$output" || fail 'component list omits couchdb'
grep -Fxq kamailio <<<"$output" || fail 'component list omits kamailio'
grep -Fxq all <<<"$output" || fail 'component list omits all'

help_output=$($INSTALLER --help)
grep -Fq -- '--verify-only' <<<"$help_output" || fail 'help omits --verify-only'
grep -Fq 'kamaialio' <<<"$help_output" || fail 'help omits supported typo alias'
grep -Fq 'KAZOO_REQUIRE_MEDIA_CONNECTION' <<<"$help_output" || \
    fail 'help omits the distributed FreeSWITCH connection control'

dry_output=$($INSTALLER --dry-run kamaialio 2>&1)
grep -Fq 'Resolved components:' <<<"$dry_output" || fail 'dry run did not resolve components'
grep -Fq 'Installing Kazoo Kamailio' <<<"$dry_output" || fail 'kamaialio alias did not select Kamailio'
if grep -Fq 'Installing RabbitMQ' <<<"$dry_output"; then
    fail 'standalone Kamailio unexpectedly selected local RabbitMQ'
fi

freeswitch_output=$($INSTALLER --dry-run freeswitch 2>&1)
grep -Fq 'Installing Kazoo FreeSWITCH 1.11.3' <<<"$freeswitch_output" || \
    fail 'standalone FreeSWITCH did not select the pinned Kazoo media build'
if grep -Eq 'Installing RabbitMQ|Compiling Kazoo' <<<"$freeswitch_output"; then
    fail 'standalone FreeSWITCH unexpectedly selected a local broker or Kazoo node'
fi

remote_output=$($INSTALLER --dry-run --couchdb-host db.example.net --amqp-host mq.example.net kazoo-apps 2>&1)
grep -Fq 'db.example.net' <<<"$remote_output" || fail 'remote CouchDB host was not accepted'
grep -Fq 'mq.example.net' <<<"$remote_output" || fail 'remote AMQP host was not accepted'
if grep -Fq 'Installing Apache CouchDB' <<<"$remote_output"; then
    fail 'standalone Kazoo apps unexpectedly selected local CouchDB'
fi

dist_output=$($INSTALLER --dry-run --erlang-dist-ip 10.20.0.13 ecallmgr 2>&1)
grep -Fq 'Erlang 10.20.0.13:11500-11999' <<<"$dist_output" || \
    fail 'distributed Erlang bind address was not accepted'

all_output=$($INSTALLER --dry-run ALL 2>&1)
grep -Fq 'Dry run complete; no components were installed or live health checks performed' <<<"$all_output" || \
    fail 'ALL dry run must not claim live installation/health acceptance'
for expected in \
    'Installing Apache CouchDB' \
    'Installing RabbitMQ' \
    'Installing HAProxy' \
    'Compiling Kazoo' \
    'Installing Kazoo FreeSWITCH' \
    'Installing Kazoo Kamailio' \
    'Installing pinned Monster UI'; do
    grep -Fq "$expected" <<<"$all_output" || fail "ALL dry run omits: $expected"
done

freeswitch_line=$(grep -n -m1 'Installing Kazoo FreeSWITCH' <<<"$all_output" | cut -d: -f1)
ecallmgr_line=$(grep -n -m1 'Installing Kazoo ecallmgr' <<<"$all_output" | cut -d: -f1)
((freeswitch_line < ecallmgr_line)) || \
    fail 'ALL must install FreeSWITCH before restarting ecallmgr/EPMD'

if $INSTALLER --dry-run definitely-not-a-component >/dev/null 2>&1; then
    fail 'unknown component unexpectedly succeeded'
fi

if KAZOO_REQUIRE_MEDIA_CONNECTION=invalid \
    $INSTALLER --dry-run freeswitch >/dev/null 2>&1; then
    fail 'invalid media connection mode unexpectedly succeeded'
fi

if KAZOO_MIN_BUILD_FREE_MB=invalid \
    $INSTALLER --dry-run freeswitch >/dev/null 2>&1; then
    fail 'invalid build-space floor unexpectedly succeeded'
fi

if KAZOO_ERLANG_DIST_IP=999.20.0.13 \
    $INSTALLER --dry-run ecallmgr >/dev/null 2>&1; then
    fail 'invalid distributed Erlang IPv4 address unexpectedly succeeded'
fi

if KAZOO_ERLANG_DIST_IP=999.20.0.13 \
    "$SCRIPT_DIR/dev-start-ecallmgr.sh" test_ecallmgr >/dev/null 2>&1; then
    fail 'ecallmgr launcher accepted an invalid distribution address'
fi

if KAZOO_COUCHDB_BIND=0.0.0.0 \
    $INSTALLER --dry-run couchdb >/dev/null 2>&1; then
    fail 'public CouchDB with default credentials unexpectedly succeeded'
fi

if KAZOO_RABBITMQ_BIND=0.0.0.0 \
    $INSTALLER --dry-run rabbitmq >/dev/null 2>&1; then
    fail 'public RabbitMQ with the default password unexpectedly succeeded'
fi

couch_bind_output=$(KAZOO_COUCHDB_BIND=10.20.0.11 \
    KAZOO_COUCHDB_USER=kazoo KAZOO_COUCHDB_PASSWORD=test-secret \
    $INSTALLER --dry-run couchdb 2>&1)
grep -Fq 'Would wait for 10.20.0.11:5984' <<<"$couch_bind_output" || \
    fail 'standalone CouchDB health check did not use its selected bind address'

grep -Fq 'FREESWITCH_VERSION=${FREESWITCH_VERSION:-1.11.3}' "$INSTALLER" || \
    fail 'FreeSWITCH 1.11.3 is not the default'
grep -Fq 'FREESWITCH_REF=${FREESWITCH_REF:-ef32e205295e29f034f1453ad245ba5efb07b94a}' "$INSTALLER" || \
    fail 'FreeSWITCH 1.11.3 source commit is not pinned'
grep -Fq 'mod-kazoo-thread-lifecycle.patch' "$INSTALLER" || \
    fail 'FreeSWITCH build does not apply the mod_kazoo shutdown-safety patch'
grep -Fq 'freeswitch-mod-sofia-thread-lifecycle.patch' "$INSTALLER" || \
    fail 'FreeSWITCH build does not apply the mod_sofia shutdown-safety patch'
grep -Fq 'freeswitch-module-load-shutdown.patch' "$INSTALLER" || \
    fail 'FreeSWITCH build does not serialize module loading with shutdown'
grep -Fq 'mod-kazoo-worker-shutdown-synchronization.patch' "$INSTALLER" || \
    fail 'FreeSWITCH build does not synchronize mod_kazoo event and API workers'
grep -Fq 'worker-shutdown-v3+cookie-redaction-v1' "$INSTALLER" || \
    fail 'FreeSWITCH build fingerprint does not include current mod_kazoo safety patches'
grep -Fq 'KAMAILIO_VERSION=${KAMAILIO_VERSION:-${KAMAILIO_SERIES:-6.1.4}}' "$INSTALLER" || \
    fail 'Kamailio 6.1.4 is not the default'
grep -Fq 'KAZOO_APPS_LIST=${KAZOO_APPS_LIST:-acdc,' "$INSTALLER" || \
    fail 'ACDC is not in the default Kazoo application set'

printf 'PASS: installer syntax, pins, aliases, modular paths, security gates, ALL path, and errors\n'
