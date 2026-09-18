#!/usr/bin/env bash
# Offline regression for kazoo-telemetry-opt-in.patch. Stock Kazoo reports
# cluster inventory to telemetry.2600hz.org every minute with no switch to turn
# it off; on the main development host each refused attempt also logged a
# "connection error" that failed the call campaigns' fresh-error log gate
# (September 18, 2026). Works on private copies; the fetched core is not changed.
set -Eeuo pipefail
umask 077
to_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
to_patch="$to_root/scripts/patches/kazoo-telemetry-opt-in.patch"
to_work=$(mktemp -d /tmp/kazoo-telemetry-opt-in.XXXXXX)
trap 'rm -rf -- "$to_work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
source_file=kazoo_telemetry/src/kazoo_telemetry_leader.erl
mkdir -p "$to_work/core/kazoo_telemetry/src" "$to_work/ebin"
# The pinned revision of the file, whether or not the installer has already patched the tree.
git -C "$to_root/core" show "HEAD:$source_file" > "$to_work/core/$source_file"
git -C "$to_work/core" init -q . && git -C "$to_work/core" apply --check "$to_patch" || fail 'patch does not apply to the pinned core'
git -C "$to_work/core" apply "$to_patch"
git -C "$to_work/core" apply --check --reverse "$to_patch" || fail 'patch does not reverse: a repeat install would not recognise it'
grep -Fq "get_boolean(?TELEMETRY_CAT, <<\"enabled\">>, 'false'" "$to_work/core/$source_file" || fail 'telemetry must default to disabled'
printf 'PASS: applies to and reverses from the pinned core; default is disabled\n'
grep -Fq 'patches/kazoo-telemetry-opt-in.patch' "$to_root/scripts/install-kazoo5.sh" || fail 'installer does not apply the patch'
export ERL_LIBS="$to_root/deps:$to_root/core:$to_root/applications"
erlc -Werror +debug_info -I "$to_root/core" -I "$to_root/core/kazoo_telemetry/include" -I "$to_root/core/kazoo_telemetry/src" \
    -pa "$to_root/deps/lager/ebin" +'{parse_transform,lager_transform}' -o "$to_work/ebin" "$to_work/core/$source_file"
erlc -Werror -o "$to_work/ebin" "$to_root/scripts/erlang-tests/kazoo_telemetry_opt_in_tests.erl"
erl -noshell -pa "$to_work/ebin" -eval 'case eunit:test(kazoo_telemetry_opt_in_tests, []) of ok -> halt(0); _ -> halt(1) end.' || \
    fail 'leader responders do not follow the opt-in setting'
printf 'PASS: no responders unless system_config telemetry.enabled is true\nAll 2 telemetry opt-in groups passed\n'
