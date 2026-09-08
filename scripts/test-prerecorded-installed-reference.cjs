'use strict';
// Wrapper trust-chain tests with an in-memory filesystem/probe. Existing tests
// cover WAV/index validation; native preparation covers actual installed bytes.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const root='/synthetic',capFile='/protected/capability.json',receiptFile='/protected/runtime/runtime-receipt.json';
const input={synthetic:true},cap={generated_at:'2026-09-08T12:00:00Z'};
const cfile='/usr/local/share/kazoo5-installer/acdc-cardinal-media.json',ffile='/usr/local/share/kazoo5-installer/acdc-gemini-media.json';
const manifest='/protected/runtime/production-beams.json';
const code=fs.readFileSync(path.join(__dirname,'test-fixtures/callback-prerecorded-reference.cjs'),'utf8');
async function run(mutation) {
    const files=new Map(),put=(file,value)=>files.set(file,Buffer.from(typeof value==='string'?value:JSON.stringify(value)));
    put(capFile,cap);const capSha=sha(files.get(capFile));
    put(cfile,'cardinal');put(ffile,'fixed');put(manifest,'beams');
    put(root+'/applications/acdc/src/acdc_gemini_map.hrl','map');
    put(root+'/scripts/assets/acdc-gemini-cardinal-model-trials-20260907/index.json','trial');
    put(root+'/scripts/acdc-cardinal-reuse-es-20260907.json','aliases');
    const receipt={node:'kazoo_apps@synthetic',account:'a'.repeat(32),finished_at:cap.generated_at,
        cardinal_receipt_sha256:sha(files.get(cfile)),fixed_receipt_sha256:sha(files.get(ffile)),
        beam_manifest_sha256:sha(files.get(manifest)),input_sha256:sha(JSON.stringify(input))};
    put(receiptFile,receipt);
    const marker={owner:'kazoo5-acdc-prerecorded-finalization',capability_sha256:capSha,receipt:receiptFile,receipt_sha256:sha(files.get(receiptFile))};
    const markerFile=capFile+'.installer-'+capSha+'.json';put(markerFile,marker);
    const ctx={files,put,receipt,marker,markerFile,capSha,unprotected:false};
    if(mutation)mutation(ctx);
    let next=1,writes=0,parsed;
    const descriptors=new Map();
    const fakeFs={constants:fs.constants,
        openSync(file,flags){assert(flags&fs.constants.O_NOFOLLOW);assert(files.has(file));const fd=next++;descriptors.set(fd,{file,at:0});return fd;},
        fstatSync(fd){return {isFile:()=>true,uid:0,nlink:1,mode:ctx.unprotected?0o666:0o600,size:files.get(descriptors.get(fd).file).length};},
        readSync(fd,buffer,offset,length){const state=descriptors.get(fd),bytes=files.get(state.file),n=Math.min(length,bytes.length-state.at);bytes.copy(buffer,offset,state.at,state.at+n);state.at+=n;return n;},
        closeSync(fd){descriptors.delete(fd);}};
    const probe={protectedParents(){},readPinned(file,digest){assert(files.has(file));assert.equal(sha(files.get(file)),digest);return files.get(file);},
        parseArgs(args){parsed=args;return args;},buildInput(){return input;},
        createEvidence(file,bytes){writes++;assert.equal(file,'/protected/output.options.json');
            const saved=JSON.parse(bytes);assert.equal(saved.schema_version,1);assert.deepEqual(saved.probe_args,parsed);
            throw Error('validated-prefix');}};
    const publisher={validateReceipt(r){assert.equal(r.node,receipt.node);},capability(){return cap;}};
    const module={exports:{}};
    const req=name=>{
        if(name==='node:fs')return fakeFs;
        if(name===root+'/scripts/probe-acdc-prerecorded-runtime.cjs')return probe;
        if(name===root+'/scripts/acdc-cardinal-catalog.cjs')return {};
        if(name===root+'/scripts/publish-acdc-prerecorded-capabilities.cjs')return publisher;
        if(name==='node:child_process')return {spawnSync(){throw Error('Unexpected subprocess');}};
        return require(name);
    };
    new Function('require','module','__dirname',code)(req,module,path.join(__dirname,'test-fixtures'));
    let error;try {await module.exports.prepareInstalled(capFile,capSha,'/protected/output',root);}catch(e){error=e;}
    assert.equal(descriptors.size,0,'Every metadata descriptor must close');
    return {writes,error,parsed};
}
(async()=>{
    const good=await run();assert.equal(good.error.message,'validated-prefix');assert.equal(good.writes,1);
    assert(good.parsed.includes('--model-trial-index')&&good.parsed.includes('--alias-sha256'));
    for(const mutate of [
        x=>x.put(capFile,{...cap,changed:true}),
        x=>x.put(x.markerFile,{...x.marker,owner:'foreign'}),
        x=>x.put(x.markerFile,{...x.marker,capability_sha256:'0'.repeat(64)}),
        x=>x.put(receiptFile,{...x.receipt,changed:true}),
        x=>x.put(cfile,'changed'),x=>x.put(ffile,'changed'),x=>x.put(manifest,'changed'),
        x=>{const r={...x.receipt,input_sha256:'0'.repeat(64)};x.put(receiptFile,r);x.put(x.markerFile,{...x.marker,receipt_sha256:sha(x.files.get(receiptFile))});},
        x=>{x.unprotected=true;}
    ]) {const failed=await run(mutate);assert(failed.error);assert.notEqual(failed.error.message,'validated-prefix');assert.equal(failed.writes,0);}
    console.log('PASS installed-reference trust chain, nine pre-write refusal cases and descriptor cleanup; synthetic metadata only');
})().catch(error=>{console.error(error);process.exitCode=1;});
