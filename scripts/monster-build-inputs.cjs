#!/usr/bin/env node
'use strict';
// Small installer build boundary. No network, catalog, service or shell calls.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {safePath,protectedDirectory,publicDirectory,hash}=require('./deploy-owned-monster.cjs');
const {configure}=require('./configure-monster-runtime.cjs');
const HOOKS=['monster_app_ref','monster_local_app_fingerprint','monster_ui_build_fingerprint',
    'sync_monster_ui_sources','configure_monster_ui_api','deploy_monster_ui_owned','verify_monster_ui_owned',
    'register_monster_apps','install_monster_ui','verify_monster_ui'];
function hooks(source) {
    return HOOKS.map(name=>{
        const matches=[...source.matchAll(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}', 'gm'))];
        assert.equal(matches.length,1,'Expected one installer build hook: '+name);
        return matches[0][0];
    }).join('\n');
}
function prepareRoots(web,...dirs) {
    publicDirectory(web);
    for(const dir of dirs) {
        safePath(dir,true);
        if(!fs.existsSync(dir)) fs.mkdirSync(dir,{recursive:true,mode:0o700});
        protectedDirectory(dir);
    }
}
function newStage(build) {
    protectedDirectory(build);
    return fs.mkdtempSync(path.join(build,'monster-owned-build.'));
}
function absentSource(source) {
    safePath(source,true); protectedDirectory(path.dirname(source));
    assert(!fs.existsSync(source),'Source target already exists; use a new installer stage, never reset operator work');
}
function publicBytes(file) {
    safePath(file);const before=fs.lstatSync(file);
    assert(before.isFile()&&before.nlink===1&&before.size<1024*1024,'Invalid public configuration');
    const bytes=fs.readFileSync(file),after=fs.lstatSync(file);
    for(const key of ['dev','ino','mode','uid','gid','nlink','size','mtimeMs','ctimeMs']) assert.equal(after[key],before[key],'Configuration changed while reading');
    assert.equal(bytes.length,before.size);return bytes;
}
function prepareLock(source,artifact) {
    protectedDirectory(source);
    const target=path.join(source,'package-lock.json'),packageFile=path.join(source,'package.json');
    const bytes=publicBytes(artifact),original=publicBytes(target);
    assert.equal(hash(publicBytes(packageFile)),'1838ddad9703350234221b5db8451b3c5d41c5c1e5cc3c7606f223fd56da873b',
        'Expected exact reviewed native-override package compatibility patch');
    const report=require('./audit-monster-lock.cjs').audit(original,bytes);
    const receipt=path.join(source,'.kazoo-npm-lock-audit.json');safePath(receipt,true);
    assert(!fs.existsSync(receipt),'Lock preparation receipt exists; use a new source stage');
    fs.writeFileSync(target,bytes,{mode:0o644});fs.chmodSync(target,0o644);
    assert.equal(hash(publicBytes(target)),report.migrated_lock_sha256);
    fs.writeFileSync(receipt,JSON.stringify(report,null,2)+'\n',{mode:0o600,flag:'wx'});
    return {status:'reviewed_lock_staged; npm_ci_not_yet_verified',sha256:report.migrated_lock_sha256};
}
function preserveConfig(web,source,options,allowChange=false) {
    protectedDirectory(source);
    const oldFile=path.join(web,'js/config.js'),newFile=path.join(source,'src/js/config.js');
    safePath(oldFile,true);safePath(newFile);
    const receipt=path.join(source,'.kazoo-configuration-plan.json');safePath(receipt,true);
    assert(!fs.existsSync(receipt),'Configuration preparation receipt already exists; use a new source stage');
    if(!fs.existsSync(oldFile)) {
        fs.writeFileSync(receipt,'null\n',{mode:0o600,flag:'wx'});
        return {status:'fresh_configuration'};
    }
    const bytes=publicBytes(oldFile);
    publicBytes(newFile);
    const transformed=configure(bytes.toString('utf8'),options);
    if(!allowChange) assert.equal(transformed,bytes.toString('utf8'),
        'Existing configuration differs from requested form; review a separate config migration, no implicit overwrite');
    fs.writeFileSync(newFile,transformed,{mode:0o644});fs.chmodSync(newFile,0o644);
    assert.equal(hash(publicBytes(oldFile)),hash(bytes),'Live config changed during build preparation');
    const change=allowChange?{before_sha256:hash(bytes),after_sha256:hash(transformed),options}:null;
    fs.writeFileSync(receipt,JSON.stringify(change,null,2)+'\n',{mode:0o600,flag:'wx'});
    return {status:hash(bytes)===hash(transformed)?'preserved_configuration':'staged_configuration_change',sha256:hash(transformed)};
}
if(require.main===module) {
    try {
        const [mode,...args]=process.argv.slice(2);
        if(mode==='--prepare-roots') prepareRoots(...args);
        else if(mode==='--new-stage') console.log(newStage(args[0]));
        else if(mode==='--absent-source') absentSource(args[0]);
        else if(mode==='--prepare-lock') console.log(JSON.stringify(prepareLock(args[0],args[1])));
        else if(mode==='--hook-hash') console.log(hash(hooks(fs.readFileSync(args[0],'utf8'))));
        else if(mode==='--preserve-config'||mode==='--configure') {
            const [web,source,api,socket,branding,braintree]=args;
            console.log(JSON.stringify(preserveConfig(web,source,{api,socket,branding,braintree},mode==='--configure')));
        } else throw Error('Unsupported build boundary mode');
    } catch(error) {console.error('FAIL Monster build boundary: '+error.message);process.exitCode=1;}
}
module.exports={hooks,prepareRoots,newStage,absentSource,preserveConfig,prepareLock};
