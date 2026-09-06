'use strict';
// Private review candidate. Static files only; never calls Kazoo or a package manager.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const APPS = ['acdc','accounts','callflows','csv-onboarding','fax','numbers','pbxs','voicemails','webhooks','voip'];
const CORE = ['apploader','appstore','auth','common','core','demo_done','myaccount','skeleton','tutorial'];
const CAP = 'apps/acdc/language-capabilities.json', CONFIG = 'js/config.js';
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const canonical = value => JSON.stringify(value, (key, item) => item && typeof item === 'object' && !Array.isArray(item)
    ? Object.fromEntries(Object.keys(item).sort().map(k => [k,item[k]])) : item);
const equal = (a,b) => canonical(a) === canonical(b);
function safePath(file, absent = false) {
    assert(path.isAbsolute(file) && path.normalize(file) === file && file !== '/' && !/[\x00-\x1f]/.test(file), 'Unsafe absolute path');
    let current = '/';
    for (const part of file.slice(1).split('/')) {
        current = path.join(current,part);
        let stat;
        try { stat = fs.lstatSync(current); } catch (e) { if (absent && e.code === 'ENOENT') return; throw e; }
        assert(!stat.isSymbolicLink(), 'Symlink path/ancestor refused');
        // A root-owned sticky temporary parent protects a root-owned child from
        // other users. No other writable ancestor or wrong owner is accepted.
        const stickyParent=stat.isDirectory() && (stat.mode & 0o1000) && stat.uid===0 && current!==file;
        assert(stat.uid===process.getuid() && (!(stat.mode & 0o022)||stickyParent), 'Writable or foreign-owned path/ancestor');
    }
}
function protectedDirectory(dir) {
    safePath(dir); const stat = fs.statSync(dir);
    assert(stat.isDirectory() && stat.uid === process.getuid() && !(stat.mode & 0o022), 'Unprotected directory');
}
function publicDirectory(dir) {
    safePath(dir,true);
    const missing=[]; let parent=dir;
    while(!fs.existsSync(parent)) {missing.push(parent);parent=path.dirname(parent);}
    protectedDirectory(parent);
    for(const created of missing.reverse()) {
        // mkdir is exclusive: never chmod an existing operator directory or an
        // EEXIST race. New public paths must remain traversable under umask 077.
        fs.mkdirSync(created,{mode:0o755});
        fs.chmodSync(created,0o755);
        protectedDirectory(created);
    }
    protectedDirectory(dir);
}
function readPrivate(file) {
    safePath(file); const stat = fs.statSync(file);
    assert(stat.isFile() && stat.uid === process.getuid() && !(stat.mode & 0o077) && stat.nlink === 1 && stat.size < 8*1024*1024, 'Unprotected receipt');
    return JSON.parse(fs.readFileSync(file,'utf8'));
}
function snapshot(root) {
    protectedDirectory(root); const files = {}; let count=0, total=0;
    function walk(dir, relative='') {
        for (const name of fs.readdirSync(dir).sort()) {
            assert(!/[\x00-\x1f]/.test(name), 'Control character in filename');
            const file=path.join(dir,name), rel=relative?relative+'/'+name:name, stat=fs.lstatSync(file);
            assert(!stat.isSymbolicLink(), 'Symlink in static tree refused');
            assert(stat.uid===process.getuid() && !(stat.mode & 0o022), 'Writable or foreign-owned static child');
            if (stat.isDirectory()) walk(file,rel);
            else {
                assert(stat.isFile() && stat.nlink === 1 && stat.size <= 20*1024*1024, 'Unsafe static file');
                total += stat.size; assert(++count <= 20000 && total <= 512*1024*1024, 'Static tree exceeds bound');
                files[rel]=hash(fs.readFileSync(file));
            }
        }
    }
    walk(root); return files;
}
function scoped(file, selected) {
    if (file === CAP || file === CONFIG || file.startsWith('apis/')) return false;
    if (file.startsWith('apps/')) return CORE.concat(selected).includes(file.split('/')[1]);
    return ['VERSION','build.txt','build-config.json','index.html'].includes(file) || /^(js|css)\//.test(file);
}
function subset(files, predicate) { return Object.fromEntries(Object.entries(files).filter(([p])=>predicate(p))); }
function preloadedApps(config, legacy=false) {
    assert(config && typeof config==='object' && !Array.isArray(config), 'Invalid preload configuration');
    const canonicalPresent=Object.hasOwn(config,'preloadedApps'), legacyPresent=Object.hasOwn(config,'preloadApps');
    const valid=list=>Array.isArray(list) && list.every(a=>typeof a==='string' && /^[a-z][a-z0-9_-]*$/.test(a)) && new Set(list).size===list.length;
    if(canonicalPresent) assert(valid(config.preloadedApps),'Invalid canonical preload list');
    if(legacyPresent) assert(valid(config.preloadApps),'Invalid legacy preload list');
    if(canonicalPresent && legacyPresent) assert(equal(config.preloadedApps,config.preloadApps),'Conflicting preload configuration keys');
    if(!legacy) assert(canonicalPresent && !legacyPresent,'New build requires canonical preloadedApps, not legacy preloadApps');
    return canonicalPresent ? config.preloadedApps : legacyPresent ? config.preloadApps : [];
}
function plan(options) {
    const {web,stage,state,selected,inputs,adopt_existing=false,configuration_change=null}=options;
    [web,stage,state].forEach(p=>safePath(p)); protectedDirectory(state);
    assert(new Set(selected).size === selected.length && selected.length && selected.every(a=>APPS.includes(a)), 'Invalid selected app set');
    assert([web,stage,state].every((p,i,a)=>a.every((q,j)=>i===j || (!p.startsWith(q+'/') && p!==q))), 'Overlapping roots');
    assert(inputs && typeof inputs === 'object' && /^[a-f0-9]{64}$/.test(inputs.fingerprint_sha256), 'Missing build-input fingerprint');
    const before=snapshot(web), built=snapshot(stage), ownerFile=path.join(state,'owned.json');
    const owner=fs.existsSync(ownerFile)?readPrivate(ownerFile):null;
    if (owner) assert(owner.version===1 && owner.web===web && owner.status==='complete' && typeof owner.files==='object', 'Invalid prior ownership');
    assert(owner || !Object.keys(before).length || adopt_existing===true, 'Existing deployment requires explicit adoption review');
    assert(!Object.hasOwn(built,CAP), 'Build cannot publish runtime capability');
    assert(['index.html',CONFIG,'build-config.json','js/main.js','css/style.css'].every(p=>built[p]), 'Incomplete build');
    const newPreload=preloadedApps(JSON.parse(fs.readFileSync(path.join(stage,'build-config.json'),'utf8')));
    if(before['build-config.json']) {
        const oldConfig=JSON.parse(fs.readFileSync(path.join(web,'build-config.json'),'utf8'));
        const oldPreload=preloadedApps(oldConfig,true);
        assert(oldPreload.every(a=>newPreload.includes(a)),
            'Build would remove an embedded/preloaded app; standalone conversion requires separate review');
    }
    if (configuration_change) {
        const {before_sha256,after_sha256,options:configOptions}=configuration_change;
        assert(before[CONFIG]&&before_sha256===before[CONFIG]&&after_sha256===built[CONFIG], 'Configuration plan hashes do not match exact input/output');
        assert(configOptions&&equal(Object.keys(configOptions).sort(),['api','socket','branding','braintree'].sort()), 'Invalid requested configuration fields');
        const current=fs.readFileSync(path.join(web,CONFIG),'utf8');
        const transformed=require('./configure-monster-runtime.cjs').configure(current,configOptions);
        assert(hash(transformed)===after_sha256,'Staged configuration is not the exact requested transform of current operator configuration');
    } else if (before[CONFIG]) assert(built[CONFIG]===before[CONFIG], 'Existing operator configuration must remain byte-identical; prepare build from it');
    for (const app of selected) assert(built[`apps/${app}/metadata/app.json`], 'Selected app missing from build');
    assert(Object.keys(built).every(p=>p===CONFIG || scoped(p,selected)), 'Build contains an unselected/unowned component');
    const previous=owner?owner.files:subset(before,p=>scoped(p,selected));
    for (const [p,h] of Object.entries(previous)) {
        assert(typeof h==='string' && /^[a-f0-9]{64}$/.test(h) && !p.split('/').includes('..') && !path.isAbsolute(p), 'Invalid owned path/hash');
        if (scoped(p,selected)) assert(before[p]===h, 'Managed artifact changed: review required');
    }
    const next=subset(built,p=>scoped(p,selected));
    if (!before[CONFIG] || configuration_change) next[CONFIG]=built[CONFIG];
    for (const p of Object.keys(next)) assert(!before[p] || previous[p] || adopt_existing || (p===CONFIG&&configuration_change), 'Unowned target collision');
    const changes=Object.keys(next).filter(p=>next[p]!==before[p]).sort();
    const removes=Object.keys(previous).filter(p=>scoped(p,selected) && !next[p]).sort();
    const preserve=subset(before,p=>!changes.includes(p)&&!removes.includes(p));
    return {version:1,web,stage,state,selected,inputs,adopt_existing,configuration_change,owner_sha256:owner?hash(fs.readFileSync(ownerFile)):null,
        before,built,changes,removes,preserve,files:{...subset(previous,p=>p!==CONFIG&&!scoped(p,selected)),...subset(next,p=>p!==CONFIG)},status:'plan_only',atomic:false};
}
function privateWrite(file,value,exclusive=false) {
    safePath(path.dirname(file)); safePath(file,true);
    if(fs.existsSync(file)) {const stat=fs.lstatSync(file);assert(stat.isFile()&&stat.nlink===1,'Unsafe receipt replacement');}
    fs.writeFileSync(file,JSON.stringify(value,null,2)+'\n',{mode:0o600,flag:exclusive?'wx':'w'}); fs.chmodSync(file,0o600);
    const fd=fs.openSync(file,'r'); try {fs.fsyncSync(fd);} finally {fs.closeSync(fd);}
}
function apply(p,approval,backup,hook=()=>{}) {
    assert(p.status==='plan_only' && p.version===1 && approval===hash(canonical(p)), 'Exact reviewed plan hash required');
    protectedDirectory(p.state); safePath(backup,true); assert(!fs.existsSync(backup), 'Backup must not exist');
    assert(!backup.startsWith(p.web+'/')&&!backup.startsWith(p.stage+'/')&&!p.web.startsWith(backup+'/'), 'Backup overlaps deployment');
    const lock=path.join(p.state,'deploy.lock'); fs.mkdirSync(lock,{mode:0o700});
    let receipt;
    try {
        const fresh=plan({web:p.web,stage:p.stage,state:p.state,selected:p.selected,inputs:p.inputs,adopt_existing:p.adopt_existing,configuration_change:p.configuration_change});
        assert(equal(fresh,p),'Plan inputs changed; obtain a new review');
        fs.mkdirSync(backup,{mode:0o700}); fs.mkdirSync(path.join(backup,'files'),{mode:0o700});
        receipt={version:1,status:'in_progress',atomic:false,plan_sha256:approval,completed:[],backup,previous_owner:p.owner_sha256};
        privateWrite(path.join(backup,'plan.json'),p,true); privateWrite(path.join(backup,'receipt.json'),receipt,true);
        if(p.owner_sha256) fs.copyFileSync(path.join(p.state,'owned.json'),path.join(backup,'owned.json'));
        // Capture exact backups before any visible file effect. No catalog activity.
        for(const file of [...p.changes,...p.removes]) if(p.before[file]) {
            const target=path.join(backup,'files',file); fs.mkdirSync(path.dirname(target),{recursive:true,mode:0o700});
            fs.copyFileSync(path.join(p.web,file),target); fs.chmodSync(target,0o600);
        }
        hook('before_write'); assert(equal(snapshot(p.web),p.before),'Concurrent web edit before activation');
        for(const file of [...p.changes,...p.removes]) {
            const target=path.join(p.web,file); safePath(target,true);
            assert(fs.existsSync(target)?hash(fs.readFileSync(target))===p.before[file]:!p.before[file], 'Concurrent target edit');
            if(p.removes.includes(file)) fs.unlinkSync(target);
            else {
                safePath(path.join(p.stage,file));
                const bytes=fs.readFileSync(path.join(p.stage,file)); assert(hash(bytes)===p.built[file],'Build changed during activation');
                publicDirectory(path.dirname(target));
                const temp=target+'.kazoo-deploy-'+crypto.randomBytes(8).toString('hex');
                fs.writeFileSync(temp,bytes,{flag:'wx',mode:0o644}); fs.chmodSync(temp,0o644); fs.renameSync(temp,target);
            }
            receipt.completed.push(file); privateWrite(path.join(backup,'receipt.json'),receipt); hook('after_file',file);
        }
        const after=snapshot(p.web), expected={...p.before}; p.removes.forEach(p=>delete expected[p]); p.changes.forEach(f=>expected[f]=p.built[f]);
        assert(equal(after,expected),'Content proof failed; do not advance ownership/fingerprint');
        for(const [file,h] of Object.entries(p.preserve)) assert(after[file]===h,'Unrelated artifact/capability changed');
        const owner={version:1,status:'complete',web:p.web,inputs:p.inputs,files:p.files,plan_sha256:approval,
            configuration_sha256:after[CONFIG],configuration_change:p.configuration_change,runtime_capability_sha256:after[CAP]||null,backup};
        privateWrite(path.join(p.state,'owned.next.json'),owner,true);
        fs.renameSync(path.join(p.state,'owned.next.json'),path.join(p.state,'owned.json'));
        hook('after_ownership');
        receipt.status='complete'; receipt.content_proof_sha256=hash(canonical(after)); privateWrite(path.join(backup,'receipt.json'),receipt);
        return {status:'complete',changed:p.changes.length,removed:p.removes.length,preserved:Object.keys(p.preserve).length,plan_sha256:approval};
    } catch(error) {
        if(receipt) {receipt.status='partial_or_failed'; privateWrite(path.join(backup,'receipt.json'),receipt);}
        throw error;
    } finally {fs.rmdirSync(lock);}
}
function verify(ownerFile) {
    const owner=readPrivate(ownerFile); assert(owner.version===1&&owner.status==='complete','Invalid ownership receipt');
    const current=snapshot(owner.web);
    assert(owner.files&&['index.html','js/main.js','css/style.css','build-config.json'].every(p=>/^[a-f0-9]{64}$/.test(owner.files[p])),'Incomplete owned framework');
    for(const [p,h]of Object.entries(owner.files)) assert(current[p]===h,'Owned artifact differs from verified deployment');
    assert(current[CONFIG]===owner.configuration_sha256,'Configuration differs from reviewed build');
    return {status:'complete',web:owner.web,managed_files:Object.keys(owner.files).length,fingerprint_sha256:owner.inputs.fingerprint_sha256};
}
if(require.main===module){
    try{
        const [mode,input,approval,backup]=process.argv.slice(2);
        if(mode==='--plan') {const p=plan(readPrivate(input));process.stdout.write(JSON.stringify({plan:p,approval_sha256:hash(canonical(p))},null,2)+'\n');}
        else if(mode==='--apply') console.log(JSON.stringify(apply(readPrivate(input),approval,backup)));
        else if(mode==='--verify') console.log(JSON.stringify(verify(input)));
        else throw Error('Unsupported mode');
    }catch(error){console.error('FAIL owned Monster deployment: '+error.message);process.exitCode=1;}
}
module.exports={plan,apply,verify,snapshot,hash,canonical,scoped,safePath,protectedDirectory,publicDirectory,preloadedApps};
