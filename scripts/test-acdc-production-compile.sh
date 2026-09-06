#!/usr/bin/env bash
# Offline production compilation of bundled ACDC. Never replace/load live BEAMs.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"
[[ $# == 0 && ! -e applications/acdc/.git && ! -L applications/acdc/.git ]]
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null

# Include every local source/header in freshness checks, but compile only the
# top-level production modules. src/ci is intentionally not a runtime module.
input_list=$(find applications/acdc/src applications/acdc/include \( -type f -o -type l \) -print | LC_ALL=C sort)
mapfile -t compile_inputs <<<"$input_list"
[[ ${#compile_inputs[@]} -gt 0 ]]
for input in "${compile_inputs[@]}"; do [[ -f $input && ! -L $input ]]; done
sources=(applications/acdc/src/*.erl)
[[ -f ${sources[0]} ]]
for input in "${sources[@]}"; do [[ -f $input && ! -L $input ]]; done
input_hashes=$(sha256sum scripts/test-acdc-production-compile.sh "${compile_inputs[@]}")
production_dir=$(mktemp -d /tmp/kazoo-acdc-production.XXXXXX)
cleanup() {
    # Only this invocation's compiler output; never traverse another directory.
    find "$production_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$production_dir"
}
trap cleanup EXIT
erlc -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' \
    -o "$production_dir" "${sources[@]}"
KAZOO_PRODUCTION_CHECK_DIR="$production_dir" KAZOO_PRODUCTION_CHECK_COUNT="${#sources[@]}" \
    erl -noshell -eval '
      Dir = os:getenv("KAZOO_PRODUCTION_CHECK_DIR"),
      Expected = list_to_integer(os:getenv("KAZOO_PRODUCTION_CHECK_COUNT")),
      Files = filelib:wildcard(filename:join(Dir, "*.beam")),
      Expected = length(Files),
      lists:foreach(fun(File) ->
        {ok,{Module,[{compile_info,Info},{exports,Exports}]}} =
          beam_lib:chunks(File, [compile_info,exports]),
        Options = proplists:get_value(options,Info,[]),
        [] = [O || O <- Options, O =:= export_all orelse O =:= {d,'\''TEST'\''}
                    orelse (is_tuple(O) andalso tuple_size(O) =:= 3
                            andalso element(1,O) =:= d andalso element(2,O) =:= '\''TEST'\'')],
        Forbidden = case Module of
          acdc_agent_fsm -> [{changed_endpoints,2},{strategy_test_state,1},{strategy_test_field,2}];
          acdc_agent_listener -> [{maybe_connect_to_agent,7}];
          _ -> []
        end,
        [] = [E || E <- Forbidden, lists:member(E,Exports)]
      end,Files),
      io:format("PASS ~p production modules compiled with -Werror; no TEST build options or agent test exports~n",[Expected]),
      halt().'
[[ $(sha256sum scripts/test-acdc-production-compile.sh "${compile_inputs[@]}") == "$input_hashes" ]]
final_input_list=$(find applications/acdc/src applications/acdc/include \( -type f -o -type l \) -print | LC_ALL=C sort)
[[ $final_input_list == "$input_list" ]]
printf '%s\n' 'PASS bundled input freshness; no application BEAM loaded or installed'
