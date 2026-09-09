'use strict';
const assert=require('node:assert/strict'),{config,prepare}=require('./bridge.cjs');
const c=config('a'.repeat(64));
assert.equal(c.PUSH_BRIDGE_AMQP_HOST,'172.30.253.12');
assert.equal(c.PUSH_BRIDGE_AMQP_VHOST,'kz5-stage-mobile-only');
assert.equal(c.PUSH_BRIDGE_BINDING_KEY,'acceptance.never');
assert(!Object.keys(c).some(k=>/TOKEN|PAYLOAD|TEST/.test(k)));
assert.throws(()=>config('bad'));
for(const state of [{owner:'other'},{owner:'distributed-install-v1',bridgeFixture:{}},
    {owner:'distributed-install-v1',roles:{}},
    {owner:'distributed-install-v1',roles:{'push-bridge':{phase:'installing'},rabbitmq:{phase:'installed-service-verified'}}}])
    assert.throws(()=>prepare({readState:()=>state,ownedNetwork:()=>{},saveState:()=>{throw Error('Must refuse before write');}}));
console.log('PASS fixed bridge fixture config and pre-write ownership/phase refusals; no broker or provider contacted');
