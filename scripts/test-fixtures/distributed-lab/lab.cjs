'use strict';
// Private credentials/state never appear on argv or stdout. No host data mounts,
// host networking, public published ports, broad deletion or automatic takeover.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os');
const ROOT=path.resolve(__dirname,'../../..'),DIR='/var/lib/kazoo5-install-lab';
const OWNER='distributed-install-v1',NETWORK='kz5-install-stage',SUBNET='172.30.253.0/24';
const ROLES=['couchdb','rabbitmq','haproxy','kazoo-apps','freeswitch','ecallmgr','kamailio','monster-ui','push-bridge'];
const UNITS={couchdb:'couchdb',rabbitmq:'rabbitmq-server',haproxy:'haproxy','kazoo-apps':'kazoo-apps',
    freeswitch:'kazoo-freeswitch',ecallmgr:'kazoo-ecallmgr',kamailio:'kazoo-kamailio'};
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function command(program,args,options={}) {
    const r=cp.spawnSync(program,args,{encoding:'utf8',timeout:30000,maxBuffer:16*1024*1024,...options});
    if(r.status!==0||r.error)throw Error('Failed '+path.basename(program)+' operation; inspect protected staging logs');
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
function overlapsSubnet(destination) {
    if(!destination || destination==='default')return false;
    const [ip,prefix='32']=destination.split('/'),mask=Number(prefix);
    assert(/^\d+\.\d+\.\d+\.\d+$/.test(ip)&&ip.split('.').every(v=>Number(v)<=255));
    assert(Number.isInteger(mask)&&mask>=0&&mask<=32);
    const num=s=>s.split('.').reduce((n,v)=>(n*256+Number(v))>>>0,0);
    const start=num('172.30.253.0'),size=2**(32-mask),low=Math.floor(num(ip)/size)*size;
    return !(start+255<low||start>low+size-1);
}
function prepare() {
    assert(!fs.existsSync(DIR+'/lab.json'),'Existing lab must be inspected, not replaced');
    assert.equal(command('git',['-C',ROOT,'status','--porcelain','--untracked-files=no']),'','Commit tracked changes before pinning lab source');
    const source=command('git',['-C',ROOT,'rev-parse','HEAD']);
    const recipe=hash(fs.readFileSync(__dirname+'/Containerfile'));
    podman(['pull','--tls-verify=true','docker.io/library/rockylinux:9'],{timeout:300000,stdio:'inherit'});
    const upstream=json(['image','inspect','docker.io/library/rockylinux:9'])[0];
    const digest=upstream.RepoDigests.find(d=>/^docker.io\/library\/rockylinux@sha256:[a-f0-9]{64}$/.test(d));
    assert(digest,'Verified repository digest required');
    const tag='localhost/kz5-install-lab:'+recipe.slice(0,16);
    podman(['build','--pull=never','--build-arg','BASE_IMAGE='+digest,'--tag',tag,'--file',__dirname+'/Containerfile',__dirname],
        {timeout:900000,stdio:'inherit'});
    const image=json(['image','inspect',tag])[0];
    assert.equal(image.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    const networks=json(['network','ls','--format','json']);
    assert(!networks.some(n=>n.name===NETWORK),'Refusing existing network name');
    // Fail before network creation if any current host route overlaps our /24.
    const routes=JSON.parse(command('ip',['-j','-4','route','show','table','all']));
    for(const r of routes)assert(!overlapsSubnet(r.dst),'Staging subnet overlaps an existing route');
    const s={owner:OWNER,source,recipe,image:image.Id,base_digest:digest,phase:'image-ready',roles:{}};
    // Record partial progress before creating persistent network/bundle resources.
    // Failures are retained for inspection; a repeated prepare never takes over.
    saveState(s);
    podman(['network','create','--subnet',SUBNET,'--gateway','172.30.253.1','--label','io.talkchief.kazoo.acceptance='+OWNER,NETWORK]);
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
    assert.equal(s.phase,'prepared','Partial preparation requires inspection');
    assert(!s.roles[role],'Role already recorded; inspect it instead of replacing it');
    const name='kz5-stage-'+role,ip='172.30.253.'+(11+ROLES.indexOf(role));
    assert(!json(['ps','--all','--format','json']).some(c=>c.Names?.includes(name)),'Existing container name refused');
    const memory=['kazoo-apps','ecallmgr','freeswitch'].includes(role)?'6g':'1g';
    const id=podman(['run','--detach','--name',name,'--hostname',name,'--network',NETWORK,'--ip',ip,
        '--label','io.talkchief.kazoo.acceptance='+OWNER,'--label','io.talkchief.kazoo.role='+role,
        '--systemd=always','--security-opt','label=disable','--cap-add=NET_ADMIN','--memory',memory,
        '--memory-swap',memory,'--pids-limit','4096',s.image]);
    assert(/^[a-f0-9]{64}$/.test(id));
    // Record ownership before subsequent checks so a partial boot is retained.
    s.roles[role]={id,name,ip,phase:'created'};saveState(s);
    podman(['exec',id,'ip','route','add','blackhole','10.1.0.0/16']);
    podman(['exec',id,'ip','route','add','blackhole','46.225.31.248/32']);
    podman(['exec',id,'ip','route','add','blackhole','91.99.188.145/32']);
    podman(['exec',id,'install','-d','-m','0700','/var/lib/kazoo-stage']);
    podman(['cp',DIR+'/source.bundle',id+':/var/lib/kazoo-stage/source.bundle']);
    podman(['exec',id,'git','clone','/var/lib/kazoo-stage/source.bundle','/opt/kz5'],{timeout:180000});
    assert.equal(podman(['exec',id,'git','-C','/opt/kz5','rev-parse','HEAD']),s.source);
    assert.equal(podman(['exec',id,'cat','/proc/1/comm']),'systemd');
    s.roles[role].phase='booted-source-ready';saveState(s);
    console.log(JSON.stringify({status:'BOOTED',role,ip,source:s.source,installed:false}));
}
function status() {
    const s=readState();if(s.network)ownedNetwork(s);
    console.log(JSON.stringify({owner:s.owner,phase:s.phase,source:s.source,base_digest:s.base_digest,roles:s.roles}));
}
function configFor(role,secrets) {
    assert(Object.hasOwn(UNITS,role),'Role provisioning not implemented');
    const ip='172.30.253.'+(11+ROLES.indexOf(role));
    const proxy=!['couchdb','rabbitmq','haproxy'].includes(role);
    return {KAZOO_ROOT:'/opt/kz5',KAZOO_AMQP_HOST:'172.30.253.12',KAZOO_AMQP_PORT:'5672',
        KAZOO_RABBITMQ_USER:'kazoo',KAZOO_RABBITMQ_PASSWORD:secrets.rabbit,KAZOO_RABBITMQ_VHOST:'/',
        KAZOO_COUCHDB_HOST:proxy?'172.30.253.13':'172.30.253.11',KAZOO_COUCHDB_PORT:proxy?'15984':'5984',
        KAZOO_COUCHDB_ADMIN_PORT:proxy?'15986':'5984',KAZOO_COUCHDB_USER:'admin',KAZOO_COUCHDB_PASSWORD:secrets.couch,
        KAZOO_RABBITMQ_BIND:ip,KAZOO_COUCHDB_BIND:ip,KAZOO_HAPROXY_BIND:ip,KAZOO_PUBLIC_IP:ip,
        KAZOO_ERLANG_DIST_IP:ip,KAZOO_COOKIE_FILE:'/etc/kazoo/.erlang.cookie',KAZOO_MAKE_JOBS:'2',
        KAZOO_API_URL:'http://172.30.253.18/v2/',KAZOO_API_UPSTREAM:'http://172.30.253.14:8000/v2/',
        KAZOO_WEBSOCKET_UPSTREAM:'http://172.30.253.14:5555/websocket',KAZOO_START_TIMEOUT:'180',
        KAZOO_REQUIRE_MEDIA_CONNECTION:role==='ecallmgr'?'true':'false',
        KAZOO_FREESWITCH_NODES:role==='ecallmgr'?'freeswitch@kz5-stage-freeswitch':'',
        KAZOO_MASTER_ACCOUNT_NAME:'IsolatedInstallerAcceptance',KAZOO_MASTER_ACCOUNT_REALM:'installer-stage.invalid',
        KAZOO_MASTER_ADMIN_USER:'admin',KAMAILIO_CHILDREN:'2',KAMAILIO_TCP_CHILDREN:'2',
        KAMAILIO_AMQP_CONSUMERS:'1',KAMAILIO_AMQP_WORKERS:'2'};
}
function installRole(role) {
    assert(Object.hasOwn(UNITS,role),'Role provisioning not implemented');
    const s=readState();ownedNetwork(s);const r=s.roles[role];assert(r,'Create role first');
    const c=json(['inspect',r.id])[0];
    assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],OWNER);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    assert.equal(c.State.Running,true);assert.equal(c.NetworkSettings.Networks[NETWORK].IPAddress,r.ip);
    assert.equal(podman(['exec',r.id,'git','-C','/opt/kz5','rev-parse','HEAD']),r.source||s.source);
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
module.exports={overlapsSubnet,ROLES,configFor};
if(require.main===module) {
try {
    assert.equal(process.getuid(),0);assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'),'Only development44 allowed');
    const args=process.argv.slice(2);
    if(args.length===1&&args[0]==='--prepare')prepare();
    else if(args.length===2&&args[0]==='--create')create(args[1]);
    else if(args.length===2&&args[0]==='--install')installRole(args[1]);
    else if(args.length===2&&args[0]==='--sync-source')syncSource(args[1]);
    else if(args.length===1&&args[0]==='--status')status();
    else throw Error('Usage: --prepare | --create ROLE | --install ROLE | --sync-source ROLE | --status');
} catch(e) {console.error('Distributed lab refused/failed: '+e.message);process.exitCode=1;}
}
