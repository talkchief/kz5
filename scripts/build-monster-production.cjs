#!/usr/bin/env node
'use strict';
// Original production task order, with an explicit no-compressor minifier profile.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const {createRequire}=require('node:module');
const {safePath,snapshot}=require('./deploy-owned-monster.cjs');
const minifierProfile=require('./monster-minifier-profile.cjs');
function workerHeapMiB(read=file=>fs.readFileSync(file,'utf8'), free=require('node:os').freemem()) {
    // Keep the old 256MiB profile inside the small development guard. Larger
    // build hosts need 512MiB for fresh full bundles; inspect all cgroup v2
    // ancestors instead of assuming host RAM is the process's allowance.
    try {
        const rows=read('/proc/self/cgroup').trim().split('\n');
        const row=rows.find(line=>line.startsWith('0::/'));
        if(!row || rows.length!==1) return 256;
        const root='/sys/fs/cgroup';
        let directory=path.resolve(root,'.'+row.slice(3)), allowance=free;
        if(directory!==root && !directory.startsWith(root+'/')) return 256;
        for (;;) {
            // The unified hierarchy root itself has no memory.max controller.
            if(directory===root) break;
            const limit=read(path.join(directory,'memory.max')).trim();
            if(limit!=='max') {
                if(!/^[0-9]+$/.test(limit) || !Number.isSafeInteger(Number(limit))) return 256;
                allowance=Math.min(allowance,Number(limit));
            }
            directory=path.dirname(directory);
        }
        return allowance>=1024*1024*1024 ? 512 : 256;
    } catch {return 256;}
}
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const FILES=['main.js','templates.js'];
const BUILD_FILES=['gulpfile.babel.js','.babelrc','.babelrc.js','.babelregister.js'];
function sourceRoot(value){
    const source=path.resolve(value);safePath(source);
    assert.equal(path.basename(source),'source','Expected private source stage');
    assert(/^monster-owned-build\.[A-Za-z0-9]+$/.test(path.basename(path.dirname(source))),'Expected installer-owned stage prefix');
    for(const relative of ['src','gulp','node_modules','package.json','package-lock.json',...BUILD_FILES])safePath(path.join(source,relative));
    for(const relative of ['tmp','dist','distRequired']){
        const target=path.join(source,relative);let present=true;
        try{fs.lstatSync(target);}catch(error){if(error.code==='ENOENT')present=false;else throw error;}
        if(present)snapshot(target);
    }
    return source;
}
function input(source,name){
    assert(FILES.includes(name),'Unsupported minifier input');
    const file=path.join(source,'tmp/js',name);safePath(file);const st=fs.lstatSync(file);
    assert(st.isFile()&&st.nlink===1&&st.size<=12*1024*1024,'Invalid bounded minifier input');
    return {file,stat:st,bytes:fs.readFileSync(file)};
}
function transformBytes(source,name,bytes){
    source=sourceRoot(source);assert(FILES.includes(name),'Unsupported minifier input');
    const {loader,profile}=minifierProfile.dependencies(source);
    const gulpPackage=loader.resolve('gulp/package.json');
    const vinylFsPackage=createRequire(gulpPackage).resolve('vinyl-fs/package.json');
    const Vinyl=createRequire(vinylFsPackage)('vinyl');
    // Same pinned factory and source-map behavior; disabling Compressor is an
    // explicit optimization change, not byte equivalence with the old default.
    const transform=loader('gulp-uglify')(profile.options),chunks=[];let failed=false;
    return new Promise((resolve,reject)=>{
        transform.on('data',file=>chunks.push(file));transform.once('error',error=>{failed=true;reject(error);});
        transform.once('end',()=>{
            if(failed)return;
            try{
                assert.equal(chunks.length,1,'Expected exactly one minified Vinyl file');
                const output=chunks[0];assert(Buffer.isBuffer(output.contents)&&!output.sourceMap,'Unexpected minifier output');
                assert.equal(output.relative,name,'Minifier relative path changed');
                resolve(output.contents);
            }catch(error){reject(error);}
        });
        transform.end(new Vinyl({cwd:source,base:path.join(source,'tmp/js'),path:path.join(source,'tmp/js',name),contents:bytes}));
    });
}
async function minifyOne(source,name){
    source=sourceRoot(source);const before=input(source,name),output=await transformBytes(source,name,before.bytes);
    const current=input(source,name);assert.equal(hash(current.bytes),hash(before.bytes),'Input changed during minification');
    assert.equal(current.stat.ino,before.stat.ino,'Input identity changed');assert.equal(current.stat.dev,before.stat.dev,'Input device changed');
    const temporary=path.join(path.dirname(before.file),'.'+name+'.kazoo-minify-'+crypto.randomBytes(12).toString('hex'));
    fs.writeFileSync(temporary,output,{flag:'wx',mode:before.stat.mode&0o777});fs.renameSync(temporary,before.file);
    return {phase:'minified',profile:minifierProfile.profile().id,file:name,input_sha256:hash(before.bytes),output_sha256:hash(output),bytes:output.length};
}
function fixedInputs(source){return {
    package:hash(fs.readFileSync(path.join(source,'package.json'))),
    lock:hash(fs.readFileSync(path.join(source,'package-lock.json'))),
    dependencies:hash(fs.readFileSync(path.join(source,'node_modules/.package-lock.json'))),
    profile:hash(fs.readFileSync(minifierProfile.PROFILE_FILE)),
    build_files:Object.fromEntries(BUILD_FILES.map(file=>[file,hash(fs.readFileSync(path.join(source,file)))])),
    build_tasks:hash(JSON.stringify(snapshot(path.join(source,'gulp')))),
    source:hash(JSON.stringify(snapshot(path.join(source,'src'))))
};}
function run(source,argv){
    const result=spawnSync(process.execPath,argv,{cwd:source,stdio:'inherit',timeout:300000,killSignal:'SIGKILL',env:{...process.env,NODE_OPTIONS:'--max-old-space-size='+workerHeapMiB()}});
    assert(!result.error&&result.status===0&&!result.signal,'Production build child failed');
}
async function build(source){
    source=sourceRoot(source);const before=fixedInputs(source);
    const gulp=path.join(source,'node_modules/gulp/bin/gulp.js');safePath(gulp);
    assert(fs.readFileSync(path.join(source,'gulpfile.babel.js'),'utf8').includes('KAZOO_BOUNDED_PRODUCTION_PHASES_V1'),'Missing pinned production phase patch');
    run(source,[gulp,'build-prod-prepare']);
    for(const name of FILES){
        const original=readInventory(source,name);
        run(source,[__filename,'--minify-file',source,name]);
        const minified=readInventory(source,name);
        assert.deepEqual(minified.modules,original.modules,'AMD registration coverage/dependencies/order changed');
        console.log(JSON.stringify({phase:'amd_inventory_verified',file:name,registrations:minified.modules.length,inventory_sha256:minified.inventory_sha256}));
    }
    run(source,[gulp,'build-prod-finalize']);
    assert.deepEqual(fixedInputs(source),before,'Production source inputs changed');
    return {status:'production_build_completed',profile:minifierProfile.profile().id,inputs:before,deployed:false};
}
function readInventory(source,name){
    const result=spawnSync(process.execPath,[path.join(__dirname,'monster-minifier-profile.cjs'),'--inventory',source,name],
        {cwd:source,stdio:['ignore','pipe','inherit'],maxBuffer:1024*1024,timeout:90000,killSignal:'SIGKILL',env:{...process.env,NODE_OPTIONS:'--max-old-space-size=256'}});
    assert(!result.error&&result.status===0&&!result.signal,'AMD inventory child failed');return JSON.parse(result.stdout);
}
if(require.main===module){
    (async()=>{
        let result;
        if(process.argv[2]==='--minify-file'){assert.equal(process.argv.length,5);result=await minifyOne(process.argv[3],process.argv[4]);}
        else{assert.equal(process.argv.length,3);result=await build(process.argv[2]);}
        console.log(JSON.stringify(result));
    })().catch(error=>{console.error('FAIL bounded Monster production build: '+(error.code||error.name));process.exitCode=1;});
}
module.exports={sourceRoot,transformBytes,minifyOne,build,workerHeapMiB};
