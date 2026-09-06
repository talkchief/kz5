#!/usr/bin/env bash
# Isolated default-Crossbar patch replay; no source BEAM or live node writes.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_root=${KAZOO_TEST_PROJECT_ROOT:-$(cd -- "$script_dir/.." && pwd -P)}
test_dir=$(mktemp -d /tmp/kazoo-monster-catalog.XXXXXX)
cleanup() {
    [[ -d $test_dir && ! -L $test_dir && $(basename -- "$test_dir") == kazoo-monster-catalog.* ]] && find "$test_dir" -depth -delete
}
trap cleanup EXIT
pin=$(node - "$script_dir/install-kazoo5.sh" <<'JS'
const fs=require('node:fs'),assert=require('node:assert/strict');
const matches=[...fs.readFileSync(process.argv[2],'utf8').matchAll(/^KAZOO_CROSSBAR_REF=\$\{KAZOO_CROSSBAR_REF:-([a-f0-9]{40})\}$/gm)];
assert.equal(matches.length,1);process.stdout.write(matches[0][1]);
JS
)
mkdir "$test_dir/source" "$test_dir/production" "$test_dir/test"
patch_file="$script_dir/patches/crossbar-kazoo5-integration.patch"
patch_before=$(sha256sum "$patch_file" | awk '{print $1}')
git -C "$project_root/applications/crossbar" archive "$pin" | tar -xf - -C "$test_dir/source"
git -C "$test_dir/source" apply --check "$patch_file"
git -C "$test_dir/source" apply "$patch_file"
cmp "$test_dir/source/src/kazoo_monster_catalog.erl" "$script_dir/../applications/crossbar/src/kazoo_monster_catalog.erl"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
compiler=(-Werror +warn_export_all +warn_unused_import +warn_unused_vars +warn_missing_spec +debug_info
    -I "$test_dir/source/include" -I "$test_dir/source/src" -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}')
erlc "${compiler[@]}" -o "$test_dir/production" "$test_dir/source/src/kazoo_monster_catalog.erl"
KAZOO_TEST_BEAM="$test_dir/production/kazoo_monster_catalog.beam" erl -noshell -eval '
  {ok,{kazoo_monster_catalog,[{exports,Exports},{imports,Imports}]}}=beam_lib:chunks(os:getenv("KAZOO_TEST_BEAM"),[exports,imports]),
  true=lists:sort(Exports)=:=lists:sort([{init_app,3},{module_info,0},{module_info,1}]),
  []=[I || I={kapps_util,_,_} <- Imports],
  true=lists:member({kapps_config,get_ne_binary,2},Imports),
  halt(0).'
erlc -DTEST "${compiler[@]}" -o "$test_dir/test" "$test_dir/source/src/kazoo_monster_catalog.erl"
erlc -DTEST -Werror -o "$test_dir/test" "$script_dir/erlang-tests/kazoo_monster_catalog_tests.erl"
erl -noshell -pa "$test_dir/test" -eval 'case eunit:test(kazoo_monster_catalog_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
[[ $(sha256sum "$patch_file" | awk '{print $1}') == "$patch_before" ]] || { printf '%s\n' 'Patch changed during tests' >&2; exit 1; }
printf 'PASS default Crossbar replay %s patch %s; production flags and exports; offline catalog tests\n' "$pin" "$patch_before"
