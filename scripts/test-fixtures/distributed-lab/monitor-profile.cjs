'use strict';
// Explicit original-lab-only transport adapter; no arbitrary host/profile input.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os');
const DIR='/var/lib/kazoo5-install-lab';
function command(program,args,options={}) {
    try{return cp.execFileSync(program,args,{encoding:'utf8',timeout:15000,maxBuffer:1048576,stdio:['pipe','pipe','pipe'],...options});}
    catch(_){throw Error('Scoped distributed monitor dependency refused');}
}
const podman=(args,options)=>command('podman',args,options);
function prepare() {
    assert.equal(process.getuid(),0);
    assert.equal(os.hostname(),'dev-testing');
    assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'));
    const st=fs.lstatSync(DIR+'/lab.json');
    assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);
    const s=JSON.parse(fs.readFileSync(DIR+'/lab.json'));assert.equal(s.owner,'distributed-install-v1');
    assert.equal(s.callFixture?.phase,'provisioned');assert.equal(s.peer?.phase,'installed');
    const network=JSON.parse(podman(['network','inspect','kz5-install-stage']))[0];
    assert.equal(network.id,s.network);assert.equal(network.labels['io.talkchief.kazoo.acceptance'],s.owner);
    assert.equal(network.subnets[0].subnet,'172.30.253.0/24');assert(/^podman[0-9]+$/.test(network.network_interface));
    const selected=[['kazoo-apps',s.roles['kazoo-apps'],'172.30.253.14'],
        ['kazoo-apps-peer',s.peer,'172.30.253.20'],['couchdb',s.roles.couchdb,'172.30.253.11'],
        ['freeswitch',s.roles.freeswitch,'172.30.253.15'],['kamailio',s.roles.kamailio,'172.30.253.17']];
    for(const [role,r,ip] of selected) {
        assert.equal(r.phase,role==='kazoo-apps-peer'?'installed':'installed-service-verified');
        const c=JSON.parse(podman(['inspect',r.id]))[0];
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
        assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);
        assert.equal(c.State.Running,true);assert.equal(c.State.Paused,false);
    }
    const get=route=>JSON.parse(podman(['exec','-i',s.roles.couchdb.id,'curl','--fail','--silent','--show-error','--config','-'],
        {input:'url = "http://172.30.253.11:5984/'+route+'"\nuser = "admin:'+s.secrets.couch+'"\n'}));
    const master=get('system_config/accounts').default?.master_account_id;
    assert(/^[a-f0-9]{32}$/.test(master));assert.equal(get('accounts/'+master).realm,'installer-stage.invalid');
    const directory=DIR+'/monitor-fixture';
    if(!fs.existsSync(directory))fs.mkdirSync(directory,{mode:0o700});
    const ds=fs.lstatSync(directory);assert(ds.isDirectory()&&!ds.isSymbolicLink()&&ds.uid===0&&(ds.mode&511)===448);
    function copy(source,name) {
        const mode=podman(['exec',s.roles['kazoo-apps'].id,'stat','-c','%u:%a:%h:%F',source]).trim();
        assert.equal(mode,'0:600:1:regular file');
        const content=podman(['exec',s.roles['kazoo-apps'].id,'cat',source]),file=directory+'/'+name;
        assert(content.length<65536);
        if(fs.existsSync(file)||fs.existsSync(file+'.tmp')) {
            const st=fs.lstatSync(file);assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);
            assert.equal(fs.readFileSync(file,'utf8'),content,'Retained fixture credentials changed; inspect rather than overwrite');
        } else fs.writeFileSync(file,content,{mode:0o600,flag:'wx'});
        return file;
    }
    return {api:'http://172.30.253.20:8000/v2',master,
        base:copy('/etc/kazoo/distributed-acceptance-secrets.env','calls.env'),
        auth:copy('/etc/kazoo/installer-secrets.env','master.env'),
        file:'/etc/kazoo/distributed-monitor-acceptance.json',
        media:s.roles.freeswitch.id,registrar:s.roles.kamailio.id,iface:network.network_interface};
}
module.exports={prepare};
