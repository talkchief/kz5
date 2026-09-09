'use strict';
// Execute the actual shell boundary with fake SUP/channel/document adapters.
// No service, SIP, broker, database or provider access.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const source=fs.readFileSync(path.join(__dirname,'test-acdc-callback-retry.sh'),'utf8');
const fn=source.match(/^retry_restart_queue_in_backoff\(\) \{\n[\s\S]*?^\}/m)?.[0];
assert(fn);
const A='8310dc3170a18de37f205d0da172df65',Q='67c5f3fb115bdd1dd574d6a604a7d29f',now=1788924000;
const base={id:'acdc-callback-test',account_id:A,queue_id:Q,original_call_id:'original',status:'retry_wait',attempts:1,
    caller_call_id:null,agent_call_id:null,reconciliation_required:false,next_attempt_at:now+62167219200+15};
const quote=s=>"'"+String(s).replaceAll("'","'\\''")+"'";
function run(options={}){
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kz5-queue-restart-boundary-'));
    try{
        if(options.already)fs.writeFileSync(path.join(dir,'callback-queue-restart-started.json'),'{}');
        const doc={...base,...options.doc};
        const script=`set -Eeuo pipefail
RUN_DIR=${quote(dir)}
RETRY_QUEUE_RESTART=true RETRY_ACCOUNT_ID=${quote(options.account||A)}
declare -A STATE=([ACCEPTANCE_ACCOUNT_ID]=${quote(A)} [ACCEPTANCE_QUEUE_ID]=${quote(options.queue||Q)})
CALLBACK_REGISTRATION_EVIDENCE=${quote(JSON.stringify({...base,...options.registered}))}
callback_document(){ printf '%s\n' ${quote(JSON.stringify(doc))}; }
retry_snapshot(){ printf '%s\n' ${quote(JSON.stringify({row_count:options.channels||0}))}; }
date(){ printf '%s\n' ${now}; }
log(){ :; }
sup(){
    printf '%s\n' "$*" >> "$RUN_DIR/actions"
    case "$*" in
        '-n kazoo_apps -t 5 acdc_queues_sup find_queue_supervisor ${A} ${Q}')
            if [[ -f $RUN_DIR/callback-queue-restart-command.txt ]]; then printf '%s\n' ${quote(options.samePid?'<19002.1778.0>':'<19002.2401.0>')};
            else printf '%s\n' '<10623.1778.0>'; fi ;;
        '-n kazoo_apps -t 10 acdc_maintenance queue_restart ${A} ${Q}') return ${options.uncertain?1:0} ;;
        *) exit 99 ;;
    esac
}
${fn}
if retry_restart_queue_in_backoff; then exit 0; else exit 1; fi
`;
        const result=spawnSync('bash',['-s'],{input:script,encoding:'utf8',timeout:5000});
        assert(!result.error,result.error?.message);
        const actions=fs.existsSync(path.join(dir,'actions'))?fs.readFileSync(path.join(dir,'actions'),'utf8'):'';
        const proof=fs.existsSync(path.join(dir,'callback-queue-restart.json'))?JSON.parse(fs.readFileSync(path.join(dir,'callback-queue-restart.json'))):null;
        return {code:result.status,actions,proof,marked:fs.existsSync(path.join(dir,'callback-queue-restart-started.json'))};
    }finally{fs.rmSync(dir,{recursive:true});}
}
const ok=run();assert.equal(ok.code,0);assert(ok.proof.replacement_verified);
assert.equal(ok.proof.callback.id,base.id);assert.equal(ok.proof.restart_requests,1);
assert.equal(ok.proof.supervisor_before_local_id,'1778.0');assert.equal(ok.proof.supervisor_after_local_id,'2401.0');
assert.equal(ok.actions.split('\n').filter(s=>s.includes('acdc_maintenance queue_restart')).length,1);
for(const options of [{account:'other'},{queue:'other'},{channels:1},{already:true},
    {doc:{status:'dialing'}},{doc:{attempts:2}},{doc:{caller_call_id:'live'}},{doc:{agent_call_id:'live'}},
    {doc:{reconciliation_required:true}},{doc:{next_attempt_at:now+62167219200+8}},
    {doc:{id:'other'}},{doc:{account_id:'other'}},{doc:{queue_id:'other'}},
    {doc:{account_id:'other'},registered:{account_id:'other'}}]){
    const result=run(options);assert.equal(result.code,1);assert.equal(result.actions,'');assert.equal(result.proof,null);
}
for(const options of [{uncertain:true},{samePid:true}]){
    const result=run(options);assert.equal(result.code,1);assert(result.marked);assert.equal(result.proof,null);
    assert.equal(result.actions.split('\n').filter(s=>s.includes('acdc_maintenance queue_restart')).length,1);
}
console.log('PASS 17 queue-restart boundary cases: exact isolated scope, no active legs, one attempt, fail closed');
