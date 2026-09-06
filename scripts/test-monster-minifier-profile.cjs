#!/usr/bin/env node
'use strict';
// Small fixed fixtures only. Never executes the full application bundle.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),vm=require('node:vm'),zlib=require('node:zlib');
const {createRequire}=require('node:module');
const candidate=require('./build-monster-production.cjs'),profile=require('./monster-minifier-profile.cjs');
const source=path.resolve(process.argv[2]||process.env.KAZOO_MONSTER_TEST_SOURCE||'');
const loader=createRequire(path.join(source,'package.json'));
const Vinyl=createRequire(createRequire(loader.resolve('gulp/package.json')).resolve('vinyl-fs/package.json'))('vinyl');
let passed=0;
function defaultTransform(bytes){return new Promise((resolve,reject)=>{
 const transform=loader('gulp-uglify')();transform.once('data',file=>resolve(file.contents));transform.once('error',reject);
 transform.end(new Vinyl({cwd:source,base:path.join(source,'tmp/js'),path:path.join(source,'tmp/js/main.js'),contents:bytes}));
});}
function execute(bytes){
 const definitions=Object.create(null),registration=[],trace=[],exports=Object.create(null);
 const context={trace,result:null};
 function define(name,deps,factory){if(!Array.isArray(deps)){factory=deps;deps=[];}registration.push({name,deps});definitions[name]={deps,factory};}
 define.amd={};context.define=define;
 function load(name){
  if(Object.hasOwn(exports,name))return exports[name];assert(Object.hasOwn(definitions,name),'Unknown fixture dependency');
  const entry=definitions[name],exp={};exports[name]=exp;
  const args=entry.deps.map(dep=>dep==='exports'?exp:dep==='require'?load:load(dep));
  const result=typeof entry.factory==='function'?entry.factory(...args):entry.factory;
  if(result!==undefined)exports[name]=result;return exports[name];
 }
 context.load=load;vm.runInNewContext(bytes.toString('utf8'),context,{timeout:1000});
 return JSON.parse(JSON.stringify({registration,trace,result:context.result}));
}
function ok(name){passed++;console.log('PASS '+name);}
(async()=>{
 candidate.sourceRoot(source);assert.equal(profile.profile().id,'uglify2-mangle-no-compress-v1');
 assert.throws(()=>profile.validateProfile({...profile.profile(),options:{compress:false,mangle:false}}),/Unsupported/);
 assert.throws(()=>profile.validateProfile({...profile.profile(),uglify_js_version:'3.0.0'}),/Unsupported/);ok('profile has exact reviewed options and engine versions');
 const fixtures=[
  ['AMD factory dependencies and order',"var counter=0; define('alpha',['exports'],function(exports){trace.push('alpha');exports.value=++counter;}); define('beta',['alpha'],function(alpha){trace.push('beta');return {value:alpha.value+2};}); result=load('beta');"],
  ['UMD AMD branch and local variable shadowing',"(function(factory){if(typeof define==='function'&&define.amd){define('umd',[],factory);}else{throw Error('wrong branch');}})(function(){var descriptiveName=7;return {n:descriptiveName};}); (function(define){define('local',[],function(){});})(function(){trace.push('shadowed');}); result=load('umd');"],
  ['short circuit getters exceptions and finally order',"var count=0,o={};Object.defineProperty(o,'n',{get:function(){trace.push('get');return ++count;}});var value=false&&o.n;try{value=o.n;throw new Error('fixture');}catch(error){trace.push(error.message);}finally{trace.push('finally');}result={value:value,count:count};"],
  ['Unicode and public property names',"define('language',[],function(){return {queue:'العربية',position:'עברית',callback:'français'};});result=load('language');"],
  ['local name mangling and no constant-folding profile',"function calculate(longInputName){var intermediateValue=longInputName+2;return intermediateValue*3;} result={value:calculate(4)};"],
  ['registration side-effect ordering inside factory',"define('first',[],function(){trace.push('factory');define('late',[],function(){return 8;});return load('late');});trace.push('registered');result=load('first');"]
 ];
 for(const [name,code]of fixtures){
  const input=Buffer.from(code),bounded=await candidate.transformBytes(source,'main.js',input),original=await defaultTransform(input);
  assert.deepEqual(execute(bounded),execute(input));assert.deepEqual(execute(original),execute(input));
  assert.deepEqual(profile.inventory(source,bounded).modules,profile.inventory(source,input).modules);
  console.log(JSON.stringify({fixture:name,input_bytes:input.length,default_bytes:original.length,profile_bytes:bounded.length,
   default_gzip:zlib.gzipSync(original,{level:9,mtime:0}).length,profile_gzip:zlib.gzipSync(bounded,{level:9,mtime:0}).length}));
  ok(name);
 }
 const inv=profile.inventory(source,Buffer.from("define('a',['b'],function(){});define('b',[],function(){});"));
 assert.equal(inv.modules.length,2);assert.deepEqual(inv.modules.map(entry=>entry.name),['a','b']);
 assert.notEqual(profile.inventory(source,Buffer.from("define('b',[],function(){});define('a',['b'],function(){});")).inventory_sha256,inv.inventory_sha256);
 assert.notEqual(profile.inventory(source,Buffer.from("define('a',['c'],function(){});define('b',[],function(){});")).inventory_sha256,inv.inventory_sha256);
 assert.notEqual(profile.inventory(source,Buffer.from("define('a',['b'],function(){});")).inventory_sha256,inv.inventory_sha256);ok('inventory detects lost module, dependency change and ordering change');
 assert.throws(()=>profile.inventory(source,Buffer.from("define('dynamic',[unknown],function(){});")),/dynamic AMD/);ok('unsupported dynamic dependencies fail closed');
 await assert.rejects(candidate.transformBytes(source,'main.js',Buffer.from('function broken( {')));ok('profile never ignores syntax errors');
 const proof=Buffer.from('function longFunction(longArgument){var longLocal=longArgument+1;return longLocal;} result=longFunction(1);');
 const output=await candidate.transformBytes(source,'main.js',proof);assert(!output.toString().includes('longArgument'));assert(!output.toString().includes('longLocal'));ok('default local name mangling remains enabled');
 console.log('PASS '+passed+' supported minifier profile groups');
})().catch(error=>{console.error('FAIL supported minifier profile: '+error.message);process.exitCode=1;});
