#!/usr/bin/env node
'use strict';
// Durable session-admission intent. Full broker/callback/producer drain is separate.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict');
const ROOT='/var/lib/kazoo5-maintenance/media',PUBLIC='/etc/kazoo5-maintenance';
const ENV={PATH:'/usr/sbin:/usr/bin:/sbin:/bin',LC_ALL:'C'};
function spec(s){
    assert(s&&typeof s==='object'&&!Array.isArray(s));
    assert.deepEqual(Object.keys(s).sort(),['generation','manifest_sha256','schema_version']);
    assert.equal(s.schema_version,1);assert(typeof s.generation==='string'&&/^[a-f0-9]{32}$/.test(s.generation));
    assert(typeof s.manifest_sha256==='string'&&/^[a-f0-9]{64}$/.test(s.manifest_sha256));
    return {schema_version:1,generation:s.generation,manifest_sha256:s.manifest_sha256};
}
function directory(dir,mode){
    assert.equal(fs.realpathSync(dir),path.resolve(dir),'Symlinked media state directory');
    const st=fs.lstatSync(dir);assert(st.isDirectory()&&st.uid===0&&(st.mode&511)===mode);
}
function sync(dir){const fd=fs.openSync(dir,fs.constants.O_RDONLY|fs.constants.O_DIRECTORY|fs.constants.O_NOFOLLOW);try{fs.fsyncSync(fd);}finally{fs.closeSync(fd);}}
function read(file,mode){
    let fd;try{fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);}catch(e){if(e.code==='ENOENT')return null;throw e;}
    try{const st=fs.fstatSync(fd);assert(st.isFile()&&st.uid===0&&st.nlink===1&&(st.mode&511)===mode&&st.size>0&&st.size<=512);
        return spec(JSON.parse(fs.readFileSync(fd,'utf8')));
    }finally{fs.closeSync(fd);}
}
function write(file,value,mode){
    const fd=fs.openSync(file,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NOFOLLOW,mode);
    try{fs.fchmodSync(fd,mode);fs.writeFileSync(fd,JSON.stringify(spec(value))+'\n');fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
    sync(path.dirname(file));
}
function command(bin,args){return cp.execFileSync(bin,args,{encoding:'utf8',env:ENV,timeout:10000,maxBuffer:32768,stdio:['ignore','pipe','pipe']}).trim();}
function epoch(){
    const pid=command('/usr/bin/systemctl',['show','kazoo-freeswitch.service','-p','MainPID','--value']);
    assert(/^[1-9][0-9]*$/.test(pid),'Media service has no main PID');
    assert.equal(fs.readlinkSync('/proc/'+pid+'/exe'),'/usr/local/freeswitch/bin/freeswitch');
    const stat=fs.readFileSync('/proc/'+pid+'/stat','utf8'),start=stat.slice(stat.lastIndexOf(')')+2).split(' ')[19];
    assert(/^[0-9]+$/.test(start));
    return {pid:Number(pid),start_ticks:start,boot_id:fs.readFileSync('/proc/sys/kernel/random/boot_id','utf8').trim()};
}
function observe(){
    const before=epoch();
    const out=JSON.parse(command('/usr/local/freeswitch/bin/fs_cli',['-H','127.0.0.1','-P','8021','-x','fsctl maintenance_check']));
    assert.deepEqual(Object.keys(out).sort(),['admission','core_uuid','schema_version','sessions']);
    assert.equal(out.schema_version,1);assert(['open','closed'].includes(out.admission),'Invalid native media marker state');
    assert(Number.isSafeInteger(out.sessions)&&out.sessions>=0);assert(typeof out.core_uuid==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(out.core_uuid));
    assert.deepEqual(epoch(),before,'Media process changed during observation');
    return {...out,process:before};
}
function supportedBinary(){
    const lib=fs.realpathSync('/usr/local/freeswitch/lib/libfreeswitch.so.1');
    assert(lib.startsWith('/usr/local/freeswitch/lib/libfreeswitch.so.'));
    const symbols=cp.execFileSync('/usr/bin/readelf',['--dyn-syms','--wide',lib],{encoding:'utf8',env:ENV,timeout:10000,maxBuffer:1048576,stdio:['ignore','pipe','pipe']});
    assert(symbols.split('\n').some(l=>/\bFUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+switch_core_session_maintenance_check$/.test(l.trim())),
        'Selected media library lacks the durable admission barrier; do not start or roll back to it');
}
class MediaFence {
    constructor(root=ROOT,publicDir=PUBLIC,observer=observe,support=supportedBinary){this.root=root;this.publicDir=publicDir;this.observer=observer;this.support=support;this.checkDirs();}
    checkDirs(){directory(this.root,0o700);directory(this.publicDir,0o755);}
    file(name){this.checkDirs();return path.join(this.root,name);}
    get(name){return read(this.file(name),0o600);}
    marker(){this.checkDirs();return read(path.join(this.publicDir,'media.closed'),0o644);}
    mark(s){const actual=this.marker();if(actual)assert.deepEqual(actual,s,'Foreign media marker');else write(path.join(this.publicDir,'media.closed'),s,0o644);}
    unmark(s){const actual=this.marker();if(actual){assert.deepEqual(actual,s,'Foreign media marker');fs.unlinkSync(path.join(this.publicDir,'media.closed'));sync(this.publicDir);}}
    native(expected){const out=this.observer();assert.equal(out.admission,expected,'Native media gate disagrees with durable intent');return out;}
    close(input){
        const s=spec(input);assert(!this.get('releasing.json'),'Release already in progress');
        assert(!this.get('released-'+s.generation+'.json'),'Released generation cannot be reused');
        const active=this.get('active.json');
        if(active)assert.deepEqual(active,s,'Different media generation');
        else{assert(!this.marker(),'Unowned media marker');this.native('open');write(this.file('active.json'),s,0o600);}
        this.mark(s);return this.verify(s.generation);
    }
    verify(generation){
        assert(!this.get('releasing.json'),'Release already in progress');
        const s=this.get('active.json');assert(s&&s.generation===generation,'No matching active media generation');
        assert.deepEqual(this.marker(),s,'Missing or changed media marker');const native=this.native('closed');
        assert.deepEqual(this.marker(),s,'Media marker changed during observation');
        return {state:'closed',generation,native};
    }
    bootGuard(){
        assert(!this.get('releasing.json'),'Interrupted media release blocks startup');
        const active=this.get('active.json');
        if(active){this.mark(active);this.support();return {state:'closed',generation:active.generation};}
        assert(!this.marker(),'Unowned media marker');this.support();return {state:'open'};
    }
    status(){
        assert(!this.get('releasing.json'),'Release already in progress');
        const s=this.get('active.json');if(s)return this.verify(s.generation);
        assert(!this.marker(),'Unowned media marker');return {state:'open',native:this.native('open')};
    }
    release(generation){
        assert(/^[a-f0-9]{32}$/.test(generation));
        const active=this.get('active.json'),pending=this.get('releasing.json'),done=this.get('released-'+generation+'.json');
        const s=active||pending||done;assert(s&&s.generation===generation,'Stale or unknown media release');
        if(pending)assert.deepEqual(pending,s);if(done)assert.deepEqual(done,s);
        if(!active&&!pending){assert(!this.marker());return {state:'open',generation,native:this.native('open')};}
        if(!pending){this.verify(generation);write(this.file('releasing.json'),s,0o600);}
        this.unmark(s);const native=this.native('open');
        if(!done)write(this.file('released-'+generation+'.json'),s,0o600);
        for(const name of ['active.json','releasing.json'])if(this.get(name)){fs.unlinkSync(this.file(name));sync(this.root);}
        return {state:'open',generation,native};
    }
}
function main(){let fd;try{
    assert.equal(process.getuid(),0);const args=process.argv.slice(2);
    assert((args.length===1&&['--boot-guard','--status'].includes(args[0]))||(args.length===2&&['--close','--verify','--release'].includes(args[0])));
    for(const [dir,mode] of [[path.dirname(ROOT),0o700],[ROOT,0o700],[PUBLIC,0o755]]){
        try{
            fs.mkdirSync(dir,{mode});fs.chmodSync(dir,mode);
            sync(dir);sync(path.dirname(dir));
        }catch(e){if(e.code!=='EEXIST')throw e;}directory(dir,mode);
    }
    fd=fs.openSync(path.join(ROOT,'lock'),fs.constants.O_RDWR|fs.constants.O_CREAT|fs.constants.O_NOFOLLOW,0o600);
    const st=fs.fstatSync(fd);assert(st.isFile()&&st.uid===0&&st.nlink===1&&(st.mode&511)===0o600);
    const locked=cp.spawnSync('/usr/bin/flock',args[0]==='--boot-guard'?['--wait','30','3']:['-n','3'],{env:ENV,timeout:35000,stdio:['ignore','pipe','pipe',fd]});
    assert(locked.status===0&&!locked.error,'Another media-fence operation is running');
    const f=new MediaFence();let result;
    if(args[0]==='--close'){assert(path.isAbsolute(args[1]));directory(path.dirname(args[1]),0o700);const s=read(args[1],0o600);assert(s);result=f.close(s);}
    else if(args[0]==='--verify')result=f.verify(args[1]);else if(args[0]==='--release')result=f.release(args[1]);
    else result=args[0]==='--boot-guard'?f.bootGuard():f.status();
    console.log(JSON.stringify(result));
}catch(_){console.error('MAINTENANCE_MEDIA_REFUSED_OR_FAILED');process.exitCode=1;}finally{if(fd!==undefined)fs.closeSync(fd);}}
module.exports={MediaFence,spec,observe};
if(require.main===module)main();
