#!/usr/bin/env node
'use strict';

// Offline, deterministic media generation. This never imports media, changes
// services, or declares a locale ready on a running Kazoo installation.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const {catalog,locales}=require('./acdc-language-catalog.cjs');
const OWNER='kazoo5-acdc-language-generator';
const ESPEAK_COMMIT='4870adfa25b1a32b4361592f1be8a40337c58d6c';
const hash=data=>crypto.createHash('sha256').update(data).digest('hex');
function execute(file,args,options={}) {
  const r=cp.spawnSync(file,args,{encoding:'utf8',timeout:30000,maxBuffer:4*1024*1024,...options});
  assert(!r.error&&r.status===0,'Offline dependency failed: '+path.basename(file));
  return r.stdout;
}
function wave(buffer) {
  assert(buffer.length>=44&&buffer.toString('ascii',0,4)==='RIFF'&&buffer.toString('ascii',8,12)==='WAVE','Not RIFF/WAVE');
  assert(buffer.readUInt32LE(4)+8===buffer.length,'Truncated or trailing WAVE data');
  let format,data;
  for(let at=12;at+8<=buffer.length;) {
    const size=buffer.readUInt32LE(at+4),end=at+8+size;assert(end<=buffer.length,'Truncated WAVE chunk');
    const id=buffer.toString('ascii',at,at+4);
    if(id==='fmt ') {assert(!format&&size>=16,'Ambiguous WAVE format');format=buffer.subarray(at+8,end);}
    if(id==='data') {assert(!data,'Multiple WAVE payloads');data=buffer.subarray(at+8,end);}
    at=end+(size%2);
  }
  assert(format&&data&&format.readUInt16LE(0)===1&&format.readUInt16LE(2)===1&&
    format.readUInt32LE(4)===8000&&format.readUInt16LE(14)===16&&data.length%2===0,'Require PCM16 mono8kHz');
  let power=0,peak=0;
  for(let at=0;at<data.length;at+=2) {const sample=data.readInt16LE(at);power+=sample*sample;peak=Math.max(peak,Math.abs(sample));}
  const duration=data.length/16000,rms=Math.sqrt(power/(data.length/2));
  assert(duration>=0.1&&duration<=30&&rms>100&&peak<32767,'Silent, clipped, or excessive prompt');
  return {duration_seconds:duration,rms:Math.round(rms),peak};
}
function options(args) {
  const o={};
  while(args.length) {
    const key=args.shift();
    if(['--dry-run','--only-fixed','--verify-only'].includes(key))o[key.slice(2)]=true;
    else {assert(['--output-dir','--espeak','--espeak-data','--locale'].includes(key)&&args.length,'Unknown/incomplete option');o[key.slice(2)]=args.shift();}
  }
  o.locales=o.locale?[o.locale]:locales;
  assert(o.locales.every(l=>locales.includes(l)),'Unknown canonical locale');
  if(!o['dry-run']) {
    assert(o['output-dir']&&path.isAbsolute(o['output-dir'])&&o['output-dir'].split('/').filter(Boolean).length>=3,'Use a dedicated absolute output directory');
    assert(!['/etc','/var/www','/usr/share','/usr/local/freeswitch'].some(p=>o['output-dir']===p||o['output-dir'].startsWith(p+'/')),
      'Generation must not write runtime configuration/web/sound directories');
    if(!o['verify-only'])assert(o.espeak&&path.isAbsolute(o.espeak)&&o['espeak-data']&&path.isAbsolute(o['espeak-data']),'Explicit pinned speech executable/data required');
  }
  return o;
}
function secureDirectory(dir,create=true) {
  const parts=path.resolve(dir).split('/').filter(Boolean);let current='/';
  for(const component of parts) {
    current=path.join(current,component);
    if(!fs.existsSync(current)) {
      assert(create,'Missing output directory; verification does not create a pack');
      fs.mkdirSync(current,{mode:493});
    }
    const s=fs.lstatSync(current);assert(s.isDirectory()&&!s.isSymbolicLink(),'Symlink/non-directory output component');
  }
}
function verifyFile(file,sha) {
  const st=fs.lstatSync(file);assert(st.isFile()&&!st.isSymbolicLink(),'Invalid audio file');
  const data=fs.readFileSync(file);assert(hash(data)===sha,'Media differs from owned generation manifest');return wave(data);
}
function main(args) {
  const o=options([...args]);
  if(o['dry-run']) {
    console.log(JSON.stringify({runtime_ready:false,locales:o.locales.map(l=>({locale:l,voice:catalog(l).voice,prompts:catalog(l).prompts.length}))}));return;
  }
  const env={...process.env,ESPEAK_DATA_PATH:o['espeak-data']};
  let version;
  if(!o['verify-only']) {
    version=execute(o.espeak,['--version'],{env}).trim();
    assert(/1\.52\.0\b/.test(version),'Pinned eSpeak1.52.0 required; no silent old-version fallback');
  }
  secureDirectory(o['output-dir'],!o['verify-only']);
  for(const locale of o.locales) {
    const c=catalog(locale),entries=c.prompts.filter(p=>!o['only-fixed']||p.kind==='fixed');
    const dir=path.join(o['output-dir'],locale),manifestFile=path.join(dir,'manifest.json');
    secureDirectory(dir,!o['verify-only']);
    let previous;
    if(fs.existsSync(manifestFile)) {
      assert(fs.lstatSync(manifestFile).isFile()&&!fs.lstatSync(manifestFile).isSymbolicLink(),'Invalid manifest path');
      previous=JSON.parse(fs.readFileSync(manifestFile,'utf8'));
      assert(previous.owner===OWNER&&previous.locale===locale,'Unowned language output');
    }
    if(o['verify-only']) {
      assert(previous&&previous.complete===true&&previous.prompts.length===c.prompts.length,'Missing/incomplete language pack');
      for(const p of c.prompts) {
        const saved=previous.prompts.find(v=>v.id===p.id);
        assert(saved&&saved.text===p.text&&saved.synthesis_text===(p.synthesis_text||p.text),'Catalog changed after synthesis');
        verifyFile(path.join(dir,p.id+'.wav'),saved.sha256);
      }
      console.log(locale+' PASS complete offline pack; runtime installation not asserted');continue;
    }
    const voice=execute(o.espeak,['--voices='+c.voice],{env});
    assert(voice.split('\n').some(line=>line.trim().split(/\s+/)[1]===c.voice),'Required exact voice missing');
    const temporary=fs.mkdtempSync(path.join(dir,'.render-'));
    const generated=[];
    try {
      for(const [index,p] of entries.entries()) {
        const input=p.synthesis_text||p.text;
        const phonemes=execute(o.espeak,['-q','-v',c.voice,'-x','--',input],{env}).trim();
        assert(phonemes.length>0&&!phonemes.includes('(en)')&&!phonemes.includes('_:'),'Speech switched language or spelled unsupported characters');
        const source=path.join(temporary,'source.wav'),rendered=path.join(temporary,'rendered.wav');
        execute(o.espeak,['-v',c.voice,'-s','150','-a','120','-w',source,'--',input],{env});
        execute('sox',[source,'-r','8000','-c','1','-b','16','-e','signed-integer',rendered,'gain','-3','highpass','80','lowpass','3600','gain','-n','-3']);
        const data=fs.readFileSync(rendered),metrics=wave(data),sha256=hash(data),destination=path.join(dir,p.id+'.wav');
        if(fs.existsSync(destination)) {
          const prior=previous?.prompts.find(v=>v.id===p.id);
          if(hash(fs.readFileSync(destination))!==sha256) {
            assert(prior,'Refusing to replace an unowned existing recording');verifyFile(destination,prior.sha256);
          } else verifyFile(destination,sha256);
        }
        fs.copyFileSync(rendered,destination);fs.chmodSync(destination,420);
        generated.push({id:p.id,text:p.text,synthesis_text:input,kind:p.kind,phonemes,sha256,...metrics});
        if((index+1)%250===0)console.log(locale+': '+(index+1)+'/'+entries.length+' offline prompts');
      }
      const manifest={schema_version:1,owner:OWNER,locale,voice:c.voice,engine:'espeak-ng',engine_version:'1.52.0',
        source_url:'https://github.com/espeak-ng/espeak-ng',source_commit:ESPEAK_COMMIT,engine_license:'GPL-3.0-or-later',
        synthesis:'formant; no external voice models',native_speaker_review:false,runtime_ready:false,
        complete:generated.length===c.prompts.length,numbers:['ar-sa','he-il'].includes(locale)?'prerecorded':'native_say',
        number_range:[0,999999999],required_prompt_ids:c.prompts.filter(p=>p.kind==='fixed').map(p=>p.id),
        numeric_prompt_count:c.prompts.filter(p=>p.kind!=='fixed').length,prompts:generated};
      manifest.asset_sha256=hash(JSON.stringify(generated.map(p=>[p.id,p.sha256])));
      const tmp=path.join(temporary,'manifest.json');fs.writeFileSync(tmp,JSON.stringify(manifest,null,2)+'\n',{mode:420});
      fs.renameSync(tmp,manifestFile);
      console.log(locale+': generated '+generated.length+' offline prompts; runtime_ready=false; native review pending');
    } finally {
      for(const file of fs.readdirSync(temporary))fs.unlinkSync(path.join(temporary,file));fs.rmdirSync(temporary);
    }
  }
}
module.exports={wave,options,main};
if(require.main===module)try{main(process.argv.slice(2));}catch(error){console.error('Language generation failed: '+error.message);process.exitCode=1;}
