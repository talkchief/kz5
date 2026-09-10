#!/usr/bin/env node
'use strict';
// Local persistent ingress fence for the cluster maintenance coordinator.
// Not a complete drain: media origination, broker/durable work and producer
// completion require separate proofs. Never expire or reopen automatically.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const TABLE = 'kz5_maintenance', ROOT = '/var/lib/kazoo5-maintenance/fence';
const ENV = {PATH:'/usr/sbin:/usr/bin:/sbin:/bin',LC_ALL:'C'};
const exact = (o, keys) => {
    assert(o && typeof o === 'object' && !Array.isArray(o));
    assert.deepEqual(Object.keys(o).sort(), [...keys].sort(), 'Unexpected fence fields');
};
const sha = s => crypto.createHash('sha256').update(s).digest('hex');
function validateSpec(s) {
    exact(s, ['schema_version','generation','manifest_sha256','roles','tcp_ports','udp_ports']);
    assert.equal(s.schema_version,1);
    assert(typeof s.generation==='string' && /^[a-f0-9]{32}$/.test(s.generation));
    assert(typeof s.manifest_sha256==='string' && /^[a-f0-9]{64}$/.test(s.manifest_sha256));
    assert(Array.isArray(s.roles) && s.roles.length>0 && s.roles.length<=4);
    assert(s.roles.every(r=>['kazoo-apps','kamailio','freeswitch','monster-ui'].includes(r)));
    assert.equal(new Set(s.roles).size,s.roles.length);
    for(const ports of [s.tcp_ports,s.udp_ports]) {
        assert(Array.isArray(ports) && ports.length<=32);
        assert.equal(new Set(ports).size,ports.length);
        // Never fence the usual SSH/data/distribution/control-plane ports.
        assert(ports.every(p=>Number.isInteger(p) && p<=65535 && (p>=1024 || p===80 || p===443) &&
            ![2222,4369,5671,5672,5984,5986,15671,15672,34512,34513].includes(p)));
    }
    assert(s.tcp_ports.length+s.udp_ports.length>0);
    return {schema_version:1,generation:s.generation,manifest_sha256:s.manifest_sha256,
        roles:[...s.roles].sort(),tcp_ports:[...s.tcp_ports].sort((a,b)=>a-b),udp_ports:[...s.udp_ports].sort((a,b)=>a-b)};
}
function marker(spec) { return 'kz5:'+spec.generation+':'+sha(JSON.stringify(spec)); }
function nftInput(input) {
    const s=validateSpec(input), lines=[`create table inet ${TABLE} {`, `comment "${marker(s)}"`,
        'chain ingress {', 'type filter hook input priority -300; policy accept;'];
    for(const [proto,ports,verdict] of [['tcp',s.tcp_ports,'reject with tcp reset'],['udp',s.udp_ports,'drop']]) {
        if(ports.length) lines.push(`${proto} dport ${ports.length===1?ports[0]:'{ '+ports.join(', ')+' }'} ${verdict}`);
    }
    return lines.concat(['}','}','']).join('\n');
}
function expectedRules(input) {
    const s=validateSpec(input), rows=[{table:{family:'inet',name:TABLE,comment:marker(s)}},
        {chain:{family:'inet',table:TABLE,name:'ingress',type:'filter',hook:'input',prio:-300,policy:'accept'}}];
    for(const [protocol,ports,verdict] of [['tcp',s.tcp_ports,{reject:{type:'tcp reset'}}],['udp',s.udp_ports,{drop:null}]]) {
        if(ports.length) rows.push({rule:{family:'inet',table:TABLE,chain:'ingress',expr:[
            {match:{op:'==',left:{payload:{protocol,field:'dport'}},right:ports.length===1?ports[0]:{set:ports}}},verdict]}});
    }
    return rows;
}
function normalizeRules(value) {
    exact(value,['nftables']);assert(Array.isArray(value.nftables));
    return value.nftables.filter(row=>!Object.hasOwn(row,'metainfo')).map(row=>{
        const keys=Object.keys(row);assert(keys.length===1&&['table','chain','rule'].includes(keys[0]));
        const copy={...row[keys[0]]};delete copy.handle;return {[keys[0]]:copy};
    });
}
function command(bin,args,input) {
    return cp.execFileSync(bin,args,{encoding:'utf8',input,timeout:15000,maxBuffer:1024*1024,
        env:ENV,stdio:['pipe','pipe','pipe']});
}
const kernel = {
    present() {
        const value=JSON.parse(command('/usr/sbin/nft',['-j','list','tables']));
        exact(value,['nftables']);assert(Array.isArray(value.nftables));
        return value.nftables.some(r=>r.table?.family==='inet'&&r.table?.name===TABLE);
    },
    rules() { return JSON.parse(command('/usr/sbin/nft',['-j','list','table','inet',TABLE])); },
    create(spec) { command('/usr/sbin/nft',['-f','-'],nftInput(spec)); },
    remove() { command('/usr/sbin/nft',['delete','table','inet',TABLE]); },
    sshPorts() {
        const ss=fs.existsSync('/usr/sbin/ss')?'/usr/sbin/ss':'/usr/bin/ss';
        const rows=command(ss,['-H','-ltnp']).trim().split('\n');
        // Protect systemd-owned listening sockets too, including socket-
        // activated SSH whose process is not yet named sshd.
        const ports=rows.filter(r=>/\("(?:sshd(?:-[a-z]+)?|systemd)"[,)]/.test(r)).map(r=>{
            const endpoint=r.trim().split(/\s+/)[3];assert(endpoint);
            const port=Number(endpoint.slice(endpoint.lastIndexOf(':')+1));
            assert(Number.isInteger(port)&&port>0&&port<=65535);return port;
        });
        if(fs.existsSync('/usr/sbin/sshd')) {
            const config=command('/usr/sbin/sshd',['-T']);
            const configured=config.split('\n').filter(l=>/^port [0-9]+$/.test(l)).map(l=>Number(l.slice(5)));
            assert(configured.length>0,'Could not verify configured SSH ports');ports.push(...configured);
        }
        return ports;
    }
};
function privateDir(dir) {
    assert.equal(path.resolve(dir),fs.realpathSync(dir),'Symlinked fence directory');
    const s=fs.lstatSync(dir);assert(s.isDirectory()&&s.uid===process.getuid()&&(s.mode&0o777)===0o700);
}
function syncDir(dir) {
    const fd=fs.openSync(dir,fs.constants.O_RDONLY|fs.constants.O_DIRECTORY|fs.constants.O_NOFOLLOW);
    try{fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
}
function readPrivate(file) {
    let fd;
    try{fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);}
    catch(e){if(e.code==='ENOENT')return null;throw e;}
    try{
        const s=fs.fstatSync(fd);
        assert(s.isFile()&&s.uid===process.getuid()&&s.nlink===1&&(s.mode&0o777)===0o600&&s.size>0&&s.size<=16384);
        return validateSpec(JSON.parse(fs.readFileSync(fd,'utf8')));
    }finally{fs.closeSync(fd);}
}
function writePrivate(file,spec) {
    const fd=fs.openSync(file,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NOFOLLOW,0o600);
    // Keep any interrupted/truncated file: recovery must not silently ignore it.
    try{fs.writeFileSync(fd,JSON.stringify(spec)+'\n');fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
    syncDir(path.dirname(file));
}
class Fence {
    constructor(root,adapter=kernel) { privateDir(root);this.root=root;this.kernel=adapter; }
    file(name){privateDir(this.root);return path.join(this.root,name);}
    read(name){return readPrivate(this.file(name));}
    assertKernel(spec){assert(this.kernel.present(),'Fence missing from kernel');assert.deepEqual(normalizeRules(this.kernel.rules()),expectedRules(spec),'Fence rule drift');}
    guardSSH(spec){assert(!this.kernel.sshPorts().some(p=>spec.tcp_ports.includes(p)),'Configured SSH listener would be fenced');}
    close(input){
        const spec=validateSpec(input);this.guardSSH(spec);
        assert(!this.read('releasing.json'),'Interrupted release requires explicit recovery');
        assert(!this.read('released-'+spec.generation+'.json'),'Completed generation cannot be reused');
        const active=this.read('active.json');
        if(active)assert.deepEqual(active,spec,'Another maintenance generation owns admission');
        else {
            assert(!this.kernel.present(),'Unowned kernel fence; do not overwrite it');
            writePrivate(this.file('active.json'),spec);
        }
        // The durable closing intent precedes the atomic kernel transaction.
        if(!this.kernel.present())this.kernel.create(spec);
        this.assertKernel(spec);return {state:'closed',generation:spec.generation};
    }
    verify(generation){
        assert(!this.read('releasing.json'),'Release is in progress');
        const s=this.read('active.json');assert(s&&s.generation===generation,'No matching active generation');
        this.assertKernel(s);return {state:'closed',generation};
    }
    bootGuard(){
        assert(!this.read('releasing.json'),'Interrupted release blocks startup');
        const active=this.read('active.json');
        if(active)return this.close(active);
        assert(!this.kernel.present(),'Orphaned kernel fence requires recovery');return {state:'open'};
    }
    status(){
        assert(!this.read('releasing.json'),'Interrupted release requires explicit recovery');
        const active=this.read('active.json');
        if(active)return this.verify(active.generation);
        assert(!this.kernel.present(),'Orphaned kernel fence requires recovery');return {state:'open'};
    }
    release(generation){
        assert(typeof generation==='string'&&/^[a-f0-9]{32}$/.test(generation));
        const active=this.read('active.json'),intent=this.read('releasing.json');
        const done=this.read('released-'+generation+'.json');
        if(!active&&!intent){assert(done&&!this.kernel.present(),'No completed matching release');return {state:'open',generation};}
        const spec=active||intent;assert.equal(spec.generation,generation,'Stale release generation');
        if(intent)assert.deepEqual(intent,spec,'Release intent changed');
        if(active&&intent)assert.deepEqual(active,intent);
        if(!intent){this.assertKernel(spec);writePrivate(this.file('releasing.json'),spec);}
        if(this.kernel.present()){this.assertKernel(spec);this.kernel.remove();}
        assert(!this.kernel.present(),'Fence removal not verified');
        if(done)assert.deepEqual(done,spec);else writePrivate(this.file('released-'+generation+'.json'),spec);
        // Retain the generation in history. An interrupted release may resume
        // only this release, never reopen a stale checkpoint for restoration.
        if(active){fs.unlinkSync(this.file('active.json'));syncDir(this.root);}
        if(this.read('releasing.json')){fs.unlinkSync(this.file('releasing.json'));syncDir(this.root);}
        return {state:'open',generation};
    }
}
function main(){let fd;try{
    assert.equal(process.getuid(),0);
    const args=process.argv.slice(2);
    assert((args.length===1&&['--boot-guard','--status'].includes(args[0]))||
        (args.length===2&&['--close','--verify','--release'].includes(args[0])),'Invalid fence command');
    for(const dir of [path.dirname(ROOT),ROOT]){
        try{fs.mkdirSync(dir,{mode:0o700});}catch(e){if(e.code!=='EEXIST')throw e;}privateDir(dir);
    }
    fd=fs.openSync(path.join(ROOT,'lock'),fs.constants.O_RDWR|fs.constants.O_CREAT|fs.constants.O_NOFOLLOW,0o600);
    const st=fs.fstatSync(fd);assert(st.isFile()&&st.uid===0&&st.nlink===1&&(st.mode&0o777)===0o600);
    // Several role units start concurrently at boot. Serialize their idempotent
    // guards instead of failing an otherwise healthy nginx start on lock busy.
    // Administrative mutations still refuse a concurrent writer immediately.
    const locked=cp.spawnSync('/usr/bin/flock',args[0]==='--boot-guard'?['--wait','30','3']:['-n','3'],
        {stdio:['ignore','pipe','pipe',fd],env:ENV,timeout:35000});
    assert(locked.status===0&&!locked.error,'Another fence operation is running');
    const f=new Fence(ROOT);let result;
    if(args[0]==='--close'){
        assert(path.isAbsolute(args[1]));privateDir(path.dirname(args[1]));
        const s=readPrivate(args[1]);assert(s);result=f.close(s);
    }else if(args[0]==='--verify')result=f.verify(args[1]);
    else if(args[0]==='--release')result=f.release(args[1]);
    else result=args[0]==='--status'?f.status():f.bootGuard();
    console.log(JSON.stringify(result));
}catch(_){console.error('MAINTENANCE_FENCE_REFUSED_OR_FAILED');process.exitCode=1;}
finally{if(fd!==undefined)fs.closeSync(fd);}}
module.exports={Fence,validateSpec,nftInput,expectedRules,normalizeRules,kernel,TABLE};
if(require.main===module)main();
