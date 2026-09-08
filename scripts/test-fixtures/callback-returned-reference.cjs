'use strict';
// Additive saved reference only; no calls, provider, database writes or runtime changes.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
const LOCALES=['en-us','he-il','fr-fr','es-es','ar-sa'],CANONICAL='acdc-callback-returned-confirmation';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const root=()=>path.resolve(__dirname,'../..');
function locale(value){assert(typeof value==='string'&&LOCALES.includes(value),'Unsupported explicit locale');return value;}
function read(file,limit=4*1024*1024){
    assert(path.isAbsolute(file)&&path.resolve(file)===file&&fs.realpathSync(file)===file,'Noncanonical evidence');
    for(let d=path.dirname(file);;d=path.dirname(d)){
        const s=fs.lstatSync(d);assert(s.isDirectory()&&!s.isSymbolicLink()&&s.uid===0&&!(s.mode&0o022));
        if(path.dirname(d)===d)break;
    }
    const before=fs.lstatSync(file),fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW|fs.constants.O_NONBLOCK);
    const same=(a,b)=>['dev','ino','size','uid','gid','mode','nlink','mtimeMs','ctimeMs'].every(k=>a[k]===b[k]);
    try{
        const s=fs.fstatSync(fd);assert(s.isFile()&&s.uid===0&&s.nlink===1&&!(s.mode&0o077)&&s.size>0&&s.size<=limit&&same(before,s));
        const out=Buffer.alloc(s.size+1);let n=0,k;
        while(n<out.length&&(k=fs.readSync(fd,out,n,out.length-n,null))>0)n+=k;
        assert(n===s.size&&same(s,fs.fstatSync(fd))&&same(s,fs.lstatSync(file)),'Changed evidence');return out.subarray(0,n);
    }finally{fs.closeSync(fd);}
}
function tools(sourceRoot){assert(path.isAbsolute(sourceRoot)&&fs.realpathSync(sourceRoot)===sourceRoot);return {importer:require(path.join(sourceRoot,'scripts/import-acdc-gemini-voices.cjs')),
    probe:require(path.join(sourceRoot,'scripts/probe-acdc-prerecorded-runtime.cjs'))};}
function asset(language,sourceRoot=root()){
    locale(language);
    const plan=tools(sourceRoot).importer.loadPlan(path.join(sourceRoot,'scripts/assets/acdc-gemini-fixed-20260905'),
        path.join(sourceRoot,'scripts/assets/acdc-gemini-completion-20260905'),[language]);
    const found=plan.filter(a=>a.locale===language&&a.canonical_id===CANONICAL);assert.equal(found.length,1);return found[0];
}
function convert(wav){
    const r=spawnSync('/usr/bin/sox',['-D','-t','wav','-','-t','raw','-r','8000','-c','1','-e','mu-law','-'],
        {input:wav,timeout:15000,maxBuffer:2*1024*1024});
    assert(!r.error&&r.status===0&&r.stdout.length>=32000&&r.stdout.length<=80000,'Returned prompt must fit4..10 seconds');return r.stdout;
}
function verify(receipt,raw,a){
    assert.deepEqual(Object.keys(receipt||{}).sort(),['schema_version','scope','language','canonical_prompt_id','model','voice',
        'document_id','attachment','revision','wav_sha256','transcript_sha256','ulaw_sha256','samples','installed_observed_at',
        'native_listening_approved','historical_installation_proven'].sort());
    assert(receipt&&receipt.schema_version===1&&receipt.scope==='returned-confirmation-reference'
        &&receipt.language===a.locale&&receipt.canonical_prompt_id===CANONICAL&&a.canonical_id===CANONICAL
        &&receipt.model==='gemini-2.5-pro-preview-tts'&&receipt.voice==='Sulafat'
        &&receipt.document_id===a.id&&receipt.attachment===a.attachment&&receipt.wav_sha256===a.sha256
        &&receipt.transcript_sha256===a.transcript_sha256&&/^[1-9][0-9]*-[a-f0-9]{32}$/.test(receipt.revision)
        &&receipt.ulaw_sha256===sha(raw)&&receipt.samples===raw.length
        &&typeof receipt.installed_observed_at==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(receipt.installed_observed_at)
        &&Number.isFinite(Date.parse(receipt.installed_observed_at))
        &&receipt.native_listening_approved===false&&receipt.historical_installation_proven===false);
    assert(raw.equals(convert(a.bytes)),'Reference differs from exact saved source recording');return receipt;
}
async function capture(directory,language,sourceRoot=root()){
    locale(language);const {importer,probe}=tools(sourceRoot);
    assert(path.isAbsolute(directory)&&fs.realpathSync(directory)===directory
        &&directory.startsWith('/var/log/kazoo-acceptance/returned-reference.'),'Unexpected reference directory');
    probe.protectedParents(directory);const s=fs.lstatSync(directory);
    assert(s.uid===0&&s.isDirectory()&&(s.mode&0o777)===0o700&&fs.readdirSync(directory).length===0);
    const a=asset(language,sourceRoot),env={};
    for(const line of read('/etc/kazoo/deployment.env',1024*1024).toString().split('\n')){
        if(!line||line.startsWith('#'))continue;const n=line.indexOf('='),key=line.slice(0,n),encoded=line.slice(n+1);
        assert(n>0&&/^[A-Z][A-Z0-9_]*$/.test(key)&&!Object.hasOwn(env,key));const bytes=Buffer.from(encoded,'base64');
        assert(bytes.toString('base64')===encoded&&!/[\r\n]/.test(bytes.toString()));env[key]=bytes.toString();
    }
    const port=Number(env.KAZOO_COUCHDB_PORT||5984);
    assert(['localhost','127.0.0.1'].includes(env.KAZOO_COUCHDB_HOST)&&Number.isInteger(port)&&port>0&&port<65536
        &&env.KAZOO_COUCHDB_USER&&!env.KAZOO_COUCHDB_USER.includes(':')&&env.KAZOO_COUCHDB_PASSWORD);
    const url='http://127.0.0.1:'+port+'/system_media/'+encodeURIComponent(a.id)+'?attachments=true&conflicts=true';
    const headers={accept:'application/json',authorization:'Basic '+Buffer.from(env.KAZOO_COUCHDB_USER+':'+env.KAZOO_COUCHDB_PASSWORD).toString('base64')};
    const get=async()=>{
        const response=await fetch(url,{headers,redirect:'error',signal:AbortSignal.timeout(15000)});
        assert(response.status===200&&response.headers.get('content-type')?.startsWith('application/json'));
        const chunks=[];let length=0;
        for await(const chunk of response.body){length+=chunk.length;assert(length<=4*1024*1024);chunks.push(chunk);}
        const doc=JSON.parse(Buffer.concat(chunks));assert(doc._conflicts===undefined||Array.isArray(doc._conflicts)&&doc._conflicts.length===0);
        importer.verifyDocument(a,doc);
        assert(doc.source_voice.model==='gemini-2.5-pro-preview-tts'&&doc.source_voice.provider==='google-gemini'
            &&doc.source_voice.voice==='Sulafat','Unexpected actual installed model/voice');return doc;
    };
    const doc=await get(),raw=convert(a.bytes);assert.equal((await get())._rev,doc._rev);
    const receipt={schema_version:1,scope:'returned-confirmation-reference',language,canonical_prompt_id:CANONICAL,
        model:'gemini-2.5-pro-preview-tts',voice:'Sulafat',document_id:a.id,attachment:a.attachment,revision:doc._rev,
        wav_sha256:a.sha256,transcript_sha256:a.transcript_sha256,ulaw_sha256:sha(raw),samples:raw.length,
        installed_observed_at:new Date().toISOString(),native_listening_approved:false,historical_installation_proven:false};
    verify(receipt,raw,a);
    probe.createEvidence(path.join(directory,'returned-confirmation.ulaw'),raw);
    const bytes=Buffer.from(JSON.stringify(receipt,null,2)+'\n');probe.createEvidence(path.join(directory,'reference.json'),bytes);
    return {reference_directory:directory,reference_sha256:sha(bytes),language,database_writes:0,provider_requests:0};
}
function load(directory,digest,language,sourceRoot=root()){
    locale(language);assert(/^[a-f0-9]{64}$/.test(digest));const bytes=read(path.join(directory,'reference.json'));
    assert.equal(sha(bytes),digest);const receipt=JSON.parse(bytes),raw=read(path.join(directory,'returned-confirmation.ulaw'));
    verify(receipt,raw,asset(language,sourceRoot));return {receipt,raw};
}
module.exports={LOCALES,CANONICAL,sha,locale,read,asset,convert,verify,capture,load};
if(require.main===module)(async()=>{
    const [action,directory,language,sourceRoot]=process.argv.slice(2);
    assert(action==='capture'&&[5,6].includes(process.argv.length));
    console.log(JSON.stringify(await capture(directory,language,sourceRoot)));
})().catch(()=>{console.error('Returned reference capture failed safely.');process.exitCode=1;});
