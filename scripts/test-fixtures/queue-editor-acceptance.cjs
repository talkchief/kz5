'use strict';
// Explicitly armed, isolated-tenant acceptance only. Importing this module does
// not authenticate, read secrets, execute SUP, or make any network request.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const fixtureAccount=require('./callback-fixture-account.cjs');
const {localMediaHost}=require('./callback-gemini-reference.cjs');
const LANGUAGES=Object.freeze(['en-us','he-il','ar-sa','fr-fr','es-es']);
const {ACCOUNT,DATABASE,ENCODED_DATABASE,fingerprint,contentFingerprint,conditionalSaveArguments,
    assertExpectedConfiguration}=require('./callback-offer-queue.cjs');
function selectedExtension(value) {
    const extension=value===undefined?'2097':value;
    assert(typeof extension==='string'&&/^209[0-9]$/.test(extension),'Choose only an explicit2090–2099 isolated acceptance extension');
    return extension;
}
// Each run still proves the chosen extension is virgin and not a public number.
// Reusing an old receipt for cleanup requires the same configured extension.
const EXTENSION=selectedExtension(process.env.KAZOO_TEST_QUEUE_EDITOR_EXTENSION), TYPES=['queue','callflow','user','acdc_callback','acdc_queue_editor_operation','acdc_queue_extension'];
const id=v=>typeof v==='string'&&/^[a-f0-9]{32}$/.test(v), hex64=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const revision=v=>typeof v==='string'&&/^[1-9][0-9]*-[a-f0-9]{32}$/.test(v);
const hash=value=>fingerprint(value), clone=value=>JSON.parse(JSON.stringify(value));
const live=d=>!d._deleted&&!d.pvt_deleted;
const publicFields=d=>Object.fromEntries(Object.entries(d).filter(([key])=>!key.startsWith('_')&&!key.startsWith('pvt_')&&key!=='id'));
function merge(target,patch) {
    const result=clone(target);
    for(const [key,value] of Object.entries(patch)) {
        if(value===null)delete result[key];
        else result[key]=value&&typeof value==='object'&&!Array.isArray(value)?merge(result[key]||{},value):value;
    }
    return result;
}
function checkRaw(document,type) {
    assert(document&&revision(document._rev)&&document.pvt_type===type&&document.pvt_account_id===ACCOUNT
        &&[DATABASE,ENCODED_DATABASE].includes(document.pvt_account_db)&&!document._attachments,'Raw document identity mismatch');
}
function checkReceipt(receipt) {
    assert(receipt&&receipt.schema_version===1&&receipt.account===ACCOUNT&&receipt.extension===EXTENSION
        &&/^acdc-editor-[a-f0-9]{24}$/.test(receipt.marker)&&receipt.baseline&&receipt.owned
        &&Array.isArray(receipt.intents)&&Array.isArray(receipt.checks),'Invalid acceptance receipt');
}
function checkQueue(document,receipt) {
    checkRaw(document,'queue');
    assert(document._id===receipt.queue_id&&document.name===receipt.marker
        &&document.kazoo_acceptance_fixture===receipt.marker&&(document.agents||[]).length===0,'Queue fixture ownership mismatch');
}
function checkRoute(document,receipt) {
    checkRaw(document,'callflow');
    assert(document._id===receipt.route_id&&document.name===receipt.marker+' (ACDC)','Route fixture identity mismatch');
    assert(hash(document.numbers)===hash([EXTENSION])&&hash(document.patterns||[])===hash([])
        &&hash(document.flags)===hash(['talkchief-acdc-managed','talkchief-acdc-queue:'+receipt.queue_id])
        &&hash(document.flow)===hash({module:'acdc_member',data:{id:receipt.queue_id},children:{}}),'Route fixture shape mismatch');
}
function checkOperation(document,receipt,intent) {
    checkRaw(document,'acdc_queue_editor_operation');
    assert(hex64(document.owner)&&document._id==='acdc_queue_editor_'+hash([ACCOUNT,document.owner,intent.body.request_id])
        &&document.body_hash===hash([intent.queue_id,intent.method,intent.body])&&document.queue_id===receipt.queue_id
        &&document.state==='complete'&&document.phase==='complete'&&document.result?.queue_id===receipt.queue_id
        &&document.result.operation_id===document._id&&document.result.state==='complete'
        &&document.result.atomic===false&&(document.remaining||[]).length===0&&(document.in_flight||[]).length===0,'Operation outcome is not a completed owned request');
}
function checkClaim(document,receipt,operationId,state) {
    checkRaw(document,'acdc_queue_extension');
    assert(document._id==='acdc_queue_extension_'+hash([ACCOUNT,EXTENSION])&&document.extension===EXTENSION
        &&document.queue_id===receipt.queue_id&&document.route_id===receipt.route_id
        &&document.operation_id===operationId&&document.state===state&&revision(document.route_revision),'Extension claim ownership mismatch');
}
function inventoryMap(documents) {
    assert(Array.isArray(documents)&&documents.length<=1000,'Unbounded acceptance inventory');
    const result={};
    for(const d of documents) {
        assert(d&&typeof d._id==='string'&&!result[d._id]&&TYPES.includes(d.pvt_type),'Invalid inventory identity');
        checkRaw(d,d.pvt_type);result[d._id]=d;
    }
    return result;
}
function assertBaseline(documents,receipt) {
    const map=inventoryMap(documents),other={};
    for(const [key,d] of Object.entries(map))if(!Object.hasOwn(receipt.owned,key))other[key]=hash(d);
    assert(hash(other)===hash(receipt.baseline),'Unrelated document inventory changed; stop without overwriting');
    for(const [key,saved] of Object.entries(receipt.owned))assert(map[key]&&hash(map[key])===saved.sha256
        &&map[key]._rev===saved.revision,'Owned document changed outside a recorded request; retain');
    return map;
}
function assertNoReferences(documents,receipt) {
    for(const d of documents) {
        if(!live(d))continue;
        if(d._id===receipt.queue_id||d._id===receipt.route_id
            ||Object.hasOwn(receipt.owned,d._id)&&['acdc_queue_editor_operation','acdc_queue_extension'].includes(d.pvt_type))continue;
        assert(!JSON.stringify(d).includes(receipt.queue_id),'Unexpected queue reference or callback; retain fixture');
    }
}
async function guard(io,receipt) {
    checkReceipt(receipt);await io.noCalls();
    const documents=await io.inventory(),map=assertBaseline(documents,receipt);
    if(receipt.queue_id) {
        checkQueue(map[receipt.queue_id],receipt);assertNoReferences(documents,receipt);
        if(live(map[receipt.queue_id]))assert((await io.callbacks(receipt.queue_id)).length===0,'Callback records exist; retain fixture');
    }
    if(receipt.route_id)checkRoute(map[receipt.route_id],receipt);
    await io.noCalls();return map;
}
function remember(receipt,document) {
    receipt.owned[document._id]={revision:document._rev,sha256:hash(document),type:document.pvt_type};
}
function body(queue,revisions,route,requestId) {
    assert(id(requestId));return {queue,roster:null,route,revisions:clone(revisions),request_id:requestId};
}
function editorData(response,queueId) {
    assert(response.status===200&&response.body.status==='success','Editor GET failed');
    const data=response.body.data;
    assert(data&&data.revisions&&data.catalogs?.users?.complete===true&&data.catalogs?.callflows?.complete===true
        &&Array.isArray(data.roster)&&data.roster.length===0,'Required complete editor catalogs or empty fixture roster missing');
    assert(queueId?data.queue.id===queueId&&revision(data.revisions.queue):data.revisions.queue===null,'Editor snapshot identity mismatch');
    return data;
}
async function change(io,receipt,queueId,payload,label) {
    const before=await guard(io,receipt),method=queueId?'PATCH':'PUT';
    const intent={label,method,queue_id:queueId||null,body:clone(payload),state:'in_flight'};
    receipt.intents.push(intent);io.persist(receipt);
    const response=await io.editor(method,queueId,payload);
    assert(response.status>=200&&response.status<300&&response.body.status==='success','Aggregate write failed; inspect private intent before any cleanup');
    const result=response.body.data;
    assert(id(result.queue_id)&&/^acdc_queue_editor_[a-f0-9]{64}$/.test(result.operation_id)
        &&result.state==='complete'&&result.atomic===false&&result.roster_preserved===true,'Unexpected aggregate outcome');
    assert(!queueId||result.queue_id===queueId,'Queue identity changed');
    if(!queueId) {
        assert(!receipt.queue_id,'Only one queue creation is permitted');
        assert(result.queue_id===hash([result.operation_id,'queue']).slice(0,32),'Create queue ID is not operation-bound');
        receipt.queue_id=result.queue_id;
        receipt.route_id=hash(['acdc_managed_route',receipt.queue_id,result.operation_id]).slice(0,32);
    }
    // Persist server identities before validation. A failed/lost outcome never
    // causes an automatic destructive rollback or revision refresh.
    intent.result=clone(result);io.persist(receipt);
    const after=inventoryMap(await io.inventory()),queue=after[receipt.queue_id],route=after[receipt.route_id];
    checkQueue(queue,receipt);checkRoute(route,receipt);
    if(!queueId) {
        const expected=clone(payload.queue);if(queue.agents!==undefined)expected.agents=[];
        assertExpectedConfiguration(queue,expected,io.queueSchema);
    } else assert(hash(publicFields(queue))===hash(merge(publicFields(before[receipt.queue_id]),payload.queue)),'Queue PATCH changed unrequested public fields');
    const removing=payload.route?.extension==='';
    assert(live(queue)&&Boolean(route.pvt_deleted)===removing,'Unexpected queue/route lifecycle');
    const operation=after[result.operation_id],claim=after['acdc_queue_extension_'+hash([ACCOUNT,EXTENSION])];
    checkOperation(operation,receipt,intent);checkClaim(claim,receipt,result.operation_id,removing?'released':'assigned');
    assert(claim.route_revision===route._rev,'Extension claim does not match exact route revision');
    for(const d of [queue,route,operation,claim])remember(receipt,d);
    assertBaseline(Object.values(after),receipt);
    intent.state='complete';receipt.checks.push(label);io.persist(receipt);return response;
}
async function unchangedRequest(io,receipt,queueId,payload,expectedStatus,label,expectedBody) {
    await guard(io,receipt);
    const response=await io.editor(queueId?'PATCH':'PUT',queueId,payload);
    assert(response.status===expectedStatus,'Unexpected replay/conflict status');
    if(expectedBody)assert(hash(response.body.data)===hash(expectedBody),'Replay result changed');
    await guard(io,receipt);receipt.checks.push(label);io.persist(receipt);
}
async function cleanup(io,receipt) {
    if(receipt.cleaned_at)return;
    assert(receipt.queue_id&&receipt.route_id&&receipt.intents.every(x=>x.state==='complete'),'Ambiguous request: retain for explicit recovery');
    let map=await guard(io,receipt);
    if(live(map[receipt.route_id])) {
        const data=editorData(await io.editor('GET',receipt.queue_id),receipt.queue_id);
        await change(io,receipt,receipt.queue_id,body({},data.revisions,{extension:''},io.randomId()),'aggregate_route_cleanup');
        map=await guard(io,receipt);
    }
    const queue=map[receipt.queue_id];
    assert(map[receipt.route_id].pvt_deleted===true,'Route must be removed through aggregate hooks first');
    assertNoReferences(Object.values(map),receipt);
    if(!queue.pvt_deleted) {
        const deletion={...queue,pvt_deleted:true,pvt_modified:Math.floor(Date.now()/1000)+62167219200};
        receipt.queue_delete_intent={revision:queue._rev,content_sha256:contentFingerprint(deletion)};io.persist(receipt);
        await io.conditionalQueueDelete(deletion);
        const after=inventoryMap(await io.inventory()),deleted=after[receipt.queue_id];checkQueue(deleted,receipt);
        assert(deleted.pvt_deleted===true&&contentFingerprint(deleted)===receipt.queue_delete_intent.content_sha256
            &&Number(deleted._rev.split('-')[0])===Number(queue._rev.split('-')[0])+1,'Conditional deletion outcome unknown; retain receipt');
        remember(receipt,deleted);io.persist(receipt);assertBaseline(Object.values(after),receipt);
    }
    await guard(io,receipt);
    assert(await io.apiMissing('queues',receipt.queue_id)&&await io.apiMissing('callflows',receipt.route_id),'Soft-deleted fixture remains API-visible');
    receipt.cleaned_at=new Date().toISOString();receipt.checks.push('exact_cas_queue_cleanup');io.persist(receipt);
}
async function runAcceptance(io,receipt,allLanguages=false) {
    assert(typeof allLanguages==='boolean','Explicit language acceptance mode required');
    assert(!receipt.queue_id&&receipt.intents.length===0,'Run cannot be restarted against a partial fixture');
    const anonymous=await io.anonymousEditor();assert([401,403].includes(anonymous.status),'Unauthenticated editor must be rejected');
    receipt.checks.push('anonymous_rejected');io.persist(receipt);
    await guard(io,receipt);const empty=editorData(await io.editor('GET'),null);
    const initial=body({name:receipt.marker,kazoo_acceptance_fixture:receipt.marker,enter_when_empty:false,
        connection_timeout:30,strategy:'round_robin',callback:{enabled:false},
        announcements:{language:'en-us',position_announcements_enabled:false,wait_time_announcements_enabled:false}},
    empty.revisions,{extension:EXTENSION},io.randomId());
    const created=await change(io,receipt,null,initial,'create_queue_and_route_one_write');
    await unchangedRequest(io,receipt,null,initial,created.status,'identical_create_replay',created.body.data);
    await unchangedRequest(io,receipt,null,{...initial,queue:{...initial.queue,connection_timeout:32}},409,'changed_create_request_id_rejected');
    const fresh=editorData(await io.editor('GET',receipt.queue_id),receipt.queue_id);
    assert(fresh.callflows.routes.some(r=>r.id===receipt.route_id),'Editor omitted newly managed route');
    const editedBody=body({connection_timeout:31,callback:{announcement:{enabled:true,initial_delay:5,interval:30}}},
        fresh.revisions,{extension:EXTENSION},io.randomId());
    const edited=await change(io,receipt,receipt.queue_id,editedBody,'edit_queue_and_route_one_write');
    await unchangedRequest(io,receipt,receipt.queue_id,editedBody,edited.status,'identical_edit_replay',edited.body.data);
    await unchangedRequest(io,receipt,receipt.queue_id,body({connection_timeout:32},fresh.revisions,null,io.randomId()),409,'stale_queue_revision_rejected');
    const current=editorData(await io.editor('GET',receipt.queue_id),receipt.queue_id);
    assert(current.queue.announcements?.language==='en-us'&&current.queue.connection_timeout===31&&current.queue.callback?.announcement?.initial_delay===5
        &&current.queue.callback?.announcement?.interval===30,'Fresh editor did not return edited settings');
    receipt.checks.push('fresh_get_confirms_edit','explicit_english_language_selection_preserved');io.persist(receipt);
    if(allLanguages)for(const language of LANGUAGES) {
        const snapshot=editorData(await io.editor('GET',receipt.queue_id),receipt.queue_id);
        // Distinct generic/callback settings, no media overrides, no roster
        // changes. Every request is pinned to a newly read revision snapshot.
        const selection=body({announcements:{language,initial_delay:45,interval:17},
            callback:{announcement:{enabled:true,initial_delay:30,interval:30}}},
        snapshot.revisions,{extension:EXTENSION},io.randomId());
        const result=await change(io,receipt,receipt.queue_id,selection,'save_language_'+language);
        await unchangedRequest(io,receipt,receipt.queue_id,selection,result.status,'replay_language_'+language,result.body.data);
        const reloaded=editorData(await io.editor('GET',receipt.queue_id),receipt.queue_id).queue;
        assert(reloaded.announcements?.language===language&&reloaded.announcements.initial_delay===45
            &&reloaded.announcements.interval===17&&reloaded.callback?.announcement?.initial_delay===30
            &&reloaded.callback.announcement.interval===30,'Language or separate intervals did not survive reload');
        receipt.checks.push('reload_language_'+language);io.persist(receipt);
    }
    await cleanup(io,receipt);return receipt;
}
function protectedRead(file) {
    const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW|fs.constants.O_NONBLOCK);
    try {
        const s=fs.fstatSync(fd);assert(s.isFile()&&s.uid===0&&s.nlink===1&&(s.mode&511)===384&&s.size<4*1024*1024,'Protected root-owned0600 file required');
        return fs.readFileSync(fd,'utf8');
    } finally {fs.closeSync(fd);}
}
function readEnv(file,encoded=false) {
    return Object.fromEntries(protectedRead(file).split('\n').filter(l=>l&&!l.startsWith('#')).map(line=>{
        const n=line.indexOf('=');assert(n>0);const key=line.slice(0,n);let value=line.slice(n+1);assert(/^[A-Z][A-Z0-9_]*$/.test(key));
        if(encoded){const b=Buffer.from(value,'base64');assert(b.toString('base64')===value);value=b.toString();}
        else if(value.startsWith("'")){assert(value.endsWith("'")&&!value.slice(1,-1).includes("'"));value=value.slice(1,-1);}
        else if(value.startsWith('"'))value=JSON.parse(value);
        assert(!/[\r\n]/.test(value));return [key,value];
    }));
}
async function runtime(action,arm,run) {
    assert(['run','run-languages','cleanup'].includes(action)&&arm==='--allow-fixture-writes'&&path.isAbsolute(run),'Explicit fixture-write flag and private run directory required');
    const s=fs.lstatSync(run);assert(s.isDirectory()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===448
        &&fs.realpathSync(run)===run&&run.startsWith('/var/log/kazoo-acceptance/'),'Invalid private acceptance directory');
    const receiptFile=path.join(run,'queue-editor-acceptance.json'),lockFile=path.join(run,'queue-editor-acceptance.lock');
    const lock=fs.openSync(lockFile,'wx',384);
    try {
        const state=fixtureAccount.readState('/etc/kazoo/acceptance-secrets.env'),secrets=readEnv('/etc/kazoo/installer-secrets.env'),deployment=readEnv('/etc/kazoo/deployment.env',true);
        assert(state.ACCEPTANCE_ACCOUNT_ID===ACCOUNT&&/^acceptance-[a-f0-9]{12}\.invalid$/.test(state.ACCEPTANCE_REALM)
            &&/^Kazoo5 Acceptance [a-f0-9]{12}$/.test(state.ACCEPTANCE_ACCOUNT_NAME),'Not the isolated acceptance tenant');
        const couchHost=localMediaHost(deployment.KAZOO_COUCHDB_HOST);
        const port=Number(deployment.KAZOO_COUCHDB_PORT||5984);assert(Number.isInteger(port)&&port>0&&port<65536);
        assert(deployment.KAZOO_COUCHDB_USER&&deployment.KAZOO_COUCHDB_PASSWORD&&!deployment.KAZOO_COUCHDB_USER.includes(':'));
        const authorization='Basic '+Buffer.from(deployment.KAZOO_COUCHDB_USER+':'+deployment.KAZOO_COUCHDB_PASSWORD).toString('base64');
        let token;
        async function request(method,relative,data,anonymous=false) {
            assert(relative==='user_auth'||relative===''||relative==='channels'
                ||relative==='queues/editor'||/^queues\/[a-f0-9]{32}(?:\/(?:editor|callbacks))?$/.test(relative)
                ||/^callflows\/[a-f0-9]{32}$/.test(relative),'Out-of-scope API resource');
            assert(method==='GET'||relative==='user_auth'&&method==='PUT'
                ||relative==='queues/editor'&&method==='PUT'||/^queues\/[a-f0-9]{32}\/editor$/.test(relative)&&method==='PATCH','Out-of-scope API mutation');
            if(method!=='GET'&&relative!=='user_auth')assert(data.roster===null,'Acceptance never changes agents');
            const url='http://127.0.0.1:8000/v2/'+(relative==='user_auth'?relative:'accounts/'+ACCOUNT+(relative?'/'+relative:''));
            const r=await fetch(url,{method,headers:{'Content-Type':'application/json',...(!anonymous&&token?{'X-Auth-Token':token}:{})},
                ...(data===undefined?{}:{body:JSON.stringify({data})}),redirect:'error',signal:AbortSignal.timeout(30000)});
            const bytes=Buffer.from(await r.arrayBuffer());assert(bytes.length<4*1024*1024,'Oversized API response');
            return {status:r.status,body:JSON.parse(bytes.toString())};
        }
        const auth=await request('PUT','user_auth',{credentials:crypto.createHash('md5').update((secrets.KAZOO_MASTER_ADMIN_USER||'admin')+':'+secrets.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex'),method:'md5',realm:secrets.KAZOO_MASTER_ACCOUNT_REALM});
        token=auth.body.auth_token;assert(auth.status===201||auth.status===200);assert(token&&auth.body.data.account_id!==ACCOUNT);
        const tenant=await request('GET','');assert(tenant.status===200&&tenant.body.data.id===ACCOUNT
            &&tenant.body.data.name===state.ACCEPTANCE_ACCOUNT_NAME&&tenant.body.data.realm===state.ACCEPTANCE_REALM);
        const ownership=spawnSync('/bin/bash',[path.join(__dirname,'../test-kazoo-call-provision.sh'),'--verify-only'],
            {encoding:'utf8',timeout:120000,maxBuffer:65536});
        assert(!ownership.error&&ownership.status===0,'Protected live acceptance resources must verify before editor writes');
        const io={randomId:()=>crypto.randomBytes(16).toString('hex'),
            persist:r=>fs.writeFileSync(receiptFile,JSON.stringify(r,null,2)+'\n',{mode:384}),
            queueSchema:JSON.parse(fs.readFileSync(path.join(__dirname,'../../applications/crossbar/priv/couchdb/schemas/queues.json'),'utf8')),
            editor:(method,queueId,data)=>request(method,'queues/'+(queueId?queueId+'/':'')+'editor',data),
            anonymousEditor:()=>request('GET','queues/editor',undefined,true),
            inventory:async()=>{
                const r=await fetch('http://'+couchHost+':'+port+'/'+ENCODED_DATABASE+'/_find',{method:'POST',headers:{authorization,'Content-Type':'application/json'},
                    body:JSON.stringify({selector:{pvt_type:{$in:TYPES}},limit:1001}),redirect:'error',signal:AbortSignal.timeout(20000)});
                assert(r.ok,'Scoped inventory read failed');const bytes=Buffer.from(await r.arrayBuffer());assert(bytes.length<4*1024*1024);
                const docs=JSON.parse(bytes.toString()).docs;inventoryMap(docs);return docs;
            },
            callbacks:async queueId=>{const r=await request('GET','queues/'+queueId+'/callbacks');assert(r.status===200&&Array.isArray(r.body.data)&&!r.body.next_start_key);return r.body.data;},
            noCalls:async()=>{
                const local=spawnSync('/usr/local/freeswitch/bin/fs_cli',['-x','show channels as json'],{encoding:'utf8',timeout:5000,maxBuffer:1048576});assert(local.status===0);
                const channels=JSON.parse(local.stdout);assert(channels.row_count===0&&(!channels.rows||channels.rows.length===0),'Live calls prohibit fixture writes');
                const remote=await request('GET','channels');assert(remote.status===200&&remote.body.data&&Object.keys(remote.body.data).length===0,'Cluster calls prohibit fixture writes');
            },
            conditionalQueueDelete:async document=>{
                const receipt=JSON.parse(protectedRead(receiptFile));checkQueue(document,receipt);
                assert(document.pvt_deleted===true&&document._rev===receipt.owned[document._id].revision
                    &&contentFingerprint(document)===receipt.queue_delete_intent.content_sha256,'Unrecorded queue deletion intent');
                const r=spawnSync('/usr/local/bin/sup',conditionalSaveArguments(document),{encoding:'utf8',timeout:20000,maxBuffer:65536});
                assert(!r.error&&r.status===0&&/^\s*\{ok,/.test(r.stdout),'Exact-revision queue deletion failed; never retry with a new revision');
            },
            apiMissing:async(collection,documentId)=>(await request('GET',collection+'/'+documentId)).status===404};
        let receipt;
        if(action==='run'||action==='run-languages') {
            assert(!fs.existsSync(receiptFile),'Existing receipt requires explicit cleanup/recovery');await io.noCalls();
            const docs=await io.inventory(),map=inventoryMap(docs);
            assert(!docs.some(d=>d.pvt_type==='callflow'&&live(d)&&(d.numbers||[]).includes(EXTENSION)),'Acceptance extension is occupied');
            assert(!map['acdc_queue_extension_'+hash([ACCOUNT,EXTENSION])],'Use a virgin extension; do not overwrite an existing reservation');
            const managed=spawnSync('/usr/local/bin/sup',['knm_converters','is_reconcilable',EXTENSION,ACCOUNT],{encoding:'utf8',timeout:10000,maxBuffer:65536});
            assert(managed.status===0&&managed.stdout.trim()==='false','Acceptance extension is a managed public number');
            receipt={schema_version:1,account:ACCOUNT,extension:EXTENSION,marker:'acdc-editor-'+crypto.randomBytes(12).toString('hex'),
                baseline:Object.fromEntries(docs.map(d=>[d._id,hash(d)])),owned:{},intents:[],checks:[],started_at:new Date().toISOString()};io.persist(receipt);
            await runAcceptance(io,receipt,action==='run-languages');
        } else {receipt=JSON.parse(protectedRead(receiptFile));checkReceipt(receipt);await cleanup(io,receipt);}
        console.log(JSON.stringify({result:'PASS',action,account:ACCOUNT,queue_id:receipt.queue_id,route_id:receipt.route_id,
            checks:receipt.checks,agents_changed:0,fixture_api_resources_removed:true,
            audit_documents_retained:Object.entries(receipt.owned).filter(([,d])=>['acdc_queue_editor_operation','acdc_queue_extension'].includes(d.type)).map(([key])=>key),
            coverage_limits:['master-admin auth only; restricted-token authorization not proven','no SIP or callback calling','no cross-document atomicity claim']}));
    } finally {fs.closeSync(lock);fs.unlinkSync(lockFile);}
}
module.exports={ACCOUNT,EXTENSION,TYPES,LANGUAGES,selectedExtension,hash,merge,body,checkReceipt,checkQueue,checkRoute,checkOperation,checkClaim,
    inventoryMap,assertBaseline,assertNoReferences,guard,change,unchangedRequest,cleanup,runAcceptance};
if(require.main===module)runtime(...process.argv.slice(2)).catch(error=>{
    // Never echo assertion actual/expected documents, HTTP bodies, tokens, or
    // SUP output. The protected receipt retains exact intent for root review.
    console.error('Queue editor acceptance FAIL ('+(error.code==='ERR_ASSERTION'?'guard_or_contract':error.name==='TimeoutError'?'timeout':'runtime')+'); inspect private receipt; no automatic recovery.');process.exitCode=1;
});
