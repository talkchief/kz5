#!/usr/bin/env node
'use strict';
// Read-only current-artifact checks. Does not compare prior generated bundles.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),vm=require('node:vm'),zlib=require('node:zlib');
const {sourceRoot}=require('./build-monster-production.cjs');
const {safePath,snapshot,hash,preloadedApps}=require('./deploy-owned-monster.cjs');
const EXCLUDED=['demo_done','skeleton','tutorial'];
function metrics(file){const bytes=fs.readFileSync(file);return {sha256:hash(bytes),bytes:bytes.length,gzip9_bytes:zlib.gzipSync(bytes,{level:9,mtime:0}).length};}
function sourceTemplates(source,apps){
    const found=new Map();
    function views(app,submodule,folder){
        if(!fs.existsSync(folder))return;
        safePath(folder);
        for(const name of fs.readdirSync(folder).sort())if(!name.startsWith('.')&&name.endsWith('.html')){
            const file=path.join(folder,name);safePath(file);assert(fs.statSync(file).isFile());
            const key=[app,'_'+submodule,...name.slice(0,-5).split('.')];
            assert(!found.has(JSON.stringify(key)),'Duplicate compiled template key');found.set(JSON.stringify(key),file);
        }
    }
    for(const app of apps){
        views(app,'main',path.join(source,'src/apps',app,'views'));
        const subs=path.join(source,'src/apps',app,'submodules');
        if(fs.existsSync(subs))for(const sub of fs.readdirSync(subs).sort())if(!sub.startsWith('.')&&fs.statSync(path.join(subs,sub)).isDirectory())views(app,sub,path.join(subs,sub,'views'));
    }
    return found;
}
function verify(source){
    source=sourceRoot(source);const dist=path.join(source,'dist'),before=snapshot(dist),src=snapshot(path.join(source,'src'));
    for(const file of ['index.html','js/main.js','js/templates.js','js/config.js','css/style.css','build-config.json','VERSION'])assert(before[file],'Missing required production artifact');
    assert(before['js/config.js']===src['js/config.js'],'Runtime configuration changed');
    assert(!before['apps/acdc/language-capabilities.json'],'Build must not publish runtime readiness');
    const apps=fs.readdirSync(path.join(source,'src/apps')).sort();
    assert.deepEqual(fs.readdirSync(path.join(dist,'apps')).sort(),apps,'Application directories differ');
    const config=JSON.parse(fs.readFileSync(path.join(dist,'build-config.json'),'utf8')),preload=apps.filter(app=>!EXCLUDED.includes(app));
    assert.equal(config.type,'production');assert.deepEqual([...preloadedApps(config)].sort(),preload,'Preload set differs');
    let metadata=0;
    for(const app of apps){const file='apps/'+app+'/metadata/app.json';if(src[file]){assert.equal(before[file],src[file],'Application metadata changed: '+app);metadata++;}}
    const index=fs.readFileSync(path.join(dist,'index.html'),'utf8'),references=[],external=[];
    for(const match of index.matchAll(/\b(?:src|href)=["']([^"']+)["']/g)){
        const url=match[1];if(/^(?:https?:)?\/\//.test(url)){external.push(url);continue;}
        if(/^(?:data:|#)/.test(url))continue;
        const relative=url.split(/[?#]/)[0];assert(!path.isAbsolute(relative)&&!relative.split('/').includes('..'),'Unsafe index reference');
        assert(before[relative],'Missing index asset '+relative);references.push(relative);
    }
    const context={monster:{cache:{templates:{}}}};vm.createContext(context);
    const runtime='js/vendor/handlebars-v4.7.7.js';assert(src[runtime],'Missing pinned Handlebars runtime');
    vm.runInContext(fs.readFileSync(path.join(source,'src',runtime),'utf8'),context,{timeout:5000});
    assert.equal(context.Handlebars.VERSION,'4.7.7');
    // Template construction validates each compiler revision without making an
    // AJAX request or invoking arbitrary application factories.
    vm.runInContext(fs.readFileSync(path.join(dist,'js/templates.js'),'utf8'),context,{timeout:15000});
    const actual=new Map();
    function walk(value,parts=[]){
        for(const key of Object.keys(value).sort()){
            const child=value[key],next=parts.concat(key);
            if(typeof child==='function')actual.set(JSON.stringify(next),child);
            else {assert(child&&typeof child==='object','Unexpected template cache value');walk(child,next);}
        }
    }
    walk(context.monster.cache.templates);
    const expected=sourceTemplates(source,preload);assert.deepEqual([...actual.keys()].sort(),[...expected.keys()].sort(),'Compiled template coverage differs from source views');
    let acdcCases=0;
    if(preload.includes('acdc')) {
        const state=JSON.stringify(['acdc','_main','state']);assert(actual.has(state),'Missing ACDC state template');
        const original=context.Handlebars.compile(fs.readFileSync(expected.get(state),'utf8'));
        for(const data of [{loading:true,message:'<caller>'},{error:true,message:'fixture',i18n:{acdc:{states:{couldNotLoad:'Unavailable'},actions:{retry:'Retry'}}}}]) {
            assert.equal(actual.get(state)(data),original(data),'ACDC template render differs');acdcCases++;
        }
    }
    assert.deepEqual(snapshot(dist),before,'Artifact changed during readback');assert.deepEqual(snapshot(path.join(source,'src')),src,'Source changed during readback');
    return {status:'passed',scope:'current static artifact/source/metadata/preload/runtime-template readback, not browser or prior-run byte equivalence',deployed:false,
        files:Object.keys(before).length,artifact_sha256:hash(JSON.stringify(before)),source_sha256:hash(JSON.stringify(src)),apps,preloads:preload,metadata_documents:metadata,
        index_local_references:references,index_external_references:external,compiled_templates:actual.size,template_keys_sha256:hash(JSON.stringify([...actual.keys()].sort())),
        handlebars_version:context.Handlebars.VERSION,acdc_state_render_cases:acdcCases,configuration_sha256:before['js/config.js'],
        metrics:Object.fromEntries(['main.js','templates.js'].map(name=>[name,metrics(path.join(dist,'js',name))])),
        css:{sha256:before['css/style.css'],bytes:fs.statSync(path.join(dist,'css/style.css')).size}};
}
if(require.main===module){try{assert.equal(process.argv.length,3);console.log(JSON.stringify(verify(process.argv[2]),null,2));}catch(error){console.error('FAIL production artifact readback: '+error.message);process.exitCode=1;}}
module.exports={verify,sourceTemplates};
