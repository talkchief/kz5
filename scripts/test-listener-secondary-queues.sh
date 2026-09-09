#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
fixture=$(mktemp -d /tmp/kazoo-listener-secondary.XXXXXX)
export ERL_LIBS="$root/deps:$root/core:$root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$fixture/erl_crash.dump"
sha256sum core/kazoo_amqp/src/gen_listener.erl scripts/erlang-tests/listener_secondary_queue_tests.erl > "$fixture/inputs.sha256"
# Derive the private record layout from the actual production module. Test-only
# export_all is confined to this private output directory, never shared ebin.
node - "$fixture/state.hrl" <<'NODE'
const fs=require('fs'), assert=require('assert/strict');
const source=fs.readFileSync('core/kazoo_amqp/src/gen_listener.erl','utf8');
const records=source.match(/-record\(state, \{[\s\S]*?\}\)\./g);
assert.equal(records?.length,1);
fs.writeFileSync(process.argv[2],records[0].replace(/ :: [^\n]*/g,''));
NODE
erlc -Werror +debug_info +export_all -I core/kazoo_amqp/src -I core/kazoo_amqp/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$fixture" core/kazoo_amqp/src/gen_listener.erl
erlc -Werror -I "$fixture" -o "$fixture" scripts/erlang-tests/listener_secondary_queue_tests.erl
erl -noshell -pa "$fixture" -eval 'case eunit:test(listener_secondary_queue_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
sha256sum --check "$fixture/inputs.sha256"
printf 'Evidence: %s\n' "$fixture"
