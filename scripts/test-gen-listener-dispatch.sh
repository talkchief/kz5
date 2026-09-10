#!/usr/bin/env bash
# Real production dispatch/monitor callbacks; transport only is controlled.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || {
    printf 'Private network namespace required\n' >&2; exit 2;
}
dispatch_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
dispatch_output=$(mktemp -d /tmp/kazoo-dispatch-maintenance.XXXXXX)
cd "$dispatch_root"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
export ERL_LIBS="$dispatch_root/deps:$dispatch_root/core:$dispatch_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$dispatch_output/erl_crash.dump"
sha256sum core/kazoo_amqp/src/gen_listener.erl scripts/erlang-tests/gen_listener_dispatch_tests.erl \
    scripts/patches/kazoo-listener-dispatch-inventory.patch \
    scripts/test-gen-listener-dispatch.sh > "$dispatch_output/source.sha256"
mkdir -p "$dispatch_output/core/kazoo_amqp/src" "$dispatch_output/before" "$dispatch_output/after" "$dispatch_output/fresh"
cp core/kazoo_amqp/src/gen_listener.erl "$dispatch_output/core/kazoo_amqp/src/"
dispatch_patch="$dispatch_root/scripts/patches/kazoo-listener-dispatch-inventory.patch"
# Check a pristine pinned checkout, not only reversal against the local tree.
git -C core archive HEAD kazoo_amqp/src/gen_listener.erl | tar -x -C "$dispatch_output/fresh"
git -C "$dispatch_output/fresh" apply "$dispatch_root/scripts/patches/kazoo-listener-secondary-queue-recovery.patch"
git -C "$dispatch_output/fresh" apply "$dispatch_patch"
cmp core/kazoo_amqp/src/gen_listener.erl "$dispatch_output/fresh/kazoo_amqp/src/gen_listener.erl"
git -C "$dispatch_output/core" apply --reverse --check "$dispatch_patch"
git -C "$dispatch_output/core" apply --reverse "$dispatch_patch"
compile_dispatch() {
    erlc -Werror +debug_info -I core/kazoo_amqp/include -I core/kazoo_amqp/src \
        -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$dispatch_output/$1" \
        "$dispatch_output/core/kazoo_amqp/src/gen_listener.erl" scripts/erlang-tests/gen_listener_dispatch_tests.erl
}
compile_dispatch before
if erl -pa "$dispatch_output/before" -noshell -eval \
    'case eunit:test(gen_listener_dispatch_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    >"$dispatch_output/before.log" 2>&1; then
    printf 'FAIL: previous source unexpectedly passed dispatch inventory tests\n' >&2; exit 1
fi
grep -q 'Failed: 12' "$dispatch_output/before.log"
grep -q 'badmap,{error,unsupported}' "$dispatch_output/before.log"
git -C "$dispatch_output/core" apply --check "$dispatch_patch"
git -C "$dispatch_output/core" apply "$dispatch_patch"
git -C "$dispatch_output/core" apply --reverse --check "$dispatch_patch"
cmp core/kazoo_amqp/src/gen_listener.erl "$dispatch_output/core/kazoo_amqp/src/gen_listener.erl"
compile_dispatch after
erl -pa "$dispatch_output/after" -noshell -eval \
    'case eunit:test(gen_listener_dispatch_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$dispatch_output/eunit.log"
sha256sum --check "$dispatch_output/source.sha256"
printf 'PASS: production asynchronous listener inventory; evidence %s\n' "$dispatch_output"
