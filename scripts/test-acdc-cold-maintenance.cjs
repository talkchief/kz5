#!/usr/bin/env node
'use strict';
// Exact private dev44 fixture: durable agent checkpoints across full apps VMs.
// NOT proof of full cluster producer/broker drain or an upgrade coordinator.
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os'),path=require('node:path');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const HELPER_FILES=Object.freeze(['install-kazoo5.sh','kazoo-maintenance-fence.cjs',
    'kazoo-maintenance-snapshot.escript','kazoo-maintenance-queues.escript',
    'kazoo-maintenance-restore.escript','kazoo-maintenance-callbacks.cjs']);
const DIR='/var/lib/kazoo5-install-lab',LOCK='/etc/kazoo/monitor-acceptance.lock';
const A='45e827067baf078029d0ca16a489fa8a',Q='cabcfb72812b530ccc32ffba30ef680d';
const FENCE='/usr/local/libexec/kazoo5-maintenance-fence',MEDIA='/usr/local/libexec/kazoo5-maintenance-media';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function run(bin,args,input){return cp.execFileSync(bin,args,{encoding:'utf8',input,timeout:180000,maxBuffer:4*1024*1024,stdio:['pipe','pipe','pipe']}).trim();}
const pod=(...args)=>run('/usr/bin/podman',args);
function owned(s,r,role,ip,phase){
    assert.equal(s.owner,'distributed-install-v1');assert.equal(r.phase,phase);assert(!r.installUnit);
    if(role!=='couchdb')assert.equal(r.source,r.installedSource);
    const x=JSON.parse(pod('inspect',r.id))[0];assert.equal(x.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
    assert.equal(x.Config.Labels['io.talkchief.kazoo.role'],role);assert(x.State.Running&&!x.State.Paused&&!x.HostConfig.Privileged);
    assert.equal(x.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);assert.equal(Object.keys(x.NetworkSettings.Networks).length,1);
}
function privateRead(file){const st=fs.lstatSync(file);assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);return fs.readFileSync(file);}
async function until(fn,seconds=120){const end=Date.now()+seconds*1000;while(Date.now()<end){try{const x=fn();if(x)return x;}catch(_){/* Unknown is not ready. */}await new Promise(r=>setTimeout(r,1000));}throw Error('Cold fixture readiness timeout');}
function request(snapshot,generation,agents=snapshot.agents){
    const revisions=new Map(snapshot.document_revisions.map(d=>[d.account_id+'/'+d.agent_id,d.revision]));
    return {schema_version:1,generation,node:snapshot.node,expected_epoch:snapshot.epoch,
        agents:agents.map(a=>({account_id:a.account_id,agent_id:a.agent_id,state:a.state,
            pause_until_unix_ms:a.pause_until_unix_ms,queues:a.queues,
            document_revision:revisions.get(a.account_id+'/'+a.agent_id)}))};
}
function matches(actual,saved){
    assert.equal(actual.agents.length,3);assert.equal(saved.agents.length,3);
    for(const a of saved.agents){const b=actual.agents.find(x=>x.agent_id===a.agent_id&&x.account_id===a.account_id);assert(b);
        assert.deepEqual([...b.queues].sort(),[...a.queues].sort());
        if(a.state==='paused'&&a.pause_until_unix_ms!=='infinity'&&a.pause_until_unix_ms<=Date.now())assert.equal(b.state,'ready');
        else{assert.equal(b.state,a.state);if(a.pause_until_unix_ms==='infinity')assert.equal(b.pause_until_unix_ms,'infinity');
            else if(a.state==='paused'){assert(b.pause_until_unix_ms<=a.pause_until_unix_ms);assert(b.pause_until_unix_ms>=a.pause_until_unix_ms-20);}}
    }
    const revisions=s=>[...s.document_revisions].sort((a,b)=>(a.account_id+'/'+a.agent_id).localeCompare(b.account_id+'/'+b.agent_id));
    assert.deepEqual(revisions(actual),revisions(saved));
}
async function main(){
    assert.deepEqual(process.argv.slice(2),['--live']);assert.equal(process.getuid(),0);assert.equal(os.hostname(),'dev-testing');
    assert(Object.values(os.networkInterfaces()).flat().some(i=>i.address==='10.1.0.44'));
    privateRead(LOCK);const lock=fs.openSync(LOCK,fs.constants.O_RDWR|fs.constants.O_NOFOLLOW);
    try{
        assert.equal(cp.spawnSync('/usr/bin/flock',['-n','3'],{stdio:['ignore','pipe','pipe',lock]}).status,0);
        assert(!fs.existsSync('/etc/kazoo/distributed-monitor-acceptance.json'));
        const s=JSON.parse(privateRead(DIR+'/lab.json')),nodes=[{...s.roles['kazoo-apps'],ip:'172.30.253.14'}, {...s.peer,ip:'172.30.253.20'}],m=s.roles.freeswitch;
        owned(s,nodes[0],'kazoo-apps',nodes[0].ip,'installed-service-verified');owned(s,nodes[1],'kazoo-apps-peer',nodes[1].ip,'installed');
        owned(s,m,'freeswitch','172.30.253.15','installed-service-verified');owned(s,s.roles.couchdb,'couchdb','172.30.253.11','installed-service-verified');
        assert.equal(nodes[0].installedSource,nodes[1].installedSource);
        const native=()=>JSON.parse(pod('exec',m.id,'node',MEDIA,'--status'));
        assert.equal(native().state,'open');assert.equal(native().native.sessions,0);
        for(const n of nodes)assert.equal(JSON.parse(pod('exec',n.id,'node',FENCE,'--status')).state,'open');
        assert(/^[a-f0-9]+$/.test(s.secrets.couch));
        const db=encodeURIComponent('account/'+A.slice(0,2)+'/'+A.slice(2,4)+'/'+A.slice(4));
        const cfg='url = "http://172.30.253.11:5984/'+db+'/_design/acdc_callbacks/_view/by_queue?reduce=false&limit=1"\nuser = "admin:'+s.secrets.couch+'"\n';
        assert.deepEqual(JSON.parse(run('/usr/bin/podman',['exec','-i',s.roles.couchdb.id,'curl','--fail','--silent','--show-error','--max-time','15','--config','-'],cfg)).rows,[]);
        const root=fs.mkdtempSync(DIR+'/cold-agent-state-');fs.chmodSync(root,0o700);
        const generation=crypto.randomBytes(16).toString('hex'),guest='/var/lib/kazoo-stage/cold-state-'+generation;
        const receipt={schema_version:1,status:'RUNNING',phase:'admitted',generation,source:nodes[0].installedSource,
            fixture_sha256:sha(fs.readFileSync(__filename)),complete_cluster_drain_proven:false,coordinated_upgrade_proven:false};
        function save(name,value){const file=root+'/'+name,fd=fs.openSync(file+'.tmp','wx',0o600);try{fs.writeFileSync(fd,JSON.stringify(value)+'\n');fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
            fs.renameSync(file+'.tmp',file);const d=fs.openSync(root,fs.constants.O_RDONLY|fs.constants.O_DIRECTORY);try{fs.fsyncSync(d);}finally{fs.closeSync(d);}return file;}
        const phase=p=>{receipt.phase=p;save('receipt.json',receipt);};
        const copy=(n,file,name)=>pod('cp',file,n.id+':'+guest+'/'+name);
        const fence=(n,...args)=>JSON.parse(pod('exec',n.id,'node',FENCE,...args));
        const snapshot=n=>JSON.parse(pod('exec',n.id,'escript','/usr/local/libexec/kazoo5-maintenance-snapshot','--snapshot',n.ip));
        let seq=0;const lastRequests=new Map();
        function restore(n,current,saved,label){
            const name='request-'+(++seq)+'.json',r=request({...current,document_revisions:saved.document_revisions},generation,saved.agents);
            const file=save(name,r);copy(n,file,name);
            lastRequests.set(n.id,name);
            for(const mode of ['--validate','--restore']){
                const out=JSON.parse(pod('exec',n.id,'escript','/usr/local/libexec/kazoo5-maintenance-restore',mode,n.ip,guest+'/'+name));
                assert.equal(out.status,'PASS');assert.equal(out.agents_validated,3);
                assert.equal(out.agents_restored,mode==='--restore'?3:0);assert.equal(out.checkpoint_sha256,sha(fs.readFileSync(file)));
                save(label+'-'+n.ip+'-'+mode.slice(2)+'.json',out);
            }
        }
        async function correlate(label){
            let attempt=0;
            return until(()=>{
                const queues=nodes.map(n=>JSON.parse(pod('exec',n.id,'escript','/usr/local/libexec/kazoo5-maintenance-queues','--snapshot',n.ip)));
                const agents=nodes.map(snapshot);const name=label+'-inventory-'+(++attempt)+'.json';
                save(name,{queues,agents});
                const merged=require('./test-acdc-native-maintenance.cjs').mergeNativeInventories(queues,agents,nodes[0].installedSource);
                save(label+'-merged.json',merged);return merged;
            },60);
        }
        let baseline,closed=[],mediaClosed=false,modified=false,passed=false;
        phase('install_helpers');
        try{
            // Invoke the real installer's helper function from a private source
            // stage, without changing the installed Erlang code or its checkout.
            for(const n of nodes){
                pod('exec',n.id,'mkdir','-m','0700',guest);pod('exec',n.id,'mkdir','-m','0700',guest+'/scripts');
                for(const name of HELPER_FILES)
                    pod('cp',path.join(__dirname,name),n.id+':'+guest+'/scripts/'+name);
                pod('exec',n.id,'bash','-c','source "$1"; install_service_maintenance_fence kazoo-apps.service; systemctl daemon-reload; verify_service_maintenance_fence kazoo-apps.service','cold-install',guest+'/scripts/install-kazoo5.sh');
            }
            baseline=nodes.map(snapshot);
            for(const b of baseline){assert.equal(b.schema_version,2);assert.equal(b.agents.length,3);assert(b.agents.every(a=>a.account_id===A&&a.state==='ready'&&a.pause_until_unix_ms===0&&a.queues.length===1&&a.queues[0]===Q));}
            matches(baseline[0],baseline[1]);
            save('baseline.json',baseline);const manifest=sha(fs.readFileSync(root+'/baseline.json'));
            phase('fencing');
            for(const n of nodes){const spec={schema_version:1,generation,manifest_sha256:manifest,roles:['kazoo-apps'],tcp_ports:[8000,8443,5555,5556,8001],udp_ports:[]};
                copy(n,save('fence-'+n.ip+'.json',spec),'fence.json');closed.push(n);assert.equal(fence(n,'--close',guest+'/fence.json').state,'closed');}
            pod('exec',m.id,'mkdir','-m','0700',guest);copy(m,save('media.json',{schema_version:1,generation,manifest_sha256:manifest}),'media.json');
            mediaClosed=true;assert.equal(JSON.parse(pod('exec',m.id,'node',MEDIA,'--close',guest+'/media.json')).state,'closed');
            phase('fixture_states');modified=true;const deadline=Date.now()+600000;
            for(let i=0;i<nodes.length;i++){
                const agents=[...baseline[i].agents].sort((a,b)=>a.agent_id.localeCompare(b.agent_id)).map((a,j)=>j===0?{...a,state:'paused',pause_until_unix_ms:deadline}:j===1?{...a,state:'paused',pause_until_unix_ms:'infinity'}:{...a,queues:[]});
                restore(nodes[i],baseline[i],{...baseline[i],agents},'setup');
            }
            const captured=nodes.map(snapshot);for(let i=0;i<2;i++){
                assert.equal(captured[i].agents.filter(a=>a.state==='paused'&&a.pause_until_unix_ms==='infinity').length,1);
                assert.equal(captured[i].agents.filter(a=>a.state==='paused'&&Number.isInteger(a.pause_until_unix_ms)&&a.pause_until_unix_ms>Date.now()+300000).length,1);
                assert.equal(captured[i].agents.filter(a=>a.state==='ready'&&a.queues.length===0).length,1);
            }
            save('checkpoint.json',captured);receipt.checkpoint_sha256=sha(fs.readFileSync(root+'/checkpoint.json'));phase('cold_restart');
            receipt.correlated_before=(await correlate('before-restart')).agents.length;
            for(const n of nodes)pod('exec',n.id,'systemctl','restart','kazoo-apps.service');
            const after=[];for(const n of nodes)after.push(await until(()=>snapshot(n)));
            for(let i=0;i<2;i++){assert.notEqual(after[i].epoch,baseline[i].epoch);assert.equal(fence(nodes[i],'--verify',generation).state,'closed');}
            receipt.before_epochs=baseline.map(x=>x.epoch);receipt.after_epochs=after.map(x=>x.epoch);phase('restore_from_disk');
            const bytes=privateRead(root+'/checkpoint.json');assert.equal(sha(bytes),receipt.checkpoint_sha256);const stored=JSON.parse(bytes);
            for(let i=0;i<2;i++)restore(nodes[i],after[i],stored[i],'cold-restore');
            const restored=nodes.map(snapshot);for(let i=0;i<2;i++)matches(restored[i],stored[i]);
            save('restored.json',restored);receipt.correlated_after=(await correlate('after-restore')).agents.length;
            receipt.restored_replicas=6;receipt.absolute_deadlines_preserved=true;receipt.infinite_pause_preserved=true;receipt.empty_membership_preserved=true;passed=true;
        }catch(_){receipt.failed_phase=receipt.phase;}
        finally{
            phase('scoped_cleanup');
            try{
                if(modified){const saved=JSON.parse(privateRead(root+'/baseline.json'));for(let i=0;i<2;i++){
                    const current=await until(()=>snapshot(nodes[i]));restore(nodes[i],current,saved[i],'cleanup');matches(snapshot(nodes[i]),saved[i]);}}
                assert.equal(native().native.sessions,0);
                // Test-fixture cleanup only, never a claimed coordinator reopen.
                if(mediaClosed){assert.equal(JSON.parse(pod('exec',m.id,'node',MEDIA,'--release',generation)).state,'open');mediaClosed=false;}
                for(const n of closed)assert.equal(fence(n,'--release',generation).state,'open');closed=[];
                if(modified){for(const n of nodes){
                    // Read-only preflight of the exact last request must refuse
                    // after release. The same guard precedes every restore write.
                    const result=cp.spawnSync('/usr/bin/podman',['exec',n.id,'escript','/usr/local/libexec/kazoo5-maintenance-restore','--validate',n.ip,guest+'/'+lastRequests.get(n.id)],
                        {encoding:'utf8',timeout:30000,stdio:['ignore','pipe','pipe']});
                    assert.equal(result.status,1);assert(!result.error);assert(result.stdout.includes('restored=0'));
                }receipt.post_release_replay_preflight_refused=true;}
                receipt.cleanup_verified=true;
            }catch(_){receipt.cleanup_verified=false;}
            receipt.status=passed&&receipt.cleanup_verified?'PASS':'FAIL';phase('finished');
            console.log(JSON.stringify({status:receipt.status,receipt:root+'/receipt.json',failed_phase:receipt.failed_phase,cleanup_verified:receipt.cleanup_verified}));
        }
        assert.equal(receipt.status,'PASS');
    }finally{fs.closeSync(lock);}
}
module.exports={request,matches,owned,HELPER_FILES};
if(require.main===module)main().catch(_=>{console.error('COLD_AGENT_MAINTENANCE_REFUSED_OR_FAILED; inspect protected receipt');process.exitCode=1;});
