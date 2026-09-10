'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {Fence,validateSpec,nftInput,expectedRules}=require('./kazoo-maintenance-fence.cjs');
const spec={schema_version:1,generation:'a'.repeat(32),manifest_sha256:'b'.repeat(64),
    roles:['kazoo-apps'],tcp_ports:[8000,8443,5555],udp_ports:[]};
function fixture(t){
    const root=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-fence-test-'));fs.chmodSync(root,0o700);
    t.after(()=>{assert(path.basename(root).startsWith('kazoo-fence-test-'));fs.rmSync(root,{recursive:true});});
    const k={value:null,ssh:[],creates:0,removes:0,present(){return this.value!==null;},
        rules(){return {nftables:[{metainfo:{version:'fixture'}},...this.value]};},
        create(s){assert.equal(this.value,null);this.value=expectedRules(s);this.creates++;},
        remove(){this.value=null;this.removes++;},sshPorts(){return this.ssh;}};
    return {root,k,f:new Fence(root,k)};
}
test('validate bounded injection-free specs and protect common control-plane ports',()=>{
    assert.deepEqual(validateSpec(spec).tcp_ports,[5555,8000,8443]);
    for(const extra of [{generation:'bad"; flush ruleset'}, {tcp_ports:[22]}, {udp_ports:[5672]},
        {tcp_ports:[8000,8000]},{tcp_ports:['8000']},{tcp_ports:[65536]}, {roles:['database']},
        {roles:['kazoo-apps','kazoo-apps']},{tcp_ports:[],udp_ports:[]},{extra:'forbidden'}])
        assert.throws(()=>validateSpec({...spec,...extra}));
    const input=nftInput(spec);assert(input.startsWith('create table inet kz5_maintenance'));
    assert(!input.includes('flush'));assert(input.includes('priority -300'));
});
test('durable closing intent, repeat close and exact generation verification',t=>{
    const {f,k,root}=fixture(t);f.close(spec);f.close(spec);
    assert.equal(k.creates,1);assert.equal(f.verify(spec.generation).state,'closed');
    assert.equal(fs.statSync(path.join(root,'active.json')).mode&0o777,0o600);
    assert.throws(()=>f.close({...spec,generation:'c'.repeat(32)}));
    assert.throws(()=>f.verify('c'.repeat(32)));assert.equal(k.removes,0);
});
test('refuse SSH/systemd socket ports before writing closing intent',t=>{
    const {f,k,root}=fixture(t);k.ssh=[8000];assert.throws(()=>f.close(spec),/SSH/);
    assert(!fs.existsSync(path.join(root,'active.json')));assert.equal(k.creates,0);
});
test('unknown or changed kernel fence is never overwritten or deleted',t=>{
    const {f,k,root}=fixture(t);k.value=expectedRules({...spec,generation:'c'.repeat(32)});
    assert.throws(()=>f.close(spec),/Unowned/);assert(!fs.existsSync(path.join(root,'active.json')));
    k.value=null;f.close(spec);k.value[1].chain.policy='drop';
    assert.throws(()=>f.close(spec),/drift/);assert.throws(()=>f.verify(spec.generation),/drift/);
    assert.throws(()=>f.release(spec.generation),/drift/);assert.equal(k.removes,0);
});
test('additional rules and dormant table flags invalidate proof',t=>{
    const {f,k}=fixture(t);f.close(spec);k.value[0].table.flags=['dormant'];
    assert.throws(()=>f.verify(spec.generation),/drift/);delete k.value[0].table.flags;
    k.value.push({rule:{family:'inet',table:'kz5_maintenance',chain:'ingress',expr:[{accept:null}]}});
    assert.throws(()=>f.verify(spec.generation),/drift/);
});
test('failed kernel creation retains intent and boot guard reinstates the fence',t=>{
    const {f,k,root}=fixture(t),create=k.create;k.create=()=>{throw Error('fixture failure');};
    assert.throws(()=>f.close(spec));assert(fs.existsSync(path.join(root,'active.json')));
    assert.throws(()=>f.verify(spec.generation),/missing/);
    k.create=create;assert.equal(f.bootGuard().state,'closed');
    k.value=null;assert.equal(f.bootGuard().state,'closed');assert.equal(k.creates,2);
});
test('release archives the generation, is idempotent and rejects later stale close',t=>{
    const {f,k,root}=fixture(t);f.close(spec);f.release(spec.generation);f.release(spec.generation);
    assert.equal(k.removes,1);assert.equal(f.bootGuard().state,'open');
    assert(fs.existsSync(path.join(root,'released-'+spec.generation+'.json')));
    assert(!fs.existsSync(path.join(root,'active.json')));assert.throws(()=>f.close(spec),/reused/);
    f.close({...spec,generation:'c'.repeat(32)});
    assert.throws(()=>f.release(spec.generation),/Stale/);assert.equal(k.removes,1);
});
test('interrupted removal cannot reopen startup or restore proof; only matching release resumes',t=>{
    const {f,k,root}=fixture(t);f.close(spec);const remove=k.remove;
    k.remove=function(){this.value=null;throw Error('fixture interruption');};
    assert.throws(()=>f.release(spec.generation));assert(fs.existsSync(path.join(root,'releasing.json')));
    assert.throws(()=>f.bootGuard(),/Interrupted/);assert.throws(()=>f.verify(spec.generation),/progress/);
    assert.throws(()=>f.close(spec),/Interrupted/);assert.throws(()=>f.release('c'.repeat(32)),/Stale/);
    k.remove=remove;assert.equal(f.release(spec.generation).state,'open');
    assert(!fs.existsSync(path.join(root,'releasing.json')));
});
test('unsafe/truncated state cannot fall back to open admission',t=>{
    const {f,root}=fixture(t),file=path.join(root,'active.json');
    fs.writeFileSync(file,'{',{mode:0o600});assert.throws(()=>f.bootGuard());
    fs.writeFileSync(file,JSON.stringify(spec));fs.chmodSync(file,0o644);assert.throws(()=>f.bootGuard());
    fs.chmodSync(file,0o600);fs.linkSync(file,path.join(root,'alias'));assert.throws(()=>f.bootGuard());
    fs.unlinkSync(path.join(root,'alias'));fs.renameSync(file,path.join(root,'alias'));
    fs.symlinkSync(path.join(root,'alias'),file);assert.throws(()=>f.bootGuard());
});
test('missing active intent with an orphaned kernel table refuses normal startup',t=>{
    const {f,k}=fixture(t);assert.equal(f.bootGuard().state,'open');k.value=expectedRules(spec);
    assert.throws(()=>f.bootGuard(),/Orphaned/);assert.equal(k.removes,0);
});
test('status never repairs a missing fence or accepts interrupted release',t=>{
    const {f,k}=fixture(t);assert.equal(f.status().state,'open');f.close(spec);
    assert.equal(f.status().state,'closed');k.value=null;
    assert.throws(()=>f.status(),/missing/);assert.equal(k.creates,1);
    f.bootGuard();k.remove=function(){this.value=null;throw Error('fixture interruption');};
    assert.throws(()=>f.release(spec.generation));assert.throws(()=>f.status(),/Interrupted/);
});
