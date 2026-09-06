#!/usr/bin/env node
'use strict';
// Actual number/MIME Makefile recipes with private tiny templates and data.
// No live source/ebin changes or downloads. Retain fixtures and expected failures.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const sources={numbers:path.join(root,'core/kazoo_numbers/Makefile'),web:path.join(root,'core/kazoo_web/Makefile')};
const inputs=Object.fromEntries([__filename,...Object.values(sources)].map(p=>[p,sha(p)]));
const out=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-generated-rebuild.'));fs.chmodSync(out,0o700);
const downloadLog=path.join(out,'forbidden-download.log');
const env={PATH:path.join(out,'bin')+':/usr/bin:/bin',TMPDIR:out,LC_ALL:'C',
 ERL_FLAGS:'+S 1:1 +A 1 -no_dot_erlang',ERL_CRASH_DUMP:'/dev/null',FORBIDDEN_DOWNLOAD_LOG:downloadLog};
const oldTime=new Date('2001-01-01T00:00:00Z'),futureTime=new Date('2050-01-01T00:00:00Z');
const numberNames=['knm_iso3166a2_itu','knm_iso3166_util'];
const targets={numbers:numberNames.map(n=>'src/'+n+'.erl'),web:['src/kz_mime.erl']};
let sequence=0,stage='prepare',passed=false,error=null;const groups=[];
function file(lane,name){return path.join(out,lane,name);}
function write(p,text){fs.writeFileSync(p,text,{mode:0o600});}
function command(lane,command,args,expected=0){
 const label=String(++sequence).padStart(2,'0')+'-'+lane+'-'+path.basename(command);
 const result=cp.spawnSync(command,args,{cwd:path.join(out,lane),env,encoding:'utf8',timeout:15000,maxBuffer:1024*1024});
 write(path.join(out,label+'.json'),JSON.stringify({cwd:path.join(out,lane),command,args,status:result.status,signal:result.signal,error:result.error?.message||null},null,2)+'\n');
 write(path.join(out,label+'.stdout'),result.stdout||'');write(path.join(out,label+'.stderr'),result.stderr||'');
 assert(!result.error,label+': '+result.error?.message);assert.equal(result.signal,null,label+' signalled');
 if(expected===0)assert.equal(result.status,0,label+': '+result.stderr+'\n'+result.stdout);
 else assert(result.status!==0&&result.status!==null,label+' unexpectedly succeeded');
 assert(!fs.existsSync(downloadLog),'download rule was invoked');return result;
}
function make(lane,force=false,selected=targets[lane],expected=0){
 return command(lane,'/usr/bin/make',['--no-print-directory','-j1','-f','Makefile',
  ...(force?['--eval=.PHONY: '+targets[lane].join(' ')]:[]),
  'ERLC_OPTS=+debug_info -Werror','ELIBS=','PA=',...selected],expected);
}
function compileNumbers(){command('numbers','/usr/bin/erlc',['+debug_info','-Werror','-o','ebin',...targets.numbers]);}
function verify(lane,version){
 const expression=lane==='numbers'
  ? 'case {knm_iso3166a2_itu:fixture_version(),knm_iso3166a2_itu:to_itu(<<"ZZ">>),knm_iso3166_util:fixture_version(),knm_iso3166_util:country(<<"ZZ">>)} of {'+version+',<<"+'+(version==='old'?'7':'8')+'">>,'+version+',#{a2 := <<"ZZ">>,a3 := <<"ZZZ">>,itu := <<"+'+(version==='old'?'7':'8')+'">>}} -> halt(0); _ -> halt(9) end.'
  : 'case {kz_mime:fixture_version(),kz_mime:from_extension(<<"'+version+'ext">>),kz_mime:to_extensions(<<"application/x-'+version+'">>)} of {'+version+',<<"application/x-'+version+'">>,[<<"'+version+'ext">>]} -> halt(0); _ -> halt(9) end.';
 command(lane,'/usr/bin/erl',['+S','1:1','+A','1','-no_dot_erlang','-noshell','-noinput','-pa',file(lane,'ebin'),'-eval',expression]);
}
function fixtureInputs(version){
 const written=[];
 function input(lane,name,text){const p=file(lane,name);write(p,text);fs.utimesSync(p,oldTime,oldTime);written.push(p);}
 for(const name of numberNames)input('numbers','src/'+name+'.erl.src',
  '-module('+name+').\n-export(['+(name.endsWith('_itu')?'to_itu':'country')+'/1,fixture_version/0]).\nfixture_version() -> '+version+'.\n');
 input('numbers','dialcodes.json',JSON.stringify([{cca2:'ZZ',cca3:'ZZZ',callingCode:[version==='old'?'7':'8']}])+'\n');
 input('web','src/kz_mime.erl.src','-module(kz_mime).\n-export([from_extension/1,to_extensions/1,fixture_version/0]).\n%% GENERATED\nfixture_version() -> '+version+'.\n');
 input('web','mime.types','application/x-'+version+' '+version+'ext\n');
 return Object.fromEntries(written.map(p=>[p,sha(p)]));
}
function artifactPaths(lane){return [...targets[lane],...(lane==='numbers'?numberNames:['kz_mime']).map(n=>'ebin/'+n+'.beam')].map(p=>file(lane,p));}
function state(paths){return Object.fromEntries(paths.map(p=>[p,{sha:sha(p),mtime:fs.statSync(p).mtimeMs}]));}
function assertInputsUnchanged(pins){for(const [p,digest] of Object.entries(pins))assert.equal(sha(p),digest,'make modified fixture input '+p);}
function done(name){groups.push(name);}
try {
 fs.mkdirSync(path.join(out,'bin'),{mode:0o700});
 const wget=path.join(out,'bin/wget');write(wget,'#!/bin/sh\nprintf "forbidden download\\n" >> "$FORBIDDEN_DOWNLOAD_LOG"\nexit 42\n');fs.chmodSync(wget,0o700);
 for(const lane of Object.keys(sources)){
  fs.mkdirSync(file(lane,'src'),{recursive:true,mode:0o700});fs.mkdirSync(file(lane,'ebin'),{mode:0o700});
  const text=fs.readFileSync(sources[lane],'utf8'),include='include $(ROOT)/make/kz.mk';
  assert.equal(text.split('\n').filter(line=>line===include).length,1,'exact single include required');
  const fixture=text.replace(include+'\n','');assert.equal(fixture.length,text.length-include.length-1);
  write(file(lane,'Makefile'),fixture);
  write(file(lane,'extraction.json'),JSON.stringify({source:sources[lane],source_sha256:inputs[sources[lane]],removed_line:include,fixture_sha256:sha(file(lane,'Makefile')),recipes_unchanged:true},null,2)+'\n');
 }
 stage='initial-generation';const initialInputs=fixtureInputs('old');
 make('numbers');compileNumbers();make('web');verify('numbers','old');verify('web','old');assertInputsUnchanged(initialInputs);done(stage);
 stage='default-stale-with-restored-inputs-and-future-artifacts';const changedInputs=fixtureInputs('new');
 const allArtifacts=[...artifactPaths('numbers'),...artifactPaths('web')];
 for(const p of allArtifacts)fs.utimesSync(p,futureTime,futureTime);
 const stale=state(allArtifacts);make('numbers');make('web');assert.deepEqual(state(allArtifacts),stale);
 verify('numbers','old');verify('web','old');assertInputsUnchanged(changedInputs);done(stage);
 stage='targeted-phony-regenerates-number-sources-not-beams';make('numbers',true);
 for(const p of targets.numbers.map(p=>file('numbers',p))){assert.notEqual(sha(p),stale[p].sha);assert(fs.statSync(p).mtimeMs<futureTime.getTime());}
 const numberBeams=numberNames.map(n=>file('numbers','ebin/'+n+'.beam'));
 assert.deepEqual(state(numberBeams),Object.fromEntries(numberBeams.map(p=>[p,stale[p]])));
 compileNumbers();verify('numbers','new');
 for(const p of numberBeams){assert.notEqual(sha(p),stale[p].sha);assert(fs.statSync(p).mtimeMs<futureTime.getTime());}done(stage);
 stage='targeted-phony-regenerates-and-compiles-mime';make('web',true);verify('web','new');
 for(const p of artifactPaths('web')){assert.notEqual(sha(p),stale[p].sha);assert(fs.statSync(p).mtimeMs<futureTime.getTime());}
 assertInputsUnchanged(changedInputs);done(stage);
 stage='malformed-number-input-fails-both-real-recipes';write(file('numbers','dialcodes.json'),'{\n');
 for(const target of targets.numbers){const result=make('numbers',true,[target],1);assert.match(result.stderr,/JSONDecodeError/);}
 done(stage);
 stage='malformed-mime-input-fails-real-generator-compiler';write(file('web','mime.types'),'application/"broken badext\n');
 const badMime=make('web',true,targets.web,1);assert.match(badMime.stdout+badMime.stderr,/syntax error|unterminated/);done(stage);
 stage='no-downloads';assert(!fs.existsSync(downloadLog));done(stage);
 stage='complete';passed=true;
} catch(e){error=e.stack||String(e);process.exitCode=1;}
finally {
 let stable=false;try{stable=Object.entries(inputs).every(([p,digest])=>sha(p)===digest);}catch(e){error=(error||'')+'\nInput recheck: '+e.message;}
 if(!stable){passed=false;process.exitCode=1;error=(error||'')+'\nTest/source inputs changed';}
 const receipt={status:passed?'pass':'failed',stage,error,groups,source_inputs:inputs,source_inputs_stable:stable,commands:sequence,output:out,
  scope:'actual generator recipes; private tiny templates/data and real erlc/erl; number BEAM compilation is a separate explicit fixture step',
  downloads_invoked:fs.existsSync(downloadLog),live_changes:false,finished_at:new Date().toISOString()};
 write(path.join(out,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(receipt));if(error)console.error(error);
}
