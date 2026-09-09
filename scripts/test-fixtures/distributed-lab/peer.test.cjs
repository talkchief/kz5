'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');
const {peerSettings,peerConfig,assertPrimary}=require('./peer.cjs');
const base={KAZOO_AMQP_HOST:'172.30.253.12',KAZOO_COUCHDB_HOST:'172.30.253.13',KAZOO_PUBLIC_IP:'172.30.253.14'};
const c=peerConfig(base);assert.equal(c.KAZOO_PUBLIC_IP,'172.30.253.20');
assert.equal(c.KAZOO_ERLANG_DIST_IP,c.KAZOO_PUBLIC_IP);
assert.equal(c.KAZOO_BOOTSTRAP_MASTER_ACCOUNT,'false');assert.equal(base.KAZOO_PUBLIC_IP,'172.30.253.14');
for(const key of ['KAZOO_AMQP_HOST','KAZOO_COUCHDB_HOST'])assert.throws(()=>peerConfig({...base,[key]:'10.1.0.44'}));
const state={owner:'distributed-install-v1',roles:{'kazoo-apps':{phase:'installed-service-verified'}}};
const container={Config:{Labels:{'io.talkchief.kazoo.acceptance':state.owner,'io.talkchief.kazoo.role':'kazoo-apps'}},
    State:{Running:true},NetworkSettings:{Networks:{'kz5-install-stage':{IPAddress:'172.30.253.14'}}}};
assertPrimary(state,container);
assert.throws(()=>assertPrimary({...state,owner:'other'},container));
assert.throws(()=>assertPrimary(state,{...container,State:{Running:false}}));
assert.throws(()=>assertPrimary(state,{...container,Config:{Labels:{}}}));
assert.throws(()=>assertPrimary(state,{...container,State:{Running:true,Paused:true}}));
assert.throws(()=>peerSettings('production'));
const ec=peerConfig(base,'ecallmgr');assert.equal(ec.KAZOO_PUBLIC_IP,'172.30.253.21');
assert.equal(ec.KAZOO_ERLANG_DIST_IP,ec.KAZOO_PUBLIC_IP);
assert.equal(peerSettings('ecallmgr').key,'ecallmgrPeer');
assert.equal(peerSettings().key,'peer');
assert.notEqual(peerSettings().filePrefix,peerSettings('ecallmgr').filePrefix);
const ecState={owner:state.owner,roles:{ecallmgr:{phase:'installed-service-verified'}}};
const ecContainer={...container,Config:{Labels:{'io.talkchief.kazoo.acceptance':state.owner,'io.talkchief.kazoo.role':'ecallmgr'}},
    NetworkSettings:{Networks:{'kz5-install-stage':{IPAddress:'172.30.253.16'}}}};
assertPrimary(ecState,ecContainer,'ecallmgr');
assert.throws(()=>assertPrimary(ecState,container,'ecallmgr'));
assert(fs.readFileSync(__dirname+'/peer-admission/kazoo-ecallmgr.service.d/99-kz5-peer-admission.conf','utf8')
    .includes('ExecCondition=/usr/bin/test ${KAZOO_ERLANG_DIST_IP} = 172.30.253.21'));
assert(fs.readFileSync(__dirname+'/peer-admission/kazoo-apps.service.d/99-kz5-peer-admission.conf','utf8')
    .includes('ExecCondition=/usr/bin/test ${KAZOO_ERLANG_DIST_IP} = 172.30.253.20'));
console.log('PASS peer scope/configuration/startup admission guards; no containers or credentials created');
