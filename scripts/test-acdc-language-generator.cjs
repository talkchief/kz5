#!/usr/bin/env node
'use strict';
// Execute the actual generator in a VM with memory-only fs/synthesis mocks.
// No generated files, subprocesses, network or live media are created here.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'generate-acdc-language-prompts.cjs'),'utf8');
const catalog=require('./acdc-language-catalog.cjs');
const ROOT='/usr/local/src/language-generator-test';
function wav(amplitude=5000) {
  const b=Buffer.alloc(44+16000);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);
  b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(8000,24);
  b.writeUInt32LE(16000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(16000,40);
  for(let i=0;i<8000;i++)b.writeInt16LE(Math.round(amplitude*Math.sin(2*Math.PI*440*i/8000)),44+i*2);
  return b;
}
function environment() {
  const files=new Map([['/',{type:'dir'}]]),writes=[],speech={version:'eSpeak NG1.52.0',phonemes:'tEst',voice:'en-us'};
  let serial=0;
  const put=(file,data,type='file')=>files.set(file,{type,data:Buffer.from(data||'')});
  const read=(file)=>{const item=files.get(file);assert(item,'ENOENT '+file);return item;};
  const children=dir=>[...files.keys()].filter(f=>f!==dir&&path.dirname(f)===dir).map(f=>path.basename(f));
  const write=(file,data)=>{assert(file.startsWith(ROOT+'/'));writes.push(file);put(file,data);};
  const fake={
    existsSync:file=>files.has(file),
    lstatSync:file=>{const i=read(file);return {isFile:()=>i.type==='file',isDirectory:()=>i.type==='dir',isSymbolicLink:()=>i.type==='symlink'};},
    mkdirSync:dir=>{files.set(dir,{type:'dir'});},
    mkdtempSync:prefix=>{const dir=prefix+(++serial);files.set(dir,{type:'dir'});return dir;},
    readFileSync:(file,encoding)=>encoding?read(file).data.toString(encoding):Buffer.from(read(file).data),
    writeFileSync:write,
    copyFileSync:(from,to)=>write(to,read(from).data),
    renameSync:(from,to)=>{write(to,read(from).data);files.delete(from);},
    chmodSync:()=>{},
    unlinkSync:file=>{assert(files.has(file));files.delete(file);},
    readdirSync:children,
    rmdirSync:dir=>{assert.equal(children(dir).length,0);files.delete(dir);}
  };
  const fakeCp={spawnSync:(file,args)=>{
    if(file==='sox'){write(args[args.indexOf('signed-integer')+1],wav());return{status:0,stdout:''};}
    if(args[0]==='--version')return {status:0,stdout:speech.version};
    if(args[0].startsWith('--voices='))return {status:0,stdout:'Pty Language Voice\n5 '+speech.voice+' --/M Voice'};
    if(args.includes('-q'))return {status:0,stdout:speech.phonemes};
    const at=args.indexOf('-w');assert(at!==-1);write(args[at+1],wav());return {status:0,stdout:''};
  }};
  const context={module:{exports:{}},console:{log:()=>{},error:()=>{}},process:{env:{}},Buffer,
    require:name=>name==='node:fs'?fake:name==='node:child_process'?fakeCp:
      name==='./acdc-language-catalog.cjs'?catalog:require(name)};
  context.require.main=null;vm.runInNewContext(source,context,{filename:'generate-acdc-language-prompts.cjs'});
  const run=(extra=[])=>context.module.exports.main(['--output-dir',ROOT,'--espeak','/pinned/espeak','--espeak-data','/pinned/data','--locale','en-us',...extra]);
  return {files,writes,speech,put,run};
}
{
  const e=environment();e.run();const m=JSON.parse(e.files.get(ROOT+'/en-us/manifest.json').data);
  assert.equal(m.prompts.length,29);assert.equal(m.complete,true);assert.equal(m.runtime_ready,false);assert.equal(m.native_speaker_review,false);
  assert.equal(m.numbers,'native_say');assert.equal(new Set(m.prompts.map(p=>p.id)).size,29);
  const before=e.writes.length;e.run(['--verify-only']);assert.equal(e.writes.length,before);
  e.run();assert.equal(JSON.parse(e.files.get(ROOT+'/en-us/manifest.json').data).asset_sha256,m.asset_sha256);
}
{
  const e=environment(),file=ROOT+'/en-us/acdc-callback-offer-0.wav';e.put(file,wav(2000));
  assert.throws(()=>e.run(),/unowned/);assert.equal(e.files.get(file).data.readInt16LE(46),wav(2000).readInt16LE(46));
  assert(!e.files.has(ROOT+'/en-us/manifest.json'));
}
{
  const e=environment();e.run();const file=ROOT+'/en-us/acdc-callback-offer-0.wav';e.put(file,wav(1000));
  assert.throws(()=>e.run(),/differs/);assert.throws(()=>e.run(['--verify-only']),/differs/);
}
{
  const e=environment();e.put(ROOT,Buffer.alloc(0),'symlink');assert.throws(()=>e.run(),/Symlink/);
  assert.equal(e.writes.length,0);
}
{
  const e=environment();e.speech.version='eSpeak NG1.50';assert.throws(()=>e.run(),/1.52/);assert.equal(e.writes.length,0);
}
{
  const e=environment();e.speech.phonemes='(en)unsupported letter';assert.throws(()=>e.run(),/switched language/);
  assert(!e.files.has(ROOT+'/en-us/manifest.json'));
}
{
  const e=environment();e.speech.voice='he';assert.throws(()=>e.run(),/exact voice/);assert.equal(e.writes.length,0);
}
{
  const e=environment();assert.throws(()=>e.run(['--verify-only']),/Missing/);assert.equal(e.files.size,1);
}
console.log('PASS8 generator fault groups: memory-only generation/idempotence/verify, owned audio, tamper/symlink/oldvoice/languagefallback/missingpack failclosed');
