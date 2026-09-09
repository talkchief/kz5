'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');
const {overlapsSubnet,ROLES,configFor}=require('./lab.cjs');
for(const dst of ['default',undefined,'10.1.0.0/16','172.30.252.0/24','172.30.254.0/24','46.225.31.248/32'])assert.equal(overlapsSubnet(dst),false);
for(const dst of ['172.30.253.0/24','172.30.253.12/32','172.30.252.0/23','172.16.0.0/12','0.0.0.0/0'])assert.equal(overlapsSubnet(dst),true);
for(const dst of ['172.30.253.0/33','bad/24','172.300.0.0/16','172.30.0.0/2.5'])assert.throws(()=>overlapsSubnet(dst));
assert.equal(new Set(ROLES).size,9);
const src=fs.readFileSync(__dirname+'/lab.cjs','utf8');
assert(src.includes("'--property=User=root'"),'Detached builds require the root login environment');
assert(src.includes("'--property=RemainAfterExit=yes'"),'Retain successful unit exit evidence until collection');
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
assert.throws(()=>configFor('push-bridge',testSecrets));
assert.throws(()=>configFor('unknown',testSecrets));
console.log('PASS 28 distributed-lab subnet, role, configuration and isolation groups; no containers or credentials created');
