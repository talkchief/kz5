'use strict';
// Protected2098 fixture. Auth/read references only on explicit runtime actions;
// only newly marked queue/callflow docs may be written or conditionally deleted.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const ACCOUNT='7807ad61761269a1ccec833dde63f621', id=v=>/^[a-f0-9]{32}$/.test(v||'');
const sha=v=>crypto.createHash('sha256').update(v).digest('hex');
const canonical=v=>JSON.stringify(v,(_key,value)=>value&&typeof value==='object'&&!Array.isArray(value)
    ?Object.fromEntries(Object.keys(value).sort().map(key=>[key,value[key]])):value);
const revision=v=>/^[1-9][0-9]*-[a-f0-9]{32}$/.test(v||'');
const DATABASE='account/'+ACCOUNT.slice(0,2)+'/'+ACCOUNT.slice(2,4)+'/'+ACCOUNT.slice(4);
const ENCODED_DATABASE=encodeURIComponent(DATABASE);
const fingerprint=document=>sha(canonical(document));
const contentFingerprint=document=>fingerprint(Object.fromEntries(Object.entries(document).filter(([key])=>key!=='_rev')));
function audioMode(value='legacy') {
    assert(['legacy','gemini'].includes(value),'Unexpected offer audio mode');return value;
}
function plan(state,user,marker,mode='legacy') {
    audioMode(mode);
    assert(state.ACCEPTANCE_ACCOUNT_ID===ACCOUNT && /^acceptance-[a-f0-9]{12}\.invalid$/.test(state.ACCEPTANCE_REALM)
        && /^Kazoo5 Acceptance [a-f0-9]{12}$/.test(state.ACCEPTANCE_ACCOUNT_NAME),'Not the isolated acceptance tenant');
    assert(id(state.ACCEPTANCE_AGENT_1_USER_ID) && user.id===state.ACCEPTANCE_AGENT_1_USER_ID && user.enabled!==false,'Callback authority must be the existing enabled fixture user');
    assert(/^acdc-offer-[a-f0-9]{24}$/.test(marker),'Invalid fixture marker');
    const queue={name:marker,kazoo_acceptance_fixture:marker,enter_when_empty:true,connection_timeout:90,
        strategy:'round_robin',moh:'silence_stream://-1',announcements:{position_announcements_enabled:mode==='legacy',
            wait_time_announcements_enabled:false,initial_delay:11,interval:15,language:'en-us'},
        callback:{enabled:true,entry_key:'6',allow_alternate_number:false,use_local_resources:true,
            caller_id_source:'inherit',outbound_authority:{type:'user',id:user.id},max_attempts:1,
            announcement:{enabled:true,initial_delay:3,interval:15}}};
    return {queue,route:queueId=>{assert(id(queueId));return {name:marker,kazoo_acceptance_fixture:marker,numbers:['2098'],
        flow:{module:'acdc_member',data:{id:queueId},children:{}}};}};
}
function assertOwned(document,fixture,collection) {
    assert(['queues','callflows'].includes(collection),'Unexpected fixture collection');
    assert(id(document.id) && document.kazoo_acceptance_fixture===fixture.marker && document.name===fixture.marker,'Fixture marker mismatch');
    if(collection==='callflows') {
        assert.equal(document.id,fixture.callflow_id);assert.deepEqual(document.numbers,['2098']);
        assert.deepEqual(document.flow,{module:'acdc_member',data:{id:fixture.queue_id},children:{}});
    } else {
        assert.equal(document.id,fixture.queue_id);assert.deepEqual(document.agents,[]);
        assert.equal(document.callback.enabled,true);assert.equal(document.callback.entry_key,'6');
        assert.deepEqual(document.callback.announcement,{enabled:true,initial_delay:3,interval:15});
        assert.equal(document.announcements.initial_delay,11);assert.equal(document.announcements.interval,15);
        if(audioMode(fixture.audio_mode)==='gemini') {
            assert.equal(document.moh,'silence_stream://-1');
            assert.equal(document.announcements.language,'en-us');
            assert.equal(document.announcements.position_announcements_enabled,false);
            assert.equal(document.announcements.wait_time_announcements_enabled,false);
            assert(document.callback.media===undefined || (document.callback.media &&
                !Array.isArray(document.callback.media) && Object.keys(document.callback.media).length===0),
                'Gemini probe must use built-in defaults without media overrides');
        }
    }
}
function assertRawOwned(document,fixture,collection) {
    assert(document&&revision(document._rev)&&document.pvt_account_id===ACCOUNT
        &&[DATABASE,ENCODED_DATABASE].includes(document.pvt_account_db)
        &&document.pvt_type===(collection==='queues'?'queue':'callflow')
        &&!document._deleted&&!document._attachments,'Unexpected raw fixture document');
    assertOwned({...document,id:document._id,agents:document.agents||[]},fixture,collection);
}
async function captureOwned(storage,fixture,collection,persist,expectedHash) {
    const key=collection==='queues'?'queue_id':'callflow_id';assert(id(fixture[key]));
    assert(!fixture[collection+'_couch'],'Never refresh a captured deletion revision automatically');
    const document=await storage.get(fixture[key]);assertRawOwned(document,fixture,collection);
    assert(!document.pvt_deleted,'Cannot capture a deleted fixture');
    if(expectedHash)assert.equal(fingerprint(document),expectedHash,'Fixture changed during recovery validation');
    fixture[collection+'_couch']={revision:document._rev,sha256:fingerprint(document)};
    persist(fixture);return document;
}
function assertExpectedConfiguration(actual,expected,schema,top=true) {
    assert(actual&&typeof actual==='object'&&!Array.isArray(actual),'Expected fixture configuration object');
    for(const [key,value] of Object.entries(expected)) {
        if(value&&typeof value==='object'&&!Array.isArray(value))assertExpectedConfiguration(actual[key],value,schema?.properties?.[key],false);
        else assert.deepEqual(actual[key],value,'Original fixture setting changed: '+key);
    }
    for(const [key,value] of Object.entries(actual)) {
        if(Object.hasOwn(expected,key)||(top&&(key.startsWith('_')||key.startsWith('pvt_'))))continue;
        const definition=schema?.properties?.[key];
        assert(definition,'Unexpected added fixture setting: '+key);
        if(Object.hasOwn(definition,'default'))assert.deepEqual(value,definition.default,'Non-default added fixture setting: '+key);
        else if(definition.type==='object')assertExpectedConfiguration(value,{},definition,false);
        else assert.fail('Unexpected added fixture setting: '+key);
    }
}
function assertDeletionResult(document,fixture,collection,intent) {
    assertRawOwned(document,fixture,collection);
    assert(document.pvt_deleted===true&&contentFingerprint(document)===intent.content_sha256
        &&Number(document._rev.split('-')[0])===Number(intent.prior_revision.split('-')[0])+1,
    'Soft-delete result differs from the exact recorded intent');
}
async function deleteOwned(storage,fixture,collection,persist,guard) {
    const key=collection==='queues'?'queue_id':'callflow_id';
    if(!fixture[key])return;
    assert(typeof guard==='function','Fresh cleanup guard required');
    await guard(collection);
    const document=await storage.get(fixture[key]);assertRawOwned(document,fixture,collection);
    const saved=fixture[collection+'_couch'], priorIntent=fixture[collection+'_delete_intent'];
    assert(saved&&revision(saved.revision)&&/^[a-f0-9]{64}$/.test(saved.sha256),'Missing raw Couch revision/hash receipt; explicit recovery capture required');
    if(document.pvt_deleted===true) {
        assert(priorIntent,'Unrecorded deletion: retain for investigation');
        assertDeletionResult(document,fixture,collection,priorIntent);
    } else {
        assert(!fixture[collection+'_deleted'],'Previously deleted fixture was restored; retain');
        assert(document._rev===saved.revision&&fingerprint(document)===saved.sha256,
            'Fixture revision or full document changed; retain instead of deleting');
        // save_doc honors this exact _rev and returns conflict. Never use
        // Crossbar DELETE (which refreshes revisions) or ensure_saved (retry).
        const deletion={...document,pvt_deleted:true,pvt_modified:Math.floor(Date.now()/1000)+62167219200};
        const intent={prior_revision:document._rev,content_sha256:contentFingerprint(deletion)};
        fixture[collection+'_delete_intent']=intent;persist(fixture);
        await storage.save(deletion);
        assertDeletionResult(await storage.get(fixture[key]),fixture,collection,intent);
    }
    assert(await storage.apiMissing(collection,fixture[key]),'Deleted fixture remains visible through Crossbar');
    fixture[collection+'_deleted']=true;persist(fixture);
}
function assertNoReferences(documents,fixture,collection) {
    assert(Array.isArray(documents)&&documents.length<=1000,'Unbounded cleanup inventory');
    const target=fixture[collection==='queues'?'queue_id':'callflow_id'];
    for(const document of documents) {
        assert(document&&typeof document._id==='string'&&typeof document.pvt_type==='string');
        if(document.pvt_type==='acdc_callback') {
            assert(!canonical(document).includes(fixture.queue_id),'A callback record references the fixture queue');
        }
        if(document._id===target||document.pvt_deleted===true||document._deleted===true)continue;
        assert(!canonical(document).includes(target),'Another document references the fixture being removed');
    }
}
function erlangTerm(value) {
    if(typeof value==='string')return '<<'+[...Buffer.from(value)].join(',')+'>>';
    if(value===null)return 'null';
    if(typeof value==='boolean')return String(value);
    if(typeof value==='number'){assert(Number.isFinite(value));return String(value);}
    if(Array.isArray(value))return '['+value.map(erlangTerm).join(',')+']';
    assert(value&&Object.getPrototypeOf(value)===Object.prototype,'Unexpected JSON term');
    return '{['+Object.entries(value).map(([key,v])=>'{'+erlangTerm(key)+','+erlangTerm(v)+'}').join(',')+']}';
}
function conditionalSaveArguments(document) {
    assert(id(document._id)&&revision(document._rev)&&document.pvt_deleted===true&&canonical(document).length<16384);
    return ['-e','kz_datamgr','save_doc',erlangTerm(ENCODED_DATABASE),erlangTerm(document),'[{publish_change_notice,true}]'];
}
function protectedRead(file) {
    const s=fs.lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===384&&s.size<4*1024*1024,'Protected root-owned0600 file required');
    return fs.readFileSync(file,'utf8');
}
function readEnv(file,encoded=false) {
    return Object.fromEntries(protectedRead(file).split('\n').filter(l=>l&&!l.startsWith('#')).map(line=>{
        const n=line.indexOf('=');assert(n>0);const key=line.slice(0,n);let value=line.slice(n+1);
        assert(/^[A-Z][A-Z0-9_]*$/.test(key));
        if(encoded){const b=Buffer.from(value,'base64');assert(b.toString('base64')===value);value=b.toString();}
        else if(value.startsWith("'")){assert(value.endsWith("'")&&!value.slice(1,-1).includes("'"));value=value.slice(1,-1);}
        else if(value.startsWith('"'))value=JSON.parse(value);
        assert(!/[\r\n]/.test(value));return [key,value];
    }));
}
function geminiAssets() {
    const importer=require('../import-acdc-gemini-voices.cjs'),root=path.resolve(__dirname,'../..');
    const assets=importer.loadPlan(path.join(root,'scripts/assets/acdc-gemini-fixed-20260905'),
        path.join(root,'scripts/assets/acdc-gemini-completion-20260905'),['en-us'],
        path.join(root,'scripts/assets/acdc-gemini-supplemental-20260906'));
    assert.equal(assets.length,42,'Complete built-in callback inventory required');
    // Match the complete selected-locale rows of the actual compiled helper map.
    const erl=v=>Number.isInteger(v)?String(v):'<<'+JSON.stringify(v)+'>>';
    const expected=assets.map(a=>'    {'+[a.locale,a.canonical_id,a.prompt_id,a.sha256,a.md5,a.bytes.length,a.transcript_sha256].map(erl).join(',')+'}').sort();
    const actual=fs.readFileSync(path.join(root,'applications/acdc/src/acdc_gemini_map.hrl'),'utf8')
        .split('\n').filter(line=>line.startsWith('    {<<"en-us">>,' )).map(line=>line.replace(/,$/,'')).sort();
    assert.deepEqual(actual,expected,'Importer assets differ from canonical runtime map');return assets;
}
async function getReference(relative,port,authorization,format='json',fetcher=fetch) {
    assert(Number.isInteger(port)&&port>0&&port<65536&&['json','wav'].includes(format),'Invalid reference request');
    const response=await fetcher('http://127.0.0.1:'+port+'/system_media/'+relative,
        {headers:{authorization,accept:format==='json'?'application/json':'audio/wav, application/octet-stream'},
            redirect:'error',signal:AbortSignal.timeout(15000)});
    assert(response.ok,'Installed media HTTP '+response.status);
    // CouchDB may otherwise select multipart/related for attachments=true.
    // Do not feed multipart bytes (or an error body) into JSON diagnostics.
    if(format==='json')assert((response.headers.get('content-type')||'').split(';')[0].trim().toLowerCase()==='application/json',
        'Installed media reference is not application/json');
    const data=Buffer.from(await response.arrayBuffer());assert(data.length<4*1024*1024,'Oversized installed media reference');return data;
}
function referenceDocument(bytes) {
    try{return JSON.parse(bytes.toString());}
    catch(_){throw Error('Invalid installed media reference JSON');}
}
async function geminiReferences(assets,get) {
    const importer=require('../import-acdc-gemini-voices.cjs');
    assert(Array.isArray(assets)&&assets.length===42&&new Set(assets.map(a=>a.id)).size===42
        &&assets.every(a=>a.locale==='en-us'),'Complete unique EN callback inventory required');
    const offer=assets.filter(a=>a.canonical_id==='acdc-callback-offer-6');assert.equal(offer.length,1);
    const a=offer[0];assert(a.duration_seconds>5&&a.duration_seconds<7,'Gemini offer must cross five seconds and fit the unchanged timing window');
    let document;
    for(const asset of assets) {
        const doc=referenceDocument(await get(encodeURIComponent(asset.id)+'?attachments=true'));
        importer.verifyDocument(asset,doc);if(asset===a)document=doc;
    }
    const after=referenceDocument(await get(encodeURIComponent(a.id)+'?attachments=true'));
    assert.equal(importer.verifyDocument(a,after),document._rev,'Immutable offer changed during reference capture');
    return {wav:Buffer.from(document._attachments[a.attachment].data,'base64'),
        receipt:{document_id:a.id,revision:document._rev,attachment:a.attachment,wav_sha256:a.sha256,
            canonical_prompt_id:a.canonical_id,immutable_path:'/system_media/'+a.id,
            installed_callback_assets_verified:42,duration_seconds:a.duration_seconds}};
}
async function references(run,mode='legacy') {
    audioMode(mode);
    // Installer deployment values are base64 data, not shell assignments.
    const env=readEnv('/etc/kazoo/deployment.env',true);
    assert(['127.0.0.1','localhost'].includes(env.KAZOO_COUCHDB_HOST),'Couch references must remain on localhost');
    const port=Number(env.KAZOO_COUCHDB_PORT||5984);assert(Number.isInteger(port)&&port>0&&port<65536);
    assert(env.KAZOO_COUCHDB_USER&&env.KAZOO_COUCHDB_PASSWORD&&!env.KAZOO_COUCHDB_USER.includes(':'));
    const authorization='Basic '+Buffer.from(env.KAZOO_COUCHDB_USER+':'+env.KAZOO_COUCHDB_PASSWORD).toString('base64');
    const get=(relative,format)=>getReference(relative,port,authorization,format);
    const receipt=mode==='gemini'?{audio_mode:'gemini',scope:'offer_only_silence_hold',position_verified:false}:{};
    if(mode==='gemini') {
        const verified=await geminiReferences(geminiAssets(),get);
        const converted=spawnSync('sox',['-t','wav','-','-t','raw','-r','8000','-c','1','-e','mu-law','-'],
            {input:verified.wav,timeout:15000,maxBuffer:4*1024*1024});
        assert(converted.status===0,'Immutable offer conversion failed');const raw=converted.stdout;
        assert(raw.length>40000&&raw.length<56000&&Math.abs(raw.length/8000-verified.receipt.duration_seconds)<.001,
            'Complete immutable offer duration mismatch');
        fs.writeFileSync(path.join(run,'offer-reference.ulaw'),raw,{mode:384});
        receipt.offer={...verified.receipt,ulaw_sha256:sha(raw)};
    } else {
    for(const [key,prompt] of [['offer','acdc-callback-offer-6'],['position','acdc-queue-your-current-position-is']]) {
        const documentId='en-us/'+prompt, document=referenceDocument(await get(encodeURIComponent(documentId)));
        assert(document._id===documentId && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(document._rev));
        const names=Object.keys(document._attachments||{});assert(names.length===1&&names[0]===prompt+'.wav','Unexpected installed prompt attachment');
        const wav=await get(encodeURIComponent(documentId)+'/'+encodeURIComponent(names[0]),'wav');
        const after=referenceDocument(await get(encodeURIComponent(documentId)));assert(after._rev===document._rev,'Installed recording changed during reference capture');
        const converted=spawnSync('sox',['-t','wav','-','-t','raw','-r','8000','-c','1','-e','mu-law','-'],{input:wav,maxBuffer:4*1024*1024});
        assert(converted.status===0,'Installed reference conversion failed');const raw=converted.stdout;
        assert(raw.length>=512&&raw.length<56000,'Installed '+key+' phrase must be shorter than7seconds; timing policy was not changed');
        fs.writeFileSync(path.join(run,key+'-reference.ulaw'),raw,{mode:384});
        receipt[key]={document_id:documentId,revision:document._rev,attachment:names[0],wav_sha256:sha(wav),ulaw_sha256:sha(raw),duration_seconds:raw.length/8000};
    }
    }
    fs.writeFileSync(path.join(run,'offer-reference-receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:384});
}
async function runtime(action,run,option) {
    assert(option===undefined||option==='--gemini','Unexpected fixture option');
    assert(option===undefined||action==='setup','Audio option applies only to setup; cleanup uses the protected receipt');
    const mode=option==='--gemini'?'gemini':'legacy';
    assert(['setup','cleanup','recover','entry'].includes(action)&&path.isAbsolute(run));
    const s=fs.lstatSync(run);assert(s.isDirectory()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===448);
    assert(fs.realpathSync(run)===run&&run.startsWith('/var/log/kazoo-acceptance/'));
    const file=path.join(run,'offer-fixture.json'),persist=x=>fs.writeFileSync(file,JSON.stringify(x,null,2)+'\n',{mode:384});
    if(action==='entry') {
        const expected=JSON.parse(protectedRead(path.join(run,'offer-call.json'))), found=[];
        const date=new Date().toISOString().slice(0,10),directory='/var/log/kazoo/kazoo_apps/log';
        for(const name of fs.readdirSync(directory).filter(n=>/^console\.log(\.[0-9]+)?$/.test(n))) {
            for(const line of fs.readFileSync(path.join(directory,name),'utf8').split('\n')) {
                if(!line.includes('|'+expected.call_id+'|acdc_queue_manager:'))continue;
                const m=/^(\d{2}:\d{2}:\d{2}\.\d{3}).*member call for queue ([a-f0-9]{32}) recv$/.exec(line);
                if(m)found.push({call_id:expected.call_id,queue_id:m[2],entry_at:date+'T'+m[1]+'Z'});
            }
        }
        assert(found.length===1&&found[0].queue_id===expected.queue_id,'Missing/ambiguous exact2098 queue entry');
        fs.writeFileSync(path.join(run,'offer-queue-entry.json'),JSON.stringify(found[0])+'\n',{mode:384});return;
    }
    const state=readEnv(process.env.KAZOO_ACCEPTANCE_STATE_FILE||'/etc/kazoo/acceptance-secrets.env',true);
    assert(state.ACCEPTANCE_ACCOUNT_ID===ACCOUNT,'Wrong acceptance tenant');
    const secrets=readEnv('/etc/kazoo/installer-secrets.env');let token;
    const api=async(method,relative,data,match,optional404=false)=>{
        assert(relative===''||relative==='user_auth'||relative==='channels'||/^(users|queues|callflows)(?:\/[a-f0-9]{32}(?:\/callbacks)?)?(?:\?paginate=false)?$/.test(relative),'Unexpected API resource');
        assert(match===undefined&&(method==='GET'||(method==='PUT'&&['user_auth','queues','callflows'].includes(relative))),'Unexpected API mutation');
        const url='http://127.0.0.1:8000/v2/'+(relative==='user_auth'?relative:'accounts/'+ACCOUNT+(relative?'/'+relative:''));
        const response=await fetch(url,{method,headers:{'Content-Type':'application/json',...(token?{'X-Auth-Token':token}:{})},
            ...(data===undefined?{}:{body:JSON.stringify({data})}),redirect:'error',signal:AbortSignal.timeout(20000)});
        if(optional404&&method==='GET'&&response.status===404)return {data:null};
        assert(response.ok,'API HTTP '+response.status+' '+method+' '+relative);const body=await response.json();assert(body.status==='success');
        return {...body,etag:response.headers.get('etag')};
    };
    const auth=await api('PUT','user_auth',{credentials:crypto.createHash('md5').update((secrets.KAZOO_MASTER_ADMIN_USER||'admin')+':'+secrets.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex'),method:'md5',realm:secrets.KAZOO_MASTER_ACCOUNT_REALM});
    token=auth.auth_token;assert(token&&auth.data.account_id!==ACCOUNT);
    const tenant=(await api('GET','')).data;assert(tenant.name===state.ACCEPTANCE_ACCOUNT_NAME&&tenant.realm===state.ACCEPTANCE_REALM);
    const deployment=readEnv('/etc/kazoo/deployment.env',true);
    assert(['127.0.0.1','localhost'].includes(deployment.KAZOO_COUCHDB_HOST));
    const couchPort=Number(deployment.KAZOO_COUCHDB_PORT||5984);assert(Number.isInteger(couchPort)&&couchPort>0&&couchPort<65536);
    assert(deployment.KAZOO_COUCHDB_USER&&deployment.KAZOO_COUCHDB_PASSWORD&&!deployment.KAZOO_COUCHDB_USER.includes(':'));
    const couchAuthorization='Basic '+Buffer.from(deployment.KAZOO_COUCHDB_USER+':'+deployment.KAZOO_COUCHDB_PASSWORD).toString('base64');
    const couch=async(relative,data)=>{
        assert(id(relative)||relative==='_find','Unexpected scoped Couch resource');
        const response=await fetch('http://127.0.0.1:'+couchPort+'/'+ENCODED_DATABASE+'/'+relative,
            {method:data===undefined?'GET':'POST',headers:{authorization:couchAuthorization,'Content-Type':'application/json'},
                ...(data===undefined?{}:{body:JSON.stringify(data)}),redirect:'error',signal:AbortSignal.timeout(15000)});
        assert(response.ok,'Scoped Couch read HTTP '+response.status);
        const bytes=Buffer.from(await response.arrayBuffer());assert(bytes.length<4*1024*1024,'Oversized scoped Couch response');
        return JSON.parse(bytes.toString());
    };
    const storage={get:documentId=>couch(documentId),
        save:async document=>{
            const result=spawnSync('/usr/local/bin/sup',conditionalSaveArguments(document),{encoding:'utf8',timeout:20000,maxBuffer:65536});
            assert(!result.error&&result.status===0&&/^\s*\{ok,/.test(result.stdout),'Exact-revision soft delete failed; no revision retry is permitted');
        },apiMissing:async(collection,documentId)=>(await api('GET',collection+'/'+documentId,undefined,undefined,true)).data===null};
    const inventory=async collection=>{const r=await api('GET',collection+'?paginate=false');assert(Array.isArray(r.data)&&!r.next_start_key);return r.data;};
    const baseline=async omit=>{const hashes={};for(const collection of ['users','queues','callflows'])for(const summary of await inventory(collection)){
        assert(id(summary.id));if(omit.includes(summary.id))continue;const d=(await api('GET',collection+'/'+summary.id)).data;hashes[collection+'/'+summary.id]=sha(canonical(d));}return hashes;};
    if(action==='setup') {
        assert(!fs.existsSync(file),'Fixture already exists');await references(run,mode);
        assert(!(await inventory('callflows')).some(flow=>(flow.numbers||[]).includes('2098')),'Extension2098 occupied');
        const user=(await api('GET','users/'+state.ACCEPTANCE_AGENT_1_USER_ID)).data;
        const fixture={account:ACCOUNT,marker:'acdc-offer-'+crypto.randomBytes(12).toString('hex'),extension:'2098',baseline:await baseline([])};
        if(mode==='gemini')fixture.audio_mode=mode;
        const desired=plan(state,user,fixture.marker,mode);persist(fixture);
        for(const collection of ['queues','callflows']) {
            const key=collection==='queues'?'queue_id':'callflow_id',body=collection==='queues'?desired.queue:desired.route(fixture.queue_id);
            const created=(await api('PUT',collection,body)).data;assert(id(created.id));fixture[key]=created.id;persist(fixture);
            const reply=await api('GET',collection+'/'+created.id);assertOwned(reply.data,fixture,collection);
            await captureOwned(storage,fixture,collection,persist);
        }
        console.log(JSON.stringify({result:'PASS',action,account:ACCOUNT,queue_id:fixture.queue_id,extension:'2098',agents_changed:0}));
    } else {
        if(!fs.existsSync(file))return;const fixture=JSON.parse(protectedRead(file));assert(fixture.account===ACCOUNT&&/^acdc-offer-[a-f0-9]{24}$/.test(fixture.marker));
        if(fixture.cleaned_at)return;
        const noCalls=async()=>{
            const channels=spawnSync('/usr/local/freeswitch/bin/fs_cli',['-x','show channels as json'],{encoding:'utf8',timeout:5000});
            assert(channels.status===0);const calls=JSON.parse(channels.stdout);assert(calls.row_count===0&&(!calls.rows||calls.rows.length===0),'Calls remain; fixture cleanup forbidden');
            const remote=(await api('GET','channels')).data;
            assert(remote&&typeof remote==='object'&&Object.keys(remote).length===0,'Acceptance tenant has cluster calls');
        };
        await noCalls();
        // Lost create replies are retained for investigation rather than guessed.
        for(const collection of ['queues','callflows']) {
            const key=collection==='queues'?'queue_id':'callflow_id';
            if(!fixture[key])assert(!(await inventory(collection)).some(d=>d.name===fixture.marker),'Lost create receipt: retain marked resource for explicit recovery');
        }
        const guard=async collection=>{
            await noCalls();
            assert.deepEqual(await baseline([fixture.queue_id,fixture.callflow_id].filter(Boolean)),fixture.baseline,
                'Unrelated documents changed; fixture cleanup forbidden');
            if(fixture.queue_id&&(await api('GET','queues/'+fixture.queue_id,undefined,undefined,true)).data!==null) {
                const callbacks=await api('GET','queues/'+fixture.queue_id+'/callbacks?paginate=false');
                assert(Array.isArray(callbacks.data)&&callbacks.data.length===0&&!callbacks.next_start_key,'Unexpected callback registration');
            }
            const response=await couch('_find',{selector:{pvt_type:{$in:['callflow','queue','user','acdc_callback']}},limit:1001});
            assertNoReferences(response.docs,fixture,collection);
            if(collection==='callflows') {
                // A managed public number would need the normal callflow
                // assignment hook. This fixture is exclusively local2098.
                const managed=spawnSync('/usr/local/bin/sup',['knm_converters','is_reconcilable','2098',ACCOUNT],{encoding:'utf8',timeout:10000,maxBuffer:65536});
                assert(managed.status===0&&managed.stdout.trim()==='false','Managed number requires API assignment hooks; retain fixture');
            }
            await noCalls();
        };
        if(action==='recover') {
            // Explicit receipt repair only, never a delete or refreshed CAS.
            // Reconstruct the original fixture body; retain altered documents.
            assert.deepEqual(await baseline([fixture.queue_id,fixture.callflow_id].filter(Boolean)),fixture.baseline,'Unrelated documents changed before recovery');
            const desired=plan(state,(await api('GET','users/'+state.ACCEPTANCE_AGENT_1_USER_ID)).data,fixture.marker,audioMode(fixture.audio_mode));
            for(const collection of ['callflows','queues']) {
                const documentId=fixture[collection==='queues'?'queue_id':'callflow_id'];
                if(!documentId||fixture[collection+'_couch'])continue;
                await guard(collection);
                const document=await storage.get(documentId), expected=collection==='queues'?desired.queue:desired.route(fixture.queue_id);
                assertRawOwned(document,fixture,collection);
                const schema=JSON.parse(fs.readFileSync(path.join(__dirname,'../../applications/crossbar/priv/couchdb/schemas',collection+'.json'),'utf8'));
                if(collection==='queues'&&document.agents!==undefined)expected.agents=[];
                assertExpectedConfiguration(document,expected,schema);
                await captureOwned(storage,fixture,collection,persist,fingerprint(document));
            }
            console.log(JSON.stringify({result:'PASS',action,receipt_repaired:true,live_documents_changed:0}));return;
        }
        await deleteOwned(storage,fixture,'callflows',persist,guard);
        await deleteOwned(storage,fixture,'queues',persist,guard);
        await noCalls();
        assert.deepEqual(await baseline([]),fixture.baseline,'Unrelated user/queue/route documents changed');
        fixture.cleaned_at=new Date().toISOString();persist(fixture);
        console.log(JSON.stringify({result:'PASS',action,agents_changed:0,conditional_cleanup:true,unrelated_documents_unchanged:true}));
    }
}
module.exports={plan,assertOwned,assertRawOwned,assertExpectedConfiguration,captureOwned,deleteOwned,assertNoReferences,conditionalSaveArguments,
    erlangTerm,fingerprint,contentFingerprint,audioMode,geminiAssets,geminiReferences,getReference,referenceDocument,ACCOUNT,DATABASE,ENCODED_DATABASE};
if(require.main===module)runtime(...process.argv.slice(2)).catch(error=>{console.error('Callback offer fixture FAIL: '+error.message);process.exitCode=1;});
