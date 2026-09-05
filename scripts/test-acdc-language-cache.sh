#!/usr/bin/env bash
# Local isolated VM only: no running node, database, or installed BEAM changes.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-language-cache-test.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +warn_missing_spec -DTEST -I applications/acdc/src -o "$test_dir" \
    applications/acdc/src/acdc_language_maintenance.erl
erlc -Werror +warn_missing_spec -I core/kazoo_media/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" core/kazoo_media/src/kz_media_map.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_language_maintenance_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_language_maintenance_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
ACDC_CACHE_TEST_DIR="$test_dir" node - <<'NODE'
const cp=require('node:child_process'),assert=require('node:assert/strict');
const {catalog,locales}=require('./scripts/acdc-language-catalog.cjs');
const expected=locales.flatMap(locale=>catalog(locale).prompts.map(p=>locale+'/'+p.id)).sort();
const actual=JSON.parse(cp.execFileSync('erl',['-pa',process.env.ACDC_CACHE_TEST_DIR,'-noshell','-eval',
    'io:put_chars(kz_json:encode(acdc_language_maintenance:catalog())), halt(0).'],{encoding:'utf8',maxBuffer:4*1024*1024}));
assert.equal(actual.length,6143);assert.deepEqual(actual.sort(),expected);
console.log('PASS exact6143 Erlang maintenance IDs match the generator/importer catalog');
NODE
