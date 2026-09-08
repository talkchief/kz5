#!/usr/bin/env bash
# Offline: production compilation/public callbacks, no live BEAMs or services.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
content_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$content_root"
[[ $# == 0 ]]
content_output=$(mktemp -d /tmp/kazoo-optional-content.XXXXXX)
export ERL_LIBS="$content_root/deps:$content_root/core:$content_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$content_output/erl_crash.dump"
export KAZOO_CONTENT_OUTPUT="$content_output"
content_sources=(applications/crossbar/src/modules/cb_apps_store.erl
    applications/crossbar/src/modules/cb_vmboxes.erl applications/crossbar/src/modules/cb_directories.erl
    applications/crossbar/src/cb_apps_util.erl applications/crossbar/src/cb_context.erl)
sha256sum "${content_sources[@]}" scripts/erlang-tests/crossbar_optional_content_tests.erl \
    scripts/test-crossbar-optional-content.sh > "$content_output/inputs.sha256"
trap 'content_rc=$?; sha256sum --status --check "$content_output/inputs.sha256" || content_rc=99; printf "Optional-content exit %s; evidence %s\n" "$content_rc" "$content_output"; exit "$content_rc"' EXIT
erlc -Werror +debug_info -I applications/crossbar/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$content_output" "${content_sources[@]}"
erlc -Werror +debug_info -o "$content_output" scripts/erlang-tests/crossbar_optional_content_tests.erl \
    scripts/erlang-tests/kazoo_bindings_lager_tests.erl
erl -noshell -pa "$content_output" -eval '
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("KAZOO_CONTENT_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[cb_apps_store,cb_vmboxes,cb_directories,cb_apps_util,cb_context]),
    case eunit:test(crossbar_optional_content_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$content_output/eunit.log"
