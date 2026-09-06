#!/usr/bin/env node
'use strict';
// Explicit optimization tradeoff: same pinned parser/mangler/output, no Compressor.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {createRequire}=require('node:module');
const {safePath}=require('./deploy-owned-monster.cjs');
const PROFILE_FILE=path.join(__dirname,'assets/monster-ui/minifier-profile.json');
const EXPECTED={id:'uglify2-mangle-no-compress-v1',gulp_uglify_version:'2.1.2',uglify_js_version:'2.8.29',options:{compress:false}};
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function validateProfile(value){assert.deepEqual(value,EXPECTED,'Unsupported minifier profile');return value;}
function profile(){safePath(PROFILE_FILE);return validateProfile(JSON.parse(fs.readFileSync(PROFILE_FILE,'utf8')));}
function dependencies(source){
    const loader=createRequire(path.join(source,'package.json')),selected=profile();
    const pluginFile=loader.resolve('gulp-uglify/package.json');safePath(pluginFile);
    const plugin=JSON.parse(fs.readFileSync(pluginFile,'utf8'));
    assert.equal(plugin.version,selected.gulp_uglify_version,'Unreviewed gulp-uglify version');
    const engineLoader=createRequire(pluginFile),engineFile=engineLoader.resolve('uglify-js/package.json');safePath(engineFile);
    const engine=JSON.parse(fs.readFileSync(engineFile,'utf8'));
    assert.equal(engine.version,selected.uglify_js_version,'Unreviewed UglifyJS version');
    return {loader,engineLoader,profile:selected};
}
function inventory(source,bytes){
    assert(Buffer.isBuffer(bytes)&&bytes.length<=12*1024*1024,'Inventory input exceeds bound');
    const {engineLoader,profile:selected}=dependencies(source),U=engineLoader('uglify-js');
    const ast=U.parse(bytes.toString('utf8'),{filename:'bounded-monster-input.js'});ast.figure_out_scope({});
    const modules=[];
    ast.walk(new U.TreeWalker(function(node){
        if(!(node instanceof U.AST_Call)||!(node.expression instanceof U.AST_SymbolRef)||node.expression.name!=='define')return;
        const definition=node.expression.definition();if(!definition||!definition.global)return;
        const named=node.args[0] instanceof U.AST_String,dependency=node.args[named?1:0];
        const entry={name:named?node.args[0].value:null,arity:node.args.length,dependencies:null};
        if(dependency instanceof U.AST_Array){
            assert(dependency.elements.every(item=>item instanceof U.AST_String),'Unsupported dynamic AMD dependency array');
            entry.dependencies=dependency.elements.map(item=>item.value);
        }
        modules.push(entry);assert(modules.length<=5000,'AMD inventory exceeds bound');
    }));
    return {profile:selected.id,input_sha256:hash(bytes),bytes:bytes.length,modules,inventory_sha256:hash(JSON.stringify(modules))};
}
function inventoryFile(source,name){
    source=path.resolve(source);safePath(source);
    assert(path.basename(source)==='source'&&/^monster-owned-build\.[A-Za-z0-9]+$/.test(path.basename(path.dirname(source))),'Expected private stage');
    assert(['main.js','templates.js'].includes(name),'Unsupported inventory file');
    const file=path.join(source,'tmp/js',name);safePath(file);const before=fs.lstatSync(file);
    assert(before.isFile()&&before.nlink===1&&before.size<=12*1024*1024,'Invalid inventory input');
    const bytes=fs.readFileSync(file),after=fs.lstatSync(file);
    for(const key of ['ino','dev','size','mtimeMs','ctimeMs','mode','uid','gid','nlink'])assert.equal(after[key],before[key],'Inventory input changed during read');
    return inventory(source,bytes);
}
if(require.main===module){
    try{assert.equal(process.argv.length,5);assert.equal(process.argv[2],'--inventory');console.log(JSON.stringify(inventoryFile(process.argv[3],process.argv[4])));}
    catch(error){console.error('FAIL Monster AMD inventory: '+(error.code||error.name));process.exitCode=1;}
}
module.exports={profile,validateProfile,dependencies,inventory,inventoryFile,PROFILE_FILE};
