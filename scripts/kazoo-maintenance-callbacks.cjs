#!/usr/bin/env node
'use strict';
// Read-only durable reservation inventory. This is NOT a producer fence,
// broker drain, media inventory or permission to activate an upgrade.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const hash=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const terminal=new Set(['completed','cancelled','failed','expired']);
const states=new Set([...terminal,'registering','queued','dialing','confirming','connecting','retry_wait','cancelling']);
const hex=value=>typeof value==='string'&&/^[a-f0-9]{32}$/.test(value);
function account(name){
    assert(typeof name==='string'&&name.length>0&&name.length<=512);
    const decoded=decodeURIComponent(name),match=/^account\/([a-f0-9]{2})\/([a-f0-9]{2})\/([a-f0-9]{28})$/.exec(decoded);
    return match?match.slice(1).join(''):null;
}
function databases(rows){
    assert(Array.isArray(rows)&&rows.length<=10000,'Invalid database inventory');
    rows.forEach(account);assert.equal(new Set(rows).size,rows.length);
    const selected=rows.filter(n=>account(n)).sort(),ids=selected.map(account);
    assert.equal(new Set(ids).size,ids.length,'Ambiguous account database aliases');
    return selected;
}
function info(value,name){
    assert.equal(value.db_name,name);assert(Number.isSafeInteger(value.doc_count)&&value.doc_count>=0);
    for(const key of ['update_seq','purge_seq'])assert((typeof value[key]==='string'&&value[key].length>0&&value[key].length<=4096)||
        (Number.isSafeInteger(value[key])&&value[key]>=0),'Missing database sequence');
    return {doc_count:value.doc_count,update_seq:value.update_seq,purge_seq:value.purge_seq};
}
function sequence(value){assert((typeof value==='string'&&value.length>0&&value.length<=4096)||
    (Number.isSafeInteger(value)&&value>=0),'Missing view sequence');return value;}
function reservation(doc,owner){
    assert(doc&&typeof doc==='object'&&!Array.isArray(doc));
    // A conflicting non-callback winning revision can hide a callback branch.
    for(const key of ['_conflicts','_deleted_conflicts'])assert(doc[key]===undefined||
        (Array.isArray(doc[key])&&doc[key].length===0),'Conflicting document prevents complete inventory');
    if(doc.pvt_type!=='acdc_callback'){
        assert(!doc._id.startsWith('acdc-callback-'),'Misclassified callback document');return null;
    }
    assert(/^acdc-callback-[a-f0-9]{64}$/.test(doc._id));
    assert.equal(doc.pvt_account_id,owner);assert(hex(doc.queue_id));
    assert(states.has(doc.status),'Unknown callback state');
    assert(doc.reconciliation_required===undefined||typeof doc.reconciliation_required==='boolean');
    const blocked=!terminal.has(doc.status)||doc.reconciliation_required===true||
        doc.reconciliation_reason!==undefined||doc.pvt_lease!==undefined;
    return {id:doc._id,revision:doc._rev,status:doc.status,blocked};
}
async function collect(get){
    const session=await get('/_session');assert(Array.isArray(session?.userCtx?.roles)&&session.userCtx.roles.includes('_admin'),'Complete inventory needs server administrator read access');
    const all=await get('/_all_dbs'),names=databases(all),before=new Map(),views=new Map();
    for(const name of names)before.set(name,info(await get('/'+encodeURIComponent(name)),name));
    let documents=0,callbacks=0,blocked=0;const counts={},inventory=crypto.createHash('sha256');
    for(const name of names){
        const start=before.get(name),path='/'+encodeURIComponent(name),owner=account(name);let seen=0,last;
        do {
            const query=new URLSearchParams({include_docs:'true',conflicts:'true',update_seq:'true',limit:'100'});
            if(last!==undefined){query.set('startkey',JSON.stringify(last));query.set('skip','1');}
            const page=await get(path+'/_all_docs?'+query);
            assert.equal(page.total_rows,start.doc_count);assert.equal(page.offset,seen);
            // Clustered CouchDB may encode db-info and all-docs tokens
            // differently. Keep tokens opaque and compare like endpoints.
            sequence(page.update_seq);
            if(!views.has(name))views.set(name,page.update_seq);
            assert.deepEqual(page.update_seq,views.get(name),'View changed during pagination');
            assert(Array.isArray(page.rows)&&page.rows.length===Math.min(100,start.doc_count-seen),'Incomplete document page');
            for(const row of page.rows){
                assert(typeof row.id==='string'&&row.id.length>0&&row.id===row.key);
                assert(last===undefined||Buffer.compare(Buffer.from(row.id),Buffer.from(last))>0,'Non-monotonic document page');
                assert(row.doc&&row.doc._id===row.id&&row.doc._rev===row.value?.rev&&!row.doc._deleted);
                assert(/^[1-9][0-9]*-[a-f0-9]{32}$/.test(row.doc._rev));
                const ticket=reservation(row.doc,owner);
                if(ticket){callbacks++;blocked+=Number(ticket.blocked);counts[ticket.status]=(counts[ticket.status]||0)+1;inventory.update(JSON.stringify([name,ticket])+'\n');}
                last=row.id;seen++;documents++;assert(documents<=1000000,'Document budget exceeded');
            }
        }while(seen<start.doc_count);
    }
    // Recheck every account after the entire scan, not just its own last page.
    for(const name of names){
        const path='/'+encodeURIComponent(name);
        // Ask CouchDB itself whether anything follows the actual all-docs
        // token; never decode tokens or compare only their numeric prefixes.
        const changes=await get(path+'/_changes?'+new URLSearchParams({since:String(views.get(name)),limit:'1',style:'all_docs'}));
        assert(Array.isArray(changes.results)&&changes.results.length===0&&changes.pending===0,'View does not cover current durable work');
        sequence(changes.last_seq);
        assert.deepEqual(info(await get(path),name),before.get(name),'Database changed before inventory completed');
    }
    assert.deepEqual((await get('/_all_dbs')).slice().sort(),all.slice().sort(),'Database set changed');
    return {schema_version:1,observed_at:new Date().toISOString(),account_databases:names.length,documents,
        callbacks,blocked_callbacks:blocked,status_counts:counts,durable_callbacks_drained:blocked===0,
        scope_sha256:hash({databases:[...before],views:[...views]}),inventory_sha256:inventory.digest('hex'),
        producer_fence_proven:false,complete_cluster_drain_proven:false};
}
function deployment(file='/etc/kazoo/deployment.env'){
    const st=fs.lstatSync(file);assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);
    const env={};for(const line of fs.readFileSync(file,'utf8').split('\n')){
        if(!line||line.startsWith('#'))continue;const at=line.indexOf('='),key=line.slice(0,at),value=line.slice(at+1);
        assert(at>0&&/^[A-Z][A-Z0-9_]+$/.test(key)&&!Object.hasOwn(env,key)&&/^[A-Za-z0-9+/]*={0,2}$/.test(value));
        env[key]=Buffer.from(value,'base64').toString();
    }return env;
}
function reader(env,request=fetch){
    assert(/^[A-Za-z0-9._-]+$/.test(env.KAZOO_COUCHDB_HOST));
    assert(/^[0-9]+$/.test(env.KAZOO_COUCHDB_PORT)&&Number(env.KAZOO_COUCHDB_PORT)>0&&Number(env.KAZOO_COUCHDB_PORT)<65536);
    assert(env.KAZOO_COUCHDB_USER&&!/[:\r\n]/.test(env.KAZOO_COUCHDB_USER)&&env.KAZOO_COUCHDB_PASSWORD&&!/[\r\n]/.test(env.KAZOO_COUCHDB_PASSWORD));
    // Matches this installer's existing private CouchDB HTTP transport. No new
    // arbitrary URL/credential override, redirects, writes or automatic retries.
    const origin='http://'+env.KAZOO_COUCHDB_HOST+':'+env.KAZOO_COUCHDB_PORT;
    const authorization='Basic '+Buffer.from(env.KAZOO_COUCHDB_USER+':'+env.KAZOO_COUCHDB_PASSWORD).toString('base64');
    const deadline=Date.now()+120000;
    return async path=>{
        assert(path.startsWith('/')&&!path.startsWith('//')&&!path.includes('#'));
        const remaining=deadline-Date.now();assert(remaining>0,'Inventory deadline exceeded');
        const response=await request(origin+path,{method:'GET',redirect:'error',signal:AbortSignal.timeout(Math.min(15000,remaining)),headers:{Authorization:authorization,Accept:'application/json'}});
        assert.equal(response.status,200,'Database inventory unavailable');let bytes=0;const chunks=[];
        for await(const chunk of response.body){bytes+=chunk.length;assert(bytes<=16*1024*1024,'Response budget exceeded');chunks.push(Buffer.from(chunk));}
        return JSON.parse(Buffer.concat(chunks).toString());
    };
}
module.exports={account,databases,info,reservation,collect,reader,deployment};
if(require.main===module)(async()=>{
    assert.equal(process.getuid(),0);assert.deepEqual(process.argv.slice(2),['--check']);
    const result=await collect(reader(deployment()));console.log(JSON.stringify(result));
    if(!result.durable_callbacks_drained)process.exitCode=2;
})().catch(()=>{console.error('MAINTENANCE_CALLBACK_INVENTORY_REFUSED');process.exitCode=1;});
