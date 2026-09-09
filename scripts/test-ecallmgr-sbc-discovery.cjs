'use strict';
// Exercise installer functions, without broker, database or service changes.
const fs=require('node:fs'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const functions=['configure_ecallmgr_sbc_discovery','verify_ecallmgr_sbc_discovery'].map(name=>{
    const body=source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'));assert(body);return body[0];
}).join('\n');
const script=`set -Eeuo pipefail
die(){ echo "$*" >&2; exit 42; }
log(){ echo "$*"; }
timeout(){ shift 2; "$@"; }
sup(){
 case "$*" in
  *'kapps_config set_default'*)
   [[ $CASE != write_error ]] || { echo SECRET; return 1; }
   [[ $CASE != rejected ]] || { echo SECRET; return; }
   echo '{ok,{[]}}' ;;
  *'erlang whereis'*)
   if [[ $CASE == already ]] || [[ -e "$MARK" ]]; then echo '<0.123.0>'; else echo undefined; fi ;;
  *'supervisor restart_child'*)
   [[ $CASE != failed_start ]] || { echo SECRET; return; }
   touch "$MARK"; echo '{ok,<0.123.0>}' ;;
  *'kz_app_config is_true'*) [[ $CASE == override ]] && echo false || echo true ;;
  *) exit 99 ;;
 esac
}
${functions}
configure_ecallmgr_sbc_discovery
`;
const dir=fs.mkdtempSync('/tmp/kz5-discovery-test.');
try {
    for(const [name,status] of [['start',0],['already',0],['write_error',42],['rejected',42],['failed_start',42],['override',42],['dry',0]]) {
        const r=spawnSync('bash',['--noprofile','--norc','-s'],{input:script,encoding:'utf8',timeout:3000,
            env:{PATH:'/usr/bin:/bin',CASE:name,MARK:dir+'/'+name,DRY_RUN:name==='dry'?'true':'false'}});
        assert.ifError(r.error);assert.equal(r.status,status,name+': '+r.stdout+r.stderr);
        assert(!(r.stdout+r.stderr).includes('SECRET'));
    }
} finally { fs.rmSync(dir,{recursive:true}); }
const install=source.match(/^install_ecallmgr\(\) \{[\s\S]*?^\}/m)[0];
assert(install.indexOf('configure_ecallmgr_sbc_discovery')<install.indexOf('register_configured_freeswitch_nodes'));
assert(source.match(/^verify_ecallmgr\(\) \{[\s\S]*?^\}/m)[0].includes('verify_ecallmgr_sbc_discovery'));
console.log('PASS seven discovery installer cases, normal install and verification wiring');
