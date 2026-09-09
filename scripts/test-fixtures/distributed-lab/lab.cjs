'use strict';
// Private credentials/state never appear on argv or stdout. No host data mounts,
// host networking, public published ports, broad deletion or automatic takeover.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os');
const ROOT=path.resolve(__dirname,'../../..');
function settingsFor(cold=false,final=false) {
    assert.equal(typeof cold,'boolean');
    assert.equal(typeof final,'boolean');assert(!final||cold);
    if(final)return {cold,dir:'/var/lib/kazoo5-cold-bootstrap-final',owner:'distributed-install-v1-cold-final',
        network:'kz5-cold-final',prefix:'172.30.251.',name:'kz5-final-',realm:'cold-final-stage.invalid'};
    return cold?{cold,dir:'/var/lib/kazoo5-cold-bootstrap-lab',owner:'distributed-install-v1-cold',
        network:'kz5-cold-stage',prefix:'172.30.252.',name:'kz5-cold-',realm:'cold-installer-stage.invalid'}:
        {cold,dir:'/var/lib/kazoo5-install-lab',owner:'distributed-install-v1',
            network:'kz5-install-stage',prefix:'172.30.253.',name:'kz5-stage-',realm:'installer-stage.invalid'};
}
const SETTINGS=settingsFor(['--cold-bootstrap','--cold-bootstrap-final'].includes(process.argv[2]),
    process.argv[2]==='--cold-bootstrap-final');
const {dir:DIR,owner:OWNER,network:NETWORK,prefix:PREFIX}=SETTINGS,SUBNET=PREFIX+'0/24';
const ROLES=['couchdb','rabbitmq','haproxy','kazoo-apps','freeswitch','ecallmgr','kamailio','monster-ui','push-bridge'];
const UNITS={couchdb:'couchdb',rabbitmq:'rabbitmq-server',haproxy:'haproxy','kazoo-apps':'kazoo-apps',
    freeswitch:'kazoo-freeswitch',ecallmgr:'kazoo-ecallmgr',kamailio:'kazoo-kamailio','push-bridge':'kazoo-push-bridge'};
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function command(program,args,options={}) {
    const r=cp.spawnSync(program,args,{encoding:'utf8',timeout:30000,maxBuffer:16*1024*1024,...options});
    if(r.status!==0||r.error) {
        const diagnostic=DIR+'/operation-failure-'+Date.now()+'-'+crypto.randomBytes(4).toString('hex')+'.json';
        fs.writeFileSync(diagnostic,JSON.stringify({program:path.basename(program),status:r.status,
            error:r.error?.code,stderr:r.stderr||''})+'\n',{mode:0o600,flag:'wx'});
        throw Error('Failed '+path.basename(program)+' operation; private diagnostic '+diagnostic);
    }
    return (r.stdout||'').trim();
}
const podman=(args,options)=>command('podman',args,options);
const json=(args)=>JSON.parse(podman(args));
function readState() {
    const f=DIR+'/lab.json',s=fs.lstatSync(f);
    assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&s.nlink===1&&(s.mode&0o777)===0o600&&s.size<65536);
    const state=JSON.parse(fs.readFileSync(f));assert.equal(state.owner,OWNER);return state;
}
function saveState(state) {
    const f=DIR+'/lab.json',temp=f+'.'+crypto.randomBytes(8).toString('hex');
    fs.writeFileSync(temp,JSON.stringify(state)+'\n',{mode:0o600,flag:'wx'});fs.renameSync(temp,f);
}
function overlapsSubnet(destination,prefix=PREFIX) {
    if(!destination || destination==='default')return false;
    const [ip,bits='32']=destination.split('/'),mask=Number(bits);
    assert(/^\d+\.\d+\.\d+\.\d+$/.test(ip)&&ip.split('.').every(v=>Number(v)<=255));
    assert(Number.isInteger(mask)&&mask>=0&&mask<=32);
    const num=s=>s.split('.').reduce((n,v)=>(n*256+Number(v))>>>0,0);
    assert(['172.30.253.','172.30.252.','172.30.251.'].includes(prefix));
    const start=num(prefix+'0'),size=2**(32-mask),low=Math.floor(num(ip)/size)*size;
    return !(start+255<low||start>low+size-1);
}
function prepare() {
    assert(!fs.existsSync(DIR+'/lab.json'),'Existing lab must be inspected, not replaced');
    assert.equal(command('git',['-C',ROOT,'status','--porcelain','--untracked-files=no']),'','Commit tracked changes before pinning lab source');
    const source=command('git',['-C',ROOT,'rev-parse','HEAD']);
    const recipe=hash(fs.readFileSync(__dirname+'/Containerfile'));
    let digest,image;
    if(SETTINGS.cold) {
        // Reuse only the verified immutable base image, never a provisioned role
        // image, its filesystem, database or credentials from the earlier lab.
        const f='/var/lib/kazoo5-install-lab/lab.json',st=fs.lstatSync(f);
        assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&0o777)===0o600);
        const prior=JSON.parse(fs.readFileSync(f));
        assert.equal(prior.owner,'distributed-install-v1');assert.equal(prior.phase,'prepared');
        assert.equal(prior.recipe,recipe);image=json(['image','inspect',prior.image])[0];
        assert.equal(image.Labels['io.talkchief.kazoo.acceptance'],'distributed-install-v1');
        digest=prior.base_digest;
        assert(/^docker.io\/library\/rockylinux@sha256:[a-f0-9]{64}$/.test(digest));
    } else {
    podman(['pull','--tls-verify=true','docker.io/library/rockylinux:9'],{timeout:300000,stdio:'inherit'});
    const upstream=json(['image','inspect','docker.io/library/rockylinux:9'])[0];
    digest=upstream.RepoDigests.find(d=>/^docker.io\/library\/rockylinux@sha256:[a-f0-9]{64}$/.test(d));
    assert(digest,'Verified repository digest required');
    const tag='localhost/kz5-install-lab:'+recipe.slice(0,16);
    podman(['build','--pull=never','--build-arg','BASE_IMAGE='+digest,'--tag',tag,'--file',__dirname+'/Containerfile',__dirname],
        {timeout:900000,stdio:'inherit'});
    image=json(['image','inspect',tag])[0];
    assert.equal(image.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    }
    const networks=json(['network','ls','--format','json']);
    assert(!networks.some(n=>n.name===NETWORK),'Refusing existing network name');
    // Fail before network creation if any current host route overlaps our /24.
    const routes=JSON.parse(command('ip',['-j','-4','route','show','table','all']));
    for(const r of routes)assert(!overlapsSubnet(r.dst),'Staging subnet overlaps an existing route');
    const s={owner:OWNER,source,recipe,image:image.Id,base_digest:digest,phase:'image-ready',roles:{}};
    // Record partial progress before creating persistent network/bundle resources.
    // Failures are retained for inspection; a repeated prepare never takes over.
    saveState(s);
    podman(['network','create','--subnet',SUBNET,'--gateway',PREFIX+'1','--label','io.talkchief.kazoo.acceptance='+OWNER,NETWORK]);
    const network=json(['network','inspect',NETWORK])[0];
    assert.equal(network.labels['io.talkchief.kazoo.acceptance'],OWNER);
    s.network=network.id;s.phase='network-ready';saveState(s);
    const bundle=DIR+'/source.bundle';assert(!fs.existsSync(bundle));
    command('git',['-C',ROOT,'bundle','create',bundle,'HEAD','master'],{timeout:180000});fs.chmodSync(bundle,0o600);
    s.phase='prepared';saveState(s);
    console.log(JSON.stringify({status:'PREPARED',source,base_digest:digest,network:NETWORK,installed_roles:0}));
}
function ownedNetwork(s) {
    const n=json(['network','inspect',NETWORK])[0];
    assert.equal(n.id,s.network);assert.equal(n.labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(n.subnets[0].subnet,SUBNET);
}
function create(role) {
    assert(ROLES.includes(role),'Unknown role');const s=readState();ownedNetwork(s);
    if(SETTINGS.cold)assert(['couchdb','rabbitmq','kazoo-apps'].includes(role),'Cold bootstrap scope is three fresh roles');
    assert.equal(s.phase,'prepared','Partial preparation requires inspection');
    assert(!s.roles[role],'Role already recorded; inspect it instead of replacing it');
    const name=SETTINGS.name+role,ip=PREFIX+(11+ROLES.indexOf(role));
    assert(!json(['ps','--all','--format','json']).some(c=>c.Names?.includes(name)),'Existing container name refused');
    const memory=['kazoo-apps','ecallmgr','freeswitch'].includes(role)?'6g':'1g';
    command('python3',[__dirname+'/inotify-headroom.py','--check']);
    const id=podman(['run','--detach','--name',name,'--hostname',name,'--network',NETWORK,'--ip',ip,
        '--label','io.talkchief.kazoo.acceptance='+OWNER,'--label','io.talkchief.kazoo.role='+role,
        '--systemd=always','--security-opt','label=disable','--cap-add=NET_ADMIN','--memory',memory,
        '--sysctl','net.ipv4.ip_local_reserved_ports=34512-34513',
        '--memory-swap',memory,'--pids-limit','4096',s.image]);
    assert(/^[a-f0-9]{64}$/.test(id));
    // Record ownership before subsequent checks so a partial boot is retained.
    s.roles[role]={id,name,ip,phase:'created'};saveState(s);
    hardenContainer(id);
    podman(['exec',id,'install','-d','-m','0700','/var/lib/kazoo-stage']);
    podman(['cp',DIR+'/source.bundle',id+':/var/lib/kazoo-stage/source.bundle']);
    podman(['exec',id,'git','clone','/var/lib/kazoo-stage/source.bundle','/opt/kz5'],{timeout:180000});
    assert.equal(podman(['exec',id,'git','-C','/opt/kz5','rev-parse','HEAD']),s.source);
    assert.equal(podman(['exec',id,'cat','/proc/1/comm']),'systemd');
    s.roles[role].phase='booted-source-ready';saveState(s);
    // The lab image/base bundle remains immutable; new roles must nevertheless
    // exercise current fixes, not the old commit used to prepare the network.
    syncSource(role);
    console.log(JSON.stringify({status:'BOOTED',role,ip,source:readState().roles[role].source,installed:false}));
}
function status() {
    const s=readState();if(s.network)ownedNetwork(s);
    console.log(JSON.stringify({owner:s.owner,phase:s.phase,source:s.source,base_digest:s.base_digest,
        coldBootstrapBaseline:s.coldBootstrapBaseline,coldBootstrapAdmissions:s.coldBootstrapAdmissions,roles:s.roles}));
}
function bootstrapStatus() {
    assert(SETTINGS.cold,'Only the isolated cold bootstrap fixture may be inspected');
    const s=readState();ownedNetwork(s);const couch=s.roles.couchdb,apps=s.roles['kazoo-apps'];
    assert(couch&&apps);
    for(const [role,r] of [['couchdb',couch],['kazoo-apps',apps]]) {
        const c=json(['inspect',r.id])[0];
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    }
    const get=p=>JSON.parse(podman(['exec','-i',couch.id,'curl','--silent','--show-error','--config','-'],
        {input:'url = "http://'+couch.ip+':5984/'+p+'"\nuser = "admin:'+s.secrets.couch+'"\n'}));
    const dbs=get('_all_dbs'),cfg=get('system_config/accounts'),rows=get('accounts/_design/accounts/_view/listing_by_id');
    const probe=cp.spawnSync('podman',['exec',apps.id,'timeout','10','sup','kapps_util','get_master_account_id'],
        {encoding:'utf8',timeout:12000,maxBuffer:65536});
    // No account documents, credentials or raw SUP exception output is exposed.
    console.log(JSON.stringify({accountDbCount:dbs.filter(n=>n.startsWith('account/')).length,
        configExists:!cfg.error,defaultMasterConfigured:!!cfg.default?.master_account_id,
        accountViewRows:rows.rows?.length,accountViewError:rows.error||null,
        sup:{exit:probe.status,stdoutBytes:(probe.stdout||'').length,
            startsOk:(probe.stdout||'').startsWith('{ok,'),containsOk:(probe.stdout||'').includes('{ok,'),
            stderrBytes:(probe.stderr||'').length}}));
}
function hardenContainer(id) {
    podman(['cp',__dirname+'/kazoo-stage-isolation.service',id+':/etc/systemd/system/kazoo-stage-isolation.service']);
    podman(['exec',id,'systemctl','daemon-reload']);
    podman(['exec',id,'systemctl','enable','--now','kazoo-stage-isolation.service']);
    assert.equal(podman(['exec',id,'systemctl','is-active','kazoo-stage-isolation.service']),'active');
}
function configFor(role,secrets,settings=SETTINGS) {
    assert(Object.hasOwn(UNITS,role),'Role provisioning not implemented');
    const prefix=settings.prefix,ip=prefix+(11+ROLES.indexOf(role));
    const proxy=!settings.cold&&!['couchdb','rabbitmq','haproxy'].includes(role);
    return {KAZOO_ROOT:'/opt/kz5',KAZOO_AMQP_HOST:prefix+'12',KAZOO_AMQP_PORT:'5672',
        KAZOO_RABBITMQ_USER:'kazoo',KAZOO_RABBITMQ_PASSWORD:secrets.rabbit,KAZOO_RABBITMQ_VHOST:'/',
        KAZOO_RABBITMQ_API_URL:'http://'+prefix+'12:15672/',
        KAZOO_RABBITMQ_API_USER:secrets.monitor?'kz5_install_monitor':'',KAZOO_RABBITMQ_API_PASSWORD:secrets.monitor||'',
        KAZOO_COUCHDB_HOST:prefix+(proxy?'13':'11'),KAZOO_COUCHDB_PORT:proxy?'15984':'5984',
        KAZOO_COUCHDB_ADMIN_PORT:proxy?'15986':'5984',KAZOO_COUCHDB_USER:'admin',KAZOO_COUCHDB_PASSWORD:secrets.couch,
        KAZOO_RABBITMQ_BIND:ip,KAZOO_COUCHDB_BIND:ip,KAZOO_HAPROXY_BIND:ip,KAZOO_PUBLIC_IP:ip,
        KAZOO_ERLANG_DIST_IP:ip,KAZOO_COOKIE_FILE:'/etc/kazoo/.erlang.cookie',KAZOO_MAKE_JOBS:'2',
        KAZOO_API_URL:'http://'+prefix+(settings.cold?'14:8000':'18')+'/v2/',KAZOO_API_UPSTREAM:'http://'+prefix+'14:8000/v2/',
        KAZOO_WEBSOCKET_UPSTREAM:'http://'+prefix+'14:5555/websocket',KAZOO_START_TIMEOUT:'180',
        KAZOO_REQUIRE_MEDIA_CONNECTION:role==='ecallmgr'?'true':'false',
        KAZOO_FREESWITCH_NODES:role==='ecallmgr'?'freeswitch@'+settings.name+'freeswitch':'',
        KAZOO_MASTER_ACCOUNT_NAME:'IsolatedInstallerAcceptance',KAZOO_MASTER_ACCOUNT_REALM:settings.realm,
        KAZOO_MASTER_ADMIN_USER:'admin',KAMAILIO_CHILDREN:'2',KAMAILIO_TCP_CHILDREN:'2',
        KAMAILIO_AMQP_CONSUMERS:'1',KAMAILIO_AMQP_WORKERS:'2'};
}
function installRole(role,detached=false) {
    assert(Object.hasOwn(UNITS,role),'Role provisioning not implemented');
    if(role==='push-bridge')assert.equal(readState().bridgeFixture?.phase,'prepared','Prepare dedicated synthetic bridge fixture first');
    if(SETTINGS.cold&&role==='kazoo-apps') {
        const before=readState();ownedNetwork(before);
        for(const dependency of ['couchdb','rabbitmq'])
            assert.equal(before.roles[dependency]?.phase,'installed-service-verified');
        assert(!before.roles[role]?.installUnit,'Collect the previous installer before changing inputs');
        // Normal apps admission requires a read-only management identity. Set
        // up this lab-owned prerequisite before copying any app configuration.
        if(!before.monitorProvisioned)provisionMonitor();
    }
    const s=readState();ownedNetwork(s);const r=s.roles[role];assert(r,'Create role first');
    const c=json(['inspect',r.id])[0];
    assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    assert.equal(c.State.Running,true);assert.equal(c.NetworkSettings.Networks[NETWORK].IPAddress,r.ip);
    assert.equal(podman(['exec',r.id,'git','-C','/opt/kz5','rev-parse','HEAD']),r.source||s.source);
    if(['kazoo-apps','ecallmgr'].includes(role))reservePivotNamespace(c);
    if(!s.secrets) {s.secrets={rabbit:crypto.randomBytes(32).toString('hex'),couch:crypto.randomBytes(32).toString('hex'),cookie:crypto.randomBytes(32).toString('hex')};saveState(s);}
    const cfg=Object.entries(configFor(role,s.secrets)).map(([k,v])=>k+'='+Buffer.from(v).toString('base64')).join('\n')+'\n';
    const config=DIR+'/'+role+'.env',cookie=DIR+'/'+role+'.cookie';
    if(!r.configured) {
        assert.equal(r.phase,'booted-source-ready');
        fs.writeFileSync(config,cfg,{mode:0o600,flag:'wx'});fs.writeFileSync(cookie,s.secrets.cookie+'\n',{mode:0o600,flag:'wx'});
        podman(['exec',r.id,'install','-d','-m','0755','/etc/kazoo']);
        podman(['cp',config,r.id+':/etc/kazoo/deployment.env']);podman(['cp',cookie,r.id+':/etc/kazoo/.erlang.cookie']);
        podman(['exec',r.id,'chmod','0600','/etc/kazoo/deployment.env','/etc/kazoo/.erlang.cookie']);
        r.configured=true;saveState(s);
    } else if(r.phase==='install-failed') {
        // A failed first preflight can be retried after correcting lab inputs,
        // but never replace independently edited container configuration.
        const prior=fs.readFileSync(config,'utf8');
        const current=podman(['exec',r.id,'cat','/etc/kazoo/deployment.env']);
        // Normal installer persistence adds resolved inputs. Verify every
        // original supplied input and preserve its additional saved settings.
        const values=text=>new Map(text.split('\n').filter(l=>l&&!l.startsWith('#')).map(l=>{
            const p=l.indexOf('=');assert(p>0,'Malformed owned role inputs');return [l.slice(0,p),l.slice(p+1)];
        }));
        const actual=values(current);
        for(const [key,value] of values(prior))assert.equal(actual.get(key),value,'Container inputs drifted; inspect before retry');
        if(prior!==cfg) {
            fs.writeFileSync(config,cfg,{mode:0o600});
            for(const [key,value] of values(cfg))actual.set(key,value);
            const merged=DIR+'/'+role+'-retry.env';
            fs.writeFileSync(merged,[...actual].map(([k,v])=>k+'='+v).join('\n')+'\n',{mode:0o600});
            podman(['cp',merged,r.id+':/etc/kazoo/deployment.env']);
            podman(['exec',r.id,'chmod','0600','/etc/kazoo/deployment.env']);
        }
    }
    const attempt=(r.attempts||0)+1,log=DIR+'/'+role+'-install-'+attempt+'.log';
    if(SETTINGS.cold&&role==='kazoo-apps'&&r.phase!=='installed-service-verified') {
        for(const dependency of ['couchdb','rabbitmq'])
            assert.equal(s.roles[dependency]?.phase,'installed-service-verified');
        const couch=s.roles.couchdb;
        const config='url = "http://'+couch.ip+':5984/_all_dbs"\nuser = "admin:'+s.secrets.couch+'"\n';
        const databases=JSON.parse(podman(['exec','-i',couch.id,'curl','--fail','--silent','--show-error','--config','-'],{input:config}));
        let existingMaster=false;
        if(databases.some(name=>!['_users','_replicator','_global_changes'].includes(name))) {
            // A failed post-create discovery must not trigger duplicate account
            // creation. Resume only the exact already-configured cold master.
            const get=p=>JSON.parse(podman(['exec','-i',couch.id,'curl','--fail','--silent','--show-error','--config','-'],
                {input:'url = "http://'+couch.ip+':5984/'+p+'"\nuser = "admin:'+s.secrets.couch+'"\n'}));
            const config=get('system_config/accounts'),id=config.default?.master_account_id;
            assert(/^[a-f0-9]{32}$/.test(id||''));
            const account=get('accounts/'+id),listing=get('accounts/_design/accounts/_view/listing_by_id');
            assert.equal(account.realm,SETTINGS.realm);assert.equal(account._id,id);
            assert.equal(listing.rows?.length,1);assert.equal(listing.rows[0].id,id);
            assert(s.coldBootstrapBaseline,'Existing master without original empty baseline refused');
            existingMaster=true;
        } else assertFreshDatabases(databases);
        const admission={time:new Date().toISOString(),databases,source:r.source||s.source,attempt,existingMaster};
        if(!s.coldBootstrapBaseline)s.coldBootstrapBaseline=admission;
        s.coldBootstrapAdmissions=[...(s.coldBootstrapAdmissions||[]),admission];saveState(s);
    }
    if(detached) {
        assert(!r.installUnit,'Collect the previous detached installer first');
        const unit='kz5-stage-install-'+role+'-'+attempt,inside='/var/lib/kazoo-stage/'+role+'-install-'+attempt+'.log';
        podman(['exec',r.id,'install','-m','0600','/dev/null',inside]);
        r.attempts=attempt;r.phase='installing';r.log=log;r.installUnit=unit;r.insideLog=inside;saveState(s);
        podman(['exec',r.id,'systemd-run','--unit',unit,'--property=User=root','--property=RemainAfterExit=yes','--property=RuntimeMaxSec=3600',
            '--property=TasksMax=2048','--property=StandardOutput=append:'+inside,'--property=StandardError=append:'+inside,
            '/usr/bin/bash','/opt/kz5/scripts/install-kazoo5.sh',role]);
        console.log(JSON.stringify({status:'INSTALLING',role,source:r.source||s.source,unit,log:inside}));return;
    }
    const fd=fs.openSync(log,'wx',0o600);r.attempts=attempt;r.phase='installing';r.log=log;saveState(s);
    let result;
    try {result=cp.spawnSync('podman',['exec',r.id,'bash','/opt/kz5/scripts/install-kazoo5.sh',role],
        {timeout:3600000,stdio:['ignore',fd,fd]});}
    finally {fs.closeSync(fd);}
    r.exit=result.status;r.phase=result.status===0&&!result.error?'installed':'install-failed';saveState(s);
    assert.equal(r.phase,'installed','Normal installer failed; inspect private role log');
    assert.equal(podman(['exec',r.id,'systemctl','is-active',UNITS[role]+'.service']),'active');
    assert.equal(podman(['exec',r.id,'systemctl','is-enabled',UNITS[role]+'.service']),'enabled');
    r.phase='installed-service-verified';saveState(s);
    console.log(JSON.stringify({status:'PASS',role,attempt,source:r.source||s.source,service:UNITS[role],log}));
}
function separateNamespace(target,host) {
    assert(target.dev!==host.dev||target.ino!==host.ino,'Refusing the host network namespace');
}
function reservePivotNamespace(container) {
    // Older owned lab containers predate --sysctl at creation. Retain their
    // compiled files/data; only enter the pinned network namespace, not mounts,
    // PID or user namespaces. No privileged container or host sysctl changes.
    assert.equal(container.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(container.State.Running,true);
    const pid=container.State.Pid;assert(Number.isSafeInteger(pid)&&pid>1);
    const fd=fs.openSync('/proc/'+pid+'/ns/net','r');
    const kernel='/proc/sys/net/ipv4/ip_local_reserved_ports';
    const before=fs.readFileSync(kernel,'utf8');
    try {
        separateNamespace(fs.fstatSync(fd),fs.statSync('/proc/self/ns/net'));
        command('nsenter',['--net=/proc/self/fd/3','--','python3',ROOT+'/scripts/reserve-kazoo-pivot-ports.py','--apply'],
            {stdio:['ignore','pipe','pipe',fd]});
        assert.equal(fs.readFileSync(kernel,'utf8'),before,'Host port reservations unexpectedly changed');
    } finally {fs.closeSync(fd);}
}
function repairLegacyPivot(role) {
    assert(!SETTINGS.cold&&['kazoo-apps','ecallmgr'].includes(role));
    const s=readState();ownedNetwork(s);const r=s.roles[role];assert(r);
    const c=json(['inspect',r.id])[0];
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    assert.equal(c.NetworkSettings.Networks[NETWORK].IPAddress,r.ip);
    assert(!c.Config.CreateCommand.includes('net.ipv4.ip_local_reserved_ports=34512-34513'),
        'Repair applies only to retained containers predating the creation fix');
    const media=s.roles.freeswitch;assert(media);
    const m=json(['inspect',media.id])[0];
    assert.equal(m.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(m.Config.Labels['io.talkchief.kazoo.role'],'freeswitch');
    assert.equal(JSON.parse(podman(['exec',media.id,'/usr/local/freeswitch/bin/fs_cli','-x','show channels as json'])).row_count,0);
    reservePivotNamespace(c);
    podman(['exec',r.id,'systemctl','restart','kazoo-pivot-port-reservation.service']);
    podman(['exec',r.id,'systemctl','start',UNITS[role]+'.service']);
    r.legacyPivotRepair={time:new Date().toISOString(),bootPassed:false};saveState(s);
    verifyRole(role);
    console.log(JSON.stringify({status:'RESTORED',role,bootPassed:false,
        reason:'retained container predates namespaced sysctl creation; not an automatic boot pass'}));
}
function collectRole(role) {
    assert(Object.hasOwn(UNITS,role));const s=readState();ownedNetwork(s);const r=s.roles[role];assert(r?.installUnit);
    const c=json(['inspect',r.id])[0];assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    const details=podman(['exec',r.id,'systemctl','show','-p','ActiveState','-p','SubState','-p','Result','-p','ExecMainStatus',
        '-p','ExecMainStartTimestamp',r.installUnit+'.service']);
    const fields=Object.fromEntries(details.split('\n').map(line=>{const p=line.indexOf('=');return [line.slice(0,p),line.slice(p+1)];}));
    if(['activating','deactivating'].includes(fields.ActiveState)||
        (fields.ActiveState==='active'&&fields.SubState!=='exited')) {
        console.log(JSON.stringify({status:'INSTALLING',role,unit:r.installUnit}));return;
    }
    podman(['cp',r.id+':'+r.insideLog,r.log]);fs.chmodSync(r.log,0o600);
    r.exit=Number(fields.ExecMainStatus);r.completedUnit=r.installUnit;delete r.installUnit;
    r.phase=fields.ExecMainStartTimestamp&&fields.Result==='success'&&fields.ExecMainStatus==='0'?'installed':'install-failed';saveState(s);
    assert.equal(r.phase,'installed','Detached normal installer failed; inspect private role log');
    assert.equal(podman(['exec',r.id,'systemctl','is-active',UNITS[role]+'.service']),'active');
    assert.equal(podman(['exec',r.id,'systemctl','is-enabled',UNITS[role]+'.service']),'enabled');
    r.phase='installed-service-verified';saveState(s);console.log(JSON.stringify({status:'PASS',role,source:r.source||s.source,log:r.log}));
}
function provisionMonitor() {
    const s=readState();ownedNetwork(s);const r=s.roles.rabbitmq;assert.equal(r?.phase,'installed-service-verified');
    const c=json(['inspect',r.id])[0];assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],'rabbitmq');
    if(!s.secrets.monitor) {s.secrets.monitor=crypto.randomBytes(32).toString('hex');saveState(s);}
    const user='kz5_install_monitor';
    const users=JSON.parse(podman(['exec',r.id,'rabbitmqctl','-q','list_users','--formatter','json']));
    assert(Array.isArray(users));
    const exists=users.some(row=>row.user===user);
    const auth=operation=>podman(['exec','-i',r.id,'rabbitmqctl',operation,user],{input:s.secrets.monitor+'\n'});
    if(!exists)auth('add_user');
    // Prove this is our newly generated identity before changing privileges.
    // Never reset a password or claim an existing unrelated monitoring user.
    auth('authenticate_user');
    podman(['exec',r.id,'rabbitmqctl','set_user_tags',user,'monitoring']);
    podman(['exec',r.id,'rabbitmqctl','set_permissions','-p','/',user,'^$','^$','.*']);
    s.monitorProvisioned=true;saveState(s);
    console.log(JSON.stringify({status:'PASS',role:'rabbitmq',check:'lab-only-read-monitor-provisioned',privilege:'monitoring; read-only selected vhost'}));
}
function syncSource(role) {
    assert(ROLES.includes(role));const s=readState();ownedNetwork(s);const r=s.roles[role];assert(r);
    const c=json(['inspect',r.id])[0];assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    assert.notEqual(r.phase,'installing');
    assert.equal(command('git',['-C',ROOT,'status','--porcelain','--untracked-files=no']),'');
    assert.equal(podman(['exec',r.id,'git','-C','/opt/kz5','status','--porcelain','--untracked-files=no']),'');
    const source=command('git',['-C',ROOT,'rev-parse','HEAD']),bundle=DIR+'/source-'+source+'.bundle';
    if(!fs.existsSync(bundle)) {
        command('git',['-C',ROOT,'bundle','create',bundle,'HEAD','master'],{timeout:180000});fs.chmodSync(bundle,0o600);
    }
    podman(['cp',bundle,r.id+':/var/lib/kazoo-stage/upgrade.bundle']);
    podman(['exec',r.id,'git','-C','/opt/kz5','fetch','/var/lib/kazoo-stage/upgrade.bundle','master'],{timeout:180000});
    podman(['exec',r.id,'git','-C','/opt/kz5','merge','--ff-only',source],{timeout:180000});
    assert.equal(podman(['exec',r.id,'git','-C','/opt/kz5','rev-parse','HEAD']),source);
    r.source=source;saveState(s);console.log(JSON.stringify({status:'SOURCE_SYNCED',role,source,installed:false}));
}
function verifyRole(role,reboot=false,drained=false) {
    assert(Object.hasOwn(UNITS,role));const s=readState();ownedNetwork(s);const r=s.roles[role];assert(r);
    assert.equal(r.phase,'installed-service-verified');
    const c=json(['inspect',r.id])[0];assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    if(reboot) {
        if(drained) {
            if(SETTINGS.cold)assert.equal(role,'kazoo-apps','Cold reboot covers only the fresh apps bootstrap fixture');
            const dependencies=SETTINGS.cold?['couchdb','rabbitmq','kazoo-apps']:['couchdb','rabbitmq','haproxy','kazoo-apps','freeswitch','ecallmgr','kamailio'];
            for(const dependency of dependencies) {
                const entry=s.roles[dependency];assert.equal(entry?.phase,'installed-service-verified');
                const live=json(['inspect',entry.id])[0];
                assert.equal(live.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
                assert.equal(live.Config.Labels['io.talkchief.kazoo.role'],dependency);
                assert.equal(live.State.Running,true);
                assert.equal(live.NetworkSettings.Networks[NETWORK].IPAddress,entry.ip);
            }
            if(SETTINGS.cold) {
                assert.deepEqual(Object.keys(s.roles).sort(),dependencies.slice().sort());
                assert(s.coldBootstrapBaseline,'Cold fixture must have a retained empty-data baseline');
                // This fixed scenario has no media node, endpoints, queues,
                // test calls or external service routes; only normal bootstrap.
            } else {
                const channels=JSON.parse(podman(['exec',s.roles.freeswitch.id,
                    '/usr/local/freeswitch/bin/fs_cli','-x','show channels as json']));
                assert.equal(channels.row_count,0,'Refusing a lab guest reboot with active media');
            }
            requirePersistentPivot(role,c.Config.CreateCommand);
            r.drainedRebootAdmission={time:new Date().toISOString(),mediaChannels:0};saveState(s);
        } else {
            assert(['couchdb','rabbitmq','haproxy'].includes(role),'Reboot acceptance limited to isolated data tier');
            assert(!Object.keys(s.roles).some(name=>!['couchdb','rabbitmq','haproxy'].includes(name)),
                'Do not reboot data roles after dependent role admission without explicit drained acceptance');
        }
        hardenContainer(r.id);
        const before=c.State.StartedAt;
        // Do not race the old conmon systemd scope's asynchronous teardown.
        // A failed same-ID immediate restart was observed to kill new conmon.
        podman(['stop','--time','30',r.id],{timeout:90000});
        assert.equal(json(['inspect',r.id])[0].State.Running,false);
        const deadline=Date.now()+30000;
        while(Date.now()<deadline) {
            const states=['libpod-'+r.id+'.scope','libpod-conmon-'+r.id+'.scope'].map(unit=>{
                const result=cp.spawnSync('systemctl',['show','--value','-p','ActiveState',unit],{encoding:'utf8',timeout:5000});
                assert(!result.error);return (result.stdout||'').trim();
            });
            if(states.every(state=>['','inactive','failed'].includes(state)))break;
            Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,250);
        }
        assert(Date.now()<deadline,'Old container scopes have not settled; container retained stopped');
        podman(['start',r.id],{timeout:90000});
        const after=json(['inspect',r.id])[0];assert.equal(after.State.Running,true);assert.notEqual(after.State.StartedAt,before);
    }
    podman(['exec',r.id,'timeout','120','bash','-c',
        'until systemctl is-active --quiet '+UNITS[role]+'.service; do sleep 1; done'],{timeout:125000});
    if(reboot) {
        assert.equal(podman(['exec',r.id,'systemctl','is-active','kazoo-stage-isolation.service']),'active');
        const routes=JSON.parse(podman(['exec',r.id,'ip','-j','route']));
        for(const dst of ['10.1.0.0/16','46.225.31.248','91.99.188.145'])
            assert(routes.some(route=>route.type==='blackhole'&&(route.dst===dst||route.dst===dst+'/32')),'Isolation route missing after boot');
    }
    const log=DIR+'/'+role+'-'+(reboot?'boot':'verify')+'-'+Date.now()+'.log',fd=fs.openSync(log,'wx',0o600);
    let result;
    try {result=cp.spawnSync('podman',['exec',r.id,'bash','/opt/kz5/scripts/install-kazoo5.sh','--verify-only',role],
        {timeout:180000,stdio:['ignore',fd,fd]});}finally{fs.closeSync(fd);}
    assert.equal(result.status,0,'Normal role verification failed; inspect private verify log');
    assert.equal(podman(['exec',r.id,'systemctl','is-enabled',UNITS[role]+'.service']),'enabled');
    r[reboot?'guestBootVerified':'reverified']={time:new Date().toISOString(),log};saveState(s);
    console.log(JSON.stringify({status:'PASS',role,check:reboot?'system-container-boot':'normal-verify',log}));
}
function assertFreshDatabases(databases) {
    assert(Array.isArray(databases),'Database inventory must be an array');
    assert(databases.every(name=>['_users','_replicator','_global_changes'].includes(name)),
        'Cold bootstrap requires a fresh CouchDB with no Kazoo databases');
}
function requirePersistentPivot(role,argv) {
    if(['kazoo-apps','ecallmgr'].includes(role))
        assert(Array.isArray(argv)&&argv.includes('net.ipv4.ip_local_reserved_ports=34512-34513'),
            'Legacy guest lacks persistent Pivot ports; refuse before stopping the working role');
}
function assertColdPark(s,settings) {
    assert.equal(settings.cold,true,'Only completed empty-bootstrap fixtures may be parked');
    assert.equal(s.owner,settings.owner);
    assert.deepEqual(Object.keys(s.roles).sort(),['couchdb','kazoo-apps','rabbitmq']);
    for(const r of Object.values(s.roles)) {
        assert.equal(r.phase,'installed-service-verified');assert(!r.installUnit);
    }
    assert(s.roles['kazoo-apps'].guestBootVerified?.log,'Require completed automatic apps boot evidence');
}
function parkCold() {
    const s=readState();ownedNetwork(s);assertColdPark(s,SETTINGS);
    assert(fs.existsSync(s.roles['kazoo-apps'].guestBootVerified.log));
    for(const role of ['kazoo-apps','rabbitmq','couchdb']) {
        const r=s.roles[role],c=json(['inspect',r.id])[0];
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
        if(c.State.Running)assert.equal(c.NetworkSettings.Networks[NETWORK].IPAddress,r.ip);
        assert.equal(c.State.Paused,false);
    }
    s.park={status:'STOPPING',started:new Date().toISOString(),dataRemoved:false};saveState(s);
    for(const role of ['kazoo-apps','rabbitmq','couchdb']) {
        const r=s.roles[role];
        if(json(['inspect',r.id])[0].State.Running)podman(['stop','--time','30',r.id],{timeout:90000});
        assert.equal(json(['inspect',r.id])[0].State.Running,false);
    }
    s.park.status='PARKED';s.park.finished=new Date().toISOString();saveState(s);
    console.log(JSON.stringify({status:'PARKED',profile:SETTINGS.name,roles:3,dataRemoved:false,
        reason:'Completed bootstrap evidence retained; release shared kernel/container resources'}));
}
module.exports={overlapsSubnet,ROLES,configFor,separateNamespace,settingsFor,assertFreshDatabases,requirePersistentPivot,assertColdPark};
if(require.main===module) {
try {
    assert.equal(process.getuid(),0);assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'),'Only development44 allowed');
    const args=process.argv.slice(SETTINGS.cold?3:2);
    if(args.length===1&&args[0]==='--prepare')prepare();
    else if(args.length===2&&args[0]==='--create')create(args[1]);
    else if(args.length===2&&args[0]==='--install')installRole(args[1]);
    else if(args.length===2&&args[0]==='--begin-install')installRole(args[1],true);
    else if(args.length===2&&args[0]==='--collect-install')collectRole(args[1]);
    else if(args.length===1&&args[0]==='--provision-monitor')provisionMonitor();
    else if(args.length===2&&args[0]==='--sync-source')syncSource(args[1]);
    else if(args.length===2&&args[0]==='--verify-role')verifyRole(args[1]);
    else if(args.length===2&&args[0]==='--reboot-role')verifyRole(args[1],true);
    else if(args.length===2&&args[0]==='--drained-reboot-role')verifyRole(args[1],true,true);
    else if(args.length===2&&args[0]==='--repair-legacy-pivot')repairLegacyPivot(args[1]);
    else if(args.length===1&&args[0]==='--status')status();
    else if(args.length===1&&args[0]==='--bootstrap-status')bootstrapStatus();
    else if(args.length===1&&args[0]==='--park')parkCold();
    else if(args.length===1&&args[0]==='--prepare-bridge') {
        assert(!SETTINGS.cold);
        require('./bridge.cjs').prepare({readState,saveState,ownedNetwork,json,podman,DIR});
    }
    else if(args.length===2&&args[0]==='--call-fixture') {
        assert(!SETTINGS.cold);assert(['start','collect'].includes(args[1]));
        require('./calls.cjs').operation(args[1],{readState,saveState,ownedNetwork,json,podman,DIR,ROOT});
    }
    else if(args.length===2&&['--apps-peer','--ecallmgr-peer'].includes(args[0])) {
        assert(!SETTINGS.cold,'Peer belongs only to the original isolated lab');
        assert(['create','resume','install','collect','sync','reboot'].includes(args[1]));
        require('./peer.cjs').peerOperation(args[1],{readState,saveState,ownedNetwork,json,podman,
            command,configFor,hardenContainer,DIR,ROOT},args[0]==='--apps-peer'?'kazoo-apps':'ecallmgr');
    }
    else throw Error('Usage: --prepare | --create ROLE | --install ROLE | --sync-source ROLE | --verify-role ROLE | --reboot-role ROLE | --status');
} catch(e) {console.error('Distributed lab refused/failed: '+e.message);process.exitCode=1;}
}
