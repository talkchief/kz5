#!/usr/bin/env node
'use strict';
// Real filesystem checks, confined to one new protected fixture directory.
// No credentials, Kazoo service, database, media import or provider is used.
const fs=require('node:fs'), path=require('node:path'), assert=require('node:assert/strict');
const {ensureAppsCapabilities}=require('./ensure-acdc-language-capabilities.cjs');
assert(process.getuid()===0, 'Run as root to test the production ownership contract');
const parent=process.argv[2];
assert(process.argv.length===3&&path.isAbsolute(parent)&&path.resolve(parent)===parent&&parent!=='/',
    'Pass a protected existing fixture parent, not a workspace/root deletion target');
for(let current=parent;;current=path.dirname(current)) {
    const stat=fs.lstatSync(current);
    assert(stat.isDirectory()&&!stat.isSymbolicLink()&&stat.uid===0&&!(stat.mode&0o022), 'Unsafe fixture ancestor');
    if(path.dirname(current)===current)break;
}
const fixture=fs.mkdtempSync(path.join(parent,'acdc-capability-filesystem.'));
fs.chmodSync(fixture,0o700);
const config=path.join(fixture,'custom-config');fs.mkdirSync(config,{mode:0o755});
const created=ensureAppsCapabilities(config), file=path.join(config,'acdc/language-capabilities.json');
assert.equal(created.result,'created_legacy_pending');assert.equal(created.path,file);
const before=fs.readFileSync(file), stat=fs.statSync(file), manifest=JSON.parse(before);
assert.equal(stat.uid,0);assert.equal(stat.mode&0o777,0o644);
assert(Object.values(manifest.languages).every(entry=>Object.values(entry).every(v=>v===false)));
const preserved=ensureAppsCapabilities(config);
assert.equal(preserved.result,'preserved');assert.equal(preserved.sha256,created.sha256);
assert(fs.readFileSync(file).equals(before));assert.equal(fs.statSync(file).ino,stat.ino);
assert.equal(fs.statSync(file).mtimeMs,stat.mtimeMs);
fs.writeFileSync(file,'{broken');
assert.throws(()=>ensureAppsCapabilities(config));assert.equal(fs.readFileSync(file,'utf8'),'{broken');
fs.renameSync(file,path.join(fixture,'retained-corrupt-fixture.json'));
const unrelated=path.join(fixture,'unrelated.json');fs.writeFileSync(unrelated,'untouched',{mode:0o644});
fs.symlinkSync(unrelated,file);assert.throws(()=>ensureAppsCapabilities(config));
assert(fs.lstatSync(file).isSymbolicLink());assert.equal(fs.readFileSync(unrelated,'utf8'),'untouched');
assert(!fs.readdirSync(path.dirname(file)).some(n=>n.startsWith('.language-capabilities-')));
console.log(JSON.stringify({result:'PASS',checks:['real create','root0644','all-false','byte/inode-preserving rerun',
    'corrupt artifact retained','symlink rejected without target change','no staging leaks'],
    fixture,retained:'Only this newly created small test fixture; no live paths changed'}));
