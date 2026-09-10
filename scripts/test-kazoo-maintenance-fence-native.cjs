#!/usr/bin/env node
'use strict';
// Real kernel packet acceptance in a fresh network namespace, never host rules.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const net=require('node:net'),dgram=require('node:dgram'),assert=require('node:assert/strict');
const {Fence,kernel}=require('./kazoo-maintenance-fence.cjs');
const sockets=new Set(),servers=[];let root;
function tcp(port,host){return new Promise(resolve=>{
    const s=net.connect({port,host});sockets.add(s);let done=false;
    const finish=v=>{if(!done){done=true;s.destroy();sockets.delete(s);resolve(v);}};
    s.setTimeout(1000,()=>finish(false));s.on('error',()=>finish(false));s.on('close',()=>finish(false));
    s.on('connect',()=>s.write('probe'));s.on('data',data=>finish(data.toString()==='probe'));
});}
function udp(){return new Promise(resolve=>{
    const s=dgram.createSocket('udp4');let done=false;
    const finish=v=>{if(!done){done=true;clearTimeout(timer);s.close();resolve(v);}};
    const timer=setTimeout(()=>finish(false),300);
    s.on('error',()=>finish(false));s.on('message',b=>finish(b.toString()==='probe'));
    s.send('probe',19802,'127.0.0.1',e=>{if(e)finish(false);});
});}
async function listen(port,host){
    const server=net.createServer(s=>{sockets.add(s);s.on('error',()=>{});s.on('close',()=>sockets.delete(s));s.on('data',b=>s.write(b));});
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,host,resolve);});
    servers.push(server);
}
async function main(){try{
    assert.equal(process.getuid(),0);assert.deepEqual(process.argv.slice(2),[]);
    assert.notEqual(fs.readlinkSync('/proc/self/ns/net'),fs.readlinkSync('/proc/1/ns/net'));
    cp.execFileSync('/usr/sbin/ip',['link','set','lo','up']);
    // A separate table must survive every close/reapply/release untouched.
    cp.execFileSync('/usr/sbin/nft',['-f','-'],{input:'create table inet kz5_fixture_unrelated { comment "preserve"; }\n'});
    await listen(19800,'127.0.0.1');await listen(19800,'::1');await listen(19801,'127.0.0.1');
    const u=dgram.createSocket('udp4');u.on('message',(b,r)=>u.send(b,r.port,r.address));
    await new Promise((resolve,reject)=>{u.once('error',reject);u.bind(19802,'127.0.0.1',resolve);});servers.push(u);
    assert(await tcp(19800,'127.0.0.1'));assert(await tcp(19800,'::1'));assert(await udp());
    const existing=net.connect({host:'127.0.0.1',port:19800});sockets.add(existing);
    await new Promise((resolve,reject)=>{existing.once('connect',resolve);existing.once('error',reject);});
    root=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-fence-native-'));fs.chmodSync(root,0o700);
    const f=new Fence(root),spec={schema_version:1,generation:'a'.repeat(32),manifest_sha256:'b'.repeat(64),
        roles:['kazoo-apps'],tcp_ports:[19800],udp_ports:[19802]};
    f.close(spec);f.verify(spec.generation);
    const oldBlocked=await new Promise(resolve=>{
        const timer=setTimeout(()=>resolve(false),1000);
        const blocked=()=>{clearTimeout(timer);resolve(true);};
        existing.once('error',blocked);existing.once('close',blocked);existing.once('data',()=>{clearTimeout(timer);resolve(false);});
        existing.write('must-not-pass');
    });assert(oldBlocked,'Preexisting TCP admission survived fence');
    assert.equal(await tcp(19800,'127.0.0.1'),false);assert.equal(await tcp(19800,'::1'),false);
    assert.equal(await udp(),false);assert(await tcp(19801,'127.0.0.1'));
    // Simulate loss of volatile kernel state; persistent intent must reinstate it.
    kernel.remove();assert.throws(()=>f.verify(spec.generation));f.bootGuard();
    assert.equal(await tcp(19800,'127.0.0.1'),false);f.verify(spec.generation);
    f.release(spec.generation);assert(await tcp(19800,'127.0.0.1'));assert(await tcp(19800,'::1'));assert(await udp());
    const other=JSON.parse(cp.execFileSync('/usr/sbin/nft',['-j','list','table','inet','kz5_fixture_unrelated']));
    assert(other.nftables.some(r=>r.table?.comment==='preserve'));assert(!kernel.present());
    console.log(JSON.stringify({status:'PASS',ipv4_tcp:true,ipv6_tcp:true,udp:true,existing_tcp_blocked:true,
        unrelated_port_survives:true,unrelated_table_preserved:true,kernel_state_loss_reapply:true,release_restores_access:true,
        complete_cluster_fence_proven:false}));
}finally{
    for(const s of sockets)s.destroy();for(const s of servers)await new Promise(resolve=>s.close(resolve));
    if(root){assert(path.basename(root).startsWith('kazoo-fence-native-'));fs.rmSync(root,{recursive:true});}
}}
main().catch(()=>{console.error('NATIVE_MAINTENANCE_FENCE_FAILED');process.exitCode=1;});
