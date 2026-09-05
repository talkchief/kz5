#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# Isolated launcher, Erlang argument parsing and native log-retention tests.
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo5-logging-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/bin/erl" "$test_dir/config/freeswitch/autoload_configs/logfile.conf.xml"
    rmdir -- "$test_dir/bin" "$test_dir/apps/log" "$test_dir/apps" \
        "$test_dir/media/log" "$test_dir/media" \
        "$test_dir/config/freeswitch/autoload_configs" "$test_dir/config/freeswitch" \
        "$test_dir/config" "$test_dir" 2>/dev/null || true
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$test_dir/bin"
install -m 0755 "$SCRIPT_DIR/test-fixtures/logging/erl" "$test_dir/bin/erl"
for fixture in apps media; do
    launcher=dev-start-apps.sh
    [[ $fixture != media ]] || launcher=dev-start-ecallmgr.sh
    output=$(PATH="$test_dir/bin:$PATH" KAZOO_LOG_ROOT="$test_dir/$fixture" \
        "$SCRIPT_DIR/$launcher" test_node)
    grep -Fxq "dump=$test_dir/$fixture/erl_crash.dump" <<<"$output" || fail 'crash path is not writable node-local storage'
    grep -Fxq 'seconds=10' <<<"$output" || fail 'crash dump time is unbounded'
    grep -Fxq 'bytes=104857600' <<<"$output" || fail 'crash dump size is unbounded'
    grep -Fxq "arg=\"$test_dir/$fixture\"" <<<"$output" || fail 'Lager path is not an Erlang string'
    ! grep -Fxq 'arg=reloader' <<<"$output" || fail 'automatic runtime reloading is enabled by default'
    enabled_output=$(PATH="$test_dir/bin:$PATH" KAZOO_LOG_ROOT="$test_dir/$fixture" \
        KAZOO_ENABLE_RELOADER=true "$SCRIPT_DIR/$launcher" test_node)
    grep -Fxq 'arg=reloader' <<<"$enabled_output" || fail 'explicit development reloader opt-in does not work'
    if PATH="$test_dir/bin:$PATH" KAZOO_LOG_ROOT="$test_dir/$fixture" \
        KAZOO_ENABLE_RELOADER=invalid "$SCRIPT_DIR/$launcher" test_node >/dev/null 2>&1; then
        fail 'invalid reloader option was accepted'
    fi
    [[ $(stat -c '%a' "$test_dir/$fixture/log") == 700 ]] || fail 'new diagnostic directory is not private'
    for invalid in relative / '/tmp/bad"path' '/tmp/white space'; do
        if PATH="$test_dir/bin:$PATH" KAZOO_LOG_ROOT="$invalid" \
            "$SCRIPT_DIR/$launcher" test_node >/dev/null 2>&1; then
            fail 'unsafe log root was accepted'
        fi
    done
done
! grep -Eq '^[[:space:]]*-s[[:space:]]+reloader([[:space:]]|$)' "$SCRIPT_DIR/../rel/dev.vm.args" || \
    fail 'shared VM arguments bypass the controlled reloader opt-in'

export KAZOO_DEPLOYMENT_CONFIG="$test_dir/no-saved-deployment"
source "$SCRIPT_DIR/install-kazoo5.sh"
KAZOO_CONFIG_DIR="$test_dir/config"
configure_freeswitch_logging
config="$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/logfile.conf.xml"
xmllint --noout "$config"
[[ $(xmllint --xpath 'count(/configuration/profiles/profile)' "$config") == 2 ]] || fail 'missing logging profile'
[[ $(xmllint --xpath 'count(//profile/settings/param[@name="rollover" and @value="10485760"])' "$config") == 2 ]] || fail 'unbounded FreeSWITCH file size'
[[ $(xmllint --xpath 'count(//profile/settings/param[@name="maximum-rotate" and @value="5"])' "$config") == 2 ]] || fail 'unbounded FreeSWITCH archive count'
initial_hash=$(sha256sum "$config")
configure_freeswitch_logging
[[ $(sha256sum "$config") == "$initial_hash" ]] || fail 'logging configuration is not idempotent'

# Validate the argument with the actual installed OTP parser, not just a mock.
if command -v erl >/dev/null && [[ -d $SCRIPT_DIR/../deps/lager/ebin ]]; then
    KAZOO_TEST_LOG_ROOT="$test_dir/apps" erl +S 2:2 +A 1 -noshell \
        -pa "$SCRIPT_DIR/../deps/lager/ebin" \
        -lager log_root "\"$test_dir/apps\"" \
        -eval 'ok = application:load(lager), {ok, Root} = application:get_env(lager, log_root), Root = os:getenv("KAZOO_TEST_LOG_ROOT"), halt(0).'
fi
printf 'PASS: per-node private logs, bounded crash diagnostics, native FreeSWITCH retention\n'
