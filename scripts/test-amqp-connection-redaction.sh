#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
fixture=$(mktemp -d /tmp/kazoo-amqp-redaction.XXXXXX)
export ERL_LIBS="$root/deps:$root/core:$root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$fixture/erl_crash.dump"
sha256sum core/kazoo_amqp/src/kz_amqp_connection.erl scripts/erlang-tests/amqp_connection_redaction_tests.erl > "$fixture/inputs.sha256"
# Direct lager entry points permit exact argument capture. Only test-private
# output omits the logging transform; production BEAMs are never overwritten.
erlc -Werror +debug_info -I core/kazoo_amqp/src -I core/kazoo_amqp/include -o "$fixture" \
    core/kazoo_amqp/src/kz_amqp_connection.erl
erlc -Werror -I core/kazoo_amqp/include -o "$fixture" scripts/erlang-tests/amqp_connection_redaction_tests.erl
erl -noshell -pa "$fixture" -eval 'case eunit:test(amqp_connection_redaction_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
sha256sum --check "$fixture/inputs.sha256"
printf 'Evidence: %s\n' "$fixture"
