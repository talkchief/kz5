'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {validate,probeCommand}=require('./media-fence.cjs');
const owner='a'.repeat(32),media='b'.repeat(64),id='11111111-1111-4111-8111-111111111111';
const r={schema_version:1,owner,media,generation:'c'.repeat(32),source:'d'.repeat(40),manifest_sha256:'e'.repeat(64),mode:'whisper',phase:'closed',probes:[id]};
test('only bounded private media-fence records are accepted',()=>{
    assert.equal(validate(r,owner,media),r);
    for(const bad of [{owner:'f'.repeat(32)},{media:'f'.repeat(64)},{generation:'../../file'},{generation:[r.generation]},
        {source:'HEAD'},{manifest_sha256:'bad'},{phase:'completed'},{mode:'raw'},{probes:[id,id]},{probes:[';rm -rf /']},{probes:[[id]]}])
        assert.throws(()=>validate({...r,...bad},owner,media));
    assert.throws(()=>validate(r,owner,undefined));
});
test('internal probe cannot dial a phone/PSTN address or inject CLI fields',()=>{
    assert.equal(probeCommand(id,r.generation),`originate {origination_uuid=${id},kazoo_maintenance_test=${r.generation},originate_timeout=3}null/kazoo-maintenance &park()`);
    for(const bad of ['sofia/gateway/route','123,ignore_early_media=true',';shutdown',[id]])assert.throws(()=>probeCommand(bad,r.generation));
    assert.throws(()=>probeCommand(id,'bad}sofia/gateway/route'));
});
test('live harness requires explicit private mode, fences the measured RTP window and keeps cleanup state',()=>{
    const source=fs.readFileSync(path.join(__dirname,'../../test-channel-monitor-live.cjs'),'utf8');
    assert(source.includes("if(args[0]==='--media-fence')"));
    assert(source.includes('[partitionEnabled,queuePartitionEnabled,mediaFenceEnabled].filter(Boolean).length<=1'));
    assert(source.includes('if(mediaFenceEnabled)await mediaContext().begin(mode)'));
    assert(source.includes('digit.time+2>=mediaProof.closed_at&&digit.time+5<=mediaProof.released_at'));
    assert(source.includes('if(fixture?.media_fence)'));
    assert(source.includes('await mediaContext().release(true)'));
});
