#!/usr/bin/env node
'use strict';
// Actual installer functions; every build/service operation is a shell double.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict'),cp=require('node:child_process');
const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
function hook(name){const match=installer.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}', 'm'));assert(match);return match[0];}
const init=installer.match(/^KAZOO_BUILD_SUCCEEDED_THIS_RUN=false$/m);assert(init);
const snapshotInit=installer.match(/^KAZOO_BUILD_SNAPSHOT_THIS_RUN=''$/m);assert(snapshotInit);
assert(!installer.slice(installer.indexOf('readonly KAZOO_PERSISTED_KEYS=('),installer.indexOf('KAZOO_AMQP_SPLIT_OVERRIDE=false')).includes('KAZOO_BUILD_SUCCEEDED_THIS_RUN'));
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-current-build.'));
try {
    for(const file of ['core/kazoo_apps/ebin/kazoo_apps.app','applications/ecallmgr/ebin/ecallmgr.app']){const target=path.join(temp,file);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'stale fixture');}
    const stubs=`
set -euo pipefail
log(){ :; }
die(){ printf '%s\\n' "$*" >&2; exit 1; }
run(){ :; }
make(){
    printf 'make %s\\n' "$*"
    if [[ -n "\${MAKE_FAIL_ARGS:-}" && "$*" == "$MAKE_FAIL_ARGS" ]]; then return 71; fi
}
rm(){ :; }
sleep(){ :; }
install_kazoo_build_dependencies(){ printf 'build-start\\n'; }
ensure_kazoo_sources(){ printf 'source-patches\\n'; }
configure_kazoo(){ :; }
remove_test_compiled_kazoo_beams(){ :; }
prepare_kazoo_runtime_artifact_permissions(){ :; }
verify_kazoo_production_beams(){ printf 'production-verify\\n'; return "$VERIFY_EXIT"; }
kazoo_build_snapshot(){ printf 'snapshot-called\\n' >&2; printf '%s\\n' "\${SNAPSHOT_DIGEST:-${'1'.repeat(64)}}"; }
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
        env:{PATH:'/usr/bin:/bin',KAZOO_ROOT:temp,KAZOO_MAKE_JOBS:'1',KAZOO_CORE_REF:'fixture',KAZOO_CROSSBAR_REF:'fixture',KAZOO_BLACKHOLE_REF:'fixture',KAZOO_ECALLMGR_REF:'fixture',KAZOO_STEPSWITCH_REF:'fixture',KAZOO_CDR_REF:'fixture',ACDC_REF:'fixture',DRY_RUN:'false',VERIFY_EXIT:'0',...overrides},
        input:stubs+'\n'+init[0]+'\n'+snapshotInit[0]+'\n'+hook('verify_kazoo_current_build')+'\n'+hook('build_kazoo')+'\n'+hook('install_ecallmgr')+'\n'+prefix+'\ninstall_ecallmgr\n'});}
    let result=run('',{KAZOO_BUILD_SUCCEEDED_THIS_RUN:'true'});assert.equal(result.status,0,result.stderr);
    assert.equal(result.stdout.split('build-start').length,2,'Existing app files/environment cannot skip current build');
    assert(result.stdout.indexOf('source-patches')<result.stdout.indexOf('production-verify'));
    assert(result.stdout.indexOf('production-verify')<result.stdout.indexOf('service'));
    const builds=result.stdout.split('\n').filter(line=>line.startsWith('make '));
    const compileArgs=[
        `-C ${temp} JOBS=1 KAZOO_FORCE_RECOMPILE=1 core fetch-apps`,
        `-C ${temp}/applications/webhooks KAZOO_FORCE_RECOMPILE=1 all`,
        `-C ${temp}/applications ROOT=${temp} -j1 KAZOO_FORCE_RECOMPILE=1 all`,
    ];
    const releaseArgs=`-C ${temp} JOBS=1 build-dev-release`;
    const forced=builds.filter(line=>line.includes('KAZOO_FORCE_RECOMPILE='));
    assert.deepEqual(forced,compileArgs.map(args=>'make '+args),'exact forced core, webhooks, direct aggregate order');
    assert(!builds.some(line=>line.startsWith(`make -C ${temp} `)&&line.endsWith(' apps')),'never reenter top-level apps/core dependency');
    assert.equal(builds.filter(line=>line==='make '+releaseArgs).length,1,'one release assembly');
    assert(builds.indexOf('make '+compileArgs[2])<builds.indexOf('make '+releaseArgs),'release follows full application compilation');
    assert(result.stdout.indexOf('make '+releaseArgs)<result.stdout.indexOf('production-verify'));
    assert(result.stderr.includes('snapshot-called'),'successful build records its source/artifact snapshot');
    for(let stage=0;stage<compileArgs.length;stage++) {
        const failed=run('',{MAKE_FAIL_ARGS:compileArgs[stage]});
        assert.equal(failed.status,71,'compile failure propagates at stage '+stage);
        assert(failed.stdout.includes('make '+compileArgs[stage]));
        for(const later of compileArgs.slice(stage+1))assert(!failed.stdout.includes('make '+later),'no later compile after stage '+stage);
        assert(!failed.stdout.includes('build-dev-release'),'no release after compile failure');
        assert(!failed.stdout.includes('production-verify'),'no production success gate after compile failure');
        assert(!failed.stderr.includes('snapshot-called'),'no successful build snapshot after compile failure');
        for(const marker of ['units','service','runtime-verify'])assert(!failed.stdout.includes(marker),'no activation after compile failure');
    }
    const parallel=run('',{KAZOO_MAKE_JOBS:'3'});assert.equal(parallel.status,0,parallel.stderr);
    assert(parallel.stdout.includes(`make -C ${temp} JOBS=3 KAZOO_FORCE_RECOMPILE=1 core fetch-apps`));
    assert(parallel.stdout.includes(`make -C ${temp}/applications ROOT=${temp} -j3 KAZOO_FORCE_RECOMPILE=1 all`),'direct aggregate consumes bounded parallelism, not unused JOBS');
    assert(builds.some(line=>line.includes('--eval=.PHONY: src/kz_mime.erl')),'force local MIME regeneration');
    assert(builds.some(line=>line.includes('--eval=.PHONY: src/knm_iso3166a2_itu.erl src/knm_iso3166_util.erl')),'force local number regeneration');
    result=run('build_kazoo');assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.split('build-start').length,2,'All-in-one reuses this invocation successful build');
    result=run('',{VERIFY_EXIT:'7'});assert.equal(result.status,7);assert(!result.stdout.includes('units'));assert(!result.stdout.includes('service'));
    result=run('',{DRY_RUN:'true'});assert.equal(result.status,0,result.stderr);assert(!result.stdout.includes('make'));assert(!result.stdout.includes('production-verify'));
    result=run('build_kazoo\nSNAPSHOT_DIGEST='+ '2'.repeat(64));assert.equal(result.status,1);assert.match(result.stderr,/changed after compilation/);assert(!result.stdout.includes('units'));assert(!result.stdout.includes('service'));
    result=run('build_kazoo\nKAZOO_BUILD_SNAPSHOT_THIS_RUN=invalid');assert.equal(result.status,1);assert(!result.stdout.includes('service'));
    result=run('',{SNAPSHOT_DIGEST:'invalid'});assert.equal(result.status,1);assert.match(result.stderr,/Invalid Kazoo build snapshot/);assert(!result.stdout.includes('service'));
    console.log('PASS exact single-core/direct-app build ordering, bounded parallelism, compile failures stop release/snapshot/activation, stale app/environment refusal, current-invocation reuse, source/artifact drift refusal, invalid snapshot rejection, failed verification stops activation, and dry-run build behavior');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
