#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-stacktrace-test.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
# No TEST macro or Lager transform: the mock sees raw logger arguments.
erlc -o "$test_dir" "$project_root/core/kazoo_stdlib/src/kz_log.erl" \
    "$project_root/scripts/erlang-tests/kz_log_stacktrace_tests.erl"
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(kz_log_stacktrace_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
git -C "$project_root/core" apply --reverse --check \
    "$project_root/scripts/patches/kazoo-stacktrace-argument-redaction.patch"
