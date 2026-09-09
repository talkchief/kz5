'use strict';
// Fresh installer fixture only: invented provider identity, private dedicated
// broker namespace, no device token, no publish and no production credentials.
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const NAME='kz5-stage-mobile-only',USER='kz5_stage_mobile';
function config(password) {
    assert(/^[a-f0-9]{64}$/.test(password));
    const values={SA_FILE:'/etc/kazoo-push-bridge/firebase-service-account.json',
        AMQP_HOST:'172.30.253.12',AMQP_PORT:'5672',AMQP_USER:USER,AMQP_PASS:password,
        AMQP_VHOST:NAME,EXCHANGE:NAME,QUEUE:NAME,BINDING_KEY:'acceptance.never',
        FCM_SCOPE:'https://www.googleapis.com/auth/firebase.messaging',
        FCM_URL_TEMPLATE:'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send',
        WORKERS:'2',APNS_WORKERS:'1',STALL_TIMEOUT:'70'};
    return Object.fromEntries(Object.entries(values).map(([k,v])=>['PUSH_BRIDGE_'+k,v]));
}
function prepare(h) {
    const {readState,saveState,ownedNetwork,json,podman,DIR}=h,s=readState();ownedNetwork(s);
    assert.equal(s.owner,'distributed-install-v1');assert(!s.bridgeFixture,'Retain existing/partial fixture for inspection');
    const r=s.roles['push-bridge'],broker=s.roles.rabbitmq;
    assert.equal(r?.phase,'booted-source-ready');assert.equal(broker?.phase,'installed-service-verified');
    for(const [role,record,ip] of [['push-bridge',r,'172.30.253.19'],['rabbitmq',broker,'172.30.253.12']]) {
        const c=json(['inspect',record.id])[0];
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
        assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);
        assert.equal(c.State.Running,true);assert.equal(c.State.Paused,false);
    }
    podman(['exec',r.id,'test','!','-e','/etc/kazoo-push-bridge']);
    const vhosts=JSON.parse(podman(['exec',broker.id,'rabbitmqctl','-q','list_vhosts','name','--formatter','json']));
    const users=JSON.parse(podman(['exec',broker.id,'rabbitmqctl','-q','list_users','--formatter','json']));
    assert(!vhosts.some(v=>v.name===NAME));assert(!users.some(u=>u.user===USER));
    const password=crypto.randomBytes(32).toString('hex');
    s.bridgeFixture={phase:'preparing',vhost:NAME,user:USER,password,provider:'synthetic-no-delivery'};saveState(s);
    podman(['exec',broker.id,'rabbitmqctl','add_vhost',NAME]);
    podman(['exec','-i',broker.id,'rabbitmqctl','add_user',USER],{input:password+'\n'});
    const resource='^'+NAME+'$';
    podman(['exec',broker.id,'rabbitmqctl','set_permissions','-p',NAME,USER,resource,resource,resource]);
    const dir=DIR+'/bridge-fixture';fs.mkdirSync(dir,{mode:0o700});
    const pair=crypto.generateKeyPairSync('rsa',{modulusLength:2048,
        privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}});
    const serviceAccount={type:'service_account',project_id:'kz5-synthetic-fixture',
        private_key:pair.privateKey,client_email:'fixture@kz5-synthetic-fixture.iam.gserviceaccount.com',
        token_uri:'https://oauth2.googleapis.com/token'};
    for(const [name,body] of [['config.json',config(password)],['firebase-service-account.json',serviceAccount]])
        fs.writeFileSync(dir+'/'+name,JSON.stringify(body)+'\n',{mode:0o600,flag:'wx'});
    podman(['exec',r.id,'install','-d','-m','0700','/etc/kazoo-push-bridge']);
    for(const name of ['config.json','firebase-service-account.json']) {
        podman(['cp',dir+'/'+name,r.id+':/etc/kazoo-push-bridge/'+name]);
        podman(['exec',r.id,'chmod','0600','/etc/kazoo-push-bridge/'+name]);
    }
    s.bridgeFixture.phase='prepared';saveState(s);
    console.log(JSON.stringify({status:'BRIDGE_FIXTURE_PREPARED',scope:'private legacy transport installation; no provider delivery, quorum or TLS claim'}));
}
module.exports={config,prepare};
