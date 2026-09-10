#!/usr/bin/env node
'use strict';
// Opt-in owned media15 process-restart acceptance, run under the host lab lock.
// Never imported-company calls, a production node, or a cluster coordinator.
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const HELPER='/usr/local/libexec/kazoo5-maintenance-media',CLI='/usr/local/freeswitch/bin/fs_cli';
const MARKER='/etc/kazoo5-maintenance/media.closed',STATE='/var/lib/kazoo5-maintenance/media';
const UNIT='kazoo-freeswitch.service';
function run(bin,args){return cp.execFileSync(bin,args,{encoding:'utf8',timeout:90000,maxBuffer:65536,stdio:['ignore','pipe','pipe']}).trim();}
function ctl(...args){return run('/usr/bin/systemctl',args);}
function cli(command){return run(CLI,['-H','127.0.0.1','-P','8021','-x',command]);}
function helper(...args){return JSON.parse(run('/usr/bin/node',[HELPER,...args]));}
function empty(p,state){assert.equal(p.state,state);assert.equal(p.native.admission,state);assert.equal(p.native.sessions,0);return p;}
function changed(before,after){
    assert.notDeepEqual(before.native.process,after.native.process,'Media process did not restart');
    assert.notEqual(before.native.core_uuid,after.native.core_uuid,'Media core did not restart');
}
function probeCommand(id,generation){
    assert(typeof id==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(id));
    assert(typeof generation==='string'&&/^[a-f0-9]{32}$/.test(generation));
    return `originate {origination_uuid=${id},kazoo_maintenance_test=${generation},originate_timeout=3}null/kazoo-maintenance &park()`;
}
async function until(fn,seconds=60){
    const end=Date.now()+seconds*1000;
    while(Date.now()<end){try{const value=fn();if(value)return value;}catch(_){/* Unknown never satisfies readiness. */}
        await new Promise(r=>setTimeout(r,250));}
    throw Error('Native observation deadline');
}
async function main(){
    assert.deepEqual(process.argv.slice(2),['--live']);assert.equal(process.getuid(),0);
    assert.equal(os.hostname(),'kz5-stage-freeswitch');
    assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='172.30.253.15'));
    assert.equal(fs.readFileSync('/proc/1/comm','utf8').trim(),'systemd');
    assert(!fs.existsSync(STATE+'/active.json')&&!fs.existsSync(STATE+'/releasing.json')&&!fs.existsSync(MARKER));
    const before=empty(helper('--status'),'open');
    assert.equal(cli('fsctl pause_check inbound'),'false');assert.equal(cli('fsctl pause_check outbound'),'false');
    const hook=ctl('show',UNIT,'-p','ExecStartPre','--value');
    assert(hook.includes(HELPER+' --boot-guard'),'Normal installed boot guard missing');
    const dir=fs.mkdtempSync('/var/lib/kazoo-stage/media-restart-');fs.chmodSync(dir,0o700);
    const generation=crypto.randomBytes(16).toString('hex');
    const spec={schema_version:1,generation,manifest_sha256:crypto.createHash('sha256').update(hook).digest('hex')};
    const receipt={schema_version:1,status:'RUNNING',phase:'admitted',generation,before,probes:[],restarts:[],
        fixture_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),
        helper_sha256:crypto.createHash('sha256').update(fs.readFileSync(HELPER)).digest('hex'),
        complete_cluster_fence_proven:false};
    function persist(){
        const fd=fs.openSync(dir+'/receipt.tmp','wx',0o600);
        try{fs.writeFileSync(fd,JSON.stringify(receipt)+'\n');fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
        fs.renameSync(dir+'/receipt.tmp',dir+'/receipt.json');
        const d=fs.openSync(dir,fs.constants.O_RDONLY|fs.constants.O_DIRECTORY);try{fs.fsyncSync(d);}finally{fs.closeSync(d);}
    }
    function phase(value){receipt.phase=value;persist();}
    async function cleanupProbes(){for(const p of receipt.probes){
        if(cli('uuid_exists '+p.id)==='false')continue;
        assert.equal(cli('uuid_getvar '+p.id+' kazoo_maintenance_test'),generation,'Unowned probe');
        assert(cli('uuid_kill '+p.id+' NORMAL_CLEARING').startsWith('+OK'));
        await until(()=>cli('uuid_exists '+p.id)==='false',5);
    }}
    async function probe(expect){
        const p={id:crypto.randomUUID(),expected:expect};receipt.probes.push(p);persist();
        const out=cli(probeCommand(p.id,generation));
        if(expect==='open'){
            assert.equal(out,'+OK '+p.id);assert.equal(cli('uuid_getvar '+p.id+' kazoo_maintenance_test'),generation);
            const call=JSON.parse(cli('uuid_dump '+p.id+' json'));assert.equal(call['Unique-ID'],p.id);
            assert(Number(call['Caller-Channel-Answered-Time']||0)>0);p.answered=true;
        }else{assert(out.startsWith('-ERR '));assert.equal(cli('uuid_exists '+p.id),'false');p.rejected=true;}
        await cleanupProbes();p.verified=true;persist();
    }
    let closeDispatched=false,pauseDispatched=false,pass=false;
    persist();
    try{
        phase('positive_before');await probe('open');empty(helper('--status'),'open');
        fs.writeFileSync(dir+'/spec.json',JSON.stringify(spec)+'\n',{mode:0o600,flag:'wx'});
        phase('closing');closeDispatched=true;empty(helper('--close',dir+'/spec.json'),'closed');
        phase('restart_with_marker');ctl('restart',UNIT);
        let after=await until(()=>empty(helper('--verify',generation),'closed'));
        changed(before,after);await probe('closed');receipt.restarts.push({kind:'marker_retained',observation:after});persist();
        phase('restart_with_marker_loss');ctl('stop',UNIT);assert.equal(ctl('show',UNIT,'-p','MainPID','--value'),'0');
        assert.deepEqual(JSON.parse(fs.readFileSync(MARKER)),spec);
        // Recoverable simulated loss: only this exact generation, while stopped.
        fs.renameSync(MARKER,dir+'/retained-marker.json');
        ctl('start',UNIT);const restored=await until(()=>empty(helper('--verify',generation),'closed'));
        changed(after,restored);assert.deepEqual(JSON.parse(fs.readFileSync(MARKER)),spec);
        await probe('closed');receipt.restarts.push({kind:'marker_restored_by_boot_guard',observation:restored});persist();
        phase('operator_pause_preservation');pauseDispatched=true;cli('fsctl pause inbound');
        assert.equal(cli('fsctl pause_check inbound'),'true');assert.equal(cli('fsctl pause_check outbound'),'false');
        phase('releasing');empty(helper('--release',generation),'open');closeDispatched=false;
        assert.equal(cli('fsctl pause_check inbound'),'true');assert.equal(cli('fsctl pause_check outbound'),'false');
        receipt.operator_pause_preserved=true;cli('fsctl resume inbound');pauseDispatched=false;
        phase('positive_after');await probe('open');empty(helper('--status'),'open');pass=true;
    }catch(_){receipt.failed_phase=receipt.phase;}
    finally{
        phase('scoped_cleanup');
        try{
            // A process interrupted during restart is started through its normal
            // guard. Never remove intent to make startup succeed.
            if(ctl('show',UNIT,'-p','MainPID','--value')==='0')ctl('start',UNIT);
            await until(()=>helper('--status'));await cleanupProbes();
            if(closeDispatched){empty(helper('--release',generation),'open');closeDispatched=false;}
            if(pauseDispatched){cli('fsctl resume inbound');pauseDispatched=false;}
            assert.equal(cli('fsctl pause_check inbound'),'false');assert.equal(cli('fsctl pause_check outbound'),'false');
            receipt.final=empty(helper('--status'),'open');receipt.scoped_cleanup_verified=true;
        }catch(_){receipt.scoped_cleanup_verified=false;}
        receipt.status=pass&&receipt.scoped_cleanup_verified?'PASS':'FAIL';receipt.phase='finished';persist();
        console.log(JSON.stringify({status:receipt.status,receipt:dir+'/receipt.json',failed_phase:receipt.failed_phase,
            restarts:receipt.restarts.length,cleanup_verified:receipt.scoped_cleanup_verified}));
    }
    assert.equal(receipt.status,'PASS');
}
module.exports={empty,changed,probeCommand};
function hostMain(){
    assert.deepEqual(process.argv.slice(2),['--distributed','--live']);assert.equal(process.getuid(),0);
    assert.equal(os.hostname(),'dev-testing');
    assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'));
    const dir='/var/lib/kazoo5-install-lab',lock='/etc/kazoo/monitor-acceptance.lock';
    for(const file of [lock,dir+'/lab.json']){
        const s=fs.lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&s.nlink===1&&(s.mode&511)===384);
    }
    const lockfd=fs.openSync(lock,fs.constants.O_RDWR|fs.constants.O_NOFOLLOW);
    try{
        assert.equal(cp.spawnSync('/usr/bin/flock',['-n','3'],{stdio:['ignore','pipe','pipe',lockfd]}).status,0);
        const s=JSON.parse(fs.readFileSync(dir+'/lab.json'));assert.equal(s.owner,'distributed-install-v1');
        assert(!fs.existsSync('/etc/kazoo/distributed-monitor-acceptance.json'));
        const pod=(...args)=>run('/usr/bin/podman',args),m=s.roles.freeswitch;
        for(const [r,role,ip,status] of [[m,'freeswitch','172.30.253.15','installed-service-verified'],
            [s.roles['kazoo-apps'],'kazoo-apps','172.30.253.14','installed-service-verified'],
            [s.peer,'kazoo-apps-peer','172.30.253.20','installed'],
            [s.roles.couchdb,'couchdb','172.30.253.11','installed-service-verified']]){
            assert.equal(r.phase,status);assert(!r.installUnit);
            if(role!=='couchdb')assert.equal(r.source,r.installedSource);
            if(r.unit){
                assert.equal(ctl('show',r.unit,'-p','SubState','--value'),'exited');
                assert.equal(ctl('show',r.unit,'-p','ExecMainStatus','--value'),'0');
            }
            const c=JSON.parse(pod('inspect',r.id))[0];
            assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
            assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
            assert(c.State.Running&&!c.State.Paused&&!c.HostConfig.Privileged);
            assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);
            assert.equal(Object.keys(c.NetworkSettings.Networks).length,1);
        }
        const account='45e827067baf078029d0ca16a489fa8a';
        for(const [r,ip] of [[s.roles['kazoo-apps'],'172.30.253.14'],[s.peer,'172.30.253.20']]){
            const inventory=JSON.parse(pod('exec',r.id,'escript','/var/lib/kazoo-stage/maintenance-snapshot.escript','--snapshot',ip));
            assert.equal(inventory.schema_version,2);assert.equal(inventory.agents.length,3);
            assert(inventory.agents.every(a=>a.account_id===account&&a.state==='ready'));
        }
        assert(/^[a-f0-9]+$/.test(s.secrets.couch));
        const db=encodeURIComponent('account/'+account.slice(0,2)+'/'+account.slice(2,4)+'/'+account.slice(4));
        const cfg='url = "http://172.30.253.11:5984/'+db+'/_design/acdc_callbacks/_view/by_queue?reduce=false&limit=1"\nuser = "admin:'+s.secrets.couch+'"\n';
        const tickets=JSON.parse(cp.execFileSync('/usr/bin/podman',['exec','-i',s.roles.couchdb.id,'curl','--fail','--silent','--show-error','--max-time','15','--config','-'],
            {input:cfg,encoding:'utf8',timeout:20000,stdio:['pipe','pipe','pipe']}));
        assert.deepEqual(tickets.rows,[]);
        empty(JSON.parse(pod('exec',m.id,'node',HELPER,'--status')),'open');
        const hash=crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex');
        const guest='/var/lib/kazoo-stage/media-restart-'+hash+'.cjs';
        assert.equal(pod('exec',m.id,'test','!','-e',guest),'');
        pod('cp',__filename,m.id+':'+guest);pod('exec',m.id,'chmod','0600',guest);
        const stem=dir+'/media-restart-'+Date.now(),fd=fs.openSync(stem+'.log','wx',0o600);
        let child;try{child=cp.spawnSync('/usr/bin/podman',['exec',m.id,'node',guest,'--live'],{timeout:360000,stdio:['ignore',fd,fd]});}
        finally{fs.closeSync(fd);}
        const rows=fs.readFileSync(stem+'.log','utf8').split('\n').filter(l=>l.startsWith('{')).map(l=>JSON.parse(l));
        const last=rows.at(-1);let receipt=null;
        if(last&&/^\/var\/lib\/kazoo-stage\/media-restart-[A-Za-z0-9]+\/receipt\.json$/.test(last.receipt))
            receipt=JSON.parse(pod('exec',m.id,'cat',last.receipt));
        const passed=child.status===0&&!child.error&&receipt?.status==='PASS'&&receipt.scoped_cleanup_verified===true;
        fs.writeFileSync(stem+'.json',JSON.stringify({status:passed?'PASS':'FAIL',source:m.installedSource,fixture_sha256:hash,
            native_exit:child.status,guest_receipt:last?.receipt,native:receipt})+'\n',{mode:0o600,flag:'wx'});
        console.log(JSON.stringify({status:passed?'PASS':'FAIL',receipt:stem+'.json'}));assert(passed);
    }finally{fs.closeSync(lockfd);}
}
if(require.main===module)Promise.resolve().then(()=>process.argv[2]==='--distributed'?hostMain():main())
    .catch(_=>{console.error('NATIVE_MEDIA_RESTART_REFUSED_OR_FAILED');process.exitCode=1;});
