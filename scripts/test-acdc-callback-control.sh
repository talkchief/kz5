#!/usr/bin/env bash
# Private compile/mailbox tests. Never loads live BEAMs or sends AMQP/HTTP/SIP.
set -Eeuo pipefail
control_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
control_source=${KAZOO_CALLBACK_CONTROL_SOURCE:-$control_root/applications/acdc/src/cf_acdc_member.erl}
control_build=$(mktemp -d /tmp/kazoo-acdc-callback-control.XXXXXX)
mkdir -m 0700 "$control_build/production"
trap 'printf "Private callback control artifacts: %s\n" "$control_build"' EXIT
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export ERL_LIBS="$control_root/deps:$control_root/core:$control_root/applications"
erlc -Werror +debug_info -I "$control_root/applications/acdc/include" \
    -pa "$control_root/deps/lager/ebin" +'{parse_transform,lager_transform}' \
    -o "$control_build/production" "$control_source"
erlc -DTEST -Werror +debug_info -I "$control_root/applications/acdc/include" \
    -o "$control_build" "$control_source" \
    "$control_root/applications/acdc/src/acdc_callback_menu.erl" \
    "$control_root/applications/acdc/src/kapi_acdc_callback.erl"
erlc -Werror -o "$control_build" "$control_root/scripts/erlang-tests/cf_acdc_callback_control_tests.erl"
erl -noshell -pa "$control_build" \
    -eval '[Production] = init:get_plain_arguments(),
           {ok,{cf_acdc_member,[{exports,[{handle,2},{module_info,0},{module_info,1}]}]}} =
               beam_lib:chunks(Production, [exports]),
           case eunit:test(cf_acdc_callback_control_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    -extra "$control_build/production/cf_acdc_member.beam"
sha256sum "$control_source" "$control_build/production/cf_acdc_member.beam"
