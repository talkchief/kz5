'use strict';
// Fixed module/path inventory. SUP output is captured, never emitted on error.
const fs = require('node:fs'), cp = require('node:child_process'), crypto = require('node:crypto');
const build = process.argv[2];
const modules = [
    {name:'crossbar_doc', target:'/opt/kz5/applications/crossbar/ebin/crossbar_doc.beam', nodes:['kazoo_apps']},
    {name:'kz_couch_doc', target:'/opt/kz5/core/kazoo_couch/ebin/kz_couch_doc.beam', nodes:['kazoo_apps','ecallmgr']}
];
let phase = 'arguments';
function need(ok) { if (!ok) throw Error('verification_failed'); }
function bytes(file) {
    const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
    try { const st=fs.fstatSync(fd); need(st.isFile() && st.uid===0 && st.nlink===1 && st.size>0 && st.size<1048576);
        return fs.readFileSync(fd); } finally { fs.closeSync(fd); }
}
function sup(node,args) {
    return cp.execFileSync('/usr/local/bin/sup',['-n',node,'-t','10','-e',...args],
        {encoding:'utf8',timeout:15000,maxBuffer:65536,stdio:['ignore','pipe','pipe']}).trim();
}
function md5(value) {
    const match=/^<<([0-9,\s]+)>>$/.exec(value); need(match);
    const numbers=match[1].split(',').map(v=>Number(v.trim()));
    need(numbers.length===16 && numbers.every(n=>Number.isInteger(n)&&n>=0&&n<=255));
    return Buffer.from(numbers).toString('hex');
}
try {
    need(process.argv.length===3 && process.getuid()===0 &&
        /^\/tmp\/(kazoo-soft-delete-couch\.[A-Za-z0-9]+|kazoo-revision-deployment\.[A-Za-z0-9]+\/before)$/.test(build));
    need(fs.realpathSync(build)===build);
    const records=[];
    for (const entry of modules) {
        phase=entry.name+'_artifact';
        const artifact=bytes(build+'/'+entry.name+'.beam'); need(artifact.equals(bytes(entry.target)));
        phase=entry.name+'_installed_metadata';
        const info=sup('kazoo_apps',['beam_lib','md5',JSON.stringify(entry.target)]);
        const match=new RegExp('^\\{ok,\\{'+entry.name+',(<<[0-9,\\s]+>>)\\}\\}$').exec(info); need(match);
        const expected=md5(match[1]);
        for (const node of entry.nodes) {
            phase=entry.name+'_'+node+'_path';
            need(fs.realpathSync(JSON.parse(sup(node,['code','which',entry.name])))===entry.target);
            phase=entry.name+'_'+node+'_loaded';
            need(md5(sup(node,[entry.name,'module_info','md5']))===expected);
            const options=sup(node,[entry.name,'module_info','compile']);
            need(!/\{d,\s*'?TEST'?\s*[,}]/.test(options) && !/\bexport_all\b/.test(options));
        }
        records.push({module:entry.name,nodes:entry.nodes,md5:expected,
            artifact_sha256:crypto.createHash('sha256').update(artifact).digest('hex')});
    }
    console.log(JSON.stringify({status:'PASS',records}));
} catch (_) {console.error('FAIL revision runtime verification: '+phase); process.exitCode=1;}
