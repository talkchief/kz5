#!/usr/bin/env node
'use strict';
// Offline tests against the pinned framework writer/reader, plus modular artifacts.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),vm=require('node:vm'),assert=require('node:assert/strict');
const {createRequire}=require('node:module');
const {verify}=require('./verify-monster-production-artifact.cjs');
const framework=path.resolve(process.argv[2]||'');
assert(process.argv[2],'Pass a prepared pinned Monster source directory');
const loader=createRequire(path.join(framework,'package.json')),lodash=loader('lodash');
const original=fs.readFileSync(path.join(framework,'gulp/tasks/write-config.js'),'utf8');
const patch=fs.readFileSync(path.join(__dirname,'patches/monster-ui-preloaded-apps.patch'),'utf8');
assert(patch.includes('-\t\t\tpreloadApps: getAppsToInclude()')&&patch.includes('+\t\t\tpreloadedApps: getAppsToInclude()'));
assert.equal(original.split('preloadApps: getAppsToInclude()').length,2,'Expected original pinned writer');
const corrected=original.replace('preloadApps: getAppsToInclude()','preloadedApps: getAppsToInclude()');
const writer=corrected.slice(corrected.indexOf('const writeFrameworkConfig ='),corrected.indexOf('const writeAppConfig ='));
let written;
vm.runInNewContext(writer+'\nwriteFrameworkConfig("prod");',{join:path.join,tmp:'/fixture',getAppsToInclude:()=>['core','acdc'],writeFile:(file,data)=>{written=JSON.parse(JSON.stringify(data));}});
assert.deepEqual(written,{type:'production',preloadedApps:['core','acdc']});
const monsterSource=fs.readFileSync(path.join(framework,'src/js/lib/monster.js'),'utf8');
const reader=monsterSource.slice(monsterSource.indexOf('loadBuildConfig: function(callback)'),monsterSource.indexOf('getScript: function(url, callback)')).trim().replace(/,$/,'');
const monster={config:{developerFlags:{}},parseVersionFile:()=>({version:'fixture'}),parallel(tasks,done){const result={};for(const [key,task]of Object.entries(tasks))task((err,value)=>{assert.ifError(err);result[key]=value;});done(null,result);}};
const context={_:lodash,monster,$:{ajax(options){options.success(options.url==='build-config.json'?written:'fixture');}}};
vm.runInNewContext('({'+reader+'}).loadBuildConfig();',context);
assert.deepEqual(monster.config.developerFlags.build.preloadedApps,['core','acdc']);
assert(!Object.hasOwn(monster.config.developerFlags.build,'preloadApps'));
console.log('PASS actual framework production writer and runtime preload reader contract');
const installer=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
assert(installer.includes('production_artifact_verifier:verify-monster-production-artifact.cjs'));
assert(installer.includes('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-preloaded-apps.patch"'));
const build=installer.indexOf('node "$SCRIPT_DIR/build-monster-production.cjs" "$source_dir"'),gate=installer.indexOf('node "$SCRIPT_DIR/verify-monster-production-artifact.cjs" "$source_dir"',build),deploy=installer.indexOf('deploy_monster_ui_owned "$source_dir"',build);
assert(build>0&&gate>build&&deploy>gate,'Artifact gate must precede activation');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'monster-owned-build.'));
try {
    const source=path.join(temp,'source');
    function put(file,bytes){const target=path.join(source,file);fs.mkdirSync(path.dirname(target),{recursive:true,mode:0o700});fs.writeFileSync(target,bytes,{mode:0o600});}
    for(const file of ['package.json','package-lock.json','node_modules/.package-lock.json','.babelrc','.babelrc.js','.babelregister.js','gulpfile.babel.js','gulp/fixture.js'])put(file,'{}');
    const runtime=fs.readFileSync(path.join(framework,'src/js/vendor/handlebars-v4.7.7.js'),'utf8');
    put('src/js/vendor/handlebars-v4.7.7.js',runtime);put('src/js/config.js','fixture config');
    put('src/apps/core/metadata/app.json','{"name":"core"}');put('dist/apps/core/metadata/app.json','{"name":"core"}');
    for(const [file,bytes]of Object.entries({'index.html':'<script src="js/main.js"></script>','js/main.js':'/* fixture */','js/templates.js':'','js/config.js':'fixture config','css/style.css':'','VERSION':'fixture','build-config.json':JSON.stringify({type:'production',preloadedApps:['core']})}))put('dist/'+file,bytes);
    let result=verify(source);assert.equal(result.acdc_state_render_cases,0);assert.deepEqual(result.preloads,['core']);
    console.log('PASS selected framework artifact without ACDC');
    const handlebarsContext={};vm.runInNewContext(runtime,handlebarsContext);const hb=handlebarsContext.Handlebars;
    const template='{{#if loading}}{{message}}{{else}}{{i18n.acdc.states.couldNotLoad}}{{/if}}';
    put('src/apps/acdc/views/state.html',template);put('src/apps/acdc/metadata/app.json','{"name":"acdc"}');put('dist/apps/acdc/metadata/app.json','{"name":"acdc"}');
    put('dist/build-config.json',JSON.stringify({type:'production',preloadedApps:['core','acdc']}));
    put('dist/js/templates.js','monster.cache.templates.acdc={_main:{state:Handlebars.template('+hb.precompile(template)+')}};');
    result=verify(source);assert.equal(result.acdc_state_render_cases,2);assert.equal(result.compiled_templates,1);
    console.log('PASS selected ACDC artifact with actual template render comparisons');
    put('dist/build-config.json',JSON.stringify({type:'production',preloadApps:['core','acdc']}));
    assert.throws(()=>verify(source),/canonical preloadedApps/);
    put('dist/build-config.json',JSON.stringify({type:'production',preloadedApps:['core']}));
    assert.throws(()=>verify(source),/Preload set differs/);
    console.log('PASS malformed and incomplete production preload rejection; installer gate precedes activation');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
