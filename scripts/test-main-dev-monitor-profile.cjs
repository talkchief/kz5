'use strict';
const assert=require('node:assert/strict');
const {validate,masterIdentity}=require('./test-fixtures/main-dev-monitor-profile.cjs');
const config={KAZOO_ROOT:'/opt/kz5',KAZOO_COUCHDB_HOST:'10.1.0.44',
    KAZOO_AMQP_HOST:'10.1.0.44',KAZOO_PUBLIC_HOSTNAME:'kz5-dev.talkchief.io'};
const master='a'.repeat(32);
assert.deepEqual(validate('dev-testing',['127.0.0.1','10.1.0.44'],config,master),{master,proxy:'10.1.0.44'});
assert.throws(()=>validate('production',['10.1.0.44'],config,master));
assert.throws(()=>validate('dev-testing',['10.1.0.10'],config,master));
for(const key of Object.keys(config))assert.throws(()=>validate('dev-testing',['10.1.0.44'],{...config,[key]:'other'},master));
for(const invalid of ['',null,'../credentials','0'.repeat(33)])assert.throws(()=>validate('dev-testing',['10.1.0.44'],config,invalid));
const reply={status:0,stdout:'{ok,<<"'+master+'">>}\n'};
assert.equal(masterIdentity(reply),master);
for(const mutation of [{status:1},{status:null},{error:Error('timeout')},{stdout:''},
    {stdout:'{error,not_found}'},{stdout:reply.stdout+'extra'}, {stdout:'{ok,<<"../file">>}'}])
    assert.throws(()=>masterIdentity({...reply,...mutation}));
console.log('PASS main-dev monitor profile: exact host, local dependencies, source root, public hostname and native master identity guards');
