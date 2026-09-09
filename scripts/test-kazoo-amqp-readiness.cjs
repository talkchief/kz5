'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const hook=source.match(/^verify_kazoo_amqp_ready\(\) \{[\s\S]*?^\}/m)[0];
for(const [mode,node,status] of [['available','ecallmgr',0],['available','kazoo_apps',0],['empty','ecallmgr',42],['error','ecallmgr',42],['available','other',42]]) {
    const script=`set -Eeuo pipefail
die(){ echo "$*" >&2; exit 42; }
log(){ echo "$*"; }
timeout(){ shift 2; "$@"; }
sup(){ case "$MODE" in available) echo true;; empty) echo false;; error) echo SECRET; return 1;; esac; }
sleep(){ SECONDS=$((SECONDS+2)); }
${hook}
verify_kazoo_amqp_ready "$NODE"
`;
    const r=spawnSync('bash',['--noprofile','--norc','-s'],{input:script,encoding:'utf8',timeout:3000,
        env:{PATH:'/usr/bin:/bin',MODE:mode,NODE:node,DRY_RUN:'false',KAZOO_START_TIMEOUT:'1'}});
    assert.ifError(r.error);assert.equal(r.status,status,r.stdout+r.stderr);
    assert(!(r.stdout+r.stderr).includes('SECRET'));
}
for(const [fn,node] of [['verify_ecallmgr','ecallmgr'],['verify_kazoo_apps','kazoo_apps']]) {
    const body=source.match(new RegExp('^'+fn+'\\(\\) \\{[\\s\\S]*?^\\}','m'))[0];
    assert(body.includes('verify_kazoo_amqp_ready '+node));
}
console.log('PASS AMQP readiness: both nodes, empty registry, RPC failure, invalid node and installer wiring');
