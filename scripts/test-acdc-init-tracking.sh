#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
init_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ $# == 0 ]] || exit 2
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || exit 2
init_output=$(mktemp -d /tmp/kazoo-acdc-init.XXXXXX)
cd "$init_root"
export ERL_LIBS="$init_root/deps:$init_root/core:$init_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
init_inputs=(applications/acdc/src/acdc_init.erl applications/acdc/src/acdc_agent_util.erl applications/acdc/src/acdc.app.src
    scripts/erlang-tests/acdc_init_tracking_tests.erl scripts/erlang-tests/acdc_agent_status_strict_tests.erl scripts/test-acdc-init-tracking.sh)
sha256sum "${init_inputs[@]}" > "$init_output/source.sha256"
erlc -Werror +warn_export_all +warn_unused_import +warn_unused_vars +warn_missing_spec +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$init_output" \
    applications/acdc/src/acdc_init.erl applications/acdc/src/acdc_agent_util.erl
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$init_output" \
    scripts/erlang-tests/acdc_init_tracking_tests.erl scripts/erlang-tests/acdc_agent_status_strict_tests.erl
erl -pa "$init_output" -noshell -eval '
    {module,acdc_init}=code:ensure_loaded(acdc_init),
    case eunit:test([acdc_init_tracking_tests,acdc_agent_status_strict_tests],[verbose]) of ok->halt(0);_->halt(1) end.'
sha256sum -c "$init_output/source.sha256"
printf 'PASS tracked production initializer; evidence %s\n' "$init_output"
