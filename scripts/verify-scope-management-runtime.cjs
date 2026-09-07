'use strict';
// Verify exact deployed production bytes before invoking installer registration.
const fs=require('node:fs'), cp=require('node:child_process'), crypto=require('node:crypto');
let phase='arguments';
const build=process.argv[2], names=['cb_scope_restrictions','crossbar_config'];
const need=ok=>{if(!ok)throw Error('failed');};
const sup=args=>cp.execFileSync('/usr/local/bin/sup',['-n','kazoo_apps','-t','10','-e',...args],
    {encoding:'utf8',timeout:15000,maxBuffer:65536,stdio:['ignore','pipe','pipe']}).trim();
function bytes(p){const fd=fs.openSync(p,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
    try{const s=fs.fstatSync(fd);need(s.isFile()&&s.uid===0&&s.nlink===1&&s.size>0&&s.size<1048576);return fs.readFileSync(fd);}finally{fs.closeSync(fd);}}
function md5(s){const m=/^<<([0-9,\s]+)>>$/.exec(s);need(m);const a=m[1].split(',').map(x=>Number(x.trim()));
    need(a.length===16&&a.every(n=>Number.isInteger(n)&&n>=0&&n<=255));return Buffer.from(a).toString('hex');}
try{
    need(process.argv.length===3&&process.getuid()===0&&/^\/tmp\/kazoo-scope-management\.[A-Za-z0-9]+$/.test(build)&&fs.realpathSync(build)===build);
    const records=[];
    for(const name of names){
        phase=name+'_bytes';const target='/opt/kz5/applications/crossbar/ebin/'+name+'.beam';
        const candidate=bytes(build+'/'+name+'.beam');need(candidate.equals(bytes(target)));
        phase=name+'_loaded';need(fs.realpathSync(JSON.parse(sup(['code','which',name])))===target);
        const info=sup(['beam_lib','md5',JSON.stringify(target)]);
        const match=new RegExp('^\\{ok,\\{'+name+',(<<[0-9,\\s]+>>)\\}\\}$').exec(info);need(match);
        const expected=md5(match[1]);need(md5(sup([name,'module_info','md5']))===expected);
        const options=sup([name,'module_info','compile']);need(!/\{d,\s*'?TEST'?\s*[,}]/.test(options)&&!/\bexport_all\b/.test(options));
        records.push({module:name,md5:expected,sha256:crypto.createHash('sha256').update(candidate).digest('hex')});
    }
    phase='capability';need(sup(['cb_scope_restrictions','management_guard_version'])==='1');
    phase='installer_registration';
    const account=cp.execFileSync('/usr/bin/getent',['passwd','0'],{encoding:'utf8',timeout:5000,maxBuffer:4096}).trim().split(':');
    need(account.length===7&&account[2]==='0'&&account[5].startsWith('/'));
    const source=fs.readFileSync('/opt/kz5/scripts/install-kazoo5.sh','utf8');
    function extract(name){const start=source.indexOf('\n'+name+'() {');need(start>=0);
        const marker=name==='kazoo_blackhole_module_output'?'\nNODE\n}':'\n}';
        const end=source.indexOf(marker,start);need(end>start);return source.slice(start+1,end+marker.length)+'\n';}
    const helpers=['kazoo_blackhole_module_output','configure_kazoo_scope_management','verify_kazoo_scope_management'].map(extract).join('\n');
    const r=cp.spawnSync('/bin/bash',['--noprofile','--norc','-s'],{input:'set -Eeuo pipefail\nDRY_RUN=false\nlog(){ :; }\ndie(){ exit 77; }\nmonster_registration_available(){ systemctl is-active --quiet kazoo-apps || exit 77; }\n'+helpers+'\nconfigure_kazoo_scope_management\nverify_kazoo_scope_management\n',
        env:{PATH:'/usr/local/bin:/usr/bin:/bin',LANG:'C',HOME:account[5]},encoding:'utf8',timeout:90000,maxBuffer:65536});
    need(!r.error&&r.status===0);need(fs.readFileSync('/opt/kz5/scripts/install-kazoo5.sh','utf8')===source);
    phase='post_registration_runtime';
    need(sup(['cb_scope_restrictions','management_guard_version'])==='1');
    for(const row of records){
        const target='/opt/kz5/applications/crossbar/ebin/'+row.module+'.beam';
        need(bytes(build+'/'+row.module+'.beam').equals(bytes(target)));
        need(crypto.createHash('sha256').update(bytes(target)).digest('hex')===row.sha256);
        need(md5(sup([row.module,'module_info','md5']))===row.md5);
    }
    console.log(JSON.stringify({result:'PASS',records,guard_version:1,registration:'running and effective'}));
}catch(_){console.error('FAIL scope runtime verification: '+phase);process.exitCode=1;}
