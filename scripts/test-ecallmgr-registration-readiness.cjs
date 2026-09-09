'use strict';
// Exercise the actual installer hook. No live services, configuration or cookies.
const fs=require('node:fs'), assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const hook=source.match(/^register_configured_freeswitch_nodes\(\) \{[\s\S]*?^\}/m)[0];
const fixture=`set -Eeuo pipefail
die(){ printf '%s\\n' "$*" >&2; exit 42; }
log(){ printf '%s\\n' "$*"; }
freeswitch_nodes_to_manage(){ echo freeswitch@fixture; }
systemctl(){ [[ $* == 'is-active --quiet kazoo-ecallmgr.service' ]]; }
verify_erlang_applications(){
 [[ $* == 'ecallmgr ecallmgr' ]] || exit 99
 [[ $READY == true ]] || die 'runtime not ready'
 echo READY
}
timeout(){ shift 2; "$@"; }
sup(){
 case "$*" in
  '-n ecallmgr ecallmgr_maintenance get_fs_nodes') echo READ_CONFIG >&2 ;;
  '-n ecallmgr ecallmgr_maintenance add_fs_node freeswitch@fixture')
   echo 'sentinel-distribution-cookie' ; [[ $ADD_STATUS == 0 ]] ;;
  *) exit 99 ;;
 esac
}
${hook}
register_configured_freeswitch_nodes
`;
for(const [ready,add,status] of [['true','0',0],['true','1',42],['false','0',42]]) {
 const r=spawnSync('bash',['--noprofile','--norc','-s'],{input:fixture,encoding:'utf8',timeout:3000,
  env:{PATH:'/usr/bin:/bin',READY:ready,ADD_STATUS:add,DRY_RUN:'false',KAZOO_START_TIMEOUT:'1'}});
 assert.ifError(r.error);assert.equal(r.status,status,r.stdout+r.stderr);
 assert(!(r.stdout+r.stderr).includes('sentinel-distribution-cookie'));
 if(ready==='false')assert(!r.stdout.includes('Registered'));
 else assert(r.stdout.includes('READY'));
}
assert(hook.indexOf('verify_erlang_applications ecallmgr ecallmgr')<hook.indexOf('if configured='));
console.log('PASS media registration: runtime gate, success, failure and cookie-safe output');
