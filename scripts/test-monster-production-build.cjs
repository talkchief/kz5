#!/usr/bin/env node
'use strict';
// Run under the validation guard after a pinned private npm/native preparation.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process'),{createRequire}=require('node:module');
const candidate=require('./build-monster-production.cjs');
const profile=require('./monster-minifier-profile.cjs');
const source=path.resolve(process.argv[2]||process.env.KAZOO_MONSTER_TEST_SOURCE||'');
const helper=path.join(__dirname,'build-monster-production.cjs');
const loader=createRequire(path.join(source,'package.json'));
const Vinyl=createRequire(createRequire(loader.resolve('gulp/package.json')).resolve('vinyl-fs/package.json'))('vinyl');
function original(name,bytes){return new Promise((resolve,reject)=>{
    const transform=loader('gulp-uglify')(profile.profile().options);transform.once('data',file=>resolve(file.contents));transform.once('error',reject);
    transform.end(new Vinyl({cwd:source,base:path.join(source,'tmp/js'),path:path.join(source,'tmp/js',name),contents:bytes}));
});}
const childCode='const fs=require("node:fs"),b=require(process.argv[1]);b.transformBytes(process.argv[2],process.argv[3],fs.readFileSync(0)).then(x=>process.stdout.write(x)).catch(()=>{process.stderr.write("fixture_rejected\\n");process.exitCode=1;});';
function isolated(name,bytes){return spawnSync(process.execPath,['-e',childCode,helper,source,name],{input:bytes,timeout:30000,maxBuffer:1024*1024,env:{...process.env,NODE_OPTIONS:'--max-old-space-size=192'}});}
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'monster-owned-build.'));let passed=0;
function write(file,data){fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});fs.writeFileSync(file,data,{mode:0o600});}
function ok(name){passed++;console.log('PASS '+name);}
(async()=>{
    candidate.sourceRoot(source);
    for(const [name,code]of [
        ['main.js','(function(){ var number = 1 + 2; window.fixture = function (value) { return value + number; }; }());'],
        ['templates.js','/*! license fixture */ var template = "hello";\n//# sourceMappingURL=fixture.map'],
        ['main.js','window.languages = ["العربية", "עברית", "français"];'],
        ['templates.js','// deliberately empty template fixture\n']
    ]){const bytes=Buffer.from(code),expected=await original(name,bytes),actual=isolated(name,bytes);assert.equal(actual.status,0,actual.stderr.toString());assert.deepEqual(actual.stdout,expected);ok('fresh process bytes equal same explicit profile factory: '+name+' case'+passed);}
    const invalid=Buffer.from('function broken( {');await assert.rejects(original('main.js',invalid));assert.notEqual(isolated('main.js',invalid).status,0);ok('syntax failure propagates nonzero');
    assert.notEqual(isolated('../config.js',Buffer.from('window.ok=true;')).status,0);ok('minifier traversal name is rejected');
    const fake=path.join(temp,'source');
    for(const [file,bytes]of Object.entries({'package.json':'{}','package-lock.json':'{}','node_modules/.package-lock.json':'{}','src/fixture.js':'keep','gulp/fixture.js':'keep','.babelrc':'{}','.babelrc.js':'module.exports={};','.babelregister.js':'','gulpfile.babel.js':'// KAZOO_BOUNDED_PRODUCTION_PHASES_V1','node_modules/gulp/bin/gulp.js':'require("fs").appendFileSync("phase.log",process.argv[2]+"\\n");process.exit(7);'}))write(path.join(fake,file),bytes);
    await assert.rejects(candidate.build(fake),/child failed/);assert.equal(fs.readFileSync(path.join(fake,'phase.log'),'utf8'),'build-prod-prepare\n');assert(!fs.existsSync(path.join(fake,'dist')));ok('prepare failure stops before minify/finalize');
    const outside=path.join(temp,'outside');fs.mkdirSync(outside,{mode:0o700});write(path.join(outside,'sentinel'),'keep');fs.symlinkSync(outside,path.join(fake,'tmp'));
    assert.throws(()=>candidate.sourceRoot(fake),/Symlink/);assert.equal(fs.readFileSync(path.join(outside,'sentinel'),'utf8'),'keep');ok('linked temporary output rejects without outside effects');
    console.log('PASS '+passed+' production build fixture groups');
})().catch(error=>{console.error('FAIL production build fixtures: '+error.message);process.exitCode=1;}).finally(()=>fs.rmSync(temp,{recursive:true,force:true}));
