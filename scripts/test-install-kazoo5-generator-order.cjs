'use strict';
const fs=require('node:fs'), cp=require('node:child_process'), assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const start=source.indexOf('    remove_test_compiled_kazoo_beams\n',source.indexOf('build_kazoo() {'));
const last='    make -C "$KAZOO_ROOT/core/kazoo_web" --eval=\'.PHONY: src/kz_mime.erl\' src/kz_mime.erl';
const end=source.indexOf(last,start);
assert(start>0&&end>start);
const body=source.slice(start,end+last.length);
const prelude=`set -euo pipefail
KAZOO_ROOT=/nonexistent/kazoo-generator-fixture
KAZOO_MAKE_JOBS=2
ready=false
remove_test_compiled_kazoo_beams() { :; }
rm() { [[ "$*" == "-f $KAZOO_ROOT/core/kazoo_numbers/.deps.rules $KAZOO_ROOT/core/kazoo_web/.deps.rules" ]]; }
make() {
 if [[ "$*" == "-C $KAZOO_ROOT JOBS=2 deps" ]]; then ready=true; printf 'deps\\n';
 elif [[ "$2" == "$KAZOO_ROOT/core/kazoo_numbers" ]]; then printf 'numbers\\n';
 elif [[ "$2" == "$KAZOO_ROOT/core/kazoo_web" ]]; then
   [[ "$ready" == true ]] || { printf 'missing lager_transform\\n' >&2; return 79; }
   printf 'mime\\n';
 else return 78; fi
}
`;
const run=b=>cp.spawnSync('/usr/bin/bash',['-c',prelude+b],{encoding:'utf8'});
let result=run(body); assert.equal(result.status,0,result.stderr); assert.equal(result.stdout,'deps\nnumbers\nmime\n');
const old=body.replace(/^    FETCH_AS=https:\/\/github.com\/ make -C "\$KAZOO_ROOT" JOBS="\$KAZOO_MAKE_JOBS" deps\n/m,'');
assert.notEqual(old,body); result=run(old); assert.equal(result.status,79); assert.match(result.stderr,/missing lager_transform/);
console.log('PASS fresh generator dependency ordering; pre-fix control fails; no packages, source files or services changed.');
