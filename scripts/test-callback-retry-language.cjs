'use strict';
// Synthetic dependencies and extracted shell functions only. No provider,
// credentials, media conversion, source planner, DB, service or SIP calls.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createRequire}=require('node:module'),{spawnSync}=require('node:child_process');
const draft=__dirname,root=process.env.KAZOO_ACCEPTANCE_SOURCE_ROOT||path.resolve(draft,'..');
const actualRequire=createRequire(path.join(root,'scripts/test-fixtures/callback-gemini-reference.cjs'));
const read=name=>fs.readFileSync(path.join(draft,name),'utf8'),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const load=(file,override={})=>{
    const module={exports:{}},filename=path.join(root,'scripts',file);
    new Function('require','module','exports','__filename','__dirname',read(file).replace(/^#![^\n]*\n/, '\n'))(
        name=>Object.hasOwn(override,name)?override[name]:actualRequire(name),module,module.exports,filename,path.dirname(filename));
    return module.exports;
};
const locals=['en-us','he-il','fr-fr','es-es','ar-sa'],raw=Buffer.alloc(40000,29),wav=Buffer.alloc(1200,17),loads=[];
const asset=locale=>({locale,canonical_id:'acdc-callback-success',id:locale+'/acdc-callback-success-gemini-sulafat-'+sha(wav).slice(0,16),
    attachment:'acdc-callback-success-gemini-sulafat-'+sha(wav).slice(0,16)+'.wav',sha256:sha(wav),bytes:wav});
const refs=load('test-fixtures/callback-gemini-reference.cjs',{
    '../import-acdc-gemini-voices.cjs':{loadPlan:(fixed,completion,selected)=>{
        assert.equal(selected.length,1);loads.push(selected[0]);return [asset(selected[0])];}},
    'node:child_process':{spawnSync:(cmd,args,options)=>{
        assert.equal(cmd,'sox');assert.deepEqual(options.input,wav);return {status:0,stdout:raw};}}
});
let groups=0;
for(const locale of locals){
    assert.equal(refs.language(locale),locale);
    const a=refs.assetFor('acdc-callback-success',locale),receipt={schema_version:1,voice_family:'gemini-sulafat',
        document_id:a.id,attachment_name:a.attachment,canonical_prompt_id:a.canonical_id,installed_wav_sha256:a.sha256,
        reference_ulaw_sha256:sha(raw),revision:'2-'+'a'.repeat(32),...(locale==='en-us'?{}:{language:locale})};
    assert.equal(refs.validateReceipt(receipt,sha(raw),locale),'gemini-sulafat');
    assert.throws(()=>refs.validateReceipt(receipt,sha(raw),locals.find(l=>l!==locale)));
    assert.throws(()=>refs.validateReceipt({...receipt,language:'xx-xx'},sha(raw),locale));
    assert.throws(()=>refs.validateReceipt({...receipt,installed_wav_sha256:'0'.repeat(64)},sha(raw),locale));
    assert.throws(()=>refs.validateReceipt(receipt,'0'.repeat(64),locale));
}
assert.deepEqual(loads,locals);assert.equal(refs.assetFor('acdc-callback-success').locale,'en-us');groups++;
for(const bad of ['en-gb','he','AR-SA','en-us\n','',null,{},['en-us']])assert.throws(()=>refs.language(bad));groups++;
const shellQuote=s=>"'"+s.replaceAll("'","'\\''")+"'";
const extract=(file,name)=>{
    const match=read(file).match(new RegExp('^'+name+'\\(\\) \\{\\n[\\s\\S]*?^\\}','m'));
    assert(match,'Missing extracted function '+name);return match[0];
};
const argsFunction=extract('test-acdc-callback-retry.sh','retry_args');
function argsRun(options,verifiedLanguage='en-us',ambientLanguage='ar-sa'){
    const script=`set -Eeuo pipefail
CALLBACK_PREPARE=false CALLBACK_LIVE=false KEEP_FIXTURE=false RETRY_REFERENCE='' RETRY_REGISTRATION_MODE=confirm-current
CALLBACK_TEST_TRANSPORT=external RETRY_LANGUAGE=en-us RETRY_LANGUAGE_EXPLICIT=false RETRY_LANGUAGE_ARGS=() RETRY_EDIT_PENDING_LANGUAGE=false RETRY_SHORT_CONFIRMATION_WINDOW=false
RETRY_ACCOUNT_ID=7807ad61761269a1ccec833dde63f621 RETRY_ACCOUNT_EXPLICIT=false
RETRY_WORKER_LOSS=false RETRY_QUEUE_RESTART=false
retry_script_dir=/synthetic
export KAZOO_CALLBACK_TEST_LANGUAGE=${shellQuote(ambientLanguage)}
die(){ exit 65; }; validate_protected_file(){ :; }; node(){ printf '%s\\n' ${shellQuote(JSON.stringify({voice_family:'gemini-sulafat',language:verifiedLanguage}))}; }
${argsFunction}
retry_args --prepare-only --confirmation-reference ${shellQuote(path.join(root,'scripts/test-acdc-callback-retry.sh'))} ${options.map(shellQuote).join(' ')}
[[ ! \${KAZOO_CALLBACK_TEST_LANGUAGE+x} ]] || exit 66
printf '%s %s\\n' "$RETRY_LANGUAGE" "$RETRY_LANGUAGE_EXPLICIT"
`;
    return spawnSync('bash',['-s'],{input:script,encoding:'utf8'});
}
assert.equal(argsRun([]).stdout.trim(),'en-us false');
for(const ambient of ['he-il','ar-sa','invalid-ambient']){
    const r=argsRun([],'en-us',ambient);assert.equal(r.status,0,r.stderr);assert.equal(r.stdout.trim(),'en-us false');
}
for(const locale of locals){const r=argsRun(['--language',locale],locale);assert.equal(r.status,0,r.stderr);assert.equal(r.stdout.trim(),locale+' true');}
for(const options of [['--language'],['--language','xx-xx'],['--language','he-il','--language','fr-fr']])assert.equal(argsRun(options).status,65);
assert.equal(argsRun(['--language','he-il'],'en-us').status,65);groups++;
assert.equal(argsRun(['--edit-pending-language']).status,65);
assert.equal(argsRun(['--fixture-account','8310dc3170a18de37f205d0da172df65','--language','en-us',
    '--transport','internal','--registration-mode','entry-only','--edit-pending-language']).status,0);
assert.equal(argsRun(['--fixture-account','8310dc3170a18de37f205d0da172df65','--language','en-us',
    '--transport','internal','--registration-mode','entry-only','--edit-pending-language','--edit-pending-language']).status,65);groups++;
const shortArgs=['--fixture-account','8310dc3170a18de37f205d0da172df65','--language','en-us',
    '--transport','internal','--registration-mode','entry-only','--short-confirmation-window'];
const restartArgs=shortArgs.slice(0,-1).concat('--queue-restart-during-backoff');
const workerArgs=shortArgs.slice(0,-1).concat('--worker-loss-during-ringing');
assert.equal(argsRun(workerArgs).status,0);
assert.equal(argsRun(['--worker-loss-during-ringing']).status,65);
for(const extra of ['--worker-loss-during-ringing','--queue-restart-during-backoff','--short-confirmation-window','--edit-pending-language','--confirmation-expiry'])
    assert.equal(argsRun([...workerArgs,extra]).status,65);
groups++;
assert.equal(argsRun(restartArgs).status,0);
assert.equal(argsRun(['--queue-restart-during-backoff']).status,65);
for(const extra of ['--queue-restart-during-backoff','--short-confirmation-window','--edit-pending-language','--confirmation-expiry'])
    assert.equal(argsRun([...restartArgs,extra]).status,65);
groups++;
assert.equal(argsRun(['--short-confirmation-window']).status,65);
assert.equal(argsRun(shortArgs).status,0);
assert.equal(argsRun(['--confirmation-expiry']).status,65);
assert.equal(argsRun([...shortArgs,'--confirmation-expiry']).status,0);
assert.equal(argsRun([...shortArgs,'--confirmation-expiry','--confirmation-expiry']).status,65);
assert.equal(argsRun([...shortArgs,'--short-confirmation-window']).status,65);
assert.equal(argsRun([...shortArgs,'--edit-pending-language']).status,65);
for(const [from,to] of [['en-us','fr-fr'],['internal','external'],['entry-only','confirm-current'],
    ['8310dc3170a18de37f205d0da172df65','7807ad61761269a1ccec833dde63f621']]){
    assert.equal(argsRun(shortArgs.map(value=>value===from?to:value)).status,65);
}groups++;
const configure=extract('test-acdc-callback-fixture.sh','configure_acceptance_queue');
const parse=extract('test-acdc-callback-fixture.sh','parse_fixture_args');
const A='7807ad61761269a1ccec833dde63f621',queue={id:'a'.repeat(32),name:'Acceptance Queue 2000',agents:['b'.repeat(32)],
    custom_operator_setting:{preserved:true},announcements:{language:'es-es',interval:37,position_announcements_enabled:true},callback:{old:true}};
function configureRun(locale,account=A){
    const script=`set -Eeuo pipefail
ACTION=setup-retry ACCEPTANCE_ACCOUNT_ID=${account} FIXTURE_ACCOUNT_ID=${account} ACCEPTANCE_QUEUE_ID=${queue.id}
ACCEPTANCE_CALLER_DEVICE_ID=${'c'.repeat(32)} OUTBOUND_CALLER_ID=+12025550100
FIXTURE_ORIGINAL_QUEUE=${shellQuote(JSON.stringify(queue))} KAZOO_CALLBACK_TEST_LANGUAGE=${shellQuote(locale)}
fixture_die(){ exit 65; }; save_fixture_state(){ :; }
api_request(){ if [[ $1 == GET ]]; then printf '%s\\n' ${shellQuote(JSON.stringify({data:queue}))}; else printf '%s\\n' "$3" >&3; fi; }
${configure}
configure_acceptance_queue 3>&1
`;
    return spawnSync('bash',['-s'],{input:script,encoding:'utf8'});
}
const baseline=configureRun('');assert.equal(baseline.status,0,baseline.stderr);const base=JSON.parse(baseline.stdout).data;
assert.deepEqual(base.announcements,queue.announcements);assert.deepEqual(base.agents,queue.agents);
for(const locale of locals){
    const r=configureRun(locale);assert.equal(r.status,0,r.stderr);const got=JSON.parse(r.stdout).data;
    assert.deepEqual(got,{...base,announcements:{...base.announcements,language:locale}});
    assert.equal(got.callback.max_attempts,2);assert.equal(got.callback.retry_delay,15);
    assert.equal(got.callback.media,undefined);
}
const wrong=configureRun('he-il','d'.repeat(32));assert.equal(wrong.status,65);assert.equal(wrong.stdout,'');groups++;
const verify=extract('test-acdc-callback-fixture.sh','verify_fixture');
function verifyRun(locale,installed){
    const resource={data:{name:'Kazoo Callback Carrier '+A.slice(0,8),kazoo_acceptance_fixture:'synthetic-marker',enabled:true,
        rules:['^\\+120255501[0-9]{2}$'],gateways:[{server:'127.0.0.30',port:16060}]}};
    const script=`set -Eeuo pipefail
ACCEPTANCE_ACCOUNT_ID=${A} FIXTURE_ACCOUNT_ID=${A} FIXTURE_RESOURCE_ID=${'d'.repeat(32)} FIXTURE_ORIGINAL_QUEUE=present
ACCEPTANCE_QUEUE_ID=${queue.id} ACCEPTANCE_CALLER_DEVICE_ID=${'c'.repeat(32)} OUTBOUND_CALLER_ID=+12025550100
ENCODED_CALLBACK_NUMBER=one CALLBACK_NUMBER=+12025550101 ENCODED_OUTBOUND_CALLER_ID=two
FIXTURE_MARKER=synthetic-marker CARRIER_IP=127.0.0.30 CARRIER_PORT=16060 KAZOO_CALLBACK_TEST_LANGUAGE=${shellQuote(locale)}
fixture_die(){ exit 65; }; fixture_log(){ :; }
api_request(){ case $2 in
*/resources/*) printf '%s\\n' ${shellQuote(JSON.stringify(resource))} ;;
*/phone_numbers/one) printf '%s\\n' '{"data":{"id":"+12025550101","state":"in_service","kazoo_acceptance_fixture":"synthetic-marker"}}' ;;
*/phone_numbers/two) printf '%s\\n' '{"data":{"id":"+12025550100","state":"in_service","kazoo_acceptance_fixture":"synthetic-marker"}}' ;;
*/queues/*) printf '%s\\n' ${shellQuote(JSON.stringify({data:installed}))} ;;
*) exit 66 ;; esac; }
${verify}
verify_fixture
`;
    return spawnSync('bash',['-s'],{input:script,encoding:'utf8'});
}
for(const locale of locals){const installed={...base,announcements:{...base.announcements,language:locale}};
    const ok=verifyRun(locale,installed);assert.equal(ok.status,0,ok.stderr);
    assert.equal(verifyRun(locals.find(l=>l!==locale),installed).status,65);
    assert.equal(verifyRun(locale,{...installed,callback:{...installed.callback,media:{success:'custom'}}}).status,65);
}groups++;
for(const [value,action] of [['xx-xx','setup-retry'],['he-il','setup'],['he-il','cleanup']]){
    const r=spawnSync('bash',['-s'],{input:`set -Eeuo pipefail\nKAZOO_CALLBACK_TEST_LANGUAGE=${shellQuote(value)}\nfixture_die(){ exit 65; }; fixture_usage(){ :; }\n${parse}\nparse_fixture_args ${action}\n`,encoding:'utf8'});
    assert.equal(r.status,65);
}groups++;
const retry=load('test-fixtures/assert-callback-retry.cjs',{'./callback-gemini-reference.cjs':refs});
const scenarios=actualRequire('./create-callback-retry-scenarios.cjs'),mode='confirm-current',receipt=scenarios.modeReceipt(mode);
const audio={result:'PASS',registration_mode:mode,expected_registration_digits:scenarios.expectedDigits(mode),observed_registration_digits:scenarios.expectedDigits(mode)};
const policy={registration_mode:mode,account_id:A,entry_key:'6',allow_alternate_number:false,fixture_verified:true};
retry.registrationModeProof(mode,receipt,policy,audio);
for(const locale of locals){retry.registrationModeProof(mode,receipt,{...policy,language:locale},audio,locale);
    assert.throws(()=>retry.registrationModeProof(mode,receipt,policy,audio,locale));
    assert.throws(()=>retry.registrationModeProof(mode,receipt,{...policy,language:'wrong'},audio,locale));}
groups++;
const retrySource=read('test-acdc-callback-retry.sh'),fixtureSource=read('test-acdc-callback-fixture.sh');
for(const gate of ['--keep-fixture is mandatory','flock -n','retry_busy_pair','retry_clear_busy','retry_wait_backoff','retry_wait_bridge','retry-service-after.txt'])assert(retrySource.includes(gate));
assert(fixtureSource.indexOf('Explicit language is confined to the isolated retry account before fixture writes')<fixtureSource.indexOf('    FIXTURE_STAGE=setup-scope'));
assert(retrySource.includes('KAZOO_CALLBACK_TEST_LANGUAGE=$RETRY_LANGUAGE KAZOO_CALLBACK_TEST_ALTERNATE_NUMBER=$alternate callback_fixture verify'));groups++;
const interfaces={eth1:[{family:'IPv4',address:'10.1.0.44'}],empty:undefined};
assert.equal(refs.localMediaHost('localhost',{}),'127.0.0.1');
assert.equal(refs.localMediaHost('127.0.0.1',{}),'127.0.0.1');
assert.equal(refs.localMediaHost('10.1.0.44',interfaces),'10.1.0.44');
for(const bad of ['10.1.0.10','couchdb.internal','10.1.0.44:5984','10.1.0.44\n',undefined])
    assert.throws(()=>refs.localMediaHost(bad,interfaces));
assert.throws(()=>refs.localMediaHost('10.1.0.44',{eth1:[{family:'IPv6',address:'10.1.0.44'}]}));groups++;
const writeCarrier=extract('test-acdc-callback-calls.sh','write_returned_carrier_csv');
const csvDir=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'callback-carrier-csv-test.'));
const csvFile=path.join(csvDir,'synthetic.csv');
function carrierCsv(options){
    if(fs.existsSync(csvFile))fs.unlinkSync(csvFile);
    const result=spawnSync('bash',['-s'],{encoding:'utf8',input:`set -Eeuo pipefail
CALLBACK_NUMBER=1001 CALLBACK_CARRIER_CONFIRM_DELAY_MS=8000 CALLBACK_BRIDGE_HOLD_MS=100000
die(){ exit 65; }
${writeCarrier}
write_returned_carrier_csv ${shellQuote(csvFile)} ${options.map(shellQuote).join(' ')}
`});
    if(result.status===0){assert.equal(fs.statSync(csvFile).mode&511,384);result.csv=fs.readFileSync(csvFile,'utf8');}
    else assert(!fs.existsSync(csvFile));
    return result;
}
try{
assert.equal(carrierCsv([]).csv,'SEQUENTIAL\n1001;8000;100000\n');
assert.equal(carrierCsv(['6000']).csv,'SEQUENTIAL\n1001;6000;100000\n');
for(const options of [['3000'],['6000','extra'],['invalid']]){
    const rejected=carrierCsv(options);assert.equal(rejected.status,65);assert.equal(rejected.stdout,'');
}groups++;
}finally{if(fs.existsSync(csvFile))fs.unlinkSync(csvFile);fs.rmdirSync(csvDir);}
console.log('PASS '+groups+' synthetic callback retry locale/reference/configuration groups; no live acceptance claim');
