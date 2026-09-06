#!/usr/bin/env node
'use strict';
// Actual kz.mk build rules + real tiny production erlc modules, all privately.
// No Kazoo source/ebin, service, network or Git mutation. Retain failed fixtures.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const sourcePath=path.resolve(__dirname,'../make/kz.mk'),source=fs.readFileSync(sourcePath,'utf8');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const inputs={[sourcePath]:sha(sourcePath),[__filename]:sha(__filename)};
const out=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-force-recompile.'));fs.chmodSync(out,0o700);
const env={PATH:'/usr/bin:/bin',TMPDIR:out,LC_ALL:'C',ERL_FLAGS:'+S 1:1 +A 1 -no_dot_erlang',ERL_CRASH_DUMP:'/dev/null'};
let sequence=0,stage='prepare',passed=false,error=null;
const oldTime=new Date('2001-01-01T00:00:00Z'),futureTime=new Date('2050-01-01T00:00:00Z');
const names=['force_fixture_main','force_fixture_helper'];
function command(command,args,expected=0){
 const label=String(++sequence).padStart(2,'0')+'-'+path.basename(command);
 const result=cp.spawnSync(command,args,{cwd:out,env,encoding:'utf8',timeout:15000,maxBuffer:1024*1024});
 fs.writeFileSync(path.join(out,label+'.json'),JSON.stringify({command,args,status:result.status,signal:result.signal,error:result.error?.message||null},null,2)+'\n',{mode:0o600});
 fs.writeFileSync(path.join(out,label+'.stdout'),result.stdout||'',{mode:0o600});
 fs.writeFileSync(path.join(out,label+'.stderr'),result.stderr||'',{mode:0o600});
 assert(!result.error,label+': '+result.error?.message);assert.equal(result.signal,null,label+' signalled');
 if(expected===0)assert.equal(result.status,0,label+': '+result.stderr);
 else assert(result.status!==0&&result.status!==null,label+' unexpectedly succeeded');
 return result;
}
function make(target,flag,jobs=2){return command('/usr/bin/make',['--no-print-directory','-j'+jobs,'-f','Makefile',target,...(flag===undefined?[]:['KAZOO_FORCE_RECOMPILE='+flag])]);}
function writeSources(value){for(const name of names){const p=path.join(out,'src',name+'.erl');
 fs.writeFileSync(p,'-module('+name+').\n-export([value/0]).\nvalue() -> '+value+'.\n',{mode:0o600});fs.utimesSync(p,oldTime,oldTime);
}}
function futureArtifacts(){for(const n of ['force_fixture.app',...names.map(n=>n+'.beam')])fs.utimesSync(path.join(out,'ebin',n),futureTime,futureTime);}
function verify(value,helper=value){
 command('/usr/bin/erl',['+S','1:1','+A','1','-no_dot_erlang','-noshell','-noinput','-pa',path.join(out,'ebin'),'-eval',
  'case {'+names.map(n=>n+':value()').join(',')+'} of {'+value+','+helper+'} -> halt(0); _ -> halt(9) end.']);
}
function artifactState(){return names.map(n=>{const p=path.join(out,'ebin',n+'.beam');return {sha:sha(p),mtime:fs.statSync(p).mtimeMs};});}
try {
 const flagStart=source.indexOf('ifeq ($(KAZOO_FORCE_RECOMPILE),1)\n');assert(flagStart>=0);
 const recipeStart=source.lastIndexOf('\nebin/$(PROJECT).app:\n');assert(recipeStart>flagStart);
 const flagRule=source.slice(flagStart,recipeStart);
 assert(flagRule.includes('.PHONY: kazoo-force-recompile')&&flagRule.includes('$(BEAMS): | ebin/$(PROJECT).app'));
 const recipeEnd=source.indexOf('\n.PHONY: depend',recipeStart);assert(recipeEnd>recipeStart);
 const recipes=source.slice(recipeStart+1,recipeEnd);
 const sourceRule=source.match(/^SOURCES\s+\?=.*$/m),beamRule=source.match(/^BEAMS :=.*$/m);
 const compileRules=source.match(/^compile:.*\ncompile-direct:.*$/m);
 assert(sourceRule&&beamRule&&compileRules);assert(recipes.includes('-o ebin/ $(SOURCES)'));
 fs.mkdirSync(path.join(out,'src'),{mode:0o700});
 fs.writeFileSync(path.join(out,'src/force_fixture.app.src'),'{application, force_fixture, [{vsn, "0"}, {modules, []}]}.\n',{mode:0o600});
 const fixture=`PROJECT = force_fixture\nKZ_VERSION = fixture\nELIBS =\nERLC_OPTS = +debug_info -Werror\nPA =\nAPPS_PA =\nMODULES = ${names.join(',')}\n`+
  sourceRule[0]+'\n'+beamRule[0]+'\n.PHONY: compile compile-direct deps apps json depend\ndeps apps json depend:\n'+
  compileRules[0]+'\n'+flagRule+'\n'+recipes+'\n';
 fs.writeFileSync(path.join(out,'Makefile'),fixture,{mode:0o600});
 fs.writeFileSync(path.join(out,'extraction.json'),JSON.stringify({source:sourcePath,source_sha256:inputs[sourcePath],source_rule:sourceRule[0],beam_rule:beamRule[0],compile_rules:compileRules[0],flag_rule:flagRule,recipes},null,2)+'\n',{mode:0o600});
 stage='initial-production-build';writeSources('old');make('compile-direct',undefined,1);verify('old');
 stage='default-incremental-updates-only-changed-source';
 const helperBefore=artifactState()[1],mainSource=path.join(out,'src/force_fixture_main.erl');
 fs.writeFileSync(mainSource,'-module(force_fixture_main).\n-export([value/0]).\nvalue() -> incremental.\n',{mode:0o600});fs.utimesSync(mainSource,futureTime,futureTime);
 let result=make('compile-direct');assert(result.stdout.includes('-o ebin/ src/force_fixture_main.erl'));
 assert.deepEqual(artifactState()[1],helperBefore);verify('incremental','old');
 stage='missing-flag-preserves-incremental';writeSources('restored');futureArtifacts();const stale=artifactState();
 result=make('compile-direct');assert(!result.stdout.includes('erlc -v'));assert.deepEqual(artifactState(),stale);verify('incremental','old');
 stage='zero-flag-preserves-incremental';result=make('compile-direct','0');assert(!result.stdout.includes('erlc -v'));assert.deepEqual(artifactState(),stale);
 stage='forced-compile-direct';result=make('compile-direct','1');assert(result.stdout.includes('-o ebin/ src/force_fixture_helper.erl src/force_fixture_main.erl'));
 verify('restored');assert(artifactState().every((s,i)=>s.sha!==stale[i].sha&&s.mtime<futureTime.getTime()));
 stage='forced-compile';writeSources('latest');futureArtifacts();make('compile','1');verify('latest');
 stage='compiler-failure-stops-app-recipe';futureArtifacts();
 const app=path.join(out,'ebin/force_fixture.app'),before={sha:sha(app),mtime:fs.statSync(app).mtimeMs};
 const invalid=path.join(out,'src/force_fixture_main.erl');fs.writeFileSync(invalid,'this is not valid Erlang.\n',{mode:0o600});fs.utimesSync(invalid,oldTime,oldTime);
 command('/usr/bin/make',['--no-print-directory','-j2','-f','Makefile','compile-direct','KAZOO_FORCE_RECOMPILE=1'],1);
 assert.deepEqual({sha:sha(app),mtime:fs.statSync(app).mtimeMs},before,'failed compiler must stop before writing .app');
 stage='complete';passed=true;
} catch(e){error=e.stack||String(e);process.exitCode=1;}
finally {
 const stable=Object.entries(inputs).every(([p,digest])=>sha(p)===digest);if(!stable){passed=false;process.exitCode=1;error=(error||'')+'\nTest/source inputs changed';}
 const receipt={status:passed?'pass':'failed',stage,error,scope:'actual extracted kz.mk rules with two tiny real erlc modules and private erl readback',source_inputs:inputs,source_inputs_stable:stable,commands:sequence,output:out,live_changes:false,finished_at:new Date().toISOString()};
 fs.writeFileSync(path.join(out,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
 console.log(JSON.stringify(receipt));
 if(error)console.error(error);
}
