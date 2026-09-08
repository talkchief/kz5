#!/usr/bin/env bash
# Focused UI-03 ancestry regression and production module build; no live writes.
set -Eeuo pipefail
umask 077
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
output=$(mktemp -d /tmp/kazoo-entitlements.XXXXXXXX)
export ERL_LIBS="$root/deps:$root/core:$root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_CRASH_DUMP="$output/erl_crash.dump"
source_file=core/kazoo_services/src/kz_entitlements.erl
test_file=core/kazoo_services/test/kz_entitlements_tests.erl
patch_file=scripts/patches/kazoo-entitlements-master-ancestry.patch
sha256sum "$source_file" "$test_file" "$patch_file" > "$output/inputs.sha256"
git -C core apply --reverse --check "$root/$patch_file"
mkdir "$output/test" "$output/production" "$output/replay"
git -C core archive HEAD kazoo_services/src/kz_entitlements.erl kazoo_services/test/kz_entitlements_tests.erl | tar -xf - -C "$output/replay"
git -C "$output/replay" apply "$root/$patch_file"
cmp "$source_file" "$output/replay/kazoo_services/src/kz_entitlements.erl"
cmp "$test_file" "$output/replay/kazoo_services/test/kz_entitlements_tests.erl"
erlc -Werror +debug_info -DTEST -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$output/test" "$source_file" "$test_file"
erl -noshell -pa "$output/test" -eval 'case eunit:test(kz_entitlements_tests:reseller_ancestors_test_(),[verbose]) of ok -> halt(0); _ -> halt(1) end.' | tee "$output/eunit.log"
erlc -Werror +debug_info -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$output/production" "$source_file"
sha256sum --status --check "$output/inputs.sha256"
printf 'PASS UI-03 entitlement ancestry tests and production compilation: %s\n' "$output"
