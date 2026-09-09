#!/usr/bin/env bash
# Actual OTP child replacement; isolated output and no broker connections.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
fixture=$(mktemp -d /tmp/kazoo-amqp-supervised.XXXXXX)
export ERL_LIBS="$root/deps:$root/core:$root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$fixture/erl_crash.dump"
mkdir -p "$fixture/core/kazoo_amqp/src" "$fixture/before" "$fixture/after"
for module in kz_amqp_connection kz_amqp_connection_sup kz_amqp_connections; do
    cp "core/kazoo_amqp/src/$module.erl" "$fixture/core/kazoo_amqp/src/"
done
patch_file=$root/scripts/patches/kazoo-amqp-supervised-registration.patch
if git -C "$fixture/core" apply --reverse --check "$patch_file" 2>/dev/null; then
    git -C "$fixture/core" apply --reverse "$patch_file"
fi
compile_case() {
    local name=$1
    erlc -Werror +debug_info -I core/kazoo_amqp/src -I core/kazoo_amqp/include \
        -o "$fixture/$name" "$fixture/core/kazoo_amqp/src/"*.erl
    erlc -Werror -I core/kazoo_amqp/include -o "$fixture/$name" \
        scripts/erlang-tests/amqp_supervised_registration_tests.erl
}
compile_case before
if erl -noshell -pa "$fixture/before" -eval \
    'case eunit:test(amqp_supervised_registration_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    >"$fixture/before.log" 2>&1; then
    echo 'FAIL pristine source unexpectedly passed replacement regression' >&2; exit 1
fi
grep -q 'replacement_registration_missing' "$fixture/before.log"
grep -q 'Failed: 3' "$fixture/before.log"
git -C "$fixture/core" apply --check "$patch_file"
git -C "$fixture/core" apply "$patch_file"
git -C "$fixture/core" apply --reverse --check "$patch_file"
compile_case after
erl -noshell -pa "$fixture/after" -eval \
    'case eunit:test(amqp_supervised_registration_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
echo "PASS three before-fail/after-pass supervised replacements; evidence $fixture"
