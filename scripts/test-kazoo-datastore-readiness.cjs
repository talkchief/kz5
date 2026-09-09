#!/usr/bin/env node
'use strict';
// Extracted installer functions with shell doubles only: no live RPC, service,
// datastore, credentials, compiler, or network. Native readiness is a separate gate.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
function hook(name){const m=source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'));assert(m,name);return m[0];}
const readiness=hook('wait_kazoo_datastore_ready');
const rpc=readiness.match(/^    rpc='([^']+)'$/m)?.[1];assert(rpc);
assert(rpc.includes('kz_dataconnections:get_server(<<"local">>)'));
assert(rpc.includes('{Driver, Server} when is_atom(Driver)'));
assert(rpc.includes('Driver:server_info(Server) of {ok, _} -> ready; _ -> not_ready'));
assert(rpc.endsWith('catch _:_ -> not_ready end.'));
assert(!/set_default|open_doc|wait_for_connection|io:|format\(/.test(rpc),'read-only expression with no raw diagnostics');
for(const name of ['install_kazoo_apps','install_ecallmgr'])assert(!hook(name).includes('sleep 5'));
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-datastore-ready.'));let cases=0;
const stubs=`
set -euo pipefail
SECONDS=0
record(){ printf '%s\\n' "$*" >>"$TRACE"; }
log(){ printf '%s\\n' "$*"; }
die(){ printf '%s\\n' "$*" >&2; exit 1; }
verify_cookie_copy(){ record cookie-check; }
find_erl_call(){ printf '/fixture/erl_call\\n'; }
sleep(){ record "sleep $1"; SECONDS=$((SECONDS + $1)); }
timeout(){
    record "rpc $*"
    local expression count=0
    IFS= read -r expression
    [[ $expression == "$EXPECTED_RPC" ]] || return 92
    if [[ -f $COUNT ]]; then read -r count <"$COUNT"; fi
    count=$((count + 1)); printf '%s\\n' "$count" >"$COUNT"
    printf 'PRIVATE_CONNECTION_SECRET\\n' >&2
    case $MODE in
        ready) printf '{ok, ready}\\n' ;;
        transition) if ((count == 1)); then printf '{ok, not_ready}\\n'; else printf '{ok, ready}\\n'; fi ;;
        unavailable) printf '{ok, not_ready}\\n' ;;
        malformed) printf '{ok, ready} PRIVATE_CONNECTION_SECRET\\n' ;;
        bare) printf 'ready\\n' ;;
        failed) printf '{ok, ready}\\n'; return 124 ;;
        *) return 93 ;;
    esac
}
build_kazoo(){ record build; }
verify_kazoo_current_build(){ record current-build; }
configure_kazoo(){ record source-config; }
install_kazoo_systemd_units(){ record units; }
install_sup_cli(){ :; }
install_nodejs_toolchain(){ :; }
acdc_broker_upgrade_preflight(){ :; }
install_call_forward_confirmation_pack(){ :; }
install_monster_catalog_receiver(){ :; }
wait_kazoo_bootstrap_ready(){ :; }
service_enable_restart(){ record "restart $1"; }
install_acdc_language_packs(){ :; }
install_acdc_editor_capabilities(){ :; }
persist_kazoo_apps_config(){ record write-apps; }
ensure_master_account(){ record write-master; }
configure_kazoo_api_modules(){ record write-api; }
install_kazoo_prompts(){ record prompts; }
activate_acdc_voice_mappings(){ record mappings; }
finalize_acdc_prerecorded_capabilities(){ record capabilities; }
verify_kazoo_apps(){ record verify-apps; }
configure_ecallmgr_dialplan_applications(){ record write-dialplan; }
configure_ecallmgr_callback_cleanup(){ record write-callback; }
configure_ecallmgr_event_stream_framing(){ record write-framing; }
register_configured_freeswitch_nodes(){ record write-nodes; }
verify_ecallmgr(){ record verify-ecallmgr; }
`;
function run(command='wait_kazoo_datastore_ready kazoo_apps',overrides={}){
    const id=String(++cases),trace=path.join(temp,id+'.trace'),count=path.join(temp,id+'.count');
    const result=cp.spawnSync('/usr/bin/bash',['--noprofile','--norc','-s'],{encoding:'utf8',timeout:10000,
        env:{PATH:'/usr/bin:/bin',TRACE:trace,COUNT:count,EXPECTED_RPC:rpc,MODE:'ready',DRY_RUN:'false',
            KAZOO_HOSTNAME:'fixture.invalid',KAZOO_NODE_NAME_TYPE:'-name',KAZOO_START_TIMEOUT:'3',
            KAZOO_RUNTIME_COOKIE_FILE:'/fixture/not-read',KAZOO_BUILD_SUCCEEDED_THIS_RUN:'true',...overrides},
        input:stubs+'\n'+readiness+'\n'+hook('install_kazoo_apps')+'\n'+hook('install_ecallmgr')+'\n'+command+'\n'});
    assert(!result.error,result.error?.message);assert.equal(result.signal,null);
    assert(!(result.stdout+result.stderr).includes('PRIVATE_CONNECTION_SECRET'),'provider/connection output is never emitted');
    return {...result,trace:fs.existsSync(trace)?fs.readFileSync(trace,'utf8').trim().split('\n'):[]};
}
try {
    for(const prefix of ['kazoo_apps','ecallmgr'])for(const mode of ['-name','-sname']){
        const r=run('wait_kazoo_datastore_ready '+prefix,{KAZOO_NODE_NAME_TYPE:mode});assert.equal(r.status,0,r.stderr);
        assert.deepEqual(r.trace,['cookie-check',`rpc --signal=KILL 3 runuser --user kazoo -- /fixture/erl_call ${mode} ${prefix}@fixture.invalid -e`]);
    }
    let r=run(undefined,{MODE:'transition'});assert.equal(r.status,0,r.stderr);
    assert.equal(r.trace.filter(x=>x.startsWith('rpc ')).length,2);
    assert(r.trace.includes('sleep 2'));assert(r.trace.some(x=>x.startsWith('rpc --signal=KILL 1 ')),'last RPC clamped to deadline');
    r=run(undefined,{KAZOO_START_TIMEOUT:'30'});assert.equal(r.status,0);assert(r.trace.some(x=>x.startsWith('rpc --signal=KILL 10 ')));
    for(const mode of ['unavailable','malformed','bare','failed']){
        r=run(undefined,{MODE:mode});assert.equal(r.status,1,mode);
        assert.equal(r.trace.filter(x=>x.startsWith('rpc ')).length,2,'bounded retry '+mode);
        assert(r.trace.includes('sleep 1'),'sleep also clamped');assert(!r.stdout.includes('PASS'));
    }
    for(const overrides of [{KAZOO_HOSTNAME:''},{KAZOO_HOSTNAME:'bad@host'},{KAZOO_NODE_NAME_TYPE:''},
        {KAZOO_NODE_NAME_TYPE:'-hidden'},{KAZOO_START_TIMEOUT:'0'},{KAZOO_START_TIMEOUT:'09'},
        {KAZOO_START_TIMEOUT:'9999999999'},{KAZOO_START_TIMEOUT:'1+2'}]){
        r=run(undefined,overrides);assert.equal(r.status,1);assert.deepEqual(r.trace,[],'validate before cookie/RPC');
    }
    r=run('wait_kazoo_datastore_ready crossbar');assert.equal(r.status,1);assert.deepEqual(r.trace,[]);
    r=run(undefined,{DRY_RUN:'true'});assert.equal(r.status,0);assert.deepEqual(r.trace,[]);
    for(const [installer,prefix,firstWrite,last] of [
        ['install_kazoo_apps','kazoo_apps','write-apps','verify-apps'],
        ['install_ecallmgr','ecallmgr','write-dialplan','verify-ecallmgr'],
    ]){
        r=run(installer,{MODE:'transition'});assert.equal(r.status,0,r.stderr);
        const rpcIndices=r.trace.map((x,i)=>x.startsWith('rpc ')?i:-1).filter(i=>i>=0);
        assert.equal(rpcIndices.length,2);assert(r.trace[rpcIndices[0]].includes(prefix+'@fixture.invalid'));
        assert(r.trace.findIndex(x=>x.startsWith('restart '))<rpcIndices[0]);
        assert(r.trace.indexOf(firstWrite)>rpcIndices[1]);assert.equal(r.trace.at(-1),last);
        r=run(installer,{MODE:'unavailable'});assert.equal(r.status,1);
        assert(!r.trace.some(x=>x.startsWith('write-')),'no startup datastore writes until ready');
        assert(!r.trace.includes(last));assert(!r.trace.includes('mappings'));
        r=run(installer,{DRY_RUN:'true'});assert.equal(r.status,0,r.stderr);
        assert(!r.trace.some(x=>x.startsWith('rpc ')||x.startsWith('write-')));
    }
    console.log('PASS '+cases+' isolated datastore readiness/timeout/privacy/startup-order cases; no live RPC or datastore execution');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
