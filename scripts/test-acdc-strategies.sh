#!/usr/bin/env bash
# Isolated source-level regression tests. No service, API or telephony mutation.
set -Eeuo pipefail
test_shard=all
if (($#)); then
    if [[ $# != 2 || $1 != --shard || ! $2 =~ ^[12]/2$ ]]; then
        printf '%s\n' 'Usage: test-acdc-strategies.sh [--shard 1/2|--shard 2/2]' >&2
        exit 2
    fi
    test_shard=${2%/2}
fi
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-strategies.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_queue_strategy.erl applications/acdc/src/acdc_queue_manager.erl \
    applications/acdc/src/acdc_queue_fsm.erl applications/acdc/src/acdc_agent_fsm.erl
erlc -Werror -I applications/acdc/src -I applications/acdc/include -o "$test_dir" scripts/erlang-tests/acdc_queue_strategy_tests.erl
# Same slow-host accommodation as test-acdc-unit.sh: mock compilation is part
# of EUnit wall time under the validation CPU quota. Keep every assertion and
# leave the external runtime/resource guard and production timers unchanged.
KAZOO_STRATEGY_TEST_SHARD="$test_shard" erl -pa "$test_dir" -noshell -eval '
  Module = acdc_queue_strategy_tests,
  Exports = Module:module_info(exports),
  Tests = lists:sort([Name || {Name,0} <- Exports,
      lists:suffix("_test", atom_to_list(Name)) orelse lists:suffix("_test_", atom_to_list(Name))]),
  true = length(Tests) > 0,
  Indexed = lists:zip(Tests, lists:seq(1,length(Tests))),
  Shard = os:getenv("KAZOO_STRATEGY_TEST_SHARD"),
  Selected = case Shard of
    "all" -> Tests;
    "1" -> [Name || {Name,I} <- Indexed, I rem 2 =:= 1];
    "2" -> [Name || {Name,I} <- Indexed, I rem 2 =:= 0]
  end,
  true = length(Selected) > 0,
  io:format("Strategy suite inventory (~p): ~p~nShard ~s selected (~p): ~p~n",
            [length(Tests),Tests,Shard,length(Selected),Selected]),
  Descriptors = [case lists:suffix("_test_",atom_to_list(Name)) of
      true -> {generator, fun() -> apply(Module,Name,[]) end};
      false -> {test,Module,Name}
    end || Name <- Selected],
  case eunit:test(Descriptors, [verbose,{scale_timeouts,4}]) of ok -> halt(0); _ -> halt(1) end.'
