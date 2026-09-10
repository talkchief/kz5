#!/usr/bin/env node
'use strict';
// Exact development fixture: run the existing real ACDC capacity campaign,
// adding native media-version/process observations, not a substitute workload.
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const ROOT='/opt/kz5',HELPER='/usr/local/libexec/kazoo5-maintenance-media';
const ACCOUNT='8310dc3170a18de37f205d0da172df65';
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function native(value,before,empty=false) {
    assert.equal(value.state,'open');assert.equal(value.native.admission,'open');
    assert(Number.isSafeInteger(value.native.sessions)&&value.native.sessions>=0);
    assert(/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value.native.core_uuid));
    assert(Number.isSafeInteger(value.native.process.pid)&&value.native.process.pid>0);
    assert(/^[0-9]+$/.test(value.native.process.start_ticks));
    assert(/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value.native.process.boot_id));
    if(before){assert.deepEqual(value.native.process,before.native.process);assert.equal(value.native.core_uuid,before.native.core_uuid);}
    if(empty)assert.equal(value.native.sessions,0);
    return value;
}
function summary(text) {
    const rows=text.trim().split('\n').map(r=>r.split('\t'));
    assert.equal(rows.length,2);assert.equal(rows[0].length,11);assert.equal(rows[1].length,11);
    assert.deepEqual(rows[0],['stage','answered_target/total_calls','caller_success','caller_failed','agent_success','agent_failed','peak_cpu_pct','min_mem_available_kb','error_logs','new_cores','verified_concurrent_hold_s']);
    const [stage,target,cs,cf,as,af,cpu,mem,errors,cores,hold]=rows[1];
    assert.equal(stage,'answered-30');assert.equal(target,'30/30');
    assert.equal(cs,'30');assert.equal(as,'30');assert.equal(cf,'0');assert.equal(af,'0');
    assert.equal(errors,'0/0');assert.equal(cores,'0');assert.equal(hold,'1800');
    assert(/^\d+(\.\d+)?$/.test(cpu)&&Number(cpu)<=100);
    assert(/^[0-9]+$/.test(mem)&&Number(mem)>=512*1024);
    return {concurrent_calls:30,verified_hold_seconds:1800,caller_success:30,agent_success:30,
        failures:0,error_logs:0,new_cores:0,peak_cpu_percent:Number(cpu),minimum_available_kib:Number(mem)};
}
function privateText(file){const s=fs.lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&s.nlink===1&&(s.mode&511)===384);return fs.readFileSync(file,'utf8');}
function values(file){const result={};for(const line of privateText(file).split('\n')){
    if(!line||line.startsWith('#'))continue;const i=line.indexOf('='),key=line.slice(0,i),encoded=line.slice(i+1);
    assert(i>0&&/^[A-Z][A-Z0-9_]+$/.test(key)&&!Object.hasOwn(result,key)&&/^[A-Za-z0-9+/]*={0,2}$/.test(encoded));
    result[key]=Buffer.from(encoded,'base64').toString();
}return result;}
const run=(bin,args)=>cp.execFileSync(bin,args,{encoding:'utf8',timeout:30000,maxBuffer:1024*1024,stdio:['ignore','pipe','pipe']}).trim();
async function main(){
    assert.deepEqual(process.argv.slice(2),['--live']);assert.equal(process.getuid(),0);
    const config=values('/etc/kazoo/deployment.env');
    require('./test-fixtures/main-dev-monitor-profile.cjs').validate(os.hostname(),Object.values(os.networkInterfaces()).flat().map(n=>n.address),config,'0'.repeat(32));
    const state=values('/etc/kazoo/acceptance-secrets.env');
    require('./test-channel-monitor-live.cjs').baseState(privateText('/etc/kazoo/acceptance-secrets.env'));
    assert.equal(state.ACCEPTANCE_ACCOUNT_ID,ACCOUNT);assert.equal(state.ACCEPTANCE_AGENT_COUNT,'30');assert.equal(state.ACCEPTANCE_SIP_PROXY_HOST,'10.1.0.44');
    assert.equal(fs.realpathSync(ROOT),ROOT);run('git',['-C',ROOT,'diff','--quiet']);run('git',['-C',ROOT,'diff','--cached','--quiet']);
    assert(!fs.existsSync('/etc/kazoo/monitor-acceptance.json')&&!fs.existsSync('/etc/kazoo/distributed-monitor-acceptance.json'));
    privateText('/etc/kazoo/monitor-acceptance.lock');
    const lock=fs.openSync('/etc/kazoo/monitor-acceptance.lock',fs.constants.O_RDWR|fs.constants.O_NOFOLLOW);
    let child,finished=false;
    try{
        assert.equal(cp.spawnSync('/usr/bin/flock',['-n','3'],{stdio:['ignore','pipe','pipe',lock]}).status,0);
        assert.equal(sha(HELPER),sha(ROOT+'/scripts/kazoo-maintenance-media.cjs'));
        assert(fs.readFileSync('/usr/local/share/kazoo5-installer/freeswitch-build','utf8').includes('durable-media-admission-v1'));
        const observe=()=>JSON.parse(run('/usr/bin/node',[HELPER,'--status']));
        const before=native(observe(),null,true);
        const inventory=()=>JSON.parse(run('escript',['/usr/local/libexec/kazoo5-maintenance-snapshot','--snapshot','10.1.0.44']));
        const agents=inventory();assert(agents.all_agent_workers_observed);assert.equal(agents.agents.length,0);
        const root=fs.mkdtempSync('/var/log/kazoo-main-media-soak-');fs.chmodSync(root,0o700);
        const configHash=sha('/etc/kazoo/deployment.env'),binary=fs.realpathSync('/usr/local/freeswitch/lib/libfreeswitch.so.1'),binaryHash=sha(binary);
        const receipt={status:'RUNNING',phase:'admitted',runner_source:run('git',['-C',ROOT,'rev-parse','HEAD']),
            harness_sha256:sha(__filename),call_harness_sha256:sha(ROOT+'/scripts/test-kazoo-calls.sh'),
            media_binary_sha256:binaryHash,media_build_fingerprint_sha256:sha('/usr/local/share/kazoo5-installer/freeswitch-build'),
            before,samples:[],full_cluster_upgrade_proven:false};
        const save=()=>{const fd=fs.openSync(root+'/receipt.tmp','wx',0o600);try{fs.writeFileSync(fd,JSON.stringify(receipt)+'\n');fs.fsyncSync(fd);}finally{fs.closeSync(fd);}fs.renameSync(root+'/receipt.tmp',root+'/receipt.json');};
        save();console.log(JSON.stringify({status:'RUNNING',receipt:root+'/receipt.json'}));
        try{
            const env={...process.env};for(const key of Object.keys(env))if(/^(KAZOO_|ACCEPTANCE_)/.test(key))delete env[key];
            const output=fs.openSync(root+'/calls.log','wx',0o600);
            // Keep the same locked open-file description in the call process,
            // so an interrupted observer cannot admit overlapping acceptance.
            try{child=cp.spawn('/usr/bin/bash',[ROOT+'/scripts/test-kazoo-calls.sh','--live','--stress','--stages','30','--queued-excess','0','--soak-seconds','1800','--no-install-deps','--run-root',root+'/calls'],{cwd:ROOT,env,stdio:['ignore',output,output,lock]});}
            finally{fs.closeSync(output);}
            let code,error;const exited=new Promise(resolve=>{child.on('error',e=>{error=e;finished=true;resolve()});child.on('exit',c=>{code=c;finished=true;resolve()})});
            receipt.phase='real_acdc_soak';save();
            while(!finished){const current=native(observe(),before);receipt.samples.push({time:Date.now(),sessions:current.native.sessions});save();await Promise.race([exited,new Promise(r=>setTimeout(r,5000))]);}
            assert(!error&&code===0,'Real call campaign failed; inspect protected calls.log');
            const dirs=fs.readdirSync(root+'/calls');assert.equal(dirs.length,1);
            receipt.capacity=summary(fs.readFileSync(root+'/calls/'+dirs[0]+'/summary.tsv','utf8'));
            assert(receipt.samples.some(s=>s.sessions>=60),'No native 30-call media allocation observation');
            receipt.after=native(observe(),before,true);assert.equal(sha(binary),binaryHash);assert.equal(sha('/etc/kazoo/deployment.env'),configHash);
            assert.equal(sha(ROOT+'/scripts/test-kazoo-calls.sh'),receipt.call_harness_sha256);
            assert.equal(sha('/usr/local/share/kazoo5-installer/freeswitch-build'),receipt.media_build_fingerprint_sha256);
            const afterAgents=inventory();assert(afterAgents.all_agent_workers_observed);assert.equal(afterAgents.agents.length,0);
            receipt.agent_cleanup_verified=true;receipt.status='PASS';receipt.phase='finished';save();
        }catch(_){receipt.status='FAIL';receipt.failed_phase=receipt.phase;save();throw Error('Native media soak failed; inspect protected receipt');}
        console.log(JSON.stringify({status:receipt.status,receipt:root+'/receipt.json',capacity:receipt.capacity,native_samples:receipt.samples.length}));
    }finally{
        if(child&&!finished){
            child.kill('SIGTERM');
            await new Promise(resolve=>{const timer=setTimeout(()=>{child.kill('SIGKILL');resolve();},180000);child.once('exit',()=>{clearTimeout(timer);resolve();});});
        }
        fs.closeSync(lock);
    }
}
module.exports={native,summary};
if(require.main===module)main().catch(()=>{console.error('MAIN_MEDIA_SOAK_REFUSED_OR_FAILED; inspect protected receipt');process.exitCode=1;});
