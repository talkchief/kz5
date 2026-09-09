'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');
const {overlapsSubnet,ROLES,configFor,separateNamespace,settingsFor,assertFreshDatabases,requirePersistentPivot,assertColdPark}=require('./lab.cjs');
assert.throws(()=>separateNamespace({dev:1,ino:2},{dev:1,ino:2}));
separateNamespace({dev:1,ino:3},{dev:1,ino:2});
separateNamespace({dev:2,ino:2},{dev:1,ino:2});
for(const dst of ['default',undefined,'10.1.0.0/16','172.30.252.0/24','172.30.254.0/24','46.225.31.248/32'])assert.equal(overlapsSubnet(dst),false);
for(const dst of ['172.30.253.0/24','172.30.253.12/32','172.30.252.0/23','172.16.0.0/12','0.0.0.0/0'])assert.equal(overlapsSubnet(dst),true);
for(const dst of ['172.30.253.0/33','bad/24','172.300.0.0/16','172.30.0.0/2.5'])assert.throws(()=>overlapsSubnet(dst));
assert.equal(new Set(ROLES).size,9);
const src=fs.readFileSync(__dirname+'/lab.cjs','utf8');
assert(src.includes("'--property=User=root'"),'Detached builds require the root login environment');
assert(src.includes("'--property=RemainAfterExit=yes'"),'Retain successful unit exit evidence until collection');
assert(src.includes("'--sysctl','net.ipv4.ip_local_reserved_ports=34512-34513'"));
assert(src.includes("'--net=/proc/self/fd/3'"),'Pin only the owned network namespace');
assert(!src.includes("'--privileged'")&&!src.includes("'--network=host'")&&!src.includes("'--publish'"));
assert(src.indexOf('saveState(s);\n    podman')<src.indexOf("['network','create'"));
const isolation=fs.readFileSync(__dirname+'/kazoo-stage-isolation.service','utf8');
assert(isolation.includes('route replace blackhole 10.1.0.0/16'));
assert(isolation.includes('Before=network-pre.target network.target network-online.target'));
const testSecrets={rabbit:'test-rabbit',couch:'test-couch'};
for(const role of ROLES.slice(0,7)) {
    const c=configFor(role,testSecrets);
    assert.equal(c.KAZOO_RABBITMQ_PASSWORD,testSecrets.rabbit);
    assert.equal(c.KAZOO_COUCHDB_PASSWORD,testSecrets.couch);
    assert.equal(c.KAZOO_RABBITMQ_BIND,c.KAZOO_PUBLIC_IP);
    assert.equal(c.KAZOO_COUCHDB_HOST,['couchdb','rabbitmq','haproxy'].includes(role)?'172.30.253.11':'172.30.253.13');
    assert(!JSON.stringify(c).includes('10.1.0.'));
}
assert.equal(configFor('push-bridge',testSecrets).KAZOO_PUBLIC_IP,'172.30.253.19');
assert.throws(()=>configFor('unknown',testSecrets));
const cold=settingsFor(true),normal=settingsFor(false);
const final=settingsFor(true,true);
assert.throws(()=>settingsFor(false,true));
for(const field of ['dir','owner','network','prefix','name','realm']) {
    assert.notEqual(final[field],normal[field]);assert.notEqual(final[field],cold[field]);
}
assert.equal(overlapsSubnet('172.30.251.0/24',final.prefix),true);
assert.equal(overlapsSubnet('172.30.252.0/24',final.prefix),false);
assert.equal(configFor('kazoo-apps',testSecrets,final).KAZOO_COUCHDB_HOST,'172.30.251.11');
for(const field of ['dir','owner','network','prefix','name','realm'])assert.notEqual(cold[field],normal[field]);
assert.throws(()=>settingsFor('anything'));
assert.equal(overlapsSubnet('172.30.253.0/24',cold.prefix),false);
assert.equal(overlapsSubnet('172.30.252.0/24',cold.prefix),true);
for(const role of ['couchdb','rabbitmq','kazoo-apps']) {
    const c=configFor(role,testSecrets,cold);
    assert.equal(c.KAZOO_COUCHDB_HOST,'172.30.252.11');
    assert.equal(c.KAZOO_COUCHDB_PORT,'5984');
    assert.equal(c.KAZOO_AMQP_HOST,'172.30.252.12');
    assert.equal(c.KAZOO_MASTER_ACCOUNT_REALM,'cold-installer-stage.invalid');
    assert(!JSON.stringify(c).includes('172.30.253.'));
}
assertFreshDatabases([]);assertFreshDatabases(['_users','_replicator']);
assert(src.indexOf('if(!before.monitorProvisioned)provisionMonitor();')<src.indexOf('const cfg=Object.entries(configFor'),
    'Cold apps must receive monitoring credentials before initial configuration is copied');
for(const dbs of [null,{},['_users','accounts'],['system_config'],['account%2Ftest']])
    assert.throws(()=>assertFreshDatabases(dbs));
for(const role of ['kazoo-apps','ecallmgr']) {
    for(const command of [undefined,[],['--sysctl','net.ipv4.ip_local_reserved_ports=34512']])
        assert.throws(()=>requirePersistentPivot(role,command));
    requirePersistentPivot(role,['--sysctl','net.ipv4.ip_local_reserved_ports=34512-34513']);
}
requirePersistentPivot('freeswitch',[]);requirePersistentPivot('kamailio',[]);
const park={owner:cold.owner,roles:Object.fromEntries(['couchdb','rabbitmq','kazoo-apps'].map(role=>[role,
    {phase:'installed-service-verified',guestBootVerified:{log:'/private/receipt'}}]))};
assertColdPark(park,cold);
assert.throws(()=>assertColdPark(park,normal));
assert.throws(()=>assertColdPark({...park,owner:normal.owner},cold));
assert.throws(()=>assertColdPark({...park,roles:{...park.roles,ecallmgr:{}}},cold));
assert.throws(()=>assertColdPark({...park,roles:{...park.roles,'kazoo-apps':{phase:'installed-service-verified'}}},cold));
assert.throws(()=>assertColdPark({...park,roles:{...park.roles,couchdb:{phase:'installing'}}},cold));
console.log('PASS distributed-lab subnet, role, configuration, namespace and cold-bootstrap isolation guards; no containers or credentials created');
