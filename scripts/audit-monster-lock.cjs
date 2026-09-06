#!/usr/bin/env node
'use strict';
// Exact source-to-build lock audit. Runtime/CI/build gates remain separate.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const SOURCE='da59e0891ebb949b5acdb81663463fcc09362ce7f956f9ed50beeafe7ecd6222';
const RETAINED='205df23382ff832ee16354e891d369e9062935f130dec17fde901eaafab01712';
const MIGRATED='6f8e2516404ce4b86048fa3d09dbe011c1e9363460c8cd204a01f9639735d396';
const SEMVER_PATH='node_modules/meow/node_modules/semver';
const ISGLOB_PATH='node_modules/glob-watcher/node_modules/chokidar/node_modules/glob-parent/node_modules/is-glob';
const ADDED_ISGLOB='node_modules/glob-stream/node_modules/glob-parent/node_modules/is-glob';
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function audit(sourceBytes,migratedBytes){
    assert.equal(sha(sourceBytes),SOURCE,'Unexpected original source lock');
    assert.equal(sha(migratedBytes),MIGRATED,'Unexpected migrated compatibility artifact');
    const old=JSON.parse(sourceBytes),next=JSON.parse(migratedBytes),paths={};
    assert.equal(old.lockfileVersion,1);assert.equal(next.lockfileVersion,3);
    assert.deepEqual(Object.keys(next.packages),Object.keys(next.packages).sort(),'Package parents must precede children');
    function flatten(deps,prefix=''){for(const [name,entry]of Object.entries(deps||{})){
        const file=prefix+'node_modules/'+name;paths[file]=entry;flatten(entry.dependencies,file+'/');}}
    flatten(old.dependencies);
    const added=Object.keys(next.packages).filter(k=>k&&!paths[k]).sort(),removed=Object.keys(paths).filter(k=>!next.packages[k]).sort();
    assert.deepEqual(added,['node_modules/glob-parent',ADDED_ISGLOB]);
    assert.deepEqual(removed,['node_modules/eslint/node_modules/glob-parent','node_modules/glob-watcher/node_modules/glob-parent','node_modules/glob-watcher/node_modules/glob-parent/node_modules/is-glob']);
    for(const [file,entry]of Object.entries(paths))if(next.packages[file]&&![SEMVER_PATH,ISGLOB_PATH].includes(file))
        for(const field of ['version','resolved','integrity'])assert.equal(next.packages[file][field],entry[field],'Changed common artifact '+file+' '+field);
    assert.equal(paths[SEMVER_PATH].version,'7.5.1');assert.equal(next.packages[SEMVER_PATH].version,'7.8.5');
    assert.equal(next.packages[SEMVER_PATH].resolved,'https://registry.npmjs.org/semver/-/semver-7.8.5.tgz');
    assert.equal(next.packages[SEMVER_PATH].integrity,'sha512-Y7/KDsb8LjooZpwaqGyulO6DQlksgCncchHGk+sZIY4SBvUocMBEFH5Ur1fI4dV+Jvl0w6cjvucaIi40puRioA==');
    assert.equal(paths[ISGLOB_PATH].version,'3.1.0');assert.equal(next.packages[ISGLOB_PATH].version,'4.0.3');
    assert.deepEqual(next.packages[ISGLOB_PATH],next.packages['node_modules/is-glob']);
    assert.deepEqual(next.packages[ADDED_ISGLOB],next.packages['node_modules/is-glob']);
    for(const file of ['node_modules/glob-parent','node_modules/glob-stream/node_modules/glob-parent','node_modules/glob-watcher/node_modules/chokidar/node_modules/glob-parent']){
        assert.equal(next.packages[file].version,'5.1.2');assert.deepEqual(next.packages[file].dependencies,{'is-glob':'^4.0.1'});
    }
    assert(!Object.hasOwn(next.packages[''],'hasInstallScript'));
    assert(!Object.hasOwn(next.packages,'node_modules/path-dirname'));
    for(const [file,entry]of Object.entries(next.packages))if(file){
        assert(entry.resolved.startsWith('https://registry.npmjs.org/'),'Unexpected artifact origin');
        assert(/^sha(1|512)-[A-Za-z0-9+/=]+$/.test(entry.integrity),'Missing content integrity');
    }
    return {status:'exact_artifact_delta_verified',source_lock_sha256:SOURCE,migrated_lock_sha256:MIGRATED,retained_lock_sha256:RETAINED,
        normalization:'canonical parent-before-child package order; corrected forced-package dependency metadata',
        original_package_paths:Object.keys(paths).length,migrated_package_paths:Object.keys(next.packages).length-1,
        changed_artifacts:[{file:SEMVER_PATH,from:'7.5.1',to:'7.8.5',consumer_range:'^7.3.4'},{file:ISGLOB_PATH,from:'3.1.0',to:'4.0.3',consumer_range:'^4.0.1',reuses_existing_artifact:true}],
        common_version_resolved_integrity_changes:2,
        added:added.map(file=>({file,version:next.packages[file].version,integrity:next.packages[file].integrity})),
        removed:removed.map(file=>({file,version:paths[file].version})),compatibility_verified:false,
        required_gate:'Exact native override package patch, isolated npm ci, installed required-dependency verification, native checks and full production build; no unpinned npx preinstall'};
}
if(require.main===module){try{console.log(JSON.stringify(audit(fs.readFileSync(process.argv[2]),fs.readFileSync(process.argv[3])),null,2));}catch(error){console.error('FAIL Monster lock audit: '+error.message);process.exitCode=1;}}
module.exports={audit,SOURCE,MIGRATED};
