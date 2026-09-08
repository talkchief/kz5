'use strict';
// Explicit EN -> FR or short-response-window pending-callback acceptance,
// never a production utility. Both modes are restricted to the main fixture.
// Parent retry harness holds the shared acceptance lock across edit and restore.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const returned=require('./assert-callback-returned-audio.cjs');
const {negotiatedPayload}=require('./assert-callback-confirmation-pcap.cjs');
const fixture=require('./callback-fixture-account.cjs');
const media=require('./callback-gemini-reference.cjs');
const importer=require('../import-acdc-gemini-voices.cjs');
const ACCOUNT='8310dc3170a18de37f205d0da172df65';
let stage='arguments';
const hash=v=>crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex');
function installedMediaHeaders(user,password){
    assert(typeof user==='string'&&user&&!user.includes(':')&&typeof password==='string'&&password);
    return {accept:'application/json',authorization:'Basic '+Buffer.from(user+':'+password).toString('base64')};
}
function privateRead(file){
    const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
    try{const s=fs.fstatSync(fd);assert(s.isFile()&&s.uid===0&&(s.mode&511)===384&&s.nlink===1&&s.size<67108864);return fs.readFileSync(fd);}
    finally{fs.closeSync(fd);}
}
function env(file,encoded){
    return Object.fromEntries(privateRead(file).toString().split('\n').filter(l=>l&&!l.startsWith('#')).map(l=>{
        const n=l.indexOf('=');assert(n>0);const k=l.slice(0,n);let v=l.slice(n+1);assert(/^[A-Z][A-Z0-9_]*$/.test(k));
        if(encoded){const b=Buffer.from(v,'base64');assert(b.toString('base64')===v);v=b.toString();}
        else if(v.startsWith("'")){assert(v.endsWith("'")&&!v.slice(1,-1).includes("'"));v=v.slice(1,-1);}
        else if(v.startsWith('"'))v=JSON.parse(v);
        assert(!/[\r\n]/.test(v));return[k,v];
    }));
}
function patchBody(editor,language,expectedRevision){
    assert(editor.queue.name==='Acceptance Queue 2000'&&editor.revisions.queue===expectedRevision);
    assert(['en-us','fr-fr'].includes(language)&&Array.isArray(editor.roster));
    return {queue:{announcements:{language}},roster:null,route:null,revisions:editor.revisions,
        request_id:crypto.randomBytes(16).toString('hex')};
}
function deadlinePatchBody(editor,seconds,expectedRevision){
    assert(editor.queue.name==='Acceptance Queue 2000'&&editor.revisions.queue===expectedRevision&&Array.isArray(editor.roster));
    assert((seconds===3&&editor.queue.callback.confirmation_timeout===15)
        ||(seconds===15&&editor.queue.callback.confirmation_timeout===3));
    return {queue:{callback:{confirmation_timeout:seconds}},roster:null,route:null,revisions:editor.revisions,
        request_id:crypto.randomBytes(16).toString('hex')};
}
function restoredGuard(current,receipt){
    assert(receipt.state==='edited'&&current.revisions.queue===receipt.after.revisions.queue
        &&hash(current.queue)===hash(receipt.after.queue)&&hash(current.roster)===hash(receipt.after.roster),
    'Intervening queue edit: no automatic overwrite');
}
async function runtime(action,run,scenario='language'){
    assert(['language','deadline'].includes(scenario));const deadline=scenario==='deadline';
    assert(['preflight','edit','verify','restore'].includes(action)&&process.getuid()===0&&path.isAbsolute(run)
        &&run.startsWith('/var/log/kazoo-acceptance/')&&fs.realpathSync(run)===run);
    const st=fs.lstatSync(run);assert(st.isDirectory()&&st.uid===0&&(st.mode&511)===448);
    // A caller cannot invoke this helper independently of the locked parent.
    stage='shared_lock';
    const lock=fs.fstatSync(9),expected=fs.statSync('/etc/kazoo/monitor-acceptance.lock');
    assert(lock.dev===expected.dev&&lock.ino===expected.ino&&lock.uid===0&&(lock.mode&511)===384);
    stage='fixture_identity';
    const state=fixture.readState('/etc/kazoo/acceptance-secrets.env');assert(state.ACCEPTANCE_ACCOUNT_ID===ACCOUNT);
    const file=path.join(run,deadline?'callback-confirmation-deadline-edit.json':'callback-language-edit.json'),save=r=>fs.writeFileSync(file,JSON.stringify(r,null,2)+'\n',{mode:384});
    let receipt=['edit','preflight'].includes(action)?null:JSON.parse(privateRead(file));
    if(receipt){assert((receipt.scenario||'language')===scenario&&receipt.account===ACCOUNT&&receipt.queue===state.ACCEPTANCE_QUEUE_ID);if(action==='restore'&&receipt.state==='restored')return;}
    stage='protected_credentials';
    const secrets=env('/etc/kazoo/installer-secrets.env'),deployment=env('/etc/kazoo/deployment.env',true);let token;
    async function api(method,resource,data){
        assert(resource==='user_auth'||resource==='accounts/'+ACCOUNT||resource==='accounts/'+ACCOUNT+'/queues/'+state.ACCEPTANCE_QUEUE_ID+'/editor');
        const r=await fetch('http://127.0.0.1:8000/v2/'+resource,{method,headers:{'Content-Type':'application/json',...(token?{'X-Auth-Token':token}:{})},
            ...(data?{body:JSON.stringify({data})}:{}),redirect:'error',signal:AbortSignal.timeout(15000)});
        assert(r.ok,'API request failed; no retry');const b=await r.json();assert(b.status==='success');return b;
    }
    stage='authentication';
    token=(await api('PUT','user_auth',{credentials:crypto.createHash('md5').update((secrets.KAZOO_MASTER_ADMIN_USER||'admin')+':'+secrets.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex'),
        method:'md5',realm:secrets.KAZOO_MASTER_ACCOUNT_REALM})).auth_token;assert(token);
    stage='tenant_read';
    const tenant=(await api('GET','accounts/'+ACCOUNT)).data;assert(tenant.name===state.ACCEPTANCE_ACCOUNT_NAME&&tenant.realm===state.ACCEPTANCE_REALM);
    const editorPath='accounts/'+ACCOUNT+'/queues/'+state.ACCEPTANCE_QUEUE_ID+'/editor';
    const get=async()=>{const d=(await api('GET',editorPath)).data;assert(d.queue.id===state.ACCEPTANCE_QUEUE_ID);return {queue:d.queue,roster:d.roster,revisions:d.revisions};};
    stage='editor_read';
    const current=await get();
    if(action==='edit'||action==='preflight'){
        stage='registered_language';
        assert(!fs.existsSync(file)&&current.queue.announcements.language==='en-us');
        if(deadline)assert(current.queue.callback.confirmation_timeout===15);
        const registered=JSON.parse(privateRead(path.join(run,'callback-registration-evidence.json')));
        assert(registered.account_id===ACCOUNT&&registered.queue_id===state.ACCEPTANCE_QUEUE_ID&&registered.status==='queued'
            &&registered.attempts===0&&registered.language==='en-us');
        stage='installed_reference';
        const assets=importer.loadPlan(path.resolve(__dirname,'../assets/acdc-gemini-fixed-20260905'),path.resolve(__dirname,'../assets/acdc-gemini-completion-20260905'),['en-us']);
        const asset=assets.find(a=>a.canonical_id==='acdc-callback-returned-confirmation');assert(asset);
        const host=media.localMediaHost(deployment.KAZOO_COUCHDB_HOST),port=Number(deployment.KAZOO_COUCHDB_PORT||5984);
        assert(Number.isInteger(port)&&port>0&&port<65536);
        const r=await fetch('http://'+host+':'+port+'/system_media/'+encodeURIComponent(asset.id)+'?attachments=true',{
            headers:installedMediaHeaders(deployment.KAZOO_COUCHDB_USER,deployment.KAZOO_COUCHDB_PASSWORD),redirect:'error',signal:AbortSignal.timeout(15000)});
        assert(r.ok);const doc=await r.json();importer.verifyDocument(asset,doc);
        const audio=media.ulaw(asset.bytes);
        if(deadline)assert(audio.length>3*8000&&audio.length<30*8000);
        if(action==='preflight'){
            console.log('PASS pending-callback helper identity/auth/editor/saved-registration/installed-audio preflight; no writes');return;
        }
        fs.writeFileSync(path.join(run,'callback-return-language.ulaw'),audio,{flag:'wx',mode:384});
        receipt={account:ACCOUNT,queue:state.ACCEPTANCE_QUEUE_ID,scenario,state:'edit_intent',before:current,callback:registered.id,
            reference_sha256:asset.sha256,reference_revision:doc._rev,
            body:deadline?deadlinePatchBody(current,3,current.revisions.queue):patchBody(current,'fr-fr',current.revisions.queue)};
        stage='editor_edit';save(receipt);
        const result=(await api('PATCH',editorPath,receipt.body)).data;receipt.result=result;save(receipt);
        assert(result.state==='complete'&&result.roster_preserved===true);
        const after=await get();assert(after.queue.announcements.language===(deadline?'en-us':'fr-fr')&&hash(after.roster)===hash(current.roster));
        if(deadline)assert(after.queue.callback.confirmation_timeout===3);
        receipt.after=after;receipt.state='edited';save(receipt);
    }else{
        stage='unchanged_queue';restoredGuard(current,receipt);
        if(action==='verify'){
            stage='returned_language';
            const bridge=JSON.parse(privateRead(path.join(run,'retry-bridge-evidence.json')));
            assert(bridge.callback.id===receipt.callback&&bridge.callback.language==='en-us'&&bridge.callback.status==='completed'&&bridge.callback.attempts===2);
            receipt.audio=returned.inspect(privateRead(path.join(run,'retry-returned.pcap')),privateRead(path.join(run,'callback-return-language.ulaw')),
                {callerCallId:bridge.caller.sip_call_id,agentCallId:bridge.agent.sip_call_id},
                negotiatedPayload(privateRead(path.join(run,'callback-carrier-negotiation.log')).toString()),'internal',returned.dependencies(path.resolve(__dirname,'../..')));
            if(deadline){
                assert(current.queue.callback.confirmation_timeout===3&&receipt.audio.phrase_samples>3*8000);
                assert(receipt.audio.completion_before_digit_seconds>0&&receipt.audio.completion_before_digit_seconds<=3);
                receipt.short_confirmation_window_verified=true;
            }
            receipt.verified=true;save(receipt);
        }else{
            stage='editor_restore';
            receipt.restore_body=deadline?deadlinePatchBody(current,15,receipt.after.revisions.queue):patchBody(current,'en-us',receipt.after.revisions.queue);receipt.state='restore_intent';save(receipt);
            const result=(await api('PATCH',editorPath,receipt.restore_body)).data;receipt.restore_result=result;save(receipt);
            assert(result.state==='complete'&&result.roster_preserved===true);
            const restored=await get();assert(restored.queue.announcements.language==='en-us'&&hash(restored.roster)===hash(receipt.before.roster));
            if(deadline)assert(restored.queue.callback.confirmation_timeout===15);
            receipt.restored=restored;receipt.state='restored';save(receipt);
        }
    }
    console.log(JSON.stringify({action,scenario,state:receipt.state,verified:receipt.verified===true,
        account_writes:deadline?'isolated queue confirmation timeout only':'isolated queue language only',gemini_requests:0}));
}
module.exports={patchBody,deadlinePatchBody,restoredGuard,installedMediaHeaders};
if(require.main===module)runtime(...process.argv.slice(2)).catch(error=>{
    const location=(error.stack||'').split('\n').slice(1).map(l=>l.match(/\/opt\/kz5\/scripts\/[A-Za-z0-9_./-]+:\d+:\d+/)?.[0]).find(Boolean)||'unavailable';
    console.error('Callback language case failed at '+stage+' ('+location+'); inspect protected receipt, no blind retry or overwrite.');process.exitCode=1;
});
