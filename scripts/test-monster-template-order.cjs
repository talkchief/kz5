#!/usr/bin/env node
'use strict';
// Proves installed wildcard streams can reorder identical template inputs;
// does not claim to reconstruct a prior unretained generated bundle.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {createRequire}=require('node:module');
const source=path.resolve(process.argv[2]||''),loader=createRequire(path.join(source,'package.json'));
const globStream=loader('glob-stream'),root=fs.mkdtempSync(path.join(os.tmpdir(),'monster-template-order.'));
const original=fs.readdir;
function hash(text){return crypto.createHash('sha256').update(text).digest('hex');}
function collect(slow){return new Promise((resolve,reject)=>{
    fs.readdir=function(file,...args){const delay=String(file)===path.join(root,slow,'views')?80:0;setTimeout(()=>original.call(fs,file,...args),delay);};
    const files=[];const stream=globStream(path.join(root,'*','views','*.html'));
    stream.on('data',entry=>files.push(entry.path));stream.once('error',error=>{fs.readdir=original;reject(error);});stream.once('end',()=>{fs.readdir=original;resolve(files);});
});}
(async()=>{
    for(const name of ['a','z']){const dir=path.join(root,name,'views');fs.mkdirSync(dir,{recursive:true,mode:0o700});fs.writeFileSync(path.join(dir,'item.html'),name,{mode:0o600});}
    const first=await collect('a'),second=await collect('z');assert.equal(first.length,2);assert.deepEqual([...first].sort(),[...second].sort());assert.notDeepEqual(first,second);
    const compile=files=>files.map(file=>'templates['+JSON.stringify(path.relative(root,file))+']='+JSON.stringify(fs.readFileSync(file,'utf8'))+';').join('\n');
    const one=compile(first),two=compile(second);assert.equal(one.length,two.length);assert.notEqual(hash(one),hash(two));
    console.log(JSON.stringify({status:'passed',scope:'installed glob-stream ordering fixture, not proof of historical bundle difference',same_files:true,same_size:true,different_concat_hash:true}));
})().catch(error=>{console.error('FAIL template order fixture: '+error.message);process.exitCode=1;}).finally(()=>{fs.readdir=original;fs.rmSync(root,{recursive:true,force:true});});
