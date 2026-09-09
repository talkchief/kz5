'use strict';
// Fixed private application/media-controller peers; no main/prod configuration.
const fs=require('node:fs'),assert=require('node:assert/strict');
const cp=require('node:child_process');
function peerSettings(kind='kazoo-apps') {
    assert(['kazoo-apps','ecallmgr'].includes(kind));
    return kind==='kazoo-apps'
        ?{kind,key:'peer',role:'kazoo-apps-peer',name:'kz5-stage-kazoo-apps-peer',ip:'172.30.253.20',
            primaryIp:'172.30.253.14',unit:'kazoo-apps',slug:'apps-peer',filePrefix:'peer'}
        :{kind,key:'ecallmgrPeer',role:'ecallmgr-peer',name:'kz5-stage-ecallmgr-peer',ip:'172.30.253.21',
            primaryIp:'172.30.253.16',unit:'kazoo-ecallmgr',slug:'ecallmgr-peer',filePrefix:'ecallmgr-peer'};
}
function peerConfig(base,kind='kazoo-apps') {
    const {ip:IP}=peerSettings(kind);
    assert.equal(base.KAZOO_AMQP_HOST,'172.30.253.12');
    assert.equal(base.KAZOO_COUCHDB_HOST,'172.30.253.13');
    return {...base,KAZOO_RABBITMQ_BIND:IP,KAZOO_COUCHDB_BIND:IP,KAZOO_HAPROXY_BIND:IP,
        KAZOO_PUBLIC_IP:IP,KAZOO_ERLANG_DIST_IP:IP,KAZOO_BOOTSTRAP_MASTER_ACCOUNT:'false'};
}
function assertPrimary(s,c,kind='kazoo-apps') {
    const settings=peerSettings(kind);
    assert.equal(s.owner,'distributed-install-v1');
    assert.equal(s.roles[kind].phase,'installed-service-verified');
    assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],kind);
    assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,settings.primaryIp);
    assert.equal(c.State.Running,true);
    assert.equal(c.State.Paused===true,false);
}
function peerOperation(action,h,kind='kazoo-apps') {
    const {key,role:ROLE,name:NAME,ip:IP,unit,slug,filePrefix}=peerSettings(kind);
    const {readState,saveState,ownedNetwork,json,podman,command,configFor,hardenContainer,DIR,ROOT}=h;
    const s=readState();ownedNetwork(s);assert.equal(s.owner,'distributed-install-v1');
    if(action==='create') {
        assert(!s[key],'Existing peer must be inspected, not replaced');
        assert.equal(command('git',['-C',ROOT,'status','--porcelain','--untracked-files=no']),'');
        assert(!json(['ps','--all','--format','json']).some(c=>c.Names?.includes(NAME)));
        const primary=s.roles[kind];assertPrimary(s,json(['inspect',primary.id])[0],kind);
        assert.equal(podman(['exec',primary.id,'systemctl','is-active',unit]),'active');
        for(const role of ['couchdb','rabbitmq','haproxy','freeswitch']) {
            assert.equal(s.roles[role].phase,'installed-service-verified');
            const c=json(['inspect',s.roles[role].id])[0];
            assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
            assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
            assert.equal(c.State.Running,true);
        }
        assert.equal(JSON.parse(podman(['exec',s.roles.freeswitch.id,
            '/usr/local/freeswitch/bin/fs_cli','-x','show channels as json'])).row_count,0);
        podman(['exec',primary.id,'test','!','-e',
            '/etc/systemd/system/'+unit+'.service.d/99-kz5-peer-admission.conf']);
        const source=command('git',['-C',ROOT,'rev-parse','HEAD']);
        // Snapshot is private and intentionally contains the same lab's
        // protected credentials. Never push this image or call it a clean base.
        const watchdog='kz5-peer-snapshot-restore-'+process.pid;
        s[key]={phase:'snapshot-started',source,primary:primary.id,name:NAME,ip:IP,watchdog};saveState(s);
        command('systemd-run',['--unit',watchdog,'--on-active=4m','--timer-property=AccuracySec=1s',
            '/usr/bin/podman','unpause',primary.id]);
        let image;
        try {image=podman(['commit','--pause=true',primary.id],{timeout:180000});}
        finally {
            if(json(['inspect',primary.id])[0].State.Paused)podman(['unpause',primary.id]);
            command('systemctl',['stop',watchdog+'.timer']);
        }
        s[key].image=image;s[key].phase='snapshot-retained';saveState(s);
        const id=podman(['create','--name',NAME,'--hostname',NAME,'--network','kz5-install-stage','--ip',IP,
            '--label','io.talkchief.kazoo.acceptance='+s.owner,'--label','io.talkchief.kazoo.role='+ROLE,
            '--systemd=always','--security-opt','label=disable','--cap-add=NET_ADMIN',
            '--sysctl','net.ipv4.ip_local_reserved_ports=34512-34513',
            '--memory','6g','--memory-swap','6g','--pids-limit','4096',image]);
        assert(/^[a-f0-9]{64}$/.test(id));s[key].id=id;s[key].phase='created-stopped';saveState(s);
        podman(['cp',__dirname+'/peer-admission/'+unit+'.service.d',id+':/etc/systemd/system/']);
        podman(['start',id],{timeout:90000});hardenContainer(id);
        const state=podman(['exec',id,'systemctl','show','--value','-p','ActiveState',unit]);
        assert.equal(state,'inactive','Peer started before normal installer configuration');
        const cfg=peerConfig(configFor(kind,s.secrets),kind);
        const env=DIR+'/'+filePrefix+'-deployment.env';
        fs.writeFileSync(env,Object.entries(cfg).map(([k,v])=>k+'='+Buffer.from(v).toString('base64')).join('\n')+'\n',
            {mode:0o600,flag:'wx'});
        podman(['cp',env,id+':/etc/kazoo/deployment.env']);
        podman(['exec',id,'chmod','0600','/etc/kazoo/deployment.env']);
        const bundle=DIR+'/'+filePrefix+'-source-'+source+'.bundle';
        command('git',['-C',ROOT,'bundle','create',bundle,'HEAD','master'],{timeout:180000});fs.chmodSync(bundle,0o600);
        podman(['cp',bundle,id+':/var/lib/kazoo-stage/peer-source.bundle']);
        podman(['exec',id,'git','-C','/opt/kz5','fetch','/var/lib/kazoo-stage/peer-source.bundle','master'],{timeout:180000});
        podman(['exec',id,'git','-C','/opt/kz5','merge','--ff-only',source],{timeout:180000});
        assert.equal(podman(['exec',id,'git','-C','/opt/kz5','rev-parse','HEAD']),source);
        s[key].phase='configured-source-ready';saveState(s);
        console.log(JSON.stringify({status:'PEER_PREPARED',role:ROLE,source,ip:IP,serviceStarted:false}));return;
    }
    const p=s[key];assert(p?.id);
    const c=json(['inspect',p.id])[0];
    assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],ROLE);
    assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,IP);
    assert.equal(c.State.Running,true);
    if(action==='sync') {
        assert(['configured-source-ready','failed','installed'].includes(p.phase));
        assert.equal(command('git',['-C',ROOT,'status','--porcelain','--untracked-files=no']),'');
        assert.equal(podman(['exec',p.id,'git','-C','/opt/kz5','status','--porcelain','--untracked-files=no']),'');
        const source=command('git',['-C',ROOT,'rev-parse','HEAD']),bundle=DIR+'/'+filePrefix+'-source-'+source+'.bundle';
        if(!fs.existsSync(bundle)) {
            command('git',['-C',ROOT,'bundle','create',bundle,'HEAD','master'],{timeout:180000});fs.chmodSync(bundle,0o600);
        }
        podman(['cp',bundle,p.id+':/var/lib/kazoo-stage/peer-source.bundle']);
        podman(['exec',p.id,'git','-C','/opt/kz5','fetch','/var/lib/kazoo-stage/peer-source.bundle','master'],{timeout:180000});
        podman(['exec',p.id,'git','-C','/opt/kz5','merge','--ff-only',source],{timeout:180000});
        assert.equal(podman(['exec',p.id,'git','-C','/opt/kz5','rev-parse','HEAD']),source);
        p.source=source;saveState(s);console.log(JSON.stringify({status:'PEER_SOURCE_SYNCED',source,installed:false}));return;
    }
    if(action==='install') {
        assert(['configured-source-ready','failed','installed'].includes(p.phase));
        assert.equal(podman(['exec',p.id,'git','-C','/opt/kz5','rev-parse','HEAD']),p.source);
        assert.equal(podman(['exec',p.id,'git','-C','/opt/kz5','status','--porcelain','--untracked-files=no']),'');
        const attempt=p.attempts?p.attempts+1:(p.phase==='failed'?2:1);p.attempts=attempt;
        p.unit='kz5-stage-install-'+slug+'-'+attempt;p.insideLog='/var/lib/kazoo-stage/'+slug+'-install-'+attempt+'.log';
        p.log=DIR+'/'+slug+'-install-'+attempt+'.log';p.phase='installing';saveState(s);
        podman(['exec',p.id,'install','-m','0600','/dev/null',p.insideLog]);
        podman(['exec',p.id,'systemd-run','--unit',p.unit,'--property=User=root','--property=RemainAfterExit=yes',
            '--property=RuntimeMaxSec=3600','--property=TasksMax=2048',
            '--property=StandardOutput=append:'+p.insideLog,'--property=StandardError=append:'+p.insideLog,
            '/usr/bin/bash','/opt/kz5/scripts/install-kazoo5.sh',kind]);
        console.log(JSON.stringify({status:'PEER_INSTALLING',unit:p.unit,source:p.source}));return;
    }
    if(action==='reboot') {
        assert.equal(p.phase,'installed');
        assert.equal(c.State.Paused,false);
        assert(c.Config.CreateCommand.includes('net.ipv4.ip_local_reserved_ports=34512-34513'));
        const media=s.roles.freeswitch,mediaContainer=json(['inspect',media.id])[0];
        assert.equal(mediaContainer.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(mediaContainer.Config.Labels['io.talkchief.kazoo.role'],'freeswitch');
        assert.equal(mediaContainer.NetworkSettings.Networks['kz5-install-stage'].IPAddress,'172.30.253.15');
        assert.equal(JSON.parse(podman(['exec',media.id,'/usr/local/freeswitch/bin/fs_cli','-x','show channels as json'])).row_count,0);
        const receipt=DIR+'/'+slug+'-boot-'+Date.now()+'.log';
        const boot=p.boot={status:'RUNNING',started:new Date().toISOString(),receipt};saveState(s);
        const watchdog='kz5-peer-boot-restore-'+process.pid;
        command('systemd-run',['--unit',watchdog,'--on-active=10m','--timer-property=AccuracySec=1s',
            '/usr/bin/podman','start',p.id]);
        try {
            podman(['stop','--time','30',p.id],{timeout:90000});
            assert.equal(json(['inspect',p.id])[0].State.Running,false);
            const deadline=Date.now()+30000;
            while(Date.now()<deadline) {
                const states=['libpod-'+p.id+'.scope','libpod-conmon-'+p.id+'.scope'].map(name=>
                    command('systemctl',['show','--value','-p','ActiveState',name]));
                if(states.every(state=>['','inactive','failed'].includes(state)))break;
                Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,250);
            }
            assert(Date.now()<deadline,'Old monitor scopes did not settle');
            podman(['start',p.id],{timeout:90000});
            assert.notEqual(json(['inspect',p.id])[0].State.StartedAt,c.State.StartedAt);
            podman(['exec',p.id,'timeout','120','bash','-c',
                'until systemctl is-active --quiet '+unit+'; do sleep 1; done'],{timeout:125000});
            assert.equal(podman(['exec',p.id,'systemctl','is-active','kazoo-stage-isolation']),'active');
            const routes=JSON.parse(podman(['exec',p.id,'ip','-j','route']));
            for(const dst of ['10.1.0.0/16','46.225.31.248','91.99.188.145'])
                assert(routes.some(r=>r.type==='blackhole'&&[dst,dst+'/32'].includes(r.dst)));
            const fd=fs.openSync(receipt,'wx',0o600);let result;
            try {result=cp.spawnSync('podman',['exec',p.id,'bash','/opt/kz5/scripts/install-kazoo5.sh','--verify-only',kind],
                {timeout:180000,stdio:['ignore',fd,fd]});}finally{fs.closeSync(fd);}
            assert.equal(result.status,0,'Normal boot verifier failed; inspect protected receipt');
            assert.equal(podman(['exec',p.id,'systemctl','is-enabled',unit]),'enabled');
            boot.status='PASS';
        } catch(error) {boot.status='FAIL';throw error;}
        finally {
            boot.finished=new Date().toISOString();saveState(s);
            // Restore availability after an ordinary test failure but never
            // relabel that recovery as an automatic-boot pass.
            if(!json(['inspect',p.id])[0].State.Running)podman(['start',p.id],{timeout:90000});
            if(podman(['exec',p.id,'systemctl','is-active',unit])==='active')
                command('systemctl',['stop',watchdog+'.timer']);
        }
        console.log(JSON.stringify({status:boot.status,role:ROLE,check:'automatic-guest-boot',receipt}));return;
    }
    assert.equal(action,'collect');assert.equal(p.phase,'installing');
    const fields=Object.fromEntries(podman(['exec',p.id,'systemctl','show','-p','ActiveState','-p','SubState',
        '-p','Result','-p','ExecMainStatus','-p','ExecMainStartTimestamp',p.unit]).split('\n').map(l=>{
        const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1)];}));
    if(['activating','deactivating'].includes(fields.ActiveState)||(fields.ActiveState==='active'&&fields.SubState!=='exited')) {
        console.log(JSON.stringify({status:'PEER_INSTALLING',unit:p.unit}));return;
    }
    podman(['cp',p.id+':'+p.insideLog,p.log]);fs.chmodSync(p.log,0o600);
    p.phase=fields.ExecMainStartTimestamp&&fields.Result==='success'&&fields.ExecMainStatus==='0'?'installed':'failed';
    p.exit=fields.ExecMainStatus;saveState(s);assert.equal(p.phase,'installed','Peer normal installer failed; inspect private log');
    assert.equal(podman(['exec',p.id,'systemctl','is-active',unit]),'active');
    assert.equal(podman(['exec',p.id,'systemctl','is-enabled',unit]),'enabled');
    console.log(JSON.stringify({status:'PEER_INSTALLED',source:p.source,ip:IP,log:p.log}));
}
module.exports={peerSettings,peerConfig,assertPrimary,peerOperation};
