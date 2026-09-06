#!/usr/bin/env node
'use strict';
// A receipt for actual replay/test inputs, not unrelated installer settings.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function pinnedRef(text) {
  const matches=[...text.matchAll(/^ACDC_REF=\$\{ACDC_REF:-([a-f0-9]{40})\}$/gm)];
  assert.equal(matches.length,1,'Expected one literal pinned ACDC_REF');
  return matches[0][1];
}
function capture({installer,patch,mapText,files=[]}) {
  return JSON.stringify({schema_version:1,
    pinned_ref:pinnedRef(fs.readFileSync(installer,'utf8')),
    patch_sha256:hash(fs.readFileSync(patch)),
    verified_map_sha256:hash(mapText),
    sources:files.map(([label,file])=>[label,hash(fs.readFileSync(file))]).sort((a,b)=>a[0].localeCompare(b[0],'en'))});
}
function projectSnapshot(projectRoot,packageRoot) {
  const {render}=require(path.join(packageRoot,'generate-acdc-gemini-map.cjs'));
  const projectFiles=[
    'scripts/erlang-tests/acdc_callback_announcement_tests.erl',
    'scripts/erlang-tests/acdc_callback_caller_tests.erl',
    'scripts/erlang-tests/cf_acdc_callback_integration_tests.erl',
    'scripts/erlang-tests/cf_acdc_callback_feedback_tests.erl',
    'core/kazoo_amqp/src/api/kapi_dialplan.erl',
    'scripts/patches/acdc-atomic-answer-runtime.patch',
    'scripts/patches/acdc-language-runtime.patch'];
  // Bind the historical projection to the bundled inputs, without a nested Git repository.
  function sourceFiles(directory) {
    return fs.readdirSync(path.join(projectRoot,directory),{withFileTypes:true}).flatMap(entry=>{
      const file=directory+'/'+entry.name;
      assert(!entry.isSymbolicLink(),'Symlinked ACDC test source: '+file);
      return entry.isDirectory()?sourceFiles(file):[file];
    });
  }
  for(const directory of ['src','include','priv','test'])
    projectFiles.push(...sourceFiles('applications/acdc/'+directory));
  const packageFiles=[
    'test-acdc-gemini-runtime.sh','generate-acdc-gemini-map.cjs','gemini-runtime-inputs.cjs',
    'test-acdc-gemini-runtime-inputs.cjs','erlang-tests/acdc_gemini_prompts_tests.erl',
    'erlang-tests/acdc_gemini_runtime_tests.erl','erlang-tests/cf_acdc_callback_success_tests.erl',
    'test-fixtures/gemini-runtime/kz_datamgr.erl'];
  return capture({installer:path.join(projectRoot,'scripts/install-kazoo5.sh'),
    patch:path.join(projectRoot,'scripts/patches/acdc-kazoo5-integration.patch'),
    // This re-runs strict manifest/audio-byte QA in a fresh Node invocation.
    mapText:render(projectRoot),
    files:[...projectFiles.map(p=>['project/'+p,path.join(projectRoot,p)]),
           ...packageFiles.map(p=>['package/'+p,path.join(packageRoot,p)])]});
}
module.exports={pinnedRef,capture,projectSnapshot};
if(require.main===module) {
  assert.equal(process.argv.length,4,'Expected project root and package scripts root');
  process.stdout.write(projectSnapshot(fs.realpathSync(process.argv[2]),fs.realpathSync(process.argv[3])));
}
