'use strict';
// Strict receipt/source correlation with a synthetic converter, never network.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createRequire}=require('node:module'),localRequire=createRequire(__filename);
const file=path.join(__dirname,'callback-returned-reference.cjs'),moduleFixture={exports:{}},raw=Buffer.alloc(42648,17);
new Function('require','module','exports','__filename','__dirname',fs.readFileSync(file,'utf8'))(
    name=>name==='node:child_process'?{spawnSync:(cmd,args,options)=>{
        assert.equal(cmd,'/usr/bin/sox');assert.equal(options.timeout,15000);return {status:0,stdout:raw};}}:localRequire(name),
    moduleFixture,moduleFixture.exports,file,__dirname);
const refs=moduleFixture.exports,sha=b=>crypto.createHash('sha256').update(b).digest('hex'),wav=Buffer.alloc(100,29);
let groups=0;
const interfaces={lo:[{family:'IPv4',address:'127.0.0.1'}],eth0:[{family:'IPv4',address:'10.1.0.44'}]};
for(const host of ['localhost','127.0.0.1','10.1.0.44'])assert.equal(refs.localDatabaseHost(host,interfaces),true);
for(const host of [undefined,null,{},'10.1.0.10','10.1.0.28','database.example','10.1.0.44.evil',
    '10.1.0.44\n','http://10.1.0.44','127.0.0.1:5984','::1'])assert.equal(refs.localDatabaseHost(host,interfaces),false);
assert.equal(refs.localDatabaseHost('10.1.0.44',{}),false);
assert.equal(refs.localDatabaseHost('10.1.0.44',{eth0:[{family:4,address:'10.1.0.44'}]}),true);
groups++;
assert.equal(refs.databaseUrl('10.1.0.44',5984,interfaces),'http://10.1.0.44:5984');
assert.equal(refs.databaseUrl('localhost',5984,interfaces),'http://127.0.0.1:5984');
assert.equal(refs.databaseUrl('127.0.0.1',15984,interfaces),'http://127.0.0.1:15984');
for(const port of [0,65536,'5984',NaN])assert.throws(()=>refs.databaseUrl('10.1.0.44',port,interfaces));
assert.throws(()=>refs.databaseUrl('10.1.0.10',5984,interfaces));
groups++;
for(const language of refs.LOCALES){
    const prompt=refs.CANONICAL+'-gemini-sulafat-'+sha(wav).slice(0,16);
    const a={locale:language,canonical_id:refs.CANONICAL,id:language+'/'+prompt,attachment:prompt+'.wav',sha256:sha(wav),transcript_sha256:sha(language),bytes:wav};
    const receipt={schema_version:1,scope:'returned-confirmation-reference',language,canonical_prompt_id:refs.CANONICAL,
        model:'gemini-2.5-pro-preview-tts',voice:'Sulafat',document_id:a.id,attachment:a.attachment,revision:'2-'+'a'.repeat(32),
        wav_sha256:a.sha256,transcript_sha256:a.transcript_sha256,ulaw_sha256:sha(raw),samples:raw.length,
        installed_observed_at:'2026-09-08T00:00:00.000Z',native_listening_approved:false,historical_installation_proven:false};
    refs.verify(receipt,raw,a);
    for(const mutate of [r=>{r.language=refs.LOCALES.find(l=>l!==language);},r=>{r.canonical_prompt_id='acdc-callback-success';},
        r=>{r.model='gemini-2.5-flash-preview-tts';},r=>{r.voice='Other';},r=>{r.document_id='en-us/wrong';},
        r=>{r.ulaw_sha256='0'.repeat(64);},r=>{r.wav_sha256='0'.repeat(64);},r=>{r.revision='unknown';},
        r=>{r.historical_installation_proven=true;},r=>{r.native_listening_approved=true;},r=>{r.unknown_claim=true;},
        r=>{r.installed_observed_at='not-a-time';}]){
        const bad={...receipt};mutate(bad);assert.throws(()=>refs.verify(bad,raw,a));
    }
    assert.throws(()=>refs.verify(receipt,Buffer.alloc(raw.length,18),a));
}groups++;
for(const value of ['',undefined,null,{},'he','fr-ca','AR-SA','en-us\n'])assert.throws(()=>refs.locale(value));groups++;
const source=fs.readFileSync(file,'utf8');
assert(source.includes("redirect:'error'")&&source.includes('AbortSignal.timeout(15000)')&&source.includes('length<=4*1024*1024'));
assert(source.includes('importer.verifyDocument(a,doc)')&&source.includes('assert.equal((await get())._rev,doc._rev)'));
console.log('PASS '+groups+' synthetic returned reference groups; no source audio conversion or service calls');
