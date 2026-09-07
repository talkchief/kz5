'use strict';
// Pure/synthetic source contracts; no network, provider, SIP, service or DB.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const helper=require('./callback-prerecorded-reference.cjs'),queue=require('./callback-offer-queue.cjs');
const {timingProfile}=require('./callback-offer-profile.cjs');
const sourceRoot=process.env.KAZOO_ACCEPTANCE_SOURCE_ROOT||path.resolve(__dirname,'../..');
const catalog=require(path.join(sourceRoot,'scripts/acdc-cardinal-catalog.cjs'));
const originalQueue=require(path.join(sourceRoot,'scripts/test-fixtures/callback-offer-queue.cjs'));
const originalProfile=require(path.join(sourceRoot,'scripts/test-fixtures/callback-offer-profile.cjs'));
const sha=x=>crypto.createHash('sha256').update(x).digest('hex'),clone=x=>JSON.parse(JSON.stringify(x));
const state={ACCEPTANCE_ACCOUNT_ID:queue.ACCOUNT,ACCEPTANCE_REALM:'acceptance-abcdef123456.invalid',
    ACCEPTANCE_ACCOUNT_NAME:'Kazoo5 Acceptance abcdef123456',ACCEPTANCE_AGENT_1_USER_ID:'3'.repeat(32)};
const user={id:'3'.repeat(32),enabled:true},marker='acdc-offer-'+'a'.repeat(24),Q='1'.repeat(32),F='2'.repeat(32);
let groups=0;
for(const [mode,profile] of [['legacy','default'],['gemini','default'],['gemini','interval-30']]) {
    assert.deepEqual(timingProfile(mode,profile),originalProfile.timingProfile(mode,profile));
    assert.deepEqual(queue.plan(state,user,marker,mode,profile).queue,originalQueue.plan(state,user,marker,mode,profile).queue);
}groups++;
assert.deepEqual(timingProfile('prerecorded','dual-prerecorded'),{name:'dual-prerecorded',initial:30,interval:30,
    offers:[30,60],positions:[45,75],positionInitial:45,duration:86,earliest:85,latest:89,silenceUntil:29});
for(const pair of [['prerecorded','default'],['gemini','dual-prerecorded'],['legacy','dual-prerecorded']])
    assert.throws(()=>timingProfile(...pair));groups++;
for(const locale of helper.LOCALES) {
    const p=queue.plan(state,user,marker,'prerecorded','dual-prerecorded',locale);
    assert.deepEqual(p.queue.announcements,{position_announcements_enabled:true,wait_time_announcements_enabled:false,
        initial_delay:45,interval:30,language:locale});
    assert.deepEqual(p.queue.callback.announcement,{enabled:true,initial_delay:30,interval:30});
    assert.equal(p.queue.callback.entry_key,'6');assert.equal(p.queue.callback.allow_alternate_number,false);
    assert.equal(p.queue.callback.use_local_resources,true);assert.deepEqual(p.route(Q).numbers,['2098']);
    const fixture={account:queue.ACCOUNT,marker,extension:'2098',queue_id:Q,callflow_id:F,
        audio_mode:'prerecorded',timing_profile:'dual-prerecorded',language:locale};
    const document={...p.queue,id:Q,agents:[]};queue.assertOwned(document,fixture,'queues');
    for(const mutate of [d=>{d.announcements.language='xx-xx';},d=>{d.announcements.wait_time_announcements_enabled=true;},
        d=>{d.announcements.position_announcements_enabled=false;},d=>{d.announcements.media={you_are_at_position:'custom'};},
        d=>{d.callback.media={offer:'custom'};},d=>{d.agents=[user.id];},d=>{d.announcements.interval=15;}]) {
        const bad=clone(document);mutate(bad);assert.throws(()=>queue.assertOwned(bad,fixture,'queues'));
    }
    assert.deepEqual(queue.referenceOptions('--prerecorded-locale',[locale,'--reference-index','/protected/index.json','--reference-index-sha256','a'.repeat(64)]),
        {locale,index:'/protected/index.json',sha256:'a'.repeat(64)});
}groups++;
for(const extra of [[],['xx-xx','--reference-index','/a','--reference-index-sha256','a'.repeat(64)],
    ['en-us','--reference-index','relative','--reference-index-sha256','a'.repeat(64)],
    ['en-us','--reference-index','/a','--reference-index-sha256','a'.repeat(63)],
    ['en-us','--reference-index','/a','--reference-index-sha256','a'.repeat(64),'extra']])
    assert.throws(()=>queue.referenceOptions('--prerecorded-locale',extra));
assert.throws(()=>queue.referenceOptions('--gemini',['extra']));
assert.throws(()=>queue.plan({...state,ACCEPTANCE_ACCOUNT_ID:'4'.repeat(32)},user,marker,'prerecorded','dual-prerecorded','en-us'));
assert.throws(()=>queue.plan(state,user,marker,'prerecorded','dual-prerecorded','fr-ca'));groups++;
const wav=Buffer.alloc(100,23),digest='md5-'+crypto.createHash('md5').update(wav).digest('base64');
function expected(locale,id,trial) {
    const model=trial?'gemini-3.1-flash-tts-preview':'gemini-2.5-pro-preview-tts',prompt=id+'-gemini-sulafat-'+sha(wav).slice(0,16);
    return {_id:locale+'/'+prompt,_rev:'2-'+'a'.repeat(32),prompt_id:prompt,language:locale,source_type:'kazoo5_acdc_gemini_voice_installer',
        content_length:wav.length,attachment:prompt+'.wav',digest,
        source_voice:{provider:'google-gemini',model,voice:'Sulafat',canonical_prompt_id:id,sha256:sha(wav),transcript_sha256:sha(locale+id)},
        source_cardinal_resolution:trial?{source_kind:'separate_model_trial',provider:'google-gemini',model,voice:'Sulafat',
            telephony_sha256:sha(wav),transcript_sha256:sha(locale+id)}:null};
}
const index={schema_version:1,owner:helper.OWNER,scope:'position-one-and-offer-six',source_probe_account:'3'.repeat(32),
    source_input_sha256:'a'.repeat(64),cardinal_receipt_sha256:'b'.repeat(64),fixed_receipt_sha256:'c'.repeat(64),
    beam_manifest_sha256:'d'.repeat(64),wait_time_verified:false,native_listening_approved:false,full_language_ready:false,
    locales:helper.LOCALES.map(locale=>{
        const intro=['he-il','ar-sa'].includes(locale)?'acdc-cardinal-intro-v1-current-position-number':'acdc-queue-your-current-position-is';
        const documents=['acdc-callback-offer-6',intro,...catalog.tokens(1,locale)].map((id,i)=>expected(locale,id,locale==='he-il'&&i>1));
        return {locale,cardinal_map_sha256:sha(locale),fixed_map_sha256:'e'.repeat(64),
            assets:helper.selection({documents},locale,catalog).map(a=>({...a,file:locale+'/'+a.key+'.ulaw',ulaw_sha256:'f'.repeat(64),samples:1000}))};
    })};
helper.validateIndex(index,catalog);groups++;
for(const mutate of [x=>x.locales.pop(),x=>{x.locales[1]=clone(x.locales[0]);},x=>{x.wait_time_verified=true;},
    x=>{x.native_listening_approved=true;},x=>{x.full_language_ready=true;},x=>{x.locales[0].assets.reverse();},
    x=>{x.locales[0].assets[0].file='../elsewhere.ulaw';},x=>{x.locales[0].assets[0].expected.source_voice.voice='Other';},
    x=>{x.locales[0].assets[0].expected.source_voice.model='gemini-3.1-flash-tts-preview';},
    x=>{x.locales[0].assets[0].expected.source_voice.model='gemini-2.5-flash-preview-tts';},
    x=>{x.locales[0].assets[2].expected.source_voice.model='gemini-2.5-flash-preview-tts';},
    x=>{x.locales[1].assets[2].expected.source_cardinal_resolution.source_kind='generated_cardinal';},
    x=>{x.locales[0].assets[1].samples=80000;}]) {
    const bad=clone(index);mutate(bad);assert.throws(()=>helper.validateIndex(bad,catalog));
}groups++;
for(const locale of index.locales)for(const a of locale.assets) {
    const e=a.expected,doc={...clone(e),pvt_type:'media',pvt_account_db:'system_media',content_type:'audio/wav',streamable:true,
        _attachments:{[e.attachment]:{content_type:'audio/wav',digest:e.digest,length:wav.length,data:wav.toString('base64')}}};
    delete doc.expected_path;delete doc.attachment;delete doc.digest;
    if(e.source_cardinal_resolution===null)delete doc.source_cardinal_resolution;
    assert.deepEqual(helper.verifyDocument(e,doc),wav);
    // CouchDB inline attachment data need not carry the stub-only length.
    const inline=clone(doc);delete inline._attachments[e.attachment].length;
    assert.deepEqual(helper.verifyDocument(e,inline),wav);
    for(const mutate of [d=>{d._rev='3-'+'a'.repeat(32);},d=>{d.source_voice.voice='Other';},
        d=>{d._deleted=true;},d=>{d._conflicts=['3-'+'a'.repeat(32)];},
        d=>{d._attachments[e.attachment].length=wav.length+1;},
        d=>{d._attachments[e.attachment].length=String(wav.length);},
        d=>{delete d._attachments[e.attachment].length;d._attachments[e.attachment].data=wav.subarray(1).toString('base64');},
        d=>{d._attachments[e.attachment].digest='md5-wrong';},
        d=>{d.source_voice.model='wrong-model';},
        d=>{d._attachments[e.attachment].data=Buffer.alloc(100,24).toString('base64');}]) {
        const bad=clone(doc);mutate(bad);assert.throws(()=>helper.verifyDocument(e,bad));
    }
}groups++;
// Exercise the installed importer's actual inline document constructor shape.
const fixedImporter=require(path.join(sourceRoot,'scripts/import-acdc-gemini-voices.cjs'));
assert.equal(require(path.join(sourceRoot,'scripts/generate-acdc-gemini-samples.cjs')).MODEL,'gemini-2.5-pro-preview-tts');
assert.equal(require(path.join(sourceRoot,'scripts/acdc-cardinal-pack.cjs')).MODEL,'gemini-2.5-pro-preview-tts');
const fixedExpected=index.locales[0].assets[0].expected;
const fixedAsset={id:fixedExpected._id,locale:fixedExpected.language,prompt_id:fixedExpected.prompt_id,
    canonical_id:fixedExpected.source_voice.canonical_prompt_id,attachment:fixedExpected.attachment,bytes:wav,
    sha256:sha(wav),md5:digest,transcript_sha256:fixedExpected.source_voice.transcript_sha256,source_file:'synthetic.wav'};
const importedInline=fixedImporter.document(fixedAsset,0);
assert.equal(importedInline.source_voice.model,'gemini-2.5-pro-preview-tts');
importedInline._rev=fixedExpected._rev;importedInline._attachments[fixedExpected.attachment].digest=digest;
assert.equal(importedInline._attachments[fixedExpected.attachment].length,undefined);
fixedImporter.verifyDocument(fixedAsset,importedInline);
assert.deepEqual(helper.verifyDocument(fixedExpected,importedInline),wav);groups++;
// Exercise the final audio-receipt API against actual pinned index bytes,
// not a hash string copied between independently mutable receipt files.
const {assertReferenceReceipt}=require('./assert-callback-offer-audio.cjs');
const receiptIndex=clone(index),raw=Buffer.alloc(1000,23);
for(const l of receiptIndex.locales)for(const a of l.assets)a.ulaw_sha256=sha(raw);
const indexBytes=Buffer.from(JSON.stringify(receiptIndex)),indexSha=sha(indexBytes);
for(const l of receiptIndex.locales) {
    const receipt={schema_version:1,audio_mode:'prerecorded',scope:'position-one-and-offer-six',locale:l.locale,
        reference_index_sha256:indexSha,assets:clone(l.assets),cardinal_map_sha256:l.cardinal_map_sha256,
        fixed_map_sha256:l.fixed_map_sha256,wait_time_verified:false,native_listening_approved:false,full_language_ready:false};
    const refs={offer:raw,position_parts:l.assets.slice(1).map(()=>raw)},expected={locale:l.locale,reference_index_sha256:indexSha};
    const check=(r=receipt,b=indexBytes)=>assertReferenceReceipt(r,refs,'prerecorded',expected,b,sourceRoot);
    check();assert.throws(()=>assertReferenceReceipt(receipt,refs,'prerecorded',expected,undefined,sourceRoot));
    assert.throws(()=>check(receipt,Buffer.from('{}')));
    const replaceCanonical=(r,i,id)=>{
        const e=r.assets[i].expected;e.source_voice.canonical_prompt_id=id;
        e.prompt_id=id+'-gemini-sulafat-'+e.source_voice.sha256.slice(0,16);
        e._id=l.locale+'/'+e.prompt_id;e.attachment=e.prompt_id+'.wav';
    };
    for(const mutate of [r=>replaceCanonical(r,2,'acdc-cardinal-v1-terminal-2'),
        r=>replaceCanonical(r,1,'acdc-queue-wait_time'),
        r=>{r.assets[2].expected.source_voice.model='gemini-other';},
        r=>{r.assets[2].expected.source_cardinal_resolution={unexpected:true};},
        r=>{r.cardinal_map_sha256='0'.repeat(64);},r=>{r.fixed_map_sha256='0'.repeat(64);}]) {
        const bad=clone(receipt);mutate(bad);assert.throws(()=>check(bad));
    }
    const altered=clone(receiptIndex);altered.locales.find(x=>x.locale===l.locale).assets[2].expected.source_voice.transcript_sha256='0'.repeat(64);
    assert.throws(()=>check(receipt,Buffer.from(JSON.stringify(altered))));
}groups++;
const shell=fs.readFileSync(path.join(__dirname,'../test-acdc-callback-offer-calls.sh'),'utf8');
for(const gate of ['flock -n','offer_empty','offer_service_snapshot','offer_clear_owned','offer_stop_capture',
    'assert_stats','offer-workers-after','core_count','new_error_log_matches','--runtime-md5'])assert(shell.includes(gate));
assert(shell.includes('hold_ms=86000'));assert(shell.includes('--reference-index-sha256'));
const source=fs.readFileSync(path.join(__dirname,'callback-prerecorded-reference.cjs'),'utf8');
const captureSource=source.slice(source.indexOf('async function capture('),source.indexOf('module.exports'));
assert(!captureSource.includes('buildInput'));assert(!source.includes('probe.execute('));
groups++;
console.log('PASS'+groups+' focused prerecorded profile/CLI/reference/compatibility groups; synthetic only, no live audio claim');
