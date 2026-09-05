#!/usr/bin/env bash
# Actual module app logic with a deterministic FS boundary; never loads a module.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
module_dir=${MOD_KAZOO_SOURCE:-/usr/local/src/kazoo5-installer/freeswitch-1.11.3/src/mod/outoftree/mod_kazoo}
test_dir=$(mktemp -d /tmp/kazoo-intercept-test.XXXXXX)
trap 'rm -f -- "$test_dir/intercept-test"; rmdir -- "$test_dir"' EXIT
gcc -std=c11 -D_XOPEN_SOURCE=700 -Wall -Wextra -Werror -pthread -I"$module_dir" \
    "$project_root/scripts/test-fixtures/mod-kazoo-intercept-test.c" -o "$test_dir/intercept-test"
"$test_dir/intercept-test"
git -C "$module_dir" apply --reverse --check "$project_root/scripts/patches/mod-kazoo-atomic-intercept.patch"
fs_root=$(cd -- "$module_dir/../../../.." && pwd -P)
ei_include=${EI_INCLUDE:-/usr/lib64/erlang/lib/erl_interface-5.5.1/include}
gcc -fsyntax-only -Wall -Wextra -Werror -Wno-unused-parameter -D_REENTRANT \
    -I"$module_dir" -I"$fs_root/src/include" -I"$fs_root/libs/libteletone/src" \
    -I"$ei_include" "$module_dir/kazoo_dptools.c" "$module_dir/mod_kazoo.c"
