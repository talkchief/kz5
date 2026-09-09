'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const hook=source.match(/^verify_ecallmgr_query_listener\(\) \{[\s\S]*?^\}/m)[0];
for(const [mode,status] of [['ready',0],['reconnecting',42],['error',42],['malformed',42]]) {
    const script=`set -Eeuo pipefail
die(){ echo "$*" >&2; exit 42; }
log(){ echo "$*"; }
timeout(){ shift 2; "$@"; }
sup(){ [[ "$*" == '-n ecallmgr -e gen_listener is_consuming ecallmgr_fs_channels' ]] || exit 43
case "$MODE" in ready) echo true;; reconnecting) echo false;; error) echo SECRET; return 1;; malformed) echo '{badrpc,SECRET}';; esac; }
sleep(){ SECONDS=$((SECONDS+2)); }
${hook}
verify_ecallmgr_query_listener
`;
    const r=spawnSync('bash',['--noprofile','--norc','-s'],{input:script,encoding:'utf8',timeout:3000,
        env:{PATH:'/usr/bin:/bin',MODE:mode,DRY_RUN:'false',KAZOO_START_TIMEOUT:'1'}});
    assert.ifError(r.error);assert.equal(r.status,status,r.stdout+r.stderr);assert(!(r.stdout+r.stderr).includes('SECRET'));
}
assert(source.match(/^verify_ecallmgr\(\) \{[\s\S]*?^\}/m)[0].includes('verify_ecallmgr_query_listener'));
console.log('PASS actual eCallMgr query-readiness function: consuming, reconnecting, RPC error, malformed output and installer wiring');
