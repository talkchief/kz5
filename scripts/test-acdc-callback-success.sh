#!/usr/bin/env bash
# Isolated accepted-callback mailbox tests: no live nodes, AMQP, database or calls.
set -Eeuo pipefail
success_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
success_source=${KAZOO_CALLBACK_SUCCESS_SOURCE:-$success_root/applications/acdc/src/cf_acdc_member.erl}
success_build=$(mktemp -d /tmp/kazoo-acdc-callback-success.XXXXXX)
mkdir -m 0700 "$success_build/production"
trap 'printf "Private callback success artifacts: %s\n" "$success_build"' EXIT
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export ERL_LIBS="$success_root/deps:$success_root/core:$success_root/applications"
erlc -Werror +debug_info -I "$success_root/applications/acdc/include" \
    -pa "$success_root/deps/lager/ebin" +'{parse_transform,lager_transform}' \
    -o "$success_build/production" "$success_source"
erlc -DTEST -Werror +debug_info -I "$success_root/applications/acdc/include" -o "$success_build" \
    "$success_source" "$success_root/applications/acdc/src/acdc_callback_menu.erl"
erlc -Werror -o "$success_build" "$success_root/scripts/erlang-tests/cf_acdc_callback_success_tests.erl"
erl -noshell -pa "$success_build" \
    -eval '[Production] = init:get_plain_arguments(),
           {ok,{cf_acdc_member,[{exports,[{handle,2},{module_info,0},{module_info,1}]}]}} =
               beam_lib:chunks(Production, [exports]),
           case eunit:test(cf_acdc_callback_success_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    -extra "$success_build/production/cf_acdc_member.beam"
sha256sum "$success_source" "$success_build/production/cf_acdc_member.beam"
