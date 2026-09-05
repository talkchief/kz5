'use strict';
// Real source functions, pinned map and local vendor only; no browser/network.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const candidate=process.env.KAZOO_ENGLISH_MEDIA_CANDIDATE;
const project=process.env.KAZOO_PROJECT_ROOT || path.resolve(__dirname,'..');
const lodash=require(path.join(process.env.KAZOO_MONSTER_VENDOR_ROOT || '/usr/local/src/kazoo5-installer/monster-ui/src/js/vendor','lodash-4.17.4.js'));
const validator=require(path.join(project,'scripts/validate-acdc-language-capabilities.cjs'));
function load(file) {
    let app;
    vm.runInNewContext(fs.readFileSync(file,'utf8'), {define(factory) {
        app=factory(name=>({lodash, jquery(){throw Error('Unexpected DOM use');},monster:{}})[name]);
    }});
    app.i18n={active:()=>JSON.parse(fs.readFileSync(path.join(project,'monster-ui/acdc/i18n/en-US.json'),'utf8'))};
    return app;
}
const app=load(candidate ? path.join(candidate,'app.js') : path.join(project,'monster-ui/acdc/app.js'));
const map=fs.readFileSync(candidate ? path.join(candidate,'acdc_gemini_map.hrl') : path.join(project,'applications/acdc/src/acdc_gemini_map.hrl'),'utf8');
const mapHash=map.match(/GEMINI_MAP_SHA256, <<"([a-f0-9]{64})">>/)[1];
const gemini=[...map.matchAll(/\{<<"en-us">>,<<"([^"]+)">>,<<"([^"]+)">>,<<"([a-f0-9]{64})">>/g)].map(m=>({
    id:'en-us/'+m[2], name:m[1],language:'en-us',has_attachments:true,prompt_id:m[2],canonical_prompt_id:m[1],
    source_type:'kazoo5_acdc_gemini_voice_installer',source_map_sha256:mapHash,sha256:m[3],import_metadata_verified:true
}));
assert.equal(gemini.length,29);
const canonical=validator.requiredPromptIds.filter(id=>id.startsWith('acdc-queue-')&&id!=='acdc-queue-your-current-position-is')
    .map(id=>id.slice(5)).concat(['agent-invalid_choice','menu-invalid_entry','cf-enter_number'])
    .map(id=>({id:'en-us/'+id,language:'en-us',has_attachments:true}));
const media=canonical.concat(gemini), manifest=validator.legacyLanguageCapabilities('2026-09-05T22:00:00Z');
function options(entries=media, value=manifest, error=null){return JSON.parse(JSON.stringify(app.languageCapabilityOptions(value,entries,error)));}
function enabled(entries){return options(entries).filter(x=>!x.disabled).map(x=>x.value);}
assert.deepEqual(enabled(media),['en-us']);
assert(Object.values(manifest.languages).every(e=>Object.values(e).every(x=>x===false)));
for(const item of media)assert.deepEqual(enabled(media.filter(x=>x!==item)),[],'Missing prerequisite accepted: '+item.id);
for(const [key,value] of [['source_type','customer'],['source_map_sha256','0'.repeat(64)],['sha256','0'.repeat(64)],
    ['canonical_prompt_id','acdc-callback-success'],['id','en-us/acdc-callback-success'],['import_metadata_verified',false],
    ['has_attachments',false],['language','he-il'],['prompt_id','unrelated']]){
    assert.deepEqual(enabled(canonical.concat([{...gemini[0],[key]:value},...gemini.slice(1)])),[],'Unproven purpose accepted: '+key);
}
assert.deepEqual(enabled(canonical.concat(gemini.map(x=>({id:x.id,canonical_prompt_id:x.canonical_prompt_id})))),[]);
assert.deepEqual(options(media,manifest,'unavailable').filter(x=>!x.disabled),[]);
assert.doesNotThrow(()=>app.verifiedGeminiEnglishPurposes([null,42,'invalid',{}]));
const oldCanonical=validator.requiredPromptIds.map(id=>({id:'en-us/'+(id.startsWith('acdc-queue-')&&id!=='acdc-queue-your-current-position-is'?id.slice(5):id),language:'en-us',has_attachments:true}));
// Stable explicit baseline oracle, independent of the functions under test.
const expectedEnglishOptions=[
    {value:'en-us',disabled:false,ready:true,label:'English (United States) — Ready'},
    {value:'ar-sa',disabled:true,ready:false,label:'العربية — Arabic — Not installed or incomplete'},
    {value:'he-il',disabled:true,ready:false,label:'עברית — Hebrew — Not installed or incomplete'},
    {value:'es-es',disabled:true,ready:false,label:'Español — Spanish — Not installed or incomplete'},
    {value:'fr-fr',disabled:true,ready:false,label:'Français — French — Not installed or incomplete'}
];
assert.deepEqual(options(media),expectedEnglishOptions,'Fresh actual-assets English options changed');
assert.deepEqual(options(media.concat(oldCanonical)),expectedEnglishOptions,
    'Existing fully supplied English catalog behavior changed');
const full=JSON.parse(JSON.stringify(manifest));delete full.backend_mode;
const entry=full.languages['en-us'];Object.assign(entry,{ready:true,position:true,wait_time:true,callback:true,numbers:'native_say',
    number_range:[0,999999999],numeric_prompt_count:0,required_prompt_ids:validator.requiredPromptIds,
    source_catalog_sha256:'a'.repeat(64),installed_media_sha256:'b'.repeat(64)});
const fullMedia=validator.requiredPromptIds.map(id=>({id:'en-us/'+id}));
assert.deepEqual(options(fullMedia,full),expectedEnglishOptions,'Full English manifest behavior changed');
const expectedDefaultQueue={
    name:'',strategy:'round_robin',agent_ring_timeout:15,agent_wrapup_time:0,
    connection_timeout:3600,max_queue_size:0,ring_simultaneously:1,caller_exit_key:'#',
    enter_when_empty:true,record_caller:false,moh:'',announce:'',
    announcements:{interval:30,initial_delay:30,position_announcements_enabled:false,
        wait_time_announcements_enabled:false,media:{
            you_are_at_position:'queue-you_are_at_position',in_the_queue:'queue-in_the_queue',
            the_estimated_wait_time_is:'queue-the_estimated_wait_time_is',
            increase_in_call_volume:'queue-increase_in_call_volume'}},
    callback:{enabled:false,announcement:{enabled:true,initial_delay:30,interval:60},
        entry_key:'6',allow_alternate_number:false,use_local_resources:false,max_attempts:3,
        retry_delay:60,ttl:3600,originate_timeout:60,ready_ack_timeout:5,confirmation_timeout:10,
        handoff_timeout:5,menu_timeout_ms:30000,success_timeout_ms:10000,
        outbound_authority:{id:'',type:'user'},outbound_caller_id:{number:'',name:''},
        media:{offer:'',menu:'',number_readback:'',confirmation:'',success:'',returned_confirmation:''}}
};
assert.deepEqual(JSON.parse(JSON.stringify(app.defaultQueue())),expectedDefaultQueue,
    'Stable baseline queue defaults changed');
const saved={announcements:{media:{you_are_at_position:'customer-position'},language:'en-us'},callback:{media:{offer:'customer-offer'}}};
assert.deepEqual(JSON.parse(JSON.stringify(app.mergeEditorDraft(saved,{callback:{announcement:{enabled:false}}}))),
    {announcements:{media:{you_are_at_position:'customer-position'},language:'en-us'},
        callback:{media:{offer:'customer-offer'},announcement:{enabled:false}}},
    'Unrelated patch must preserve both saved prompt overrides and explicit language');
assert.deepEqual(saved,{announcements:{media:{you_are_at_position:'customer-position'},language:'en-us'},
    callback:{media:{offer:'customer-offer'}}},'Draft merge must not mutate its source');
console.log('PASS fresh44 prerequisites, each missing asset, nine provenance/identity negatives, no fake aliases, stable supplied-English/full-mode/default oracles and exact custom-setting preservation; zero network');
