'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {MediaFence,spec,epoch}=require('./kazoo-maintenance-media.cjs');
const input={schema_version:1,generation:'a'.repeat(32),manifest_sha256:'b'.repeat(64)};
function fixture(t){
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-media-intent-'));
    const root=path.join(dir,'private'),pub=path.join(dir,'public');fs.mkdirSync(root,{mode:0o700});fs.mkdirSync(pub,{mode:0o755});fs.chmodSync(pub,0o755);
    t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
    const k={calls:0,fail:false,sessions:0,observe(){this.calls++;if(this.fail)throw Error('native unavailable');return {admission:fs.existsSync(path.join(pub,'media.closed'))?'closed':'open',sessions:this.sessions};}};
    return {root,pub,k,f:new MediaFence(root,pub,()=>k.observe(),()=>{})};
}
test('media spec is exact and bounded',()=>{
    assert.deepEqual(spec(input),input);
    for(const bad of [{extra:1},{generation:'../bad'},{generation:[input.generation]},{manifest_sha256:[input.manifest_sha256]},{schema_version:2}])assert.throws(()=>spec({...input,...bad}));
});
function processFixture(){
    const calls=[],status='Uid:\t999\t999\t999\t999\n',boot='11111111-1111-1111-1111-111111111111';
    const io={command(bin,args){calls.push([bin,args]);if(bin==='/usr/bin/systemctl')return '123';if(bin==='/usr/bin/id')return '999';
        assert.deepEqual([bin,args],['/usr/sbin/runuser',['-u','freeswitch','--','/usr/bin/readlink','/proc/123/exe']]);return '/usr/local/freeswitch/bin/freeswitch';},
        read(p){if(p.endsWith('/status'))return status;if(p.endsWith('/stat'))return '123 (freeswitch) S '+Array(18).fill('0').join(' ')+' 456';return boot;},
        readlink(){throw Object.assign(Error('restricted proc'),{code:'EACCES'});}};
    return {io,calls,boot};
}
test('restricted container proc identity is verified as the service UID without ptrace privileges',()=>{
    const {io,calls,boot}=processFixture();assert.deepEqual(epoch(io),{pid:123,start_ticks:'456',boot_id:boot});
    assert(calls.some(([bin])=>bin==='/usr/sbin/runuser'));
});
test('wrong service credentials refuse before same-UID proc fallback',()=>{
    const {io,calls}=processFixture(),read=io.read;io.read=p=>p.endsWith('/status')?'Uid:\t0\t0\t0\t0\n':read(p);
    assert.throws(()=>epoch(io),/unexpected credentials/);assert(!calls.some(([bin])=>bin==='/usr/sbin/runuser'));
});
test('unexpected executable or non-permission proc failure is never bypassed',()=>{
    const {io,calls}=processFixture();io.readlink=()=>'/usr/bin/other';assert.throws(()=>epoch(io));
    io.readlink=()=>{throw Object.assign(Error('process gone'),{code:'ENOENT'});};assert.throws(()=>epoch(io),/process gone/);
    assert(!calls.some(([bin])=>bin==='/usr/sbin/runuser'));
});
test('close persists intent before marking and native observation; current sessions are not killed',t=>{
    const {f,k,root,pub}=fixture(t);k.sessions=3;const mark=f.mark.bind(f);
    f.mark=s=>{assert(fs.existsSync(path.join(root,'active.json')));mark(s);};
    const proof=f.close(input);assert.equal(proof.native.sessions,3);assert.equal(f.verify(input.generation).state,'closed');f.close(input);
    assert.equal(fs.statSync(path.join(root,'active.json')).mode&511,0o600);
    assert.equal(fs.statSync(path.join(pub,'media.closed')).mode&511,0o644);
});
test('unsupported or unavailable native core refuses new closing intent',t=>{
    const {f,k,root,pub}=fixture(t);k.fail=true;assert.throws(()=>f.close(input));
    assert(!fs.existsSync(path.join(root,'active.json')));assert(!fs.existsSync(path.join(pub,'media.closed')));
});
test('failed marker creation retains intent and boot repairs before media starts',t=>{
    const {f,k,root}=fixture(t),mark=f.mark;f.mark=()=>{throw Error('write failed');};
    assert.throws(()=>f.close(input));assert(fs.existsSync(path.join(root,'active.json')));
    f.mark=mark;k.fail=true;assert.equal(f.bootGuard().state,'closed');k.fail=false;assert.equal(f.verify(input.generation).state,'closed');
});
test('volatile marker loss is repaired only by explicit close or startup guard',t=>{
    const {f,pub}=fixture(t);f.close(input);fs.unlinkSync(path.join(pub,'media.closed'));
    assert.throws(()=>f.status());assert.throws(()=>f.verify(input.generation));
    assert.equal(f.bootGuard().state,'closed');assert.equal(f.status().state,'closed');
});
test('startup refuses an unsupported rollback library and retains the closed marker',t=>{
    const {f,pub}=fixture(t);f.close(input);f.support=()=>{throw Error('unsupported library');};
    assert.throws(()=>f.bootGuard());assert(fs.existsSync(path.join(pub,'media.closed')));
});
test('corrupt intent and orphaned marker block startup and are not overwritten',t=>{
    const {f,root,pub}=fixture(t);fs.writeFileSync(path.join(pub,'media.closed'),JSON.stringify(input),{mode:0o644});
    assert.throws(()=>f.close(input));assert.throws(()=>f.bootGuard());fs.unlinkSync(path.join(pub,'media.closed'));
    fs.writeFileSync(path.join(root,'active.json'),'{',{mode:0o600});assert.throws(()=>f.bootGuard());
});
test('foreign generation and symlink marker refuse verify/release without changing it',t=>{
    const {f,pub}=fixture(t);f.close(input);assert.throws(()=>f.close({...input,generation:'c'.repeat(32)}));
    assert.throws(()=>f.release('c'.repeat(32)));fs.unlinkSync(path.join(pub,'media.closed'));fs.symlinkSync('missing',path.join(pub,'media.closed'));
    assert.throws(()=>f.verify(input.generation));assert.throws(()=>f.release(input.generation));assert(fs.lstatSync(path.join(pub,'media.closed')).isSymbolicLink());
});
test('release archives the generation and refuses stale restore/reuse',t=>{
    const {f,root}=fixture(t);f.close(input);f.release(input.generation);assert.equal(f.bootGuard().state,'open');f.release(input.generation);
    assert(fs.existsSync(path.join(root,'released-'+input.generation+'.json')));assert.throws(()=>f.close(input));
    f.close({...input,generation:'c'.repeat(32)});assert.throws(()=>f.release(input.generation));
});
test('interrupted release keeps durable releasing state and blocks startup',t=>{
    const {f,root}=fixture(t);f.close(input);const unmark=f.unmark;f.unmark=()=>{throw Error('remove failed');};
    assert.throws(()=>f.release(input.generation));assert(fs.existsSync(path.join(root,'releasing.json')));
    assert.throws(()=>f.bootGuard());assert.throws(()=>f.close(input));assert.throws(()=>f.verify(input.generation));
    f.unmark=unmark;assert.equal(f.release(input.generation).state,'open');
});
test('lost response after unmark never silently recloses or replays restore',t=>{
    const {f,k,pub}=fixture(t);f.close(input);const unmark=f.unmark.bind(f);f.unmark=s=>{unmark(s);k.fail=true;};
    assert.throws(()=>f.release(input.generation));assert(!fs.existsSync(path.join(pub,'media.closed')));assert.throws(()=>f.bootGuard());
    f.unmark=unmark;k.fail=false;assert.equal(f.release(input.generation).state,'open');
});
