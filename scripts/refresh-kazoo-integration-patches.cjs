#!/usr/bin/env node
'use strict';
// Ignored upstream source is reproduced by explicit patch layers.
// ACDC is tracked directly in kz5 and is intentionally excluded; its patches
// remain historical test fixtures and must not overwrite the bundled source.
// README: language and atomic layers are STAGED, NOT default installer hooks.
// --write preserves their baseline versions; it never promotes staged changes
// into the installed aggregate. Language is preserved, atomic files are explicit.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),patchDir=path.join(__dirname,'patches');
const mode=process.argv[2];
assert(process.argv.length===3&&['--check','--write'].includes(mode),
    'Usage: node scripts/refresh-kazoo-integration-patches.cjs --check|--write');
const components=[
    {name:'crossbar',base:'crossbar-kazoo5-integration.patch',layers:[]},
    {name:'ecallmgr',base:'ecallmgr-kazoo5-integration.patch',layers:[
        {name:'ecallmgr-atomic-answer-runtime.patch',files:['src/ecallmgr_originate.erl']}]},
    {name:'cdr',base:'cdr-report-timestamp-fallback.patch',layers:[]}
];
function git(cwd,args,{diff=false,missing=false}={}) {
    const r=cp.spawnSync('git',args,{cwd,encoding:'utf8',maxBuffer:64*1024*1024});
    assert(!r.error&&((missing&&r.status===128)||r.status===0||(diff&&r.status===1)),
        'Git failed for '+path.basename(cwd)+': '+args[0]+' '+(r.stderr||'').slice(0,300));
    return r.status===128?null:r.stdout;
}
function safe(file) {
    assert(/^(?:src|priv|test)\/[A-Za-z0-9_./-]+\.(?:erl|hrl|json)$/.test(file)&&!file.split('/').includes('..'),
        'Unexpected component source path: '+file);return file;
}
function sections(text) {
    assert(text.startsWith('diff --git ')&&text.endsWith('\n'),'Empty or malformed source patch');
    const result=new Map();
    for(const part of text.split(/(?=^diff --git )/m).filter(Boolean)) {
        const m=part.match(/^diff --git a\/(\S+) b\/(\S+)\n/);
        assert(m&&m[1]===m[2],'Renamed or ambiguous patch path');
        const file=safe(m[1]);assert(!result.has(file),'Duplicate patch section');result.set(file,part);
    }
    return result;
}
function source(cwd,file) {
    const target=path.join(cwd,safe(file)),stat=fs.lstatSync(target);
    assert(stat.isFile()&&!stat.isSymbolicLink(),'Non-regular source');return fs.readFileSync(target);
}
function put(directory,file,bytes) {
    const target=path.join(directory,safe(file));fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,bytes);
}
function apply(directory,file,reverse=false) {
    const flag=reverse?['--reverse']:[];
    git(directory,['apply',...flag,'--check',file]);git(directory,['apply',...flag,file]);
}
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-patch-checkpoint-'));
const outputs=new Map(),inputs=new Map(),snapshots=[];
try {
    for(const component of components) {
        const cwd=path.join(root,'applications',component.name);
        assert.equal(fs.realpathSync(cwd),cwd,'Symlinked component');
        assert.equal(git(cwd,['rev-parse','--show-toplevel']).trim(),cwd,'Expected independent checkout');
        const originalBase=fs.readFileSync(path.join(patchDir,component.base),'utf8');
        inputs.set(component.base,originalBase);
        const old=sections(originalBase),staged=new Set(component.layers.flatMap(l=>l.files));
        assert.equal(staged.size,component.layers.reduce((n,l)=>n+l.files.length,0),'Overlapping staged ownership');
        let generated=git(cwd,['diff','--binary','HEAD','--','src','priv','test']);
        const untracked=git(cwd,['ls-files','--others','--exclude-standard','-z','--','src','priv','test']).split('\0').filter(Boolean).sort();
        for(const file of untracked) {source(cwd,file);generated+=git(cwd,['diff','--no-index','--binary','--','/dev/null',file],{diff:true});}
        const changed=sections(generated),baseline=new Map(changed);
        for(const file of staged) {if(old.has(file))baseline.set(file,old.get(file));else baseline.delete(file);}
        // Preserve the original generator's tracked-then-untracked section order.
        const candidate=[...baseline.values()].join('');
        sections(candidate);outputs.set(component.base,candidate);
        const replay=path.join(temporary,component.name);fs.mkdirSync(replay);
        const allPaths=new Set([...changed.keys(),...old.keys(),...staged]),heads=new Map();
        for(const file of allPaths) {
            const head=git(cwd,['show','HEAD:'+safe(file)],{missing:true});heads.set(file,head);
            if(head!==null)put(replay,file,head);
            if(fs.existsSync(path.join(cwd,file)))snapshots.push([cwd,file,source(cwd,file)]);
        }
        const applied=[];
        function layerFile(name,text) {
            const file=path.join(temporary,name);fs.writeFileSync(file,text);apply(replay,file);applied.push(file);
        }
        layerFile(component.base,candidate);
        for(const layer of component.layers) {
            let text;
            if(layer.preserve) {
                text=fs.readFileSync(path.join(patchDir,layer.name),'utf8');inputs.set(layer.name,text);
                assert.deepEqual([...sections(text).keys()].sort(),[...layer.files].sort(),'Preserved layer manifest drift');
            } else {
                text='';
                for(const file of layer.files) {
                    assert(fs.existsSync(path.join(replay,file)),'Atomic layer requires baseline file');
                    put(temporary,'src/diff-old.erl',fs.readFileSync(path.join(replay,file)));
                    put(temporary,'src/diff-new.erl',source(cwd,file));
                    text+=git(temporary,['diff','--no-index','--binary','--','src/diff-old.erl','src/diff-new.erl'],{diff:true})
                        .replaceAll('a/src/diff-old.erl','a/'+file).replaceAll('b/src/diff-new.erl','b/'+file);
                }
                assert.deepEqual([...sections(text).keys()].sort(),[...layer.files].sort(),'Atomic layer manifest drift');
                outputs.set(layer.name,text);
                if(fs.existsSync(path.join(patchDir,layer.name)))inputs.set(layer.name,fs.readFileSync(path.join(patchDir,layer.name),'utf8'));
            }
            layerFile(layer.name,text);
        }
        for(const file of allPaths) {
            const live=fs.existsSync(path.join(cwd,file))?source(cwd,file):null;
            const reproduced=fs.existsSync(path.join(replay,file))?fs.readFileSync(path.join(replay,file)):null;
            assert.deepEqual(reproduced,live,'Unpackaged '+component.name+'/'+file+'; update its explicit layer');
        }
        for(const file of [...applied].reverse())apply(replay,file,true);
        for(const [file,head]of heads)assert.equal(fs.existsSync(path.join(replay,file))?fs.readFileSync(path.join(replay,file),'utf8'):null,head,
            'Reverse replay did not restore pinned '+component.name+'/'+file);
        console.log('PASS '+component.name+': pinned forward + layered byte-match + reverse replay ('+allPaths.size+' source files)');
    }
    // Validate every layer and input snapshot before replacing any parent patch.
    // --check creates only a private replay directory, never changes parent files.
    for(const [cwd,file,bytes]of snapshots)assert.deepEqual(source(cwd,file),bytes,'Source changed during generation');
    for(const [name,text]of inputs)assert.equal(fs.readFileSync(path.join(patchDir,name),'utf8'),text,'Patch changed during generation');
    for(const [name,text]of outputs) {
        const target=path.join(patchDir,name);
        if(mode==='--check')assert.equal(fs.readFileSync(target,'utf8'),text,'Unpackaged '+name+'; run layered --write');
        else {
            // Bulk mechanical diff artifacts, not changes to nested source.
            const staged=target+'.'+process.pid+'.tmp';fs.writeFileSync(staged,text,{mode:0o644,flag:'wx'});fs.renameSync(staged,target);
        }
    }
    console.log('PASS staged language/atomic layers remain separate from default installer baseline');
} finally {
    assert(temporary.startsWith(path.join(os.tmpdir(),'kazoo-patch-checkpoint-')),'Unsafe temporary cleanup');
    fs.rmSync(temporary,{recursive:true,force:false});
}
