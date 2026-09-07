'use strict';
// Installer function doubles only. No actual SUP, credentials or services.
const fs=require('node:fs'), cp=require('node:child_process'), path=require('node:path'), os=require('node:os');
const assert=require('node:assert/strict');
const file=path.join(__dirname,'install-kazoo5.sh'), source=fs.readFileSync(file,'utf8');
function extract(name) {
    const start=source.indexOf('\n'+name+'() {'); assert(start>=0);
    const marker=name==='kazoo_blackhole_module_output'?'\nNODE\n}':'\n}';
    const end=source.indexOf(marker,start);assert(end>start);return source.slice(start+1,end+marker.length)+'\n';
}
const helpers=['kazoo_blackhole_module_output','configure_kazoo_scope_management','verify_kazoo_scope_management'].map(extract).join('\n');
const proof=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-scope-registration.'));fs.chmodSync(proof,0o700);
const setup=`set -Eeuo pipefail
log(){ :; }
die(){ printf '%s\\n' "$*" >&2; exit 77; }
monster_registration_available(){ [[ $AUTHORITY == true ]]; }
timeout(){ [[ $1 == 30 && $2 == sup ]] || exit 95; shift; "$@"; }
sup(){
    printf '%s\\n' "$*" >>"$TRACE"
    case "$*" in
        'cb_scope_restrictions management_guard_version') [[ $FAIL != guard ]] || return 1; printf '%s\\n' "$GUARD" ;;
        'crossbar_config autoload_modules')
            [[ $FAIL != autoload ]] || return 1
            if [[ -e $STATE ]]; then printf '%s\\n' "$AFTER_AUTO"; else printf '%s\\n' "$BEFORE_AUTO"; fi ;;
        'crossbar_bindings modules_loaded')
            [[ $FAIL != running ]] || return 1
            if [[ -e $STATE ]]; then printf '%s\\n' "$AFTER_RUN"; else printf '%s\\n' "$BEFORE_RUN"; fi ;;
        'crossbar_maintenance start_module cb_scope_restrictions')
            [[ $FAIL != start ]] || return 1
            : >"$STATE"
            printf '%s\\n' "$START_OUTPUT" ;;
        *) exit 95 ;;
    esac
}
`;
const base={DRY_RUN:'false',AUTHORITY:'true',FAIL:'',GUARD:'1',
    BEFORE_AUTO:'[<<"cb_accounts">>,<<"cb_scope_retrictions">>,<<"cb_custom">>]',
    BEFORE_RUN:'[cb_accounts,cb_custom]',
    AFTER_AUTO:'[<<"cb_scope_restrictions">>,<<"cb_accounts">>,<<"cb_scope_retrictions">>,<<"cb_custom">>]',
    AFTER_RUN:'[cb_accounts,cb_scope_restrictions,cb_custom]',START_OUTPUT:'started and added cb_scope_restrictions to autoloaded modules\nok'};
let groups=0;const cases=[];
function run(name,env={},want=0,action='configure_kazoo_scope_management') {
    const dir=path.join(proof,name);fs.mkdirSync(dir,{mode:0o700});
    const trace=path.join(dir,'trace');
    const r=cp.spawnSync('/bin/bash',['--noprofile','--norc','-s'],{
        input:setup+helpers+`\nif ${action}; then exit 0; else exit 78; fi\n`,
        env:{PATH:'/usr/bin:/bin',LANG:'C',...base,...env,TRACE:trace,STATE:path.join(dir,'state')},
        encoding:'utf8',timeout:5000,maxBuffer:65536});
    assert.ifError(r.error);assert.equal(r.status,want,name+': '+r.stderr);
    const calls=fs.existsSync(trace)?fs.readFileSync(trace,'utf8').trim().split('\n'):[];
    assert(!calls.some(c=>/set_|stop_|flush/.test(c)));
    cases.push({name,calls,status:r.status});groups++;return calls;
}
try {
    assert.equal(run('normal').filter(c=>c==='crossbar_maintenance start_module cb_scope_restrictions').length,1);
    const already={BEFORE_AUTO:base.AFTER_AUTO,BEFORE_RUN:base.AFTER_RUN};
    assert.equal(run('idempotent',already).length,3);
    assert.deepEqual(run('dry',{DRY_RUN:'true'}),[]);
    assert.deepEqual(run('remote',{AUTHORITY:'false'}),[]);
    for(const name of ['guard','autoload','running','start']) run('failure-'+name,{FAIL:name},77);
    for(const [name,value] of [['old','0'],['other','11'],['error','{error,undef}'],['extra','1\nok']]) {
        assert.equal(run('guard-'+name,{GUARD:value},77).length,1);
    }
    run('printed-start-error',{START_OUTPUT:'failed to start cb_scope_restrictions: undef\nok'},77);
    run('masked-override',{AFTER_AUTO:base.BEFORE_AUTO},77);
    run('not-running',{AFTER_RUN:base.BEFORE_RUN},77);
    run('lost-autoload',{AFTER_AUTO:'[<<"cb_scope_restrictions">>]'},77);
    run('lost-running',{AFTER_RUN:'[cb_scope_restrictions]'},77);
    for(const [name,value] of [['substring','[<<"cb_scope_restrictions_other">>]'],['malformed','[<<"cb_scope_restrictions">>,]'],['error','{error,unavailable}']])
        run('invalid-'+name,{BEFORE_AUTO:value},77,'verify_kazoo_scope_management');
    assert.equal(run('verify',already,0,'verify_kazoo_scope_management').length,3);
    run('verify-running-missing',{...already,BEFORE_RUN:'[cb_accounts]'},77,'verify_kazoo_scope_management');
    assert(extract('configure_kazoo_api_modules').includes('    configure_kazoo_scope_management\n'));
    assert(extract('verify_acdc_interfaces').includes('    verify_kazoo_scope_management\n'));
    assert(source.includes('"$SCRIPT_DIR/patches/crossbar-scope-management-guard.patch"'));
    assert.equal(fs.readFileSync(file,'utf8'),source);
    console.log(JSON.stringify({result:'PASS',groups,scope:'installer helpers with controlled SUP only',proof}));
} finally {
    fs.writeFileSync(path.join(proof,'receipt.json'),JSON.stringify({groups,cases,source_stable:fs.readFileSync(file,'utf8')===source},null,2)+'\n');
}
