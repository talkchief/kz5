'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {empty,changed,probeCommand}=require('./test-kazoo-maintenance-media-restart.cjs');
test('native restart evidence requires empty matching admission and changed process/core',()=>{
    const a={state:'closed',native:{admission:'closed',sessions:0,process:{pid:3},core_uuid:'first'}};
    assert.equal(empty(a,'closed'),a);
    assert.throws(()=>empty({...a,native:{...a.native,sessions:1}},'closed'));
    assert.throws(()=>empty(a,'open'));assert.throws(()=>changed(a,a));
    assert.throws(()=>changed(a,{...a,native:{...a.native,process:{pid:4}}}));
    changed(a,{state:'closed',native:{...a.native,process:{pid:4},core_uuid:'second'}});
});
test('restart probes cannot select a real phone, dial string, or arbitrary command',()=>{
    const id='11111111-1111-4111-8111-111111111111',g='a'.repeat(32);
    assert(probeCommand(id,g).endsWith('null/kazoo-maintenance &park()'));
    for(const bad of ['sofia/gateway/a',';shutdown',[id]])assert.throws(()=>probeCommand(bad,g));
    assert.throws(()=>probeCommand(id,'bad}sofia/gateway/a'));
});
test('native harness is explicit and retains failed evidence and owned marker',()=>{
    const source=fs.readFileSync(require.resolve('./test-kazoo-maintenance-media-restart.cjs'),'utf8');
    assert(source.includes("assert.deepEqual(process.argv.slice(2),['--live'])"));
    assert(source.includes("assert.equal(os.hostname(),'kz5-stage-freeswitch')"));
    assert(source.includes("fs.renameSync(MARKER,dir+'/retained-marker.json')"));
    assert(source.includes("receipt.failed_phase=receipt.phase"));
    assert(source.includes("receipt.status=pass&&receipt.scoped_cleanup_verified?'PASS':'FAIL'"));
});
