#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly INSTALLER="$SCRIPT_DIR/install-kazoo5.sh"
readonly TEST_COOKIE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
readonly TEST_CONFIG_DIR="/tmp/kazoo5-installer-modular-test-config.$$"
readonly MISSING_DEPLOYMENT_CONFIG="/tmp/kazoo5-installer-modular-test-missing.$$"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_dry() {
    env \
        KAZOO_DEPLOYMENT_CONFIG="$MISSING_DEPLOYMENT_CONFIG" \
        KAZOO_CONFIG_DIR="$TEST_CONFIG_DIR" \
        KAZOO_COOKIE="$TEST_COOKIE" \
        "$INSTALLER" --dry-run "$@"
}

bash -n "$INSTALLER"

nodes_output=$(KAZOO_FREESWITCH_NODES='freeswitch@media1.example.net,media2.example.net' \
    run_dry freeswitch 2>&1)
grep -Fxq '[kazoo5] Would register FreeSWITCH node with eCallMgr: freeswitch@media1.example.net' \
    <<<"$nodes_output" || fail 'first comma-separated FreeSWITCH node was not parsed independently'
grep -Fxq '[kazoo5] Would register FreeSWITCH node with eCallMgr: freeswitch@media2.example.net' \
    <<<"$nodes_output" || fail 'second comma-separated FreeSWITCH node was not normalized independently'

if KAZOO_AMQP_URI='amqps://kazoo:secret@mq.example.net:5671/%2F' \
    run_dry freeswitch >/dev/null 2>&1; then
    fail 'FreeSWITCH accepted an AMQP URI that conflicts with its split wrapper settings'
fi

host_override_output=$(KAZOO_AMQP_URI='amqps://kazoo:secret@old.example.net:5671/%2F' \
    run_dry --amqp-host mq.example.net freeswitch 2>&1)
grep -Fq 'AMQP mq.example.net:5672' <<<"$host_override_output" || \
    fail '--amqp-host did not clear and rebuild an inherited AMQP URI'

monster_output=$(MONSTER_UI_APPS_LIST=accounts run_dry monster-ui 2>&1)
grep -Fq 'Would remove unselected Monster UI app source: callflows' <<<"$monster_output" || \
    fail 'custom Monster UI bundle did not converge away an unselected Callflows source'
if grep -Fq 'Would apply the Callflows production-CSS compatibility patch' <<<"$monster_output"; then
    fail 'custom Monster UI bundle tried to patch unselected Callflows source'
fi

acdc_output=$(MONSTER_UI_APPS_LIST=acdc run_dry monster-ui 2>&1)
grep -Fq 'Bundled Monster UI ACDC Call Center app: local-sha256:' <<<"$acdc_output" || \
    fail 'ACDC source is not included with a content fingerprint'
if grep -Fq 'github.com/2600hz/monster-ui-acdc.git' <<<"$acdc_output"; then
    fail 'Bundled ACDC app incorrectly tried to download a nonexistent upstream app'
fi
grep -Fq 'Would remove unselected Monster UI app source: acdc' <<<"$monster_output" || \
    fail 'Custom UI bundles cannot deselect the bundled ACDC app'

# Simulate the source layout of a fresh project before ignored checkouts exist.
fresh_root=$(mktemp -d /tmp/kazoo5-fresh-layout.XXXXXX)
cleanup_fresh_layout() {
    rm -- "$fresh_root/make/apps.mk"
    rmdir -- "$fresh_root/.git" "$fresh_root/make" "$fresh_root"
}
trap cleanup_fresh_layout EXIT
mkdir -p "$fresh_root/.git" "$fresh_root/make"
cp "$SCRIPT_DIR/../make/apps.mk" "$fresh_root/make/apps.mk"
fresh_output=$(KAZOO_ROOT="$fresh_root" run_dry kazoo-apps 2>&1)
fetch_line=$(grep -n -m1 'fetch-core fetch-apps' <<<"$fresh_output" | cut -d: -f1)
patch_line=$(grep -n -m1 'Would apply the Kazoo/SUP cookie-redaction patch' <<<"$fresh_output" | cut -d: -f1)
if [[ -z $fetch_line || -z $patch_line ]] || ((fetch_line >= patch_line)); then
    fail 'Fresh installs must fetch ignored source checkouts before applying patches'
fi
[[ ! -d $fresh_root/core && ! -d $fresh_root/applications ]] || \
    fail 'Fresh-layout dry run unexpectedly created source checkouts'

# These checks deliberately match the generator's literal shell variable.
# shellcheck disable=SC2016
grep -Fq '"db_set_busy_timeout", "$config_dir/db/kazoo.db=1000;"' "$INSTALLER" || \
    fail 'Kamailio SQLite connections omit the writer-contention timeout'
# shellcheck disable=SC2016
grep -Fq '"db_set_journal_mode", "$config_dir/db/kazoo.db=WAL;"' "$INSTALLER" || \
    fail 'Kamailio SQLite connections omit write-ahead logging'

grep -Fq "tr ',' '\\n'" "$INSTALLER" || \
    fail 'FreeSWITCH node list is not split one node per line'
grep -Fq "sofia status profile sipinterface_1" "$INSTALLER" || \
    fail 'FreeSWITCH verification omits its Sofia SIP profile'
grep -Fq 'Crossbar API JSON check' "$INSTALLER" || \
    fail 'Kazoo applications verification omits the Crossbar API'
grep -Fq 'verify_kamailio_amqp_connection' "$INSTALLER" || \
    fail 'Kamailio verification omits its AMQP transport'
grep -Fq '#!define REGISTRAR_CHECK_AMQP_AVAILABILITY 0' "$INSTALLER" || \
    fail 'Kamailio does not disable the unsupported stock-module amqpc XAVP guard'
grep -Fq '#!define REGISTRAR_AMQP_FLAGS ""' "$INSTALLER" || \
    fail 'Kamailio passes newer numeric publish flags to the stock module AMQP-header argument'
grep -Fq 'omits the optional registrar AMQP-header argument' "$INSTALLER" || \
    fail 'Kamailio compatibility does not remove the stock module optional header argument'
grep -Fq 'mod-kazoo-prefixes-serialization.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo cannot serialize Kazoo 5 multi-prefix channel variables'
grep -Fq 'mod-kazoo-fetch-channel-data.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo does not enrich dialplan fetches from their live channel'
grep -Fq 'mod-kazoo-fetch-log-redaction.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo fetch logging can expose directory credentials or global variables'
grep -Fq 'mod-kazoo-originate-compatibility.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo cannot execute or cancel current eCallMgr originate requests'
grep -Fq 'mod-kazoo-reply-completeness.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo can send malformed incomplete replies to eCallMgr'
grep -Fq 'did not encode a reply; returning badarg' "$SCRIPT_DIR/patches/mod-kazoo-reply-completeness.patch" || \
    fail 'FreeSWITCH mod_kazoo does not repair incomplete C-node replies'
grep -Fq 'mod-kazoo-sync-command-protocol.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo cannot decode current Kazoo command synchronization fields'
grep -Fq 'mod-kazoo-originate-reconcile.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_kazoo cannot reconcile a lost callback originate owner'
grep -Fq 'kazoo-amqp-originate-reconcile.patch' "$INSTALLER" || \
    fail 'Kazoo AMQP does not expose correlated originate reconciliation'
grep -Fq 'ecallmgr-kazoo5-integration.patch' "$INSTALLER" && \
    grep -Fq 'kz_originate_reconcile' "$SCRIPT_DIR/patches/ecallmgr-kazoo5-integration.patch" || \
    fail 'eCallMgr does not query FreeSWITCH originate lifecycle evidence'
grep -Fq 'freeswitch-mod-sofia-kazoo-proxy-uri.patch' "$INSTALLER" || \
    fail 'FreeSWITCH mod_sofia cannot route current Kazoo registrar proxy dialstrings'
grep -Fq 'switch_channel_get_variable(channel, "sip_proxy_uri")' \
    "$SCRIPT_DIR/patches/freeswitch-mod-sofia-kazoo-proxy-uri.patch" || \
    fail 'FreeSWITCH mod_sofia does not consume Kazoo registrar proxy URIs'
grep -Fq 'zstr(invite_route_uri) && !zstr(initial_route)' \
    "$SCRIPT_DIR/patches/freeswitch-mod-sofia-kazoo-proxy-uri.patch" || \
    fail 'FreeSWITCH mod_sofia does not preserve distinct Kazoo initial routes'
grep -Fq 'if (!zstr(val))' \
    "$SCRIPT_DIR/patches/freeswitch-mod-sofia-kazoo-proxy-uri.patch" || \
    fail 'FreeSWITCH mod_sofia accepts empty Kazoo proxy/route pointers'

proxy_fixture_value() {
    [[ $1 == - ]] && printf '' || printf '%s' "$1"
}

while read -r fixture proxy route explicit expected_proxy expected_initial; do
    [[ -n $fixture && $fixture != \#* ]] || continue
    proxy=$(proxy_fixture_value "$proxy")
    route=$(proxy_fixture_value "$route")
    explicit=$(proxy_fixture_value "$explicit")
    expected_proxy=$(proxy_fixture_value "$expected_proxy")
    expected_initial=$(proxy_fixture_value "$expected_initial")

    selected_proxy=''
    selected_initial=$explicit
    if [[ -n $proxy ]]; then
        selected_proxy=$proxy
        [[ -n $selected_initial || -z $route ]] || selected_initial=$route
    elif [[ -n $route ]]; then
        selected_proxy=$route
    fi

    [[ $selected_proxy == "$expected_proxy" && $selected_initial == "$expected_initial" ]] || \
        fail "FreeSWITCH Kazoo proxy fixture failed: ${fixture}"
done < "$SCRIPT_DIR/test-fixtures/freeswitch-kazoo-proxy-uri.tsv"
grep -Fq 'ei_decode_boolean' "$SCRIPT_DIR/patches/mod-kazoo-sync-command-protocol.patch" || \
    fail 'FreeSWITCH mod_kazoo does not validate the current command synchronization field'
grep -Fq 'switch_ivr_parse_event' "$SCRIPT_DIR/patches/mod-kazoo-sync-command-protocol.patch" || \
    fail 'FreeSWITCH mod_kazoo does not execute synchronized commands immediately'
grep -Fq 'arity != 4 || ei_decode_boolean' "$SCRIPT_DIR/patches/mod-kazoo-sync-command-protocol.patch" || \
    fail 'FreeSWITCH mod_kazoo does not enforce legacy/current command tuple arities'
grep -Fq 'propslist_length > 1024' "$SCRIPT_DIR/patches/mod-kazoo-sync-command-protocol.patch" || \
    fail 'FreeSWITCH mod_kazoo does not bound command-batch prevalidation'
grep -Fq 'tail_length != 0' "$SCRIPT_DIR/patches/mod-kazoo-sync-command-protocol.patch" || \
    fail 'FreeSWITCH mod_kazoo does not reject improper command/event lists'
grep -Fq 'kz_originate_action' "$SCRIPT_DIR/patches/mod-kazoo-originate-compatibility.patch" || \
    fail 'FreeSWITCH Kazoo originate compatibility does not preserve quoted channel variables'
grep -Fq 'switch_core_hash_find(kz_originate_hash, cmd)' "$SCRIPT_DIR/patches/mod-kazoo-originate-compatibility.patch" || \
    fail 'FreeSWITCH Kazoo originate compatibility does not implement request cancellation'
grep -Fq "grep -Eq '^kz_originate,' <<<\"\$api_list\"" "$INSTALLER" || \
    fail 'FreeSWITCH verification omits the Kazoo originate API'
grep -Fq "grep -Eq '^kz_originate_cancel,' <<<\"\$api_list\"" "$INSTALLER" || \
    fail 'FreeSWITCH verification omits the Kazoo originate cancellation API'
grep -Fq "grep -Eq '^kz_originate_reconcile,' <<<\"\$api_list\"" "$INSTALLER" || \
    fail 'FreeSWITCH verification omits the Kazoo originate reconciliation API'
grep -Fq 'configure_ecallmgr_dialplan_applications' "$INSTALLER" || \
    fail 'eCallMgr does not select dialplan applications supported by public mod_kazoo'
grep -Fq 'configure_ecallmgr_event_stream_framing' "$INSTALLER" || \
    fail 'eCallMgr does not configure event streams for large Kazoo call events'
grep -Fq 'configure_ecallmgr_callback_cleanup' "$INSTALLER" || \
    fail 'eCallMgr does not configure exact-node ACDC callback cleanup'
grep -Fq '[<<"node_call_command_allowed_applications">>,<<"acdc">>,<<"hangup">>]' "$INSTALLER" || \
    fail 'ACDC callback cleanup permission is not restricted to the hangup command'
grep -Fq 'remove_test_compiled_kazoo_beams' "$INSTALLER" || \
    fail 'Kazoo builds can reuse TEST-compiled runtime BEAM files'
grep -Fq "({d, '\\''TEST'\\'', _}) -> true" "$INSTALLER" || \
    fail 'Kazoo production build does not inspect BEAM compile definitions'
grep -Fq "halt(2)" "$INSTALLER" || \
    fail 'Kazoo BEAM audit does not fail closed when a generated module is unreadable'
[[ $(grep -Fc 'ExecStartPre=/usr/bin/env KAZOO_DEPLOYMENT_CONFIG=/nonexistent' "$INSTALLER") -eq 2 ]] || \
    fail 'Kazoo services can start with TEST-compiled runtime BEAM files'
grep -Fq 'kapps_config fetch_current' "$INSTALLER" || \
    fail 'Kamailio SBC registration does not verify the persisted default ACL scope'
grep -Fq "output != *'error getting system acls'" "$INSTALLER" || \
    fail 'Kamailio SBC registration accepts a zero-exit SUP exception response'
grep -Fq 'cdr-report-timestamp-fallback.patch' "$INSTALLER" || \
    fail 'CDR reports without an optional Timestamp can crash the CDR worker'
grep -Fq 'acdc-kazoo5-integration.patch' "$INSTALLER" || \
    fail 'ACDC durable callback state is not included in reproducible source preparation'
grep -Fq 'callback_recover(' "$SCRIPT_DIR/patches/acdc-kazoo5-integration.patch" || \
    fail 'ACDC integration omits callback recovery'
grep -Fq 'maybe_announce_before_connect(' "$SCRIPT_DIR/patches/acdc-kazoo5-integration.patch" || \
    fail 'ACDC queue announce media is configured but never played before agent connection'
grep -Fq 'start_announcement(Media, Call)' \
    "$SCRIPT_DIR/patches/acdc-queue-preconnect-announcement.patch" || \
    fail 'ACDC queue announcement does not use an asynchronous playback barrier'
grep -Fq 'announce_played=' \
    "$SCRIPT_DIR/patches/acdc-queue-preconnect-announcement.patch" || \
    fail 'ACDC queue announcement can replay during agent retries'
grep -Fq "'undefined' -> kz_time:now_s()" "$SCRIPT_DIR/patches/cdr-report-timestamp-fallback.patch" || \
    fail 'CDR Timestamp compatibility does not provide a safe current-time fallback'
grep -Fq "'<<\"tcp_packet_type\">>' 4" "$INSTALLER" || \
    fail 'eCallMgr does not persist four-byte event-stream framing'
grep -Fq 'event_stream_framing "' "$INSTALLER" || \
    fail 'eCallMgr does not verify negotiated FreeSWITCH event-stream framing'
grep -Fq '<param name="event-stream-framing" value="4" />' "$INSTALLER" || \
    fail 'FreeSWITCH does not persist four-byte event-stream framing'
grep -Fq 'option event-stream-framing' "$INSTALLER" || \
    fail 'FreeSWITCH does not verify every connected eCallMgr event-stream framing value'
grep -Fq 'FILTER_COMPARE_PREFIXES' "$SCRIPT_DIR/patches/mod-kazoo-prefixes-serialization.patch" || \
    fail 'FreeSWITCH mod_kazoo cannot apply Kazoo 5 multi-prefix event filters'
grep -Fq 'FILTER_COMPARE_CONTAINS' "$SCRIPT_DIR/patches/mod-kazoo-prefixes-serialization.patch" || \
    fail 'FreeSWITCH mod_kazoo cannot apply Kazoo 5 contains event filters'
grep -Fq "kazoo_(async_query|publish)\\(.*REGISTRAR_AMQP_FLAGS" "$INSTALLER" || \
    fail 'Kamailio verification does not reject an unconverted registrar header argument'
grep -Fq 'Header-Value can.t be parsed' "$INSTALLER" || \
    fail 'Kamailio verification ignores stock-module AMQP-header compatibility errors'
grep -Fq 'cfg.get kazoo registrar_check_amqp_availability' "$INSTALLER" || \
    fail 'Kamailio verification does not enforce the stock-module registrar compatibility setting'
grep -Fq 'The query itself still fails closed on AMQP' "$INSTALLER" || \
    fail 'Kamailio registrar compatibility does not document fail-closed authentication'
grep -Fq "rpm -q --qf '%{VERSION}-%{RELEASE}' couchdb" "$INSTALLER" || \
    fail 'CouchDB exact package version is not verified'
grep -Fq "rpm -q --qf '%{VERSION}' rabbitmq-server" "$INSTALLER" || \
    fail 'RabbitMQ exact package version is not verified'
grep -Fq 'Deployed Monster UI does not match the requested pinned build' "$INSTALLER" || \
    fail 'Monster UI build fingerprint is not verified'

printf 'PASS: modular endpoints, node parsing, service gates, versions, and custom UI bundles\n'
