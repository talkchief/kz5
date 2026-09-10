#!/usr/bin/env node
'use strict';
// Explicit private apps14-only acceptance. The host must hold the owned-lab
// acceptance lock. Installs the actual installer hook without restarting apps.
const fs=require('node:fs'),cp=require('node:child_process'),os=require('node:os'),path=require('node:path');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const STATE='/var/lib/kazoo5-maintenance/fence',HELPER='/usr/local/libexec/kazoo5-maintenance-fence';
const UNIT='kazoo-maintenance-fence-native-acceptance.service';
const UNITFILE='/etc/systemd/system/'+UNIT;
let root,logfd,generation,proof,phase='admission',started=false,closed=false,corrupt=false;
function run(bin,args){return cp.execFileSync(bin,args,{encoding:'utf8',timeout:30000,stdio:['ignore','pipe','pipe']}).trim();}
function ctl(...args){return run('/usr/bin/systemctl',args);}
function cli(...args){return JSON.parse(run('/usr/bin/node',[HELPER,...args]));}
function live(){
    assert.equal(ctl('is-active',UNIT),'active');
    const pid=Number(ctl('show',UNIT,'-p','MainPID','--value'));assert(pid>1);
    const uid=fs.readFileSync('/proc/'+pid+'/status','utf8').match(/^Uid:\s+(\d+)/m);
    assert(uid&&Number(uid[1])!==0,'Fixture must run unprivileged after privileged guard');
}
function rejectsStart(){
    const r=cp.spawnSync('/usr/bin/systemctl',['start',UNIT],{timeout:30000,stdio:['ignore',logfd,logfd]});
    assert.notEqual(r.status,0);assert.equal(ctl('show',UNIT,'-p','MainPID','--value'),'0');
}
function restoreCorruption(){
    if(corrupt){fs.renameSync(STATE+'/active.json',root+'/retained-corrupt-active.json');
        fs.renameSync(root+'/saved-active.json',STATE+'/active.json');corrupt=false;}
}
function main(){try{
    assert.equal(process.getuid(),0);assert.deepEqual(process.argv.slice(2),['--live']);
    assert.equal(os.hostname(),'kz5-stage-kazoo-apps');
    assert(Object.values(os.networkInterfaces()).flat().some(a=>a.address==='172.30.253.14'));
    assert.equal(fs.readFileSync('/proc/1/comm','utf8').trim(),'systemd');
    assert(!fs.existsSync(UNITFILE),'Existing fixture unit is not ours');
    assert(!fs.existsSync(STATE+'/active.json')&&!fs.existsSync(STATE+'/releasing.json'),'Existing maintenance owns admission');
    root=fs.mkdtempSync('/var/lib/kazoo-stage/fence-systemd-');fs.chmodSync(root,0o700);
    logfd=fs.openSync(root+'/native.log','wx',0o600);
    phase='install_hook';
    const install=cp.spawnSync('/usr/bin/bash',['-c',
        'source "$1"; install_service_maintenance_fence kazoo-apps.service; systemctl daemon-reload; verify_service_maintenance_fence kazoo-apps.service',
        'fence-install',path.join(__dirname,'install-kazoo5.sh')],{timeout:240000,stdio:['ignore',logfd,logfd]});
    assert.equal(install.status,0,'Actual installer startup hook failed');assert(!install.error);
    assert.equal(cli('--status').state,'open');
    const hook=fs.readFileSync('/etc/systemd/system/kazoo-apps.service.d/35-kazoo-maintenance-fence.conf','utf8');
    assert(hook.includes('ExecStartPre=+/usr/bin/node '+HELPER+' --boot-guard'));
    fs.writeFileSync(UNITFILE,'[Unit]\nDescription=Owned maintenance guard acceptance\n[Service]\nType=simple\nUser=nobody\nExecStart=/usr/bin/sleep infinity\n'+
        hook.slice(hook.indexOf('[Service]')+'[Service]'.length),{mode:0o644,flag:'wx'});started=true;
    phase='normal_start';ctl('daemon-reload');ctl('start',UNIT);live();ctl('stop',UNIT);
    // Hold the same open-file-description flock another startup guard would
    // own. A separate process releases it after one second while systemd starts.
    phase='concurrent_startup_lock';
    const lockfd=fs.openSync(STATE+'/lock',fs.constants.O_RDWR|fs.constants.O_NOFOLLOW);
    try{
        assert.equal(cp.spawnSync('/usr/bin/flock',['-n','3'],{stdio:['ignore','pipe','pipe',lockfd]}).status,0);
        const unlocker=cp.spawn('/usr/bin/bash',['-c','sleep 1; /usr/bin/flock --unlock 3'],
            {stdio:['ignore','ignore','ignore',lockfd]});
        assert(unlocker.pid>1);ctl('start',UNIT);live();ctl('stop',UNIT);
    }finally{fs.closeSync(lockfd);}
    phase='closed_start';generation=crypto.randomBytes(16).toString('hex');
    const spec={schema_version:1,generation,manifest_sha256:crypto.createHash('sha256').update(hook).digest('hex'),
        roles:['kazoo-apps'],tcp_ports:[19800],udp_ports:[]};
    fs.writeFileSync(root+'/spec.json',JSON.stringify(spec)+'\n',{mode:0o600,flag:'wx'});
    assert.equal(cli('--close',root+'/spec.json').state,'closed');closed=true;
    ctl('start',UNIT);live();assert.equal(cli('--verify',generation).state,'closed');ctl('stop',UNIT);
    phase='kernel_loss_reapply';run('/usr/sbin/nft',['delete','table','inet','kz5_maintenance']);
    ctl('start',UNIT);live();assert.equal(cli('--verify',generation).state,'closed');ctl('stop',UNIT);
    // Simulated torn durable intent must fail before the unprivileged main PID.
    phase='torn_intent';fs.renameSync(STATE+'/active.json',root+'/saved-active.json');corrupt=true;
    fs.writeFileSync(STATE+'/active.json','{',{mode:0o600,flag:'wx'});rejectsStart();restoreCorruption();
    ctl('reset-failed',UNIT);
    phase='explicit_release';assert.equal(cli('--release',generation).state,'open');closed=false;
    ctl('start',UNIT);live();ctl('stop',UNIT);
    proof={status:'PASS',actual_installer_hook:true,unprivileged_service_start:true,concurrent_startup_lock_wait:true,
        kernel_loss_reapplied_before_start:true,corrupt_intent_blocks_start:true,explicit_release_restores_start:true,
        apps_service_restarted:false,complete_cluster_fence_proven:false,
        fixture_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),
        helper_sha256:crypto.createHash('sha256').update(fs.readFileSync(HELPER)).digest('hex')};
}finally{
    restoreCorruption();
    if(started)ctl('stop',UNIT);
    if(closed&&generation){cli('--release',generation);closed=false;}
    if(started){fs.unlinkSync(UNITFILE);ctl('daemon-reload');}
    if(logfd!==undefined)fs.closeSync(logfd);
}
    assert(proof);assert.equal(cli('--status').state,'open');assert(!fs.existsSync(UNITFILE));
    proof.scoped_cleanup_verified=true;
    fs.writeFileSync(root+'/receipt.json',JSON.stringify(proof)+'\n',{mode:0o600,flag:'wx'});
    console.log(JSON.stringify({...proof,receipt:root+'/receipt.json'}));
}
try{main();}catch(_){
    if(root&&!fs.existsSync(root+'/receipt.json'))fs.writeFileSync(root+'/receipt.json',
        JSON.stringify({status:'FAIL',failed_phase:phase,complete_cluster_fence_proven:false})+'\n',{mode:0o600,flag:'wx'});
    console.error('NATIVE_SYSTEMD_FENCE_FAILED; protected evidence retained');process.exitCode=1;
}
