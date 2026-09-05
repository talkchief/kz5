#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Exact, operator-reviewed one-time catalog migration. Never discovers owners.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), {spawnSync} = require('node:child_process');
const ACCOUNT = '302ae5a70c403124f764cbc54229cfcd';
const DATABASE = 'account%2F30%2F2a%2Fe5a70c403124f764cbc54229cfcd';
const SOURCE = 'http://91.99.188.145:8000/v2/', TARGET = 'http://kz5.talkchief.io/v2/';
const APPS = Object.freeze([
    ['accounts','6fd9207e022cedcc3b1c9493b1bf7b20'],['acdc','9ed4c13921516bb1d2afb9f1874290a3'],
    ['callflows','f607173df478e2654a7aa28b219c1a72'],['csv-onboarding','747e264204ec61bae44a47fe8bc24532'],
    ['fax','1468daf86a7ec165af980daaf908bfdd'],['numbers','f3248fe1214da79cb5d089614bf22651'],
    ['pbxs','ee30412619e9e4d922c99467db8a5268'],['voicemails','f61021d214b6e7e8d3a41429133ea99b'],
    ['voip','f9a82ad18cf17c9a73b836ff0feba33f'],['webhooks','b94a5cff43467f9e0755aa2f7e9d560e']
].map(Object.freeze));
const REVISION = /^[1-9][0-9]*-[a-f0-9]+$/, HASH = /^[a-f0-9]{64}$/;
const MAX_DOCUMENT = 1024*1024, MAX_RECEIPT = 16*1024*1024;
class MigrationError extends Error { constructor(code) { super(code); this.code=code; } }
const check = (test, code) => { if (!test) throw new MigrationError(code); };
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
function canonical(value, depth=0) {
    check(depth < 50, 'document_depth');
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
    if (typeof value === 'number') {
        check(Number.isFinite(value) && (!Number.isInteger(value) || Number.isSafeInteger(value)), 'unsafe_number');
        return JSON.stringify(value);
    }
    if (Array.isArray(value)) return '[' + value.map(v => canonical(v,depth+1)).join(',') + ']';
    check(object(value), 'document_type');
    return '{' + Object.keys(value).sort().map(k => JSON.stringify(k)+':'+canonical(value[k],depth+1)).join(',') + '}';
}
function parseDocument(raw, name, id, url) {
    check(typeof raw === 'string' && Buffer.byteLength(raw) <= MAX_DOCUMENT, 'document_size');
    let doc;
    try { doc=JSON.parse(raw); } catch { throw new MigrationError('document_json'); }
    check(object(doc) && doc._id===id && doc.name===name && APPS.some(pair => pair[0]===name && pair[1]===id), 'app_identity');
    check(doc.pvt_type==='app' && doc.pvt_account_id===ACCOUNT && doc.pvt_account_db===DATABASE, 'account_identity');
    check(REVISION.test(doc._rev) && !Object.hasOwn(doc,'id')
        && (doc._deleted===undefined || doc._deleted===false)
        && (doc.pvt_deleted===undefined || doc.pvt_deleted===false), 'document_shape');
    check(doc.api_url===url, 'unexpected_api_url');
    check(!doc._conflicts || (Array.isArray(doc._conflicts) && doc._conflicts.length===0), 'document_conflicts');
    if (doc._attachments !== undefined) {
        check(object(doc._attachments) && Object.values(doc._attachments).every(stub => object(stub)
            && stub.stub===true && !Object.hasOwn(stub,'data')), 'attachment_not_stub');
    }
    canonical(doc);
    return doc;
}
function unchangedFields(doc) {
    return canonical(Object.fromEntries(Object.entries(doc).filter(([key]) => key!=='api_url' && key!=='_rev')));
}
const allowlistHash = sha(canonical(APPS));
function validateReceipt(receipt) {
    check(object(receipt) && receipt.version===1 && receipt.account_id===ACCOUNT && receipt.database===DATABASE
        && receipt.source_url===SOURCE && receipt.target_url===TARGET && receipt.allowlist_sha256===allowlistHash
        && /^[a-f0-9]{32}$/.test(receipt.receipt_id) && Array.isArray(receipt.apps) && receipt.apps.length===APPS.length,
    'receipt_scope');
    check(['planned','applying','partial','complete'].includes(receipt.state), 'receipt_state');
    receipt.apps.forEach((entry,index) => {
        const [name,id]=APPS[index];
        check(entry.name===name && entry.id===id && ['planned','in_flight','uncertain','committed'].includes(entry.state), 'receipt_entry');
        const before=parseDocument(entry.original_raw_json,name,id,SOURCE);
        check(entry.original_revision===before._rev && entry.original_sha256===sha(entry.original_raw_json)
            && entry.original_canonical_sha256===sha(canonical(before)), 'snapshot_mismatch');
        if (entry.state==='committed') {
            check(REVISION.test(entry.committed_revision) && entry.committed_revision!==entry.original_revision, 'commit_receipt');
            if (entry.verified_raw_json !== undefined) {
                const after=parseDocument(entry.verified_raw_json,name,id,TARGET);
                check(after._rev===entry.committed_revision && unchangedFields(after)===unchangedFields(before)
                    && entry.verified_sha256===sha(entry.verified_raw_json), 'verified_receipt');
            }
        }
    });
    if (receipt.state==='complete') check(receipt.apps.every(e=>e.state==='committed' && e.verified_raw_json), 'incomplete_receipt');
    return receipt;
}
function makePlan(storage, persist=()=>{}) {
    const receipt={version:1,receipt_id:crypto.randomBytes(16).toString('hex'),account_id:ACCOUNT,database:DATABASE,
        source_url:SOURCE,target_url:TARGET,allowlist_sha256:allowlistHash,state:'planned',created_at:new Date().toISOString(),apps:[]};
    // Complete the read/validation set before publishing an applicable plan.
    for (const [name,id] of APPS) {
        const raw=storage.read(id), doc=parseDocument(raw,name,id,SOURCE);
        receipt.apps.push({name,id,state:'planned',original_revision:doc._rev,original_raw_json:raw,
            original_sha256:sha(raw),original_canonical_sha256:sha(canonical(doc))});
    }
    validateReceipt(receipt); persist(receipt); return receipt;
}
function verifyCurrent(storage,entry) {
    const raw=storage.read(entry.id), url=entry.state==='committed'?TARGET:SOURCE;
    const current=parseDocument(raw,entry.name,entry.id,url);
    if (entry.state==='committed') {
        const original=parseDocument(entry.original_raw_json,entry.name,entry.id,SOURCE);
        check(current._rev===entry.committed_revision && unchangedFields(current)===unchangedFields(original), 'committed_document_changed');
    } else check(current._rev===entry.original_revision && sha(raw)===entry.original_sha256, 'source_document_changed');
    return raw;
}
function applyPlan(receipt,storage,persist=()=>{},report=()=>{}) {
    validateReceipt(receipt);
    check(receipt.apps.every(entry => ['planned','committed'].includes(entry.state)), 'manual_reconciliation_required');
    // Refuse any changed/custom/pre-migrated app before making this run's writes.
    for (const entry of receipt.apps) verifyCurrent(storage,entry);
    for (const entry of receipt.apps) {
        if (entry.state==='committed') {
            report({name:entry.name,id:entry.id,status:'receipt_verified_noop',revision:entry.committed_revision});
            continue;
        }
        // This local durable boundary must precede the remote write.
        entry.state='in_flight'; receipt.state='applying'; persist(receipt);
        let result;
        try { result=storage.save(entry.id,entry.original_revision,entry.original_sha256); }
        catch { result={status:'uncertain'}; }
        if (!result || result.status!=='committed' || !REVISION.test(result.revision) || result.revision===entry.original_revision) {
            entry.state='uncertain'; receipt.state='partial'; persist(receipt);
            throw new MigrationError('save_unconfirmed_manual_reconciliation');
        }
        // Preserve a received commit acknowledgement before a fallible read-back.
        entry.state='committed'; entry.committed_revision=result.revision; persist(receipt);
        try {
            entry.verified_raw_json=verifyCurrent(storage,entry);
            entry.verified_sha256=sha(entry.verified_raw_json); persist(receipt);
        } catch (error) {
            receipt.state='partial'; persist(receipt);
            throw error;
        }
        report({name:entry.name,id:entry.id,status:'committed_verified',revision:entry.committed_revision,
            sha256:entry.verified_sha256});
    }
    // Re-read committed rows even on replay, then persist missing verification
    // after a prior acknowledged save whose immediate read-back failed.
    for (const entry of receipt.apps) {
        entry.verified_raw_json=verifyCurrent(storage,entry);
        entry.verified_sha256=sha(entry.verified_raw_json);
    }
    receipt.state='complete'; receipt.completed_at=new Date().toISOString(); persist(receipt);
    return receipt;
}
function validatePath(value) {
    check(typeof value==='string' && path.isAbsolute(value) && path.normalize(value)===value && value!=='/', 'unsafe_path');
    let current='/';
    for (const part of value.split('/').filter(Boolean)) {
        current=path.join(current,part);
        if (fs.existsSync(current) || (()=>{try{return fs.lstatSync(current).isSymbolicLink();}catch{return false;}})()) {
            check(!fs.lstatSync(current).isSymbolicLink(), 'symlink_path');
        }
    }
}
function existsEntry(file) {try{fs.lstatSync(file);return true;}catch(error){if(error.code==='ENOENT')return false;throw error;}}
function protectedFile(file,maximum) {
    validatePath(file);
    const stat=fs.lstatSync(file);
    check(stat.isFile() && stat.uid===0 && (stat.mode&0o777)===0o600 && stat.nlink===1 && stat.size<=maximum, 'unsafe_private_file');
    return fs.readFileSync(file,'utf8');
}
function receiptStore(directory,create) {
    validatePath(directory);
    if (create) fs.mkdirSync(directory,{mode:0o700});
    const st=fs.lstatSync(directory);
    check(st.isDirectory() && st.uid===0 && (st.mode&0o777)===0o700, 'unsafe_receipt_directory');
    const file=path.join(directory,'receipt.json'),lock=path.join(directory,'migration.lock');
    const lockfd=fs.openSync(lock,fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_WRONLY|fs.constants.O_NOFOLLOW,0o600);
    fs.writeFileSync(lockfd,JSON.stringify({pid:process.pid,created_at:new Date().toISOString()})+'\n');fs.fsyncSync(lockfd);fs.closeSync(lockfd);
    const persist=receipt=>{
        const bytes=JSON.stringify(receipt,null,2)+'\n';check(Buffer.byteLength(bytes)<=MAX_RECEIPT,'receipt_size');
        if(existsEntry(file)) protectedFile(file,MAX_RECEIPT);
        const temporary=path.join(directory,'receipt.'+crypto.randomBytes(12).toString('hex')+'.tmp');
        const fd=fs.openSync(temporary,fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_WRONLY|fs.constants.O_NOFOLLOW,0o600);
        try {fs.writeFileSync(fd,bytes);fs.fsyncSync(fd);} finally{fs.closeSync(fd);}
        fs.renameSync(temporary,file);
        const dirfd=fs.openSync(directory,fs.constants.O_RDONLY);try{fs.fsyncSync(dirfd);}finally{fs.closeSync(dirfd);}
    };
    return {persist,read:()=>JSON.parse(protectedFile(file,MAX_RECEIPT)),close:()=>fs.unlinkSync(lock)};
}
function rpcStorage({node,cookieFile},spawn=spawnSync) {
    check(node==='kazoo_apps@'+os.hostname(),'nonlocal_node');
    protectedFile(cookieFile,256); // Validate privately; never print or pass contents.
    const bridge=path.join(__dirname,'monster-app-url-rpc.escript');
    function request(input) {
        const result=spawn('/usr/bin/escript',[bridge,'--node',node,'--cookie-file',cookieFile],{
            input:JSON.stringify(input)+'\n',encoding:'utf8',timeout:15000,maxBuffer:2*MAX_DOCUMENT,
            env:{...process.env,ERL_CRASH_DUMP:'/dev/null',ERL_FLAGS:'',ERL_AFLAGS:'',ERL_ZFLAGS:''}});
        let response;try{response=JSON.parse(result.stdout);}catch{throw new MigrationError('bridge_unconfirmed');}
        check(result.status===0 && object(response),'bridge_unconfirmed');
        return response;
    }
    return {read(id){const r=request({action:'read',id});check(r.status==='ok','read_failed');return r.raw_json;},
        save(id,revision,hash){return request({action:'save',id,expected_revision:revision,expected_sha256:hash});}};
}
function main(args) {
    if(args.length===0 || args.includes('--help')) {
        console.log('Usage: migrate-monster-app-api-url.cjs --plan|--apply --receipt-dir NEW_OR_EXISTING_PRIVATE_DIR [--node kazoo_apps@LOCAL_HOST] [--cookie-file /etc/kazoo/.erlang.cookie]');return;
    }
    check(process.getuid()===0,'root_required');
    let mode, directory;const options={node:'kazoo_apps@'+os.hostname(),cookieFile:'/etc/kazoo/.erlang.cookie'};
    for(let i=0;i<args.length;i++) {
        const arg=args[i];
        if(arg==='--plan'||arg==='--apply') {check(!mode,'choose_one_mode');mode=arg.slice(2);}
        else if(arg==='--receipt-dir') {check(!directory && args[i+1],'receipt_directory_required');directory=args[++i];}
        else if(arg==='--node') options.node=args[++i];
        else if(arg==='--cookie-file') options.cookieFile=args[++i];
        else throw new MigrationError('unknown_argument');
    }
    check(mode && directory,'mode_and_receipt_required');
    const storage=rpcStorage(options), store=receiptStore(directory,mode==='plan');
    try {
        if(mode==='plan') {
            const receipt=makePlan(storage,store.persist);
            for(const entry of receipt.apps) console.log(JSON.stringify({name:entry.name,id:entry.id,status:'planned',revision:entry.original_revision,sha256:entry.original_sha256}));
        } else applyPlan(store.read(),storage,store.persist,entry=>console.log(JSON.stringify(entry)));
    } finally {store.close();}
}
module.exports={ACCOUNT,DATABASE,SOURCE,TARGET,APPS,sha,canonical,parseDocument,validateReceipt,makePlan,applyPlan,
    receiptStore,protectedFile,rpcStorage,MigrationError};
if(require.main===module) {
    try{main(process.argv.slice(2));}catch(error){console.error('Migration stopped: '+(error instanceof MigrationError?error.code:'local_or_bridge_failure'));process.exitCode=1;}
}
