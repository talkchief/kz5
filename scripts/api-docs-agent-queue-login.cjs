'use strict';
// Source-reviewed runtime-only queue login. No live deployment claim.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
function applyAgentQueueLogin({spec,root}) {
    const sourceFile='applications/acdc/src/cb_acdc_agent_queue.erl',source=fs.readFileSync(path.join(root,sourceFile));
    for(const expected of ['cb_context:req_value(Context, <<"runtime_only">>) =/= \'undefined\'',
        'byte_size(QueueId) =< 128','lists:member(QueueId, Queues)',
        'crossbar_util:response_202(', 'Validator, 2000)', 'kz_api:msg_id(Reply) =:= MsgId',
        'length(Queues) =< 1024', 'length(Queues) =:= length(lists:usort(Queues))',
        'Confirmed = Observed andalso Member', '<<"cache-control">>, <<"no-store">>']) {
        assert(source.toString().includes(expected),'Runtime queue login source contract changed');
    }
    const route='/accounts/{ACCOUNT_ID}/agents/{USER_ID}/queue_status',ops=spec.paths[route],schemas=spec.components.schemas;
    if(!ops?.get||!ops?.post)throw Error('Existing agent queue_status operations are required');
    const ref=name=>({$ref:'#/components/schemas/'+name}),id={type:'string',pattern:'^[a-f0-9]{32}$'},queueId={type:'string',minLength:1,maxLength:128,'x-max-utf8-bytes':128,description:'Runtime-only queue IDs are limited to 128 UTF-8 bytes, not 128 multibyte characters.'};
    const object=(properties,required=Object.keys(properties))=>({type:'object',properties,required});
    const envelope=data=>object({status:{type:'string'},data,request_id:{type:'string'}},['data']);
    const noStore={'Cache-Control':{description:'Runtime-only handler responses are not cacheable. Legacy and pre-handler authentication/load errors retain their existing behavior.',schema:{type:'string',enum:['no-store']}}};
    const response=(description,data,cache=true)=>({description,...(cache?{headers:noStore}:{}),content:{'application/json':{schema:envelope(data)}}});
    const runtime={account_id:id,agent_id:id,queue_id:queueId,action:{type:'string',enum:['login']},runtime_only:{type:'boolean',enum:[true]},
        state:{type:'string'},confirmed:{type:'boolean'},runtime_member:{type:'boolean'},runtime_observed:{type:'boolean'},
        agent_status:{type:'string',description:'Observed global agent status, or unknown when no valid runtime reply arrived. This is separate from selected-queue membership.'}};
    schemas.AgentQueueRuntimePending={...object({...runtime,state:{type:'string',enum:['pending']},confirmed:{type:'boolean',enum:[false]},runtime_member:{type:'boolean',enum:[false]}}),
        description:'No selected-queue membership confirmation. runtime_observed=false means missing/old/malformed/unmatched/timed-out proof; true means a fresh listener reply did not include the queue. This is not a saved-roster result.'};
    schemas.AgentQueueRuntimeConfirmed={...object({...runtime,state:{type:'string',enum:['confirmed']},confirmed:{type:'boolean',enum:[true]},runtime_member:{type:'boolean',enum:[true]},runtime_observed:{type:'boolean',enum:[true]}}),
        description:'A fresh correlated account/agent listener reply included the selected queue. Membership only: not ready, ringing, SIP registration, audio or queue-manager acknowledgement.'};
    schemas.AgentQueueRuntimeSnapshot={oneOf:[ref('AgentQueueRuntimePending'),ref('AgentQueueRuntimeConfirmed')]};
    schemas.AgentQueueRuntimeAccepted={allOf:[ref('AgentQueueRuntimePending'),{type:'object',properties:{runtime_observed:{type:'boolean',enum:[false]},agent_status:{type:'string',enum:['unknown']}}}],description:'POST acknowledgement only; no runtime observation has been made.'};
    schemas.AgentQueueRuntimeLogin=object({runtime_only:{type:'boolean',enum:[true]},action:{type:'string',enum:['login']},queue_id:queueId});
    schemas.AgentQueueLegacyUpdate={...object({action:{type:'string',enum:['login','logout']},queue_id:queueId}),not:{required:['runtime_only']},
        description:'Legacy mode is selected only when runtime_only is absent. This route changes persisted user.queues enrollment and sends a queue command. It is not a runtime-only login or confirmation.'};
    const description='Implemented in source; not yet live-deployed. Same authenticated account-scoped route and existing authorization rules. Opt in with runtime_only=true plus action=login and a selected queue_id already in the enabled account-owned user’s persisted enrollment. The queue must exist, have queue type and belong to the same account. Validation and POST execution recheck enrollment; the AMQP consumer checks it again. No roster/user/queue document is saved in runtime-only mode. A running agent keeps other queues and its status; a new agent starts with only the selected runtime queue. No other agent is logged out. Probe runtime-only GET before POST: a legacy array response is not support or confirmation.';
    ops.get.summary='Read persisted enrollment or check selected runtime queue membership';
    ops.get.description=description+' Without runtime_only, GET returns the legacy persisted queue-ID array. With runtime_only=true, a fresh correlated listener sync is bounded to two seconds. Timeout, absent/old/stale/foreign/malformed proof remains pending with runtime_observed=false; global ready alone is never confirmation. A valid listener reply without the queue is pending with runtime_observed=true.';
    ops.get.parameters.push({in:'query',name:'runtime_only',schema:{type:'boolean',enum:[true]},description:'Optional opt-in. Omit for legacy enrollment; false or malformed explicit values are invalid.'},
        {in:'query',name:'action',schema:{type:'string',enum:['login']},description:'Required when runtime_only=true; no runtime-only logout operation.'},
        {in:'query',name:'queue_id',schema:queueId,description:'Required when runtime_only=true; must be an existing selected enrollment.'});
    ops.get.responses['200']=response('Legacy enrollment array, or runtime-only pending/confirmed membership proof',{oneOf:[{type:'array',items:queueId},ref('AgentQueueRuntimeSnapshot')]});
    ops.post.summary='Request selected runtime queue login or change legacy enrollment';ops.post.description=description+' POST 202 is always pending/confirmed=false; it acknowledges publication only. Poll runtime-only GET to confirm membership. Do not automatically repeat a POST after an ambiguous response. Legacy unflagged login/logout still changes persisted enrollment and returns its queue-ID array; use that only when an enrollment change is intended.';
    ops.post.requestBody={required:true,content:{'application/json':{
        schema:object({data:{oneOf:[ref('AgentQueueRuntimeLogin'),ref('AgentQueueLegacyUpdate')]}}),
        examples:{
            runtime_only_login:{summary:'Selected already-enrolled queue; no enrollment write',value:{data:{runtime_only:true,action:'login',queue_id:'00000000000000000000000000000000'}}},
            legacy_enrollment:{summary:'Legacy enrollment mutation — not runtime-only',value:{data:{action:'login',queue_id:'00000000000000000000000000000000'}}}
        }
    }}};
    ops.post.responses['200']=response('Legacy persisted-enrollment update only; not runtime confirmation',{type:'array',items:queueId},false);
    ops.post.responses['202']=response('Runtime-only login command published; confirmation pending',ref('AgentQueueRuntimeAccepted'));
    for(const op of [ops.get,ops.post]){
        op['x-implementation-status']='implemented-in-source; not-live-deployed';op['x-runtime-verification']='Offline contract/source validation only; a deployment-specific live runtime proof remains required.';
        op['x-source-files']=['applications/acdc/src/cb_agents.erl','applications/acdc/src/cb_acdc_agent_queue.erl'];
        op['x-runtime-source-sha256']=crypto.createHash('sha256').update(source).digest('hex');
        for(const [code,message]of Object.entries({400:'Invalid explicit runtime_only mode, missing/non-login action, or invalid queue ID.',403:'Agent is disabled/deleted, foreign-account or not enrolled in the selected queue; existing authorization also applies.',404:'Selected queue missing, deleted, wrong type or foreign-account; existing resource-load errors are retained.',503:'Queue datastore or command publication unavailable; do not blindly retry a mutation.'})){
            op.responses[code]={description:message,headers:noStore,content:{'application/json':{schema:ref('CrossbarError')}}};
        }
    }
    const ownFile='scripts/api-docs-agent-queue-login.cjs',files=['applications/acdc/src/cb_agents.erl',sourceFile,'applications/acdc/src/acdc_agent_handler.erl','applications/acdc/src/acdc_agent_listener.erl','applications/acdc/src/kapi_acdc_agent.erl',ownFile];
    return {inputs:files.map(file=>({file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file===ownFile?__filename:path.join(root,file))).digest('hex')}))};
}
module.exports={applyAgentQueueLogin};
