'use strict';
// SPDX-License-Identifier: MPL-2.0
// Actual extracted shell cleanup functions, with FS/API/process/file mutations
// replaced by private stubs. No credentials, network, SIP or real files touched.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'test-acdc-callback-fixture.sh'), 'utf8');
const A = 'a'.repeat(32), M = 'b'.repeat(32), Q = 'c'.repeat(32), R = 'd'.repeat(32), D = 'e'.repeat(32);
const C = '1'.repeat(32), G = '2'.repeat(32) + '-' + '3'.repeat(32) + '-12345678';
const T = 'acdc-callback-' + '4'.repeat(64), O = '1-777@127.0.0.20';
const doc = {id:T, account_id:A, queue_id:Q, number:'+12025550101', status:'completed',
    original_call_id:O, caller_call_id:C, agent_call_id:G, attempts:1, reconciliation_required:false};
const caller = {'Unique-ID':C, 'variable_ecallmgr_Account-ID':A, 'variable_ecallmgr_Callback-ID':T,
    variable_bridge_to:G, variable_sip_contact_host:'127.0.0.30', variable_sip_contact_port:'16060',
    'Channel-Call-State':'ACTIVE', 'Channel-State':'CS_EXECUTE'};
const agent = {'Unique-ID':G, 'variable_ecallmgr_Account-ID':A, 'variable_ecallmgr_Member-Call-ID':C,
    variable_bridge_to:C, variable_sip_contact_host:'127.0.0.20', variable_sip_contact_port:'15100',
    'Channel-Call-State':'ACTIVE', 'Channel-State':'CS_EXCHANGE_MEDIA'};
const functions = ['verify_fixture','fixture_cleanup_scope','fixture_channel_snapshot','fixture_terminal_document',
    'fixture_document_legs_down','fixture_channel_dump','teardown_completed_test_pair','fixture_assert_quiescent',
    'cancel_original_callback','delete_marked_number','cleanup_fixture'].map(name => {
    const match = new RegExp('^' + name + '\\(\\) \\{\\n[\\s\\S]*?^\\}', 'm').exec(source);
    assert(match, 'Missing helper function: ' + name); return match[0];
}).join('\n');
const dump = x => Object.entries(x).map(([k,v])=>k+': '+v).join('\n');
function run(options = {}) {
    const resource = {status:'success',data:{id:R,name:'Kazoo Callback Carrier '+A.slice(0,8),enabled:true,
        rules:['^\\+120255501[0-9]{2}$'],kazoo_acceptance_fixture:options.unmarked?'foreign':'kazoo-acdc-callback-local-v1',
        gateways:[{server:'127.0.0.30',port:16060}]}};
    const queue = {data:{id:Q,name:'Acceptance Queue 2000',callback:{enabled:true,entry_key:'6',allow_alternate_number:false,
        use_local_resources:true,outbound_authority:{id:D,type:'device'},outbound_caller_id:{number:'+12025550100'}}}};
    const record = {...doc,...options.document};
    const before = options.documents || [record], after = options.after || before;
    const ids = options.liveIds || [C,G];
    const script = `
exec 3>&1
trace() { printf '%s\\n' "$*" >&3; }
fixture_die() { trace 'denied'; exit 1; }
fixture_log() { trace 'verified'; }
sleep() { [[ $MODE == stuck ]] || PHASE=down; }
rm() { trace "file-delete $*"; }
reload_local_resources() { trace reload; }
callback_evidence() { [[ $PHASE == down ]] && printf '%s' "$AFTER_DOCS" || printf '%s' "$BEFORE_DOCS"; }
fixture_fs_command() {
    case "$1" in
      'show channels as json')
        [[ $MODE != transport ]] || return 7
        if [[ $PHASE == down ]]; then printf '%s' "$DOWN_SNAPSHOT"; else printf '%s' "$LIVE_SNAPSHOT"; fi ;;
      "uuid_dump $CALLER_ID") printf '%s' "$CALLER_DUMP" ;;
      "uuid_dump $AGENT_ID") printf '%s' "$AGENT_DUMP" ;;
      "uuid_kill $CALLER_ID NORMAL_CLEARING") trace "hangup $1"; printf '%s' "$KILL_RESPONSE"; return "$KILL_RESULT" ;;
      *) trace unexpected-fs; return 91 ;;
    esac
}
api_get_optional() {
    if [[ $1 == "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID" && $RESOURCE_OPTIONAL_CODE != 0 ]]; then return "$RESOURCE_OPTIONAL_CODE"; fi
    if [[ $1 == *'/phone_numbers/'* && $NUMBER_OPTIONAL_CODE != 0 ]]; then return "$NUMBER_OPTIONAL_CODE"; fi
    api_request GET "$1"
}
api_request() {
    if [[ $1 == DELETE && $2 == "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID/callbacks/$TICKET_ID" ]]; then
        trace callback-cancel; printf '%s' "$CANCEL_RESPONSE"; return
    fi
    if [[ $1 == POST || $1 == DELETE ]]; then trace "api-write $1 $2"; printf '{"status":"success","data":{}}'; return; fi
    [[ $1 == GET ]] || { trace unexpected-api; return 92; }
    case "$2" in
      "accounts/$ACCEPTANCE_ACCOUNT_ID") printf '%s' "$ACCOUNT_RESPONSE" ;;
      "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID") printf '%s' "$RESOURCE_RESPONSE" ;;
      "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID") printf '%s' "$QUEUE_RESPONSE" ;;
      "accounts/$ACCEPTANCE_ACCOUNT_ID/channels") printf '%s' "$CHANNEL_RESPONSE" ;;
      "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/%2B12025550101") printf '%s' "$NUMBER_RESPONSE" ;;
      "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/%2B12025550100") printf '%s' "$CID_RESPONSE" ;;
      *) trace unexpected-api; return 93 ;;
    esac
}
${functions}
if [[ $TASK == cleanup ]]; then cleanup_fixture; else cancel_original_callback; fi
`;
    const number = n => JSON.stringify({status:'success',data:{id:n,state:'in_service',kazoo_acceptance_fixture:'kazoo-acdc-callback-local-v1'}});
    const env = {PATH:'/usr/bin:/bin',LANG:'C',TASK:options.task||'cancel',MODE:options.mode||'normal',PHASE:options.down?'down':'live',
        KAZOO_CALLBACK_TEST_TRANSPORT:options.transport||'external',ACCEPTANCE_CALLER_USER_ID:'5'.repeat(32),ACCEPTANCE_CALLER_CALLFLOW_ID:'6'.repeat(32),
        ACCEPTANCE_ACCOUNT_ID:options.master?M:A,MASTER_ACCOUNT_ID:M,FIXTURE_ACCOUNT_ID:options.master?M:A,
        ACCEPTANCE_ACCOUNT_NAME:'Kazoo5 Acceptance abcdef123456',ACCEPTANCE_QUEUE_ID:Q,ACCEPTANCE_CALLER_DEVICE_ID:D,
        FIXTURE_ORIGINAL_QUEUE:JSON.stringify(options.savedQueue||{id:Q,name:'Acceptance Queue 2000'}),FIXTURE_RESOURCE_ID:R,FIXTURE_STATE_FILE:'/private/exact-fixture-state',
        FIXTURE_MARKER:'kazoo-acdc-callback-local-v1',CALLBACK_NUMBER:'+12025550101',OUTBOUND_CALLER_ID:'+12025550100',
        ENCODED_CALLBACK_NUMBER:'%2B12025550101',ENCODED_OUTBOUND_CALLER_ID:'%2B12025550100',CARRIER_IP:'127.0.0.30',CARRIER_PORT:'16060',
        CANCEL_ORIGINAL_CALL_ID:O,CALLER_ID:C,AGENT_ID:G,TICKET_ID:T,BEFORE_DOCS:JSON.stringify(before),AFTER_DOCS:JSON.stringify(after),
        RESOURCE_OPTIONAL_CODE:String(options.resourceOptionalCode||0),NUMBER_OPTIONAL_CODE:String(options.numberOptionalCode||0),
        LIVE_SNAPSHOT:JSON.stringify(options.snapshot||{row_count:ids.length,rows:ids.map(uuid=>({uuid}))}),
        DOWN_SNAPSHOT:JSON.stringify(options.downSnapshot||{row_count:0}),
        CALLER_DUMP:options.callerDump||dump({...caller,...options.caller}),AGENT_DUMP:options.agentDump||dump({...agent,...options.agent}),
        KILL_RESULT:String(options.killResult||0),KILL_RESPONSE:options.killResponse===undefined?'+OK':options.killResponse,
        ACCOUNT_RESPONSE:JSON.stringify({data:{id:A,name:options.wrongName?'Foreign Account':'Kazoo5 Acceptance abcdef123456'}}),
        RESOURCE_RESPONSE:JSON.stringify(resource),QUEUE_RESPONSE:JSON.stringify(queue),NUMBER_RESPONSE:number('+12025550101'),
        CID_RESPONSE:number('+12025550100'),CHANNEL_RESPONSE:JSON.stringify(options.channels||{data:[]}),
        CANCEL_RESPONSE:JSON.stringify({data:{status:options.cancelStatus||'cancelling'}})};
    const result=cp.spawnSync('bash',['--noprofile','--norc','-s'],{input:'set -Eeuo pipefail\n'+script,env,encoding:'utf8',timeout:15000});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);
    const actions=result.stdout.trim().split('\n').filter(Boolean);
    assert(!actions.some(x=>x.startsWith('unexpected')), result.stdout);
    return {status:result.status,actions,stderr:result.stderr};
}
let passed=0;
function test(name,body){body();passed++;console.log('PASS: '+name);}
function denied(item,mayKill=false){assert.notEqual(item.status,0,item.stderr);assert(!item.actions.some(x=>/^api-write|file-delete|callback-cancel/.test(x)),item.actions.join('\n'));
    if(!mayKill)assert(!item.actions.some(x=>x.startsWith('hangup')),item.actions.join('\n'));}
test('Exact completed pair is cleared once through caller and both-down proof is mandatory',()=>{
    const r=run();assert.equal(r.status,0,r.stderr);assert.deepEqual(r.actions.filter(x=>x.startsWith('hangup')),['hangup uuid_kill '+C+' NORMAL_CLEARING']);
    assert(!r.actions.includes('callback-cancel'));assert(!r.actions.some(x=>x.startsWith('api-write')));
});
test('Already absent completed or cancelled legs are idempotent and never hung up',()=>{
    for(const status of ['completed','cancelled','failed','expired']){const r=run({down:true,document:{status}});assert.equal(r.status,0,r.stderr);assert(!r.actions.some(x=>x.startsWith('hangup')));}
});
test('Exact two-attempt retry completion keeps every identity and live-leg safeguard',()=>{
    const retry = {...doc, attempts:2, max_attempts:2, retry_delay:15};
    const live = run({document:retry}); assert.equal(live.status,0,live.stderr);
    assert.deepEqual(live.actions.filter(x=>x.startsWith('hangup')),['hangup uuid_kill '+C+' NORMAL_CLEARING']);
    const down = run({down:true,document:retry}); assert.equal(down.status,0,down.stderr);
    assert(!down.actions.some(x=>x.startsWith('hangup')));
    for(const change of [{max_attempts:3},{retry_delay:5},{attempts:3},{reconciliation_required:true},
        {account_id:M},{queue_id:M},{agent_call_id:null}]) denied(run({document:{...retry,...change}}));
    const old = {...doc,id:'acdc-callback-'+'5'.repeat(64),original_call_id:'1-778@127.0.0.20',
        status:'cancelling',reconciliation_required:true};
    denied(run({task:'cleanup',down:true,documents:[retry,old]}));
});
test('Internal1001 cleanup requires the exact pinned fixture user/flow and returned endpoint',()=>{
    const internal={...doc,number:'1001',internal_target:{number:'1001',type:'user',id:'5'.repeat(32),flow_id:'6'.repeat(32)}};
    const options={transport:'internal',document:internal,caller:{variable_sip_contact_host:'127.0.0.20'}};
    assert.equal(run(options).status,0);
    assert.equal(run({...options,down:true}).status,0);
    denied(run({...options,transport:'external'}));
    denied(run({...options,caller:{variable_sip_contact_host:'127.0.0.30'}}));
    for(const patch of [{id:M},{flow_id:M},{type:'device'},{number:'1000'}]) {
        denied(run({...options,document:{...internal,internal_target:{...internal.internal_target,...patch}}}));
    }
});
test('MASTER, changed identity, duplicate original callback and unmarked fixture are refused',()=>{
    for(const o of [{master:true},{wrongName:true},{savedQueue:{}},{savedQueue:{id:R,name:'Acceptance Queue 2000'}},
        {documents:[doc,doc]},{unmarked:true},{document:{account_id:M}},
        {document:{queue_id:M}},{document:{number:'+12025550999'}},{document:{attempts:2}},{document:{reconciliation_required:true}}])denied(run(o));
});
test('Wrong/reused UUID, tenant, callback, member, bridge, endpoint or channel state never authorizes a kill',()=>{
    const changes=[{caller:{'Unique-ID':'9'.repeat(32)}},{agent:{'Unique-ID':C}},
        {caller:{'variable_ecallmgr_Account-ID':M}},{agent:{'variable_ecallmgr_Account-ID':M}},
        {caller:{'variable_ecallmgr_Callback-ID':'acdc-callback-'+'9'.repeat(64)}},
        {agent:{'variable_ecallmgr_Member-Call-ID':'9'.repeat(32)}},{caller:{variable_bridge_to:C}},
        {agent:{variable_bridge_to:G}},{caller:{variable_sip_contact_host:'127.0.0.40'}},
        {agent:{variable_sip_contact_host:'127.0.0.40'}},{caller:{variable_sip_contact_port:'5060'}},
        {agent:{variable_sip_contact_port:'17100'}},{caller:{'Channel-Call-State':'HANGUP'}},
        {agent:{'Channel-State':'CS_DESTROY'}},{liveIds:[O,C,G]}];
    for(const o of changes)denied(run(o));
});
test('Incomplete/transport/error/duplicate dumps and malformed snapshots fail closed',()=>{
    for(const o of [{mode:'transport'},{snapshot:{}},{snapshot:{row_count:1,rows:[]}},{snapshot:{row_count:2,rows:[{uuid:C},{uuid:C}]}},
        {callerDump:'-ERR No such channel!'},{agentDump:'-ERR No such channel!'},
        {callerDump:dump(caller)+'\nmalformed'},{callerDump:dump(caller)+'\nUnique-ID: '+C}])denied(run(o));
});
test('Failed kill, acknowledgement without down proof and later inventory failure retain resources',()=>{
    for(const o of [{killResult:7},{killResponse:'-ERR failure'},{killResponse:'+OK untrusted'},
        {mode:'stuck'},{downSnapshot:{}},{downSnapshot:{row_count:1,rows:[{uuid:G}]}}]){
        const r=run(o);denied(r,true);assert.equal(r.actions.filter(x=>x.startsWith('hangup')).length,1);
    }
});
test('Manual fixture deletion independently refuses active, nonterminal, ambiguous or API-visible calls',()=>{
    for(const o of [{},{down:true,document:{status:'queued'}},{down:true,documents:[doc,doc]},
        {down:true,downSnapshot:{row_count:1,rows:[{uuid:'untracked-live-call'}]}},
        {down:true,document:{agent_call_id:null}},{down:true,channels:{data:[{active:true}]}},
        {down:true,channels:{data:[],next_start_key:'more'}},{down:true,channels:{data:{}}}])denied(run({task:'cleanup',...o}));
});
test('Only a terminal idle fixture can restore/delete its exact marked resources',()=>{
    const r=run({task:'cleanup',down:true});assert.equal(r.status,0,r.stderr);assert(!r.actions.some(x=>x.startsWith('hangup')));
    assert.deepEqual(r.actions.filter(x=>x.startsWith('api-write')),['api-write POST accounts/'+A+'/queues/'+Q,
        'api-write DELETE accounts/'+A+'/resources/'+R,'api-write DELETE accounts/'+A+'/phone_numbers/%2B12025550101?hard=true',
        'api-write DELETE accounts/'+A+'/phone_numbers/%2B12025550100?hard=true']);
    assert(r.actions.includes('file-delete -f -- /private/exact-fixture-state'));
});
test('Noncompleted cancellation still uses production API and cannot hide unresolved durable state',()=>{
    const r=run({document:{status:'queued'},cancelStatus:'cancelling'});assert.notEqual(r.status,0);
    assert.deepEqual(r.actions.filter(x=>x==='callback-cancel'),['callback-cancel']);assert(!r.actions.some(x=>/^hangup|api-write|file-delete/.test(x)));
});
test('A failed number lookup retains state and retry safely skips only an already404 resource',()=>{
    const failed=run({task:'cleanup',down:true,numberOptionalCode:1});assert.notEqual(failed.status,0);
    assert(failed.actions.includes('api-write DELETE accounts/'+A+'/resources/'+R));
    assert(!failed.actions.some(x=>x.startsWith('file-delete')||x.includes('/phone_numbers/')&&x.startsWith('api-write')));
    const retried=run({task:'cleanup',down:true,resourceOptionalCode:4});assert.equal(retried.status,0,retried.stderr);
    assert(!retried.actions.includes('api-write DELETE accounts/'+A+'/resources/'+R));
    assert.equal(retried.actions.filter(x=>x.startsWith('api-write DELETE')&&x.includes('/phone_numbers/')).length,2);
    assert(retried.actions.includes('file-delete -f -- /private/exact-fixture-state'));
    const unavailable=run({task:'cleanup',down:true,resourceOptionalCode:1});assert.notEqual(unavailable.status,0);
    assert(!unavailable.actions.some(x=>/^api-write DELETE|file-delete/.test(x)));
});
test('Actual optional GET reserves4 for HTTP404; transport/500 never permit create or skip deletion',()=>{
    const defs=['api_get_optional','create_owned_number','delete_marked_number'].map(name=>
        source.match(new RegExp('^'+name+'\\(\\) \\{\\n[\\s\\S]*?^\\}','m'))[0]).join('\n');
    for(const action of ['create_owned_number','delete_marked_number'])for(const fault of [
        {http:'404',code:0,ok:true},{http:'500',code:0,ok:false},{http:'000',code:7,ok:false},
        {http:'200',code:0,ok:true}]){
        const result=cp.spawnSync('bash',['--noprofile','--norc','-s'],{encoding:'utf8',timeout:10000,
            env:{PATH:'/usr/bin:/bin',LANG:'C',HTTP_STATUS:fault.http,CURL_RESULT:String(fault.code),MASTER_TOKEN:'unused-private-stub',
                API_BASE:'http://127.0.0.1:8000/v2',ACCEPTANCE_ACCOUNT_ID:A,FIXTURE_MARKER:'kazoo-acdc-callback-local-v1'},
            input:`set -Eeuo pipefail
fixture_die() { exit 1; }
mktemp() { printf /private/mock-response; }
rm() { :; }
curl() { printf '%s' "$HTTP_STATUS"; return "$CURL_RESULT"; }
cat() { printf '%s' '${JSON.stringify({status:'success',data:{id:'+12025550101',state:'in_service',kazoo_acceptance_fixture:'kazoo-acdc-callback-local-v1'}})}'; }
api_request() { printf '%s\\n' "$1" >&2; cat; }
${defs}
${action} %2B12025550101 +12025550101
`});
        assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(result.status===0,fault.ok);
        const writes=result.stderr.trim();
        const expected=fault.ok?(action==='create_owned_number'&&fault.http==='404'?'PUT':action==='delete_marked_number'&&fault.http==='200'?'DELETE':''):'';
        assert.equal(writes,expected);
    }
});
console.log('PASS: '+passed+' private exact fixture cleanup groups; no API/SIP/filesystem mutations');
