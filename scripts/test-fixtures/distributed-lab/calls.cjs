'use strict';
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function operation(action,h) {
    const {readState,saveState,ownedNetwork,json,podman,DIR,ROOT}=h,s=readState();ownedNetwork(s);
    assert.equal(s.owner,'distributed-install-v1');
    const app=s.roles['kazoo-apps'];assert(app);
    for(const role of ['couchdb','rabbitmq','haproxy','kazoo-apps','freeswitch','ecallmgr','kamailio']) {
        const r=s.roles[role];assert.equal(r?.phase,'installed-service-verified');
        const c=json(['inspect',r.id])[0];
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
        assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,r.ip);
        assert.equal(c.State.Running,true);assert.equal(c.State.Paused,false);
    }
    if(action==='start') {
        assert(!s.callFixture,'Retain existing or interrupted fixture; do not create a replacement');
        assert.equal(JSON.parse(podman(['exec',s.roles.freeswitch.id,
            '/usr/local/freeswitch/bin/fs_cli','-x','show channels as json'])).row_count,0);
        podman(['exec',app.id,'test','!','-e','/etc/kazoo/distributed-acceptance-secrets.env']);
        const provisioner=ROOT+'/scripts/test-kazoo-call-provision.sh';
        assert.equal(podman(['exec',app.id,'sha256sum',provisioner]).split(' ')[0],hash(fs.readFileSync(provisioner)),
            'Installed fixture library differs from reviewed source');
        const unit='kz5-stage-provision-calls',inside='/var/lib/kazoo-stage/provision-calls.log';
        s.callFixture={phase:'provisioning',unit,inside,log:DIR+'/provision-calls.log',started:new Date().toISOString()};saveState(s);
        podman(['cp',__dirname+'/provision-calls.sh',app.id+':/var/lib/kazoo-stage/provision-calls.sh']);
        podman(['exec',app.id,'install','-m','0600','/dev/null',inside]);
        podman(['exec',app.id,'systemd-run','--unit',unit,'--property=User=root','--property=RemainAfterExit=yes',
            '--property=RuntimeMaxSec=900','--property=StandardOutput=append:'+inside,'--property=StandardError=append:'+inside,
            '/usr/bin/bash','/var/lib/kazoo-stage/provision-calls.sh']);
        console.log(JSON.stringify({status:'PROVISIONING',unit,scope:'three synthetic agents; no calls started'}));return;
    }
    assert.equal(action,'collect');const r=s.callFixture;assert.equal(r?.phase,'provisioning');
    const state=Object.fromEntries(podman(['exec',app.id,'systemctl','show','-p','ActiveState','-p','SubState','-p','Result',
        '-p','ExecMainStatus','-p','ExecMainStartTimestamp',r.unit]).split('\n').map(v=>{const i=v.indexOf('=');return [v.slice(0,i),v.slice(i+1)];}));
    if(state.ActiveState==='activating'||(state.ActiveState==='active'&&state.SubState!=='exited')) {
        console.log(JSON.stringify({status:'PROVISIONING',unit:r.unit}));return;
    }
    podman(['cp',app.id+':'+r.inside,r.log]);fs.chmodSync(r.log,0o600);
    r.phase=state.ExecMainStartTimestamp&&state.Result==='success'&&state.ExecMainStatus==='0'?'provisioned':'failed';
    r.finished=new Date().toISOString();saveState(s);
    assert.equal(r.phase,'provisioned','Fixture provisioning failed; inspect protected log');
    console.log(JSON.stringify({status:'PROVISIONED',log:r.log,callsTested:false}));
}
module.exports={operation};
