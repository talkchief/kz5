#!/usr/bin/env node
'use strict';
// Small filesystem fixtures only: no server, package manager, network or build.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const owned=require('./deploy-owned-monster.cjs'),build=require('./monster-build-inputs.cjs');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'monster-public-modes.'));
let groups=0;
const mode=file=>fs.statSync(file).mode&0o777;
const test=(name,fn)=>{fn();groups++;console.log('PASS '+name);};
function masked(mask,fn) {const previous=process.umask(mask);try{return fn();}finally{process.umask(previous);}}
function put(dir,file,bytes) {const target=path.join(dir,file);fs.mkdirSync(path.dirname(target),{recursive:true,mode:0o700});fs.writeFileSync(target,bytes,{mode:0o600});}
function stage(dir,apps=['acdc']) {
    fs.mkdirSync(dir,{mode:0o700});
    for(const [file,bytes] of Object.entries({'index.html':'fixture','js/main.js':'fixture main',
        'js/config.js':'define({api:{default:"http://fixture.invalid/v2/"},custom:{preserved:true}});',
        'css/style.css':'fixture css','build-config.json':JSON.stringify({preloadedApps:['core',...apps]})}))put(dir,file,bytes);
    for(const app of apps)put(dir,`apps/${app}/metadata/app.json`,JSON.stringify({name:app}));
}
function deploy(web,source,state,selected,backup) {
    const p=owned.plan({web,stage:source,state,selected,inputs:{fingerprint_sha256:owned.hash('mode-fixture')}});
    return owned.apply(p,owned.hash(owned.canonical(p)),backup);
}
function privateTree(dir) {
    assert.equal(mode(dir),0o700,dir);
    for(const name of fs.readdirSync(dir)) {const file=path.join(dir,name),s=fs.statSync(file);if(s.isDirectory())privateTree(file);else assert.equal(mode(file),0o600,file);}
}
try {
    test('fresh nested web is public under umask 077; state, build, stage and backup stay private',()=>masked(0o077,()=>{
        const base=path.join(root,'fresh');fs.mkdirSync(base,{mode:0o700});
        const web=path.join(base,'public/html/monster'),state=path.join(base,'registry/owned'),cache=path.join(base,'build/cache');
        build.prepareRoots(web,state,cache);
        for(const dir of ['public','public/html','public/html/monster'])assert.equal(mode(path.join(base,dir)),0o755);
        for(const dir of ['registry','registry/owned','build','build/cache'])assert.equal(mode(path.join(base,dir)),0o700);
        const source=path.join(base,'source');stage(source);const temporary=build.newStage(cache);assert.equal(mode(temporary),0o700);
        const backup=path.join(base,'backup');assert.equal(deploy(web,source,state,['acdc'],backup).status,'complete');
        for(const dir of ['js','css','apps','apps/acdc','apps/acdc/metadata'])assert.equal(mode(path.join(web,dir)),0o755,dir);
        for(const file of Object.keys(owned.snapshot(web)))assert.equal(mode(path.join(web,file)),0o644,file);
        privateTree(backup);assert.equal(mode(path.join(state,'owned.json')),0o600);
        assert.equal(owned.verify(path.join(state,'owned.json')).status,'complete');
    }));
    test('repeat install adds public app/nested paths without chmod of existing operator paths',()=>masked(0o077,()=>{
        const base=path.join(root,'repeat');fs.mkdirSync(base,{mode:0o700});
        const web=path.join(base,'web'),state=path.join(base,'state'),cache=path.join(base,'cache');build.prepareRoots(web,state,cache);
        const first=path.join(base,'first');stage(first);deploy(web,first,state,['acdc'],path.join(base,'backup-first'));
        const existing={'':0o750,'apps':0o710,'js':0o700,'apps/acdc':0o750,'apps/acdc/metadata':0o710};
        for(const [dir,bits]of Object.entries(existing))fs.chmodSync(path.join(web,dir),bits);
        put(web,'apps/operator-owned/private/note.txt','preserve customer asset');
        put(web,'apps/acdc/language-capabilities.json','preserve independently managed capability');
        put(web,'apis/index.html','preserve separately managed documentation');
        fs.chmodSync(path.join(web,'apps/operator-owned'),0o750);fs.chmodSync(state,0o710);fs.chmodSync(cache,0o750);
        const before=owned.snapshot(web),second=path.join(base,'second');stage(second,['acdc','accounts']);
        put(second,'apps/accounts/views/deep/main.html','new app view');put(second,'apps/acdc/views/deep/main.html','new existing-app view');
        build.prepareRoots(web,state,cache);assert.equal(mode(state),0o710);assert.equal(mode(cache),0o750);
        const backup=path.join(base,'backup-second');deploy(web,second,state,['acdc','accounts'],backup);
        for(const [dir,bits]of Object.entries(existing))assert.equal(mode(path.join(web,dir)),bits,dir);
        for(const dir of ['apps/accounts','apps/accounts/metadata','apps/accounts/views','apps/accounts/views/deep','apps/acdc/views','apps/acdc/views/deep'])
            assert.equal(mode(path.join(web,dir)),0o755,dir);
        for(const file of ['apps/operator-owned/private/note.txt','apps/acdc/language-capabilities.json','apis/index.html','js/config.js'])
            assert.equal(owned.snapshot(web)[file],before[file],file);
        assert.equal(mode(path.join(web,'apps/operator-owned')),0o750);
        assert.equal(mode(path.join(web,'apps/operator-owned/private')),0o700);
        assert.equal(mode(path.join(web,'apps/operator-owned/private/note.txt')),0o600);
        assert.equal(mode(path.join(web,'apps/acdc/language-capabilities.json')),0o600);
        privateTree(backup);assert.equal(owned.verify(path.join(state,'owned.json')).status,'complete');
    }));
    test('new protected roots are 0700 even with ordinary umask 022',()=>masked(0o022,()=>{
        const base=path.join(root,'normal');fs.mkdirSync(base,{mode:0o700});
        build.prepareRoots(path.join(base,'web'),path.join(base,'state'),path.join(base,'build'));
        assert.equal(mode(path.join(base,'web')),0o755);assert.equal(mode(path.join(base,'state')),0o700);assert.equal(mode(path.join(base,'build')),0o700);
    }));
    test('existing restrictive public ancestors are deliberately preserved',()=>masked(0o077,()=>{
        const base=path.join(root,'operator-private');fs.mkdirSync(base,{mode:0o700});
        owned.publicDirectory(path.join(base,'new/nested'));assert.equal(mode(base),0o700);
        assert.equal(mode(path.join(base,'new')),0o755);assert.equal(mode(path.join(base,'new/nested')),0o755);
        owned.publicDirectory(base);assert.equal(mode(base),0o700);
    }));
    test('unsafe writable ancestor is refused without chmod or child creation',()=>{
        const base=path.join(root,'writable');fs.mkdirSync(base,{mode:0o700});fs.chmodSync(base,0o777);
        assert.throws(()=>build.prepareRoots(path.join(base,'child')),/Writable/);
        assert.equal(mode(base),0o777);assert(!fs.existsSync(path.join(base,'child')));fs.chmodSync(base,0o700);
    });
    test('symlink ancestor is refused without following or changing its target',()=>{
        const base=path.join(root,'target');fs.mkdirSync(base,{mode:0o700});const link=path.join(root,'alias');fs.symlinkSync(base,link);
        assert.throws(()=>owned.publicDirectory(path.join(link,'child')),/Symlink/);assert.equal(mode(base),0o700);assert(!fs.existsSync(path.join(base,'child')));
    });
    test('mkdir EEXIST race never chmods the directory created by another owner operation',()=>masked(0o077,()=>{
        const dir=path.join(root,'race'),mkdir=fs.mkdirSync;
        fs.mkdirSync=function(file,options) {if(file===dir){mkdir.call(fs,file,{mode:0o700});fs.chmodSync(file,0o710);const e=Error('injected EEXIST');e.code='EEXIST';throw e;}return mkdir.call(fs,file,options);};
        try {assert.throws(()=>owned.publicDirectory(dir),/EEXIST/);}finally {fs.mkdirSync=mkdir;}
        assert.equal(mode(dir),0o710);
    }));
    console.log(JSON.stringify({status:'PASS',groups,scope:'temporary filesystem fixtures only; no live deployment'}));
} finally {fs.rmSync(root,{recursive:true,force:true});}
