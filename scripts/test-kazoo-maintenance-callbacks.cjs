'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {account,databases,info,reservation,collect,reader}=require('./kazoo-maintenance-callbacks.cjs');
const A='a'.repeat(32),DB='account%2Faa%2Faa%2F'+'a'.repeat(28),REV='1-'+'b'.repeat(32);
const ticket=(status='completed')=>({_id:'acdc-callback-'+'c'.repeat(64),_rev:REV,pvt_type:'acdc_callback',pvt_account_id:A,queue_id:'d'.repeat(32),status});
function fixture(docs=[],change=()=>{}){
    const calls=[];let infos=0;
    const get=async path=>{
        calls.push(path);const u=new URL(path,'http://fixture.invalid');let result;
        if(u.pathname==='/_session')result={userCtx:{roles:['_admin']}};
        else if(u.pathname==='/_all_dbs')result=[DB,'system_config'];
        else if(u.pathname.endsWith('/_changes')){
            assert.equal(u.searchParams.get('since'),'view-17-opaque');assert.equal(u.searchParams.get('limit'),'1');
            assert.equal(u.searchParams.get('style'),'all_docs');result={results:[],pending:0,last_seq:'17-opaque'};
        }
        else if(u.pathname.endsWith('/_all_docs')){
            const start=u.searchParams.has('startkey')?JSON.parse(u.searchParams.get('startkey')):null;
            const offset=start===null?0:docs.findIndex(d=>d._id===start)+1;
            result={offset,total_rows:docs.length,update_seq:'view-17-opaque',rows:docs.slice(offset,offset+100).map(doc=>({id:doc._id,key:doc._id,value:{rev:doc._rev},doc:{...doc}}))};
            assert.equal(u.searchParams.get('include_docs'),'true');assert.equal(u.searchParams.get('conflicts'),'true');
            assert.equal(u.searchParams.get('update_seq'),'true');assert.equal(u.searchParams.get('limit'),'100');
            if(start!==null)assert.equal(u.searchParams.get('skip'),'1');
        }else {infos++;assert.equal(decodeURIComponent(u.pathname.slice(1)),DB);result={db_name:DB,doc_count:docs.length,update_seq:'17-opaque',purge_seq:'0-opaque'};}
        return change(result,{path,infos,calls})||result;
    };return {get,calls};
}
test('account scope accepts literal and encoded slashes; excludes monthly/system DBs and refuses aliases',()=>{
    assert.equal(account(DB),A);assert.equal(account(decodeURIComponent(DB)),A);
    assert.equal(account(DB+'-202609'),null);assert.equal(account('system_config'),null);
    assert.throws(()=>databases([DB,decodeURIComponent(DB)]));assert.throws(()=>databases([DB,DB]));
    assert.throws(()=>databases(['bad%']));
});
test('opaque sequences are preserved and missing or mismatched metadata refuses',()=>{
    const valid={db_name:DB,doc_count:0,update_seq:'abc',purge_seq:0};assert.equal(info(valid,DB).update_seq,'abc');
    for(const patch of [{db_name:'other'},{doc_count:-1},{update_seq:undefined},{purge_seq:undefined}])assert.throws(()=>info({...valid,...patch},DB));
});
test('all terminal statuses drain; all nonterminal statuses block',()=>{
    for(const state of ['completed','cancelled','failed','expired'])assert.equal(reservation(ticket(state),A).blocked,false);
    for(const state of ['registering','queued','dialing','confirming','connecting','retry_wait','cancelling'])assert.equal(reservation(ticket(state),A).blocked,true);
});
test('terminal labels do not override unresolved reconciliation or leases',()=>{
    for(const patch of [{reconciliation_required:true},{reconciliation_reason:'cleanup_pending'},{pvt_lease:{until:1}},{pvt_lease:null}])
        assert.equal(reservation({...ticket(),...patch},A).blocked,true);
    assert.equal(reservation({...ticket(),reconciliation_required:false},A).blocked,false);
});
test('unknown states, ownership mismatch and conflicts refuse including non-callback winners',()=>{
    for(const patch of [{status:'new-state'},{pvt_account_id:'e'.repeat(32)},{queue_id:'bad'},
        {_id:'bad'},{pvt_type:'device'},{reconciliation_required:'false'},{_conflicts:[REV]},{_deleted_conflicts:[REV]}])
        assert.throws(()=>reservation({...ticket(),...patch},A));
    assert.throws(()=>reservation({_id:'user',pvt_type:'user',_conflicts:[REV]},A));
});
test('empty account still checks both sequences and complete database inventory',async()=>{
    const f=fixture(),r=await collect(f.get);assert.equal(r.durable_callbacks_drained,true);assert.equal(r.documents,0);
    assert.equal(r.producer_fence_proven,false);assert.equal(r.complete_cluster_drain_proven,false);
    assert.equal(f.calls.filter(p=>p==='/_all_dbs').length,2);assert(f.calls.some(p=>p.includes('_all_docs')));
});
test('keyset pagination sees callback beyond first 200 documents without custom views',async()=>{
    const docs=Array.from({length:200},(_,i)=>({_id:'a'+String(i).padStart(4,'0'),_rev:REV,pvt_type:'user'}));
    docs.push(ticket('retry_wait'));const f=fixture(docs),r=await collect(f.get);
    assert.equal(r.documents,201);assert.equal(r.callbacks,1);assert.equal(r.blocked_callbacks,1);
    assert.equal(r.durable_callbacks_drained,false);assert.equal(f.calls.filter(p=>p.includes('_all_docs')).length,3);
    assert(!JSON.stringify(r).includes(A));assert(!JSON.stringify(r).includes(ticket()._id));
});
for(const [name,mutate] of [
    ['missing rows',r=>{r.rows=[];}],['wrong offset',r=>{r.offset=1;}],['wrong total',r=>{r.total_rows=0;}],
    ['sequence drift',r=>{r.update_seq='18-new';}],['missing document',r=>{delete r.rows[0].doc;}],
    ['revision mismatch',r=>{r.rows[0].doc._rev='2-'+'e'.repeat(32);}],
    ['wrong key',r=>{r.rows[0].key='other';}],['deleted winner',r=>{r.rows[0].doc._deleted=true;}]
])test('page refuses '+name,async()=>{const f=fixture([ticket()],(r,{path})=>{if(path.includes('_all_docs'))mutate(r);});await assert.rejects(collect(f.get));});
test('late purge, update or database-set changes refuse the whole observation',async()=>{
    for(const field of ['purge_seq','update_seq']){
        const f=fixture([ticket()],(r,{infos,path})=>{if(infos===2&&!path.includes('_all_docs'))r[field]='changed';});
        await assert.rejects(collect(f.get));
    }
    const f=fixture([],(r,{path,calls})=>path==='/_all_dbs'&&calls.length>2?[DB]:undefined);await assert.rejects(collect(f.get));
});
test('non-admin and forged roles refuse before any database access',async()=>{
    for(const roles of [[],['reader'],'prefix_admin_suffix']){
        const f=fixture([],(r,{path})=>path==='/_session'?{userCtx:{roles}}:undefined);await assert.rejects(collect(f.get));assert.equal(f.calls.length,1);
    }
});
test('CouchDB must confirm the opaque all-docs token has no later changes or pending rows',async()=>{
    for(const patch of [{results:[{id:'new-work'}]},{pending:1},{pending:undefined},{last_seq:undefined}]){
        const f=fixture([ticket()],(r,{path})=>path.includes('/_changes')?{...r,...patch}:undefined);
        await assert.rejects(collect(f.get));
    }
});
test('view token changes between full pages refuse without decoding opaque values',async()=>{
    const docs=Array.from({length:101},(_,i)=>({_id:'a'+String(i).padStart(4,'0'),_rev:REV,pvt_type:'user'}));
    const f=fixture(docs,(r,{path})=>{if(path.includes('startkey='))r.update_seq='different-token';});
    await assert.rejects(collect(f.get));
});
test('HTTP transport is GET-only, refuses redirects/errors, keeps credentials in headers',async()=>{
    const env={KAZOO_COUCHDB_HOST:'127.0.0.1',KAZOO_COUCHDB_PORT:'5984',KAZOO_COUCHDB_USER:'fixture',KAZOO_COUCHDB_PASSWORD:'not-a-real-password'};
    const get=reader(env,async(url,options)=>{assert.equal(url,'http://127.0.0.1:5984/_session');assert.equal(options.method,'GET');assert.equal(options.redirect,'error');assert(options.headers.Authorization.startsWith('Basic '));return new Response('{}',{status:200});});
    assert.deepEqual(await get('/_session'),{});await assert.rejects(get('//other.invalid/'));
    for(const status of [301,401,403,404,500])await assert.rejects(reader(env,async()=>new Response('{}',{status}))('/_session'));
    assert.throws(()=>reader({...env,KAZOO_COUCHDB_HOST:'user@host'}));assert.throws(()=>reader({...env,KAZOO_COUCHDB_PORT:'0'}));
});
