'use strict';
// Execute the real SUP Makefile with private compiler/archive adapters. The
// native installer still must verify its full real build separately.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-sup-archive.'));
const original=cp.execFileSync('git',['show','HEAD:sup/Makefile'],{cwd:root+'/core',encoding:'utf8'});
const patch=root+'/scripts/patches/kazoo-sup-archive-order.patch';
const replay=dir+'/replay';fs.mkdirSync(replay+'/sup',{recursive:true});
fs.writeFileSync(replay+'/sup/Makefile',original);
cp.execFileSync('git',['apply','--check',patch],{cwd:replay});
cp.execFileSync('git',['apply',patch],{cwd:replay});
cp.execFileSync('git',['apply','--reverse','--check',patch],{cwd:replay});
const corrected=fs.readFileSync(replay+'/sup/Makefile','utf8');
assert.equal(corrected,fs.readFileSync(root+'/core/sup/Makefile','utf8'));
const files={props:'kazoo_stdlib',kz_binary:'kazoo_stdlib',kz_term:'kazoo_stdlib',
    kz_network_utils:'kazoo_stdlib',kazoo_config_init:'kazoo_config',kz_config:'kazoo_config'};
for(const [kind,source] of [['before',original],['after',corrected]]) {
    const target=dir+'/'+kind,app=target+'/sup';
    fs.mkdirSync(app+'/ebin',{recursive:true});fs.mkdirSync(target+'/make');
    fs.writeFileSync(app+'/Makefile',source);fs.copyFileSync(root+'/core/sup/ebin/sup.beam',app+'/ebin/sup.beam');
    for(const [name,library] of Object.entries(files)) {
        const destination=target+'/core/'+library+'/ebin';fs.mkdirSync(destination,{recursive:true});
        fs.copyFileSync(root+'/core/'+library+'/ebin/'+name+'.beam',destination+'/'+name+'.beam');
    }
    fs.writeFileSync(target+'/make/kz.mk','CORE_DIR=$(ROOT)/core\n.PHONY: compile\ncompile:\n\t@true\n');
    // ZIP contains actual BEAM bytes. A delay exposes premature cleanup in
    // parallel scheduling without mocking the Makefile's prerequisite graph.
    fs.writeFileSync(target+'/erlang.mk','escript:\n\t@sleep 0.1\n\t@zip -q sup ebin/*.beam\n\t@mv sup.zip sup\n');
    for(let run=0;run<3;run++) {
        const result=cp.spawnSync('make',['-j8','ROOT='+target,'all'],{cwd:app,encoding:'utf8',timeout:15000});
        fs.writeFileSync(target+'/make-'+run+'.log',(result.stdout||'')+(result.stderr||''));
        assert.equal(result.status,0,'Make invocation failed: '+kind);
        const names=cp.execFileSync('unzip',['-Z1',app+'/sup'],{encoding:'utf8'}).trim().split('\n');
        const present=Object.keys(files).every(name=>names.includes('ebin/'+name+'.beam'));
        assert.equal(present,kind==='after','Embedded archive dependency gate: '+kind);
        if(kind==='before')break;
        for(const name of Object.keys(files))assert(!fs.existsSync(app+'/ebin/'+name+'.beam'),'Staging cleanup must finish after archiving');
    }
}
console.log('PASS original missing-library reproduction; corrected parallel/repeated Makefile archive scheduling and actual BEAM contents: '+dir);
