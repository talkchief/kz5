'use strict';
// Bounded real worker fault in original private lab, never main44 services.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os'),path=require('node:path');
const DIR='/var/lib/kazoo5-install-lab';
function command(args,timeout=15000) {
    try{return cp.execFileSync(args[0],args.slice(1),{encoding:'utf8',timeout,maxBuffer:1048576,stdio:['pipe','pipe','pipe']}).trim();}
    catch {throw Error('Scoped AMQP replacement command failed');}
}
function main() {
    assert.equal(process.getuid(),0);assert.equal(os.hostname(),'dev-testing');
    assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'));
    assert.deepEqual(process.argv.slice(2),['--live']);
    const st=fs.lstatSync(DIR+'/lab.json');assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&(st.mode&511)===384);
    const s=JSON.parse(fs.readFileSync(DIR+'/lab.json'));assert.equal(s.owner,'distributed-install-v1');
    for(const [role,entry,ip,phase] of [['ecallmgr',s.roles.ecallmgr,'172.30.253.16','installed-service-verified'],
        ['ecallmgr-peer',s.ecallmgrPeer,'172.30.253.21','installed'],['freeswitch',s.roles.freeswitch,'172.30.253.15','installed-service-verified']]) {
        assert.equal(entry.phase,phase);
        const c=JSON.parse(command(['podman','inspect',entry.id]))[0];
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);assert.equal(c.State.Running,true);
        assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);
    }
    const media=['podman','exec',s.roles.freeswitch.id,'/usr/local/freeswitch/bin/fs_cli','-x'];
    assert.equal(JSON.parse(command([...media,'show channels as json'])).row_count,0);
    const target=s.roles.ecallmgr.id,inside='/var/lib/kazoo-stage/amqp-restart.escript';
    command(['podman','cp',path.join(__dirname,'test-fixtures/distributed-lab/amqp-restart.escript'),target+':'+inside]);
    command(['podman','exec',target,'chmod','0600',inside]);
    const watchdog='kz5-amqp-restart-restore-'+process.pid;
    const receipt=DIR+'/amqp-restart-'+Date.now()+'.json',result={status:'RUNNING',started:new Date().toISOString()};
    const save=()=>fs.writeFileSync(receipt,JSON.stringify(result,null,2)+'\n',{mode:0o600});save();
    command(['systemd-run','--unit',watchdog,'--on-active=5m','--timer-property=AccuracySec=1s',
        '/usr/bin/podman','exec',target,'systemctl','restart','kazoo-ecallmgr']);
    try {
        const proof=command(['podman','exec',target,'escript',inside],35000);
        assert(/^PASS supervised replacement old=<[^>]+> new=<[^>]+> same_vm=true zone_preserved=true broker_available=true$/.test(proof));
        result.proof=proof;
        command(['podman','exec',target,'bash','/opt/kz5/scripts/install-kazoo5.sh','--verify-only','ecallmgr'],180000);
        assert.equal(JSON.parse(command([...media,'show channels as json'])).row_count,0);
        result.status='PASS';
    } catch {result.status='FAIL';process.exitCode=1;
        // Development fixture only; preserve failed status if recovery needs a restart.
        command(['podman','exec',target,'systemctl','restart','kazoo-ecallmgr'],90000);
        result.fallbackRestart=true;
    } finally {
        command(['systemctl','stop',watchdog+'.timer']);result.finished=new Date().toISOString();save();
    }
    console.log(JSON.stringify({...result,receipt}));
}
try {main();} catch {console.error('Isolated AMQP replacement acceptance refused/failed');process.exitCode=1;}
