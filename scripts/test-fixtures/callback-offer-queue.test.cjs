'use strict';
// Pure plans and in-memory Couch compare-and-swap; no protected state/live API.
const assert=require('node:assert/strict');
const {plan,assertOwned,assertRawOwned,assertExpectedConfiguration,captureOwned,deleteOwned,assertNoReferences,conditionalSaveArguments,
    erlangTerm,fingerprint,audioMode,geminiAssets,geminiReferences,getReference,referenceDocument,ACCOUNT,ENCODED_DATABASE}=require('./callback-offer-queue.cjs');
const Q='11111111111111111111111111111111',F='22222222222222222222222222222222',U='33333333333333333333333333333333';
const marker='acdc-offer-'+'a'.repeat(24),rev='1-'+'b'.repeat(32),next='2-'+'c'.repeat(32);
const state={ACCEPTANCE_ACCOUNT_ID:ACCOUNT,ACCEPTANCE_REALM:'acceptance-abcdef123456.invalid',
    ACCEPTANCE_ACCOUNT_NAME:'Kazoo5 Acceptance abcdef123456',ACCEPTANCE_AGENT_1_USER_ID:U};
const user={id:U,enabled:true},base={account:ACCOUNT,marker,extension:'2098',queue_id:Q,callflow_id:F};
const clone=x=>JSON.parse(JSON.stringify(x));
let groups=0;
const desired=plan(state,user,marker);
assert.deepEqual(desired.queue.callback.announcement,{enabled:true,initial_delay:3,interval:15});
assert.equal(desired.queue.announcements.initial_delay,11);assert.equal(desired.queue.announcements.interval,15);
assert.equal(desired.queue.callback.use_local_resources,true);assert.equal(desired.queue.callback.allow_alternate_number,false);
assert.equal(desired.queue.callback.entry_key,'6');assert.deepEqual(desired.queue.callback.outbound_authority,{type:'user',id:U});
assert.deepEqual(desired.route(Q).numbers,['2098']);assert.equal(Object.hasOwn(desired.queue,'agents'),false);groups++;
for(const wrong of [{...state,ACCEPTANCE_ACCOUNT_ID:Q},{...state,ACCEPTANCE_REALM:'master.example'},
    {...state,ACCEPTANCE_ACCOUNT_NAME:'KazooMaster'},{...state,ACCEPTANCE_AGENT_1_USER_ID:'bad'}])assert.throws(()=>plan(wrong,user,marker));groups++;
for(const wrong of [{id:Q,enabled:true},{id:U,enabled:false}])assert.throws(()=>plan(state,wrong,marker));
assert.throws(()=>plan(state,user,'operator-queue'));assert.throws(()=>desired.route('2098'));groups++;
const queue={...desired.queue,id:Q,agents:[]},route={...desired.route(Q),id:F};
assertOwned(queue,base,'queues');assertOwned(route,base,'callflows');groups++;
for(const wrong of [{...route,kazoo_acceptance_fixture:'foreign'},{...route,numbers:['2000']},
    {...route,flow:{module:'acdc_member',data:{id:F},children:{}}},{...route,flow:{...route.flow,children:{_: {module:'user'}}}}])assert.throws(()=>assertOwned(wrong,base,'callflows'));groups++;
for(const wrong of [{...queue,agents:[U]},{...queue,callback:{...queue.callback,enabled:false}},
    {...queue,callback:{...queue.callback,announcement:{enabled:true,initial_delay:1,interval:15}}}])assert.throws(()=>assertOwned(wrong,base,'queues'));groups++;
function raw(collection) {
    const {id:documentId,...body}=collection==='queues'?queue:route;
    return {...clone(body),_id:documentId,_rev:rev,pvt_type:collection==='queues'?'queue':'callflow',
        pvt_account_id:ACCOUNT,pvt_account_db:ENCODED_DATABASE,pvt_modified:63900000000};
}
function store(collection,hook=()=>{}) {
    let document=raw(collection);const calls=[];
    return {calls,get document(){return document;},set document(value){document=value;},
        async get(documentId){calls.push('get');assert.equal(documentId,document._id);await hook('get',document);return clone(document);},
        async save(value){calls.push('save');await hook('save',document);
            assert.equal(value._rev,document._rev,'HTTP409 exact Couch revision conflict');
            assert.equal(value.pvt_deleted,true);assert.equal(value._deleted,undefined);
            document={...clone(value),_rev:next};await hook('saved',document);},
        async apiMissing(){calls.push('apiMissing');return document.pvt_deleted===true;}};
}
async function captured(collection,storage){const fixture=clone(base);await captureOwned(storage,fixture,collection,()=>{});storage.calls.length=0;return fixture;}
(async()=>{
    const transportRequests=[],jsonResponse={ok:true,status:200,headers:{get:()=> 'application/json; charset=utf-8'},
        arrayBuffer:async()=>Buffer.from('{"safe":true}')};
    const fetched=await getReference('en-us%2Ffixture?attachments=true',5984,'Basic OFFLINE_SENTINEL','json',async(url,options)=>{
        transportRequests.push({url,options});return jsonResponse;
    });
    assert.deepEqual(referenceDocument(fetched),{safe:true});
    assert.equal(transportRequests[0].url,'http://127.0.0.1:5984/system_media/en-us%2Ffixture?attachments=true');
    assert.equal(transportRequests[0].options.headers.accept,'application/json');
    assert.equal(transportRequests[0].options.redirect,'error');
    assert(transportRequests[0].options.signal instanceof AbortSignal);groups++;
    for(const contentType of ['multipart/related; boundary=OFFLINE_SECRET','text/plain','']) {
        await assert.rejects(getReference('fixture',5984,'Basic OFFLINE_SENTINEL','json',async()=>({...jsonResponse,
            headers:{get:()=>contentType},arrayBuffer:async()=>assert.fail('Do not read non-JSON body')})),
            error=>error.message==='Installed media reference is not application/json');
    }groups++;
    assert.throws(()=>referenceDocument(Buffer.from('01OFFLINE_SECRET')),
        error=>error.message==='Invalid installed media reference JSON');
    await getReference('fixture.wav',5984,'Basic OFFLINE_SENTINEL','wav',async(_url,options)=>{
        assert.equal(options.headers.accept,'audio/wav, application/octet-stream');
        return {...jsonResponse,headers:{get:()=> 'audio/wav'}};
    });groups++;
    const geminiPlan=plan(state,user,marker,'gemini'),geminiFixture={...base,audio_mode:'gemini'};
    assert.equal(geminiPlan.queue.announcements.position_announcements_enabled,false);
    assert.equal(geminiPlan.queue.announcements.wait_time_announcements_enabled,false);
    assert.equal(geminiPlan.queue.announcements.language,'en-us');
    assert.equal(geminiPlan.queue.moh,'silence_stream://-1');assert.equal(geminiPlan.queue.callback.media,undefined);
    assert.deepEqual(geminiPlan.queue.callback.announcement,{enabled:true,initial_delay:3,interval:15});
    assert.equal(audioMode(undefined),'legacy');assert.throws(()=>audioMode('automatic'));groups++;
    const thirtyPlan=plan(state,user,marker,'gemini','interval-30');
    const thirtyFixture={...base,audio_mode:'gemini',timing_profile:'interval-30'};
    const thirtyQueue={...thirtyPlan.queue,id:Q,agents:[]};
    assert.deepEqual(thirtyQueue.callback.announcement,{enabled:true,initial_delay:30,interval:30});
    assert.equal(thirtyQueue.announcements.interval,15);
    assert.equal(thirtyQueue.announcements.position_announcements_enabled,false);
    assertOwned(thirtyQueue,thirtyFixture,'queues');
    assert.throws(()=>assertOwned(thirtyQueue,{...thirtyFixture,timing_profile:'default'},'queues'));
    assert.throws(()=>assertOwned({...thirtyQueue,callback:geminiPlan.queue.callback},thirtyFixture,'queues'));
    assert.throws(()=>plan(state,user,marker,'legacy','interval-30'));
    for(const invalid of [null,30,'30',[],{},'unknown'])assert.throws(()=>plan(state,user,marker,'gemini',invalid));
    const thirtyStore=store('queues');thirtyStore.document={...raw('queues'),...thirtyPlan.queue};
    await captureOwned(thirtyStore,thirtyFixture,'queues',()=>{});
    await deleteOwned(thirtyStore,thirtyFixture,'queues',()=>{},async()=>{});
    assert.equal(thirtyFixture.queues_deleted,true);groups++;
    const geminiQueue={...geminiPlan.queue,id:Q,agents:[]};assertOwned(geminiQueue,geminiFixture,'queues');
    for(const wrong of [{...geminiQueue,moh:'local_stream://default'},
        {...geminiQueue,announcements:{...geminiQueue.announcements,position_announcements_enabled:true}},
        {...geminiQueue,callback:{...geminiQueue.callback,media:{offer:'legacy'}}}])
        assert.throws(()=>assertOwned(wrong,geminiFixture,'queues'));groups++;
    const geminiStore=store('queues');geminiStore.document={...raw('queues'),...geminiPlan.queue};
    await captureOwned(geminiStore,geminiFixture,'queues',()=>{});
    await deleteOwned(geminiStore,geminiFixture,'queues',()=>{},async()=>{});
    assert.equal(geminiFixture.queues_deleted,true);assert.equal(geminiStore.document.pvt_deleted,true);groups++;
    const changedGemini=store('queues'),changedGeminiFixture={...base,audio_mode:'gemini'};
    changedGemini.document={...raw('queues'),...geminiPlan.queue};
    await captureOwned(changedGemini,changedGeminiFixture,'queues',()=>{});changedGemini.document._rev=next;
    await assert.rejects(deleteOwned(changedGemini,changedGeminiFixture,'queues',()=>{},async()=>{}),/revision or full document changed/);
    assert.equal(changedGemini.document.pvt_deleted,undefined);groups++;
    const assets=geminiAssets(),importer=require('../import-acdc-gemini-voices.cjs');
    const docs=new Map(assets.map(a=>{const d=importer.document(a,0);d._rev=rev;d._attachments[a.attachment].digest=a.md5;return [a.id,d];}));
    const gets=[],get=async relative=>{assert(relative.endsWith('?attachments=true'));const key=decodeURIComponent(relative.split('?')[0]);gets.push(key);
        assert(docs.has(key),'Missing immutable asset');return Buffer.from(JSON.stringify(docs.get(key)));};
    const verified=await geminiReferences(assets,get);
    assert.equal(gets.length,43);assert.equal(new Set(gets).size,42);
    assert(verified.receipt.duration_seconds>5&&verified.receipt.duration_seconds<7);
    assert.equal(verified.receipt.installed_callback_assets_verified,42);
    assert.equal(require('node:crypto').createHash('sha256').update(verified.wav).digest('hex'),verified.receipt.wav_sha256);groups++;
    const offer=assets.find(a=>a.canonical_id==='acdc-callback-offer-6'),original=clone(docs.get(offer.id));
    for(const mutate of [d=>d.source_type='foreign',d=>d.source_voice.voice='Other',
        d=>d.source_voice.sha256='0'.repeat(64),d=>d._attachments[offer.attachment].data=Buffer.from('wrong').toString('base64'),
        d=>d._id='en-us/acdc-callback-offer-6']) {
        const bad=clone(original);mutate(bad);docs.set(offer.id,bad);
        await assert.rejects(geminiReferences(assets,get));
    }docs.set(offer.id,original);groups++;
    const missingAsset=assets.at(-1);docs.delete(missingAsset.id);
    await assert.rejects(geminiReferences(assets,get),/Missing immutable asset/);
    const restored=importer.document(missingAsset,0);restored._rev=rev;restored._attachments[missingAsset.attachment].digest=missingAsset.md5;
    docs.set(missingAsset.id,restored);
    await assert.rejects(geminiReferences(assets.slice(1),get));
    await assert.rejects(geminiReferences([...assets.slice(1),assets[1]],get));groups++;
    let offerReads=0;
    await assert.rejects(geminiReferences(assets,async relative=>{
        if(decodeURIComponent(relative.split('?')[0])===offer.id&&++offerReads===2)return Buffer.from(JSON.stringify({...original,_rev:next}));
        return get(relative);
    }),/changed during reference capture/);groups++;
    for(const collection of ['queues','callflows']) {
        const storage=store(collection),fixture=await captured(collection,storage),saved=[];
        assert.equal(fixture[collection+'_couch'].revision,rev);
        assert.equal(fixture[collection+'_couch'].sha256,fingerprint(storage.document));
        assert.equal(fixture[collection+'_etag'],undefined);
        await deleteOwned(storage,fixture,collection,x=>saved.push(clone(x)),async()=>storage.calls.push('guard'));
        assert.deepEqual(storage.calls,['guard','get','save','get','apiMissing']);
        assert.equal(saved.length,2);assert.equal(saved[0][collection+'_deleted'],undefined);
        assert.equal(saved[1][collection+'_deleted'],true);groups++;
    }
    const changed=store('queues'),changedFixture=await captured('queues',changed);
    changed.document._rev=next;
    await assert.rejects(deleteOwned(changed,changedFixture,'queues',()=>assert.fail('No persist'),async()=>{}),/revision or full document changed/);
    assert.deepEqual(changed.calls,['get']);groups++;
    const modified=store('queues'),modifiedFixture=await captured('queues',modified);
    modified.document.new_administrator_setting=true;
    await assert.rejects(deleteOwned(modified,modifiedFixture,'queues',()=>assert.fail('No persist'),async()=>{}),/revision or full document changed/);
    assert.deepEqual(modified.calls,['get']);groups++;
    const raced=store('queues',(phase,doc)=>{if(phase==='save'){doc._rev=next;doc.administrator_owned=true;}});
    const racedFixture=await captured('queues',raced);
    await assert.rejects(deleteOwned(raced,racedFixture,'queues',()=>{},async()=>{}),/HTTP409/);
    assert.equal(racedFixture.queues_deleted,undefined);assert.equal(raced.document.pvt_deleted,undefined);
    assert.equal(raced.document.administrator_owned,true);assert.deepEqual(raced.calls,['get','save']);groups++;
    for(const tag of [undefined,'W/"automatic"','"'+rev+'"']) {
        const storage=store('queues'),fixture={...base,queues_etag:tag};
        await assert.rejects(deleteOwned(storage,fixture,'queues',()=>assert.fail('No persist'),async()=>{}),/Missing raw Couch revision/);
        assert.deepEqual(storage.calls,['get']);
    }groups++;
    const stale=store('queues'),staleFixture=await captured('queues',stale);
    await assert.rejects(captureOwned(stale,staleFixture,'queues',()=>assert.fail('No refresh')),/Never refresh/);
    assert.deepEqual(stale.calls,[]);groups++;
    const recovery=store('queues'),recovered=clone(base);
    await captureOwned(recovery,recovered,'queues',()=>{});
    assert.equal(recovered.queues_couch.revision,rev);assert.equal(recovery.document.pvt_deleted,undefined);
    assert.deepEqual(recovery.calls,['get']);groups++;
    const duringRecovery=store('queues'),validationHash=fingerprint(duringRecovery.document);
    duringRecovery.document._rev=next;
    await assert.rejects(captureOwned(duringRecovery,clone(base),'queues',()=>assert.fail('No stale capture'),validationHash),/changed during recovery/);groups++;
    const schema={properties:{value:{type:'number'},nested:{type:'object',properties:{enabled:{type:'boolean'},limit:{default:3}}},strategy:{default:'round_robin'}}};
    assertExpectedConfiguration({value:1,nested:{enabled:true,limit:3},strategy:'round_robin',_rev:rev,pvt_type:'queue'},{value:1,nested:{enabled:true}},schema);
    assert.throws(()=>assertExpectedConfiguration({value:1,nested:{enabled:true,limit:4}},{value:1,nested:{enabled:true}},schema),/Non-default/);
    assert.throws(()=>assertExpectedConfiguration({value:1,nested:{enabled:true},unrelated:true},{value:1,nested:{enabled:true}},schema),/Unexpected added/);groups++;
    const crashed=store('queues'),crashedFixture=await captured('queues',crashed);let persisted=0;
    await assert.rejects(deleteOwned(crashed,crashedFixture,'queues',()=>{if(++persisted===2)throw Error('receipt write crash');},async()=>{}),/receipt write crash/);
    delete crashedFixture.queues_deleted;crashed.calls.length=0;
    await deleteOwned(crashed,crashedFixture,'queues',()=>{},async()=>{});
    assert.deepEqual(crashed.calls,['get','apiMissing']);assert.equal(crashedFixture.queues_deleted,true);groups++;
    const after=store('queues',(phase,doc)=>{if(phase==='saved'){doc._rev='3-'+'d'.repeat(32);doc.race_after_delete=true;}});
    const afterFixture=await captured('queues',after);
    await assert.rejects(deleteOwned(after,afterFixture,'queues',()=>{},async()=>{}),/Soft-delete result differs/);
    assert.equal(afterFixture.queues_deleted,undefined);assert.deepEqual(after.calls,['get','save','get']);groups++;
    const foreign=raw('queues');foreign.pvt_account_id=Q;assert.throws(()=>assertRawOwned(foreign,base,'queues'));
    const missing=store('queues');missing.get=async()=>null;
    await assert.rejects(deleteOwned(missing,{...base},'queues',()=>{},async()=>{}),/Unexpected raw/);
    const blocked=store('queues'),blockedFixture=await captured('queues',blocked);
    await assert.rejects(deleteOwned(blocked,blockedFixture,'queues',()=>assert.fail('No persist'),async()=>{throw Error('calls remain');}),/calls remain/);
    assert.deepEqual(blocked.calls,[]);groups++;
    assertNoReferences([raw('queues')],base,'queues');
    assert.throws(()=>assertNoReferences([raw('callflows')],base,'queues'),/references/);
    assert.throws(()=>assertNoReferences([{_id:U,pvt_type:'user',queues:[Q]}],base,'queues'),/references/);
    assertNoReferences([{...raw('callflows'),pvt_deleted:true}],base,'queues');
    assert.throws(()=>assertNoReferences([{_id:'job',pvt_type:'acdc_callback',queue_id:Q,pvt_deleted:true}],base,'queues'),/callback record/);
    assert.throws(()=>assertNoReferences(Array(1001).fill(raw('queues')),base,'queues'),/Unbounded/);groups++;
    const args=conditionalSaveArguments({...raw('queues'),pvt_deleted:true});
    assert.deepEqual(args.slice(0,3),['-e','kz_datamgr','save_doc']);
    assert.equal(args.at(-1),'[{publish_change_notice,true}]');
    assert(args[4].includes(erlangTerm('_rev')+','+erlangTerm(rev)));
    assert(!args.some(arg=>arg.includes('ensure_saved')||arg.includes('crossbar_doc')));
    assert.equal(erlangTerm('";halt().'), '<<34,59,104,97,108,116,40,41,46>>');groups++;
    console.log('PASS '+groups+' memory-only offer fixture plan/ownership/raw-revision/CAS groups; no API/filesystem writes');
})().catch(error=>{console.error(error.stack);process.exitCode=1;});
