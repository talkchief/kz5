'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {ACCOUNT,DATABASE}=require('./callback-offer-queue.cjs');
const h=require('./queue-editor-acceptance.cjs');
test('Repeat acceptance extension is bounded and explicitly selected, never auto-allocated',()=>{
    assert.equal(h.selectedExtension(undefined),'2097');
    for(const value of ['2090','2096','2099'])assert.equal(h.selectedExtension(value),value);
    for(const value of ['',2096,'2000','2100','+2096','2096;bad','20960'])assert.throws(()=>h.selectedExtension(value));
});
const copy=x=>JSON.parse(JSON.stringify(x)),owner='a'.repeat(64),userId='1'.repeat(32);
function fixture() {
    let serial=0,writes=0,deletes=0,calls=0,callbackCount=0;
    const documents={};
    function save(d) {
        const prior=documents[d._id];assert(!prior||prior._rev===d._rev,'CAS conflict');
        const n=prior?Number(prior._rev.split('-')[0])+1:1;
        documents[d._id]={...copy(d),_rev:n+'-'+String(++serial).padStart(32,'0')};return documents[d._id];
    }
    function raw(id,type,fields){return {_id:id,pvt_type:type,pvt_account_id:ACCOUNT,pvt_account_db:DATABASE,...fields};}
    save(raw(userId,'user',{name:'Preserved acceptance user',queues:['2'.repeat(32)],enabled:true}));
    const receipt={schema_version:1,account:ACCOUNT,extension:h.EXTENSION,marker:'acdc-editor-'+'3'.repeat(24),
        baseline:Object.fromEntries(Object.values(documents).map(d=>[d._id,h.hash(d)])),owned:{},intents:[],checks:[]};
    function revisions(queueId) {
        return {queue:queueId?documents[queueId]._rev:null,users:{[userId]:documents[userId]._rev},
            callflows:Object.fromEntries(Object.values(documents).filter(d=>d.pvt_type==='callflow'&&!d.pvt_deleted).map(d=>[d._id,d._rev]))};
    }
    function get(queueId) {
        const q=queueId?copy(documents[queueId]):{};
        return {status:200,body:{status:'success',data:{queue:{...q,id:queueId,agents:[]},roster:[],revisions:revisions(queueId),
            catalogs:{users:{complete:true},callflows:{complete:true}},callflows:{routes:Object.values(documents)
                .filter(d=>d.pvt_type==='callflow'&&!d.pvt_deleted).map(d=>({...copy(d),id:d._id}))}}}};
    }
    const io={queueSchema:{},randomId:()=>String(++serial).padStart(32,'0'),persist:()=>{},inventory:async()=>copy(Object.values(documents)),
        noCalls:async()=>{assert.equal(calls,0,'active call');},callbacks:async()=>Array(callbackCount).fill({}),
        anonymousEditor:async()=>({status:401,body:{status:'error',error:'401',message:'invalid_credentials',request_id:String(++serial).padStart(32,'0')}}),
        apiLookup:async(_collection,id)=>({status:documents[id]?.pvt_deleted?404:200,
            body:{status:'error',error:'404',message:'bad_identifier',request_id:String(++serial).padStart(32,'0')}}),
        conditionalQueueDelete:async d=>{deletes++;save(d);},
        editor:async(method,queueId,body)=>{
            if(method==='GET')return get(queueId);
            assert.equal(body.roster,null);const opId='acdc_queue_editor_'+h.hash([ACCOUNT,owner,body.request_id]);
            const bh=h.hash([queueId||null,method,body]);
            if(documents[opId])return documents[opId].body_hash===bh
                ?{status:method==='PUT'?201:200,body:{status:'success',data:copy(documents[opId].result)}}
                :{status:409,body:{status:'error'}};
            if(body.revisions.queue!==(queueId?documents[queueId]._rev:null))return {status:409,body:{status:'error'}};
            writes++;
            const qid=queueId||h.hash([opId,'queue']).slice(0,32);
            const priorRoute=Object.values(documents).find(d=>d.pvt_type==='callflow'&&d.flow.data.id===qid&&!d.pvt_deleted);
            const rid=priorRoute?priorRoute._id:h.hash(['acdc_managed_route',qid,opId]).slice(0,32);
            const q=save(queueId?h.merge(documents[qid],body.queue):raw(qid,'queue',body.queue));
            const r=save(raw(rid,'callflow',{...(priorRoute?copy(priorRoute):{}),name:q.name+' (ACDC)',numbers:[h.EXTENSION],patterns:[],
                flags:['talkchief-acdc-managed','talkchief-acdc-queue:'+qid],flow:{module:'acdc_member',data:{id:qid},children:{}},
                ...(body.route?.extension===''?{pvt_deleted:true}:{})}));
            const cid='acdc_queue_extension_'+h.hash([ACCOUNT,h.EXTENSION]);
            save(raw(cid,'acdc_queue_extension',{...(documents[cid]?copy(documents[cid]):{}),extension:h.EXTENSION,queue_id:qid,
                route_id:rid,operation_id:opId,state:body.route?.extension===''?'released':'assigned',route_revision:r._rev}));
            const result={queue_id:qid,operation_id:opId,state:'complete',atomic:false,roster_preserved:true,route_preserved:body.route===null,reload_required:true};
            save(raw(opId,'acdc_queue_editor_operation',{owner,body_hash:bh,queue_id:qid,state:'complete',phase:'complete',remaining:[],in_flight:[],result}));
            return {status:method==='PUT'?201:200,body:{status:'success',data:copy(result)},etag:'W/automatic-not-a-revision'};
        }};
    const editor=io.editor;
    io.editor=async(...args)=>{
        const response=await editor(...args);
        if(response.status>=400)Object.assign(response.body,{request_id:String(++serial).padStart(32,'0'),error:String(response.status),message:'fixture_conflict'});
        return response;
    };
    return {io,receipt,documents,save,get,counts:()=>({writes,deletes}),calls:n=>{calls=n;},callbacks:n=>{callbackCount=n;}};
}
async function create(f) {
    const data=f.get(null).body.data;
    await h.change(f.io,f.receipt,null,h.body({name:f.receipt.marker,kazoo_acceptance_fixture:f.receipt.marker,callback:{enabled:false}},
        data.revisions,{extension:h.EXTENSION},f.io.randomId()),'create');
}
test('entire isolated sequence uses real raw revisions; GET/create/edit/replay/conflict and cleanup preserve unrelated roster',async()=>{
    const f=fixture(),before=copy(f.documents[userId]);await h.runAcceptance(f.io,f.receipt);
    assert(f.receipt.cleaned_at);assert.deepEqual(f.documents[userId],before);
    assert.deepEqual(f.counts(),{writes:3,deletes:1});
    assert.deepEqual(f.receipt.checks,['anonymous_rejected','create_queue_and_route_one_write','identical_create_replay',
        'changed_create_request_id_rejected','edit_queue_and_route_one_write','identical_edit_replay','stale_queue_revision_rejected',
        'fresh_get_confirms_edit','explicit_english_language_selection_preserved','aggregate_route_cleanup','exact_cas_queue_cleanup']);
    assert(f.documents[f.receipt.route_id].pvt_deleted);assert(f.documents[f.receipt.queue_id].pvt_deleted);
    assert.equal(Object.values(f.documents).filter(d=>d.pvt_type==='acdc_queue_editor_operation').length,3);
    assert.equal(f.receipt.http_rejections.length,5);
});
test('changed unrelated user revision blocks mutation and cleanup before deletion',async()=>{
    const f=fixture();await create(f);f.save({...f.documents[userId],queues:['4'.repeat(32)]});
    await assert.rejects(()=>h.cleanup(f.io,f.receipt),/Unrelated document/);assert.equal(f.counts().deletes,0);
});
test('all-five mode saves and reloads each language with distinct intervals and preserved roster',async()=>{
    const f=fixture(),before=copy(f.documents[userId]);await h.runAcceptance(f.io,f.receipt,true);
    assert(f.receipt.cleaned_at);assert.deepEqual(f.documents[userId],before);
    assert.deepEqual(f.counts(),{writes:8,deletes:1});
    for(const language of h.LANGUAGES)for(const action of ['save','replay','reload'])
        assert(f.receipt.checks.includes(action+'_language_'+language));
    assert.equal(f.documents[f.receipt.queue_id].announcements.language,'es-es');
    assert.equal(f.documents[f.receipt.queue_id].announcements.interval,17);
    assert.equal(f.documents[f.receipt.queue_id].callback.announcement.interval,30);
});
test('incorrect fresh language readback fails without deleting or retrying the save',async()=>{
    const f=fixture(),editor=f.io.editor;
    f.io.editor=async(...args)=>{
        const response=await editor(...args);
        if(args[0]==='GET'&&f.receipt.checks.includes('replay_language_he-il'))
            response.body.data.queue.announcements.language='en-us';
        return response;
    };
    await assert.rejects(()=>h.runAcceptance(f.io,f.receipt,true),/did not survive reload/);
    assert.equal(f.counts().deletes,0);assert.equal(f.counts().writes,4);
    assert(!f.receipt.cleaned_at);assert.equal(f.documents[f.receipt.queue_id].announcements.language,'he-il');
});
test('ambiguous language PATCH retains intent and refuses automatic cleanup',async()=>{
    const f=fixture(),editor=f.io.editor;
    f.io.editor=async(...args)=>{
        const response=await editor(...args);
        if(args[0]==='PATCH'&&args[2].queue.announcements?.language==='ar-sa')throw Error('lost language reply');
        return response;
    };
    await assert.rejects(()=>h.runAcceptance(f.io,f.receipt,true),/lost language reply/);
    assert.equal(f.receipt.intents.at(-1).state,'in_flight');
    await assert.rejects(()=>h.cleanup(f.io,f.receipt),/Ambiguous request/);
    assert.equal(f.counts().deletes,0);assert(!f.receipt.cleaned_at);
});
test('changed marked fixture is retained; never recaptures its new revision',async()=>{
    const f=fixture();await create(f);const old=f.receipt.owned[f.receipt.queue_id].revision;
    f.save({...f.documents[f.receipt.queue_id],connection_timeout:123});
    await assert.rejects(()=>h.cleanup(f.io,f.receipt),/Owned document changed/);
    assert.equal(f.receipt.owned[f.receipt.queue_id].revision,old);assert.equal(f.counts().deletes,0);
});
test('live calls, callback records and a new user reference all prevent cleanup',async()=>{
    for(const kind of ['calls','callbacks','reference']) {
        const f=fixture();await create(f);
        if(kind==='calls')f.calls(1);
        if(kind==='callbacks')f.callbacks(1);
        if(kind==='reference') {
            f.save({...f.documents[userId],queues:[f.receipt.queue_id]});
            // Prove the separate reference gate, even if the baseline were
            // deliberately re-established by a human during recovery review.
            f.receipt.baseline[userId]=h.hash(f.documents[userId]);
        }
        await assert.rejects(()=>h.cleanup(f.io,f.receipt));assert.equal(f.counts().deletes,0);
    }
});
test('CAS race after guard retains changed queue and never retries deletion',async()=>{
    const f=fixture();await create(f);let attempts=0;
    f.io.conditionalQueueDelete=async d=>{attempts++;f.save({...f.documents[d._id],connection_timeout:66});f.save(d);};
    await assert.rejects(()=>h.cleanup(f.io,f.receipt),/CAS conflict/);assert.equal(attempts,1);
    assert.equal(f.documents[f.receipt.queue_id].connection_timeout,66);assert(!f.documents[f.receipt.queue_id].pvt_deleted);
});
test('lost aggregate outcome stays ambiguous and cleanup refuses it',async()=>{
    const f=fixture(),editor=f.io.editor;
    f.io.editor=async(...args)=>{const r=await editor(...args);if(args[0]!=='GET')throw Error('lost response');return r;};
    await assert.rejects(()=>create(f),/lost response/);assert.equal(f.receipt.intents[0].state,'in_flight');
    await assert.rejects(()=>h.cleanup(f.io,f.receipt),/Ambiguous request/);assert.equal(f.counts().deletes,0);
});
test('tampered operation owner/body and route identity cannot become owned cleanup targets',async()=>{
    for(const kind of ['operation','route']) {
        const f=fixture(),inventory=f.io.inventory;
        f.io.inventory=async()=>{const docs=await inventory();if(f.counts().writes) {
            const d=docs.find(x=>x.pvt_type===(kind==='operation'?'acdc_queue_editor_operation':'callflow'));
            if(kind==='operation')d.body_hash='f'.repeat(64);else d.flags=['foreign'];
        }return docs;};
        await assert.rejects(()=>create(f));assert.equal(f.receipt.intents[0].state,'in_flight');assert.equal(f.counts().deletes,0);
    }
});
test('explicit no-write rejection checks assert unchanged raw snapshots',async()=>{
    const f=fixture();await create(f);const original=f.io.editor;
    f.io.editor=async(...args)=>{const response=await original(...args);f.save({...f.documents[f.receipt.queue_id],bad_write:true});return response;};
    const stale=h.body({}, {queue:'1-'+'f'.repeat(32)},null,f.io.randomId());
    await assert.rejects(()=>h.unchangedRequest(f.io,f.receipt,f.receipt.queue_id,stale,409,'conflict'),/Owned document changed/);
});
test('receipt cannot target MASTER; resource routing remains explicit and no API deletes exist',()=>{
    const f=fixture();assert.throws(()=>h.checkReceipt({...f.receipt,account:'302ae5a70c403124f764cbc54229cfcd'}));
    const source=require('node:fs').readFileSync(require.resolve('./queue-editor-acceptance.cjs'),'utf8');
    assert(!source.includes("request('DELETE'"));assert(source.includes("data.roster===null"));
    assert(source.includes("--allow-fixture-writes"));assert(source.includes("conditionalSaveArguments(document)"));
});
