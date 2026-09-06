#!/usr/bin/env node
'use strict';
// Actual installer functions; every build/service operation is a shell double.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict'),cp=require('node:child_process');
const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
function hook(name){const match=installer.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}', 'm'));assert(match);return match[0];}
const init=installer.match(/^KAZOO_BUILD_SUCCEEDED_THIS_RUN=false$/m);assert(init);
assert(!installer.slice(installer.indexOf('readonly KAZOO_PERSISTED_KEYS=('),installer.indexOf('KAZOO_AMQP_SPLIT_OVERRIDE=false')).includes('KAZOO_BUILD_SUCCEEDED_THIS_RUN'));
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-current-build.'));
try {
    for(const file of ['core/kazoo_apps/ebin/kazoo_apps.app','applications/ecallmgr/ebin/ecallmgr.app']){const target=path.join(temp,file);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'stale fixture');}
    const stubs=`
set -euo pipefail
log(){ :; }
run(){ :; }
make(){ printf 'make\\n'; }
rm(){ :; }
sleep(){ :; }
install_kazoo_build_dependencies(){ printf 'build-start\\n'; }
ensure_kazoo_sources(){ printf 'source-patches\\n'; }
configure_kazoo(){ :; }
remove_test_compiled_kazoo_beams(){ :; }
prepare_kazoo_runtime_artifact_permissions(){ :; }
verify_kazoo_production_beams(){ printf 'production-verify\\n'; return "$VERIFY_EXIT"; }
install_kazoo_systemd_units(){ printf 'units\\n'; }
install_sup_cli(){ :; }
service_enable_restart(){ printf 'service\\n'; }
configure_ecallmgr_dialplan_applications(){ :; }
configure_ecallmgr_callback_cleanup(){ :; }
configure_ecallmgr_event_stream_framing(){ :; }
register_configured_freeswitch_nodes(){ :; }
verify_ecallmgr(){ printf 'runtime-verify\\n'; }
`;
    function run(prefix='',overrides={}){return cp.spawnSync('/usr/bin/bash',['--noprofile','--norc','-s'],{encoding:'utf8',timeout:10000,
        env:{PATH:'/usr/bin:/bin',KAZOO_ROOT:temp,KAZOO_MAKE_JOBS:'1',KAZOO_CORE_REF:'fixture',KAZOO_CROSSBAR_REF:'fixture',KAZOO_ECALLMGR_REF:'fixture',KAZOO_STEPSWITCH_REF:'fixture',KAZOO_CDR_REF:'fixture',ACDC_REF:'fixture',DRY_RUN:'false',VERIFY_EXIT:'0',...overrides},
        input:stubs+'\n'+init[0]+'\n'+hook('build_kazoo')+'\n'+hook('install_ecallmgr')+'\n'+prefix+'\ninstall_ecallmgr\n'});}
    let result=run('',{KAZOO_BUILD_SUCCEEDED_THIS_RUN:'true'});assert.equal(result.status,0,result.stderr);
    assert.equal(result.stdout.split('build-start').length,2,'Existing app files/environment cannot skip current build');
    assert(result.stdout.indexOf('source-patches')<result.stdout.indexOf('production-verify'));
    assert(result.stdout.indexOf('production-verify')<result.stdout.indexOf('service'));
    result=run('build_kazoo');assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.split('build-start').length,2,'All-in-one reuses this invocation successful build');
    result=run('',{VERIFY_EXIT:'7'});assert.equal(result.status,7);assert(!result.stdout.includes('units'));assert(!result.stdout.includes('service'));
    result=run('',{DRY_RUN:'true'});assert.equal(result.status,0,result.stderr);assert(!result.stdout.includes('make'));assert(!result.stdout.includes('production-verify'));
    console.log('PASS stale app/environment refusal, current-invocation reuse, failed verification stops activation, and dry-run build behavior');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
