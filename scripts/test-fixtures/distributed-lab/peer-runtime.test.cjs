'use strict';
// Actual orchestration with private in-memory Podman/systemd adapters only.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process');
const {peerOperation}=require('./peer.cjs');
function run(change=()=>{},verifyStatus=0) {
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kz5-peer-runtime.'));
    const peer={id:'a'.repeat(64),phase:'installed'},media={id:'b'.repeat(64)};
    const state={owner:'distributed-install-v1',ecallmgrPeer:peer,roles:{freeswitch:media}};
    const container=(role,ip)=>({Config:{Labels:{'io.talkchief.kazoo.acceptance':state.owner,'io.talkchief.kazoo.role':role},
        CreateCommand:['--sysctl','net.ipv4.ip_local_reserved_ports=34512-34513']},
        NetworkSettings:{Networks:{'kz5-install-stage':{IPAddress:ip}}},State:{Running:true,Paused:false,StartedAt:'before'}});
    const containers={[peer.id]:container('ecallmgr-peer','172.30.253.21'),[media.id]:container('freeswitch','172.30.253.15')};
    const fixture={state,peer,media,containers,channels:0,actions:[]};change(fixture);
    const native=cp.spawnSync;
    cp.spawnSync=(program,args,options)=>{
        assert.equal(program,'podman');assert.deepEqual(args,['exec',peer.id,'bash','/opt/kz5/scripts/install-kazoo5.sh','--verify-only','ecallmgr']);
        assert.equal(options.timeout,180000);fixture.actions.push('verify');return {status:verifyStatus};
    };
    let error;
    try {
        peerOperation('reboot',{
            readState:()=>state,saveState:s=>{assert.equal(s,state);},ownedNetwork:()=>{},DIR:dir,ROOT:'/unused',
            json:args=>{assert.equal(args[0],'inspect');return [structuredClone(containers[args[1]])];},
            command:(program,args)=>{fixture.actions.push(program+':'+args.join(' '));return args[0]==='show'?'inactive':'';},
            podman:args=>{
                fixture.actions.push(args[0]);
                if(args[0]==='stop'){containers[peer.id].State.Running=false;return '';}
                if(args[0]==='start'){containers[peer.id].State={Running:true,Paused:false,StartedAt:'after'};return '';}
                assert.equal(args[0],'exec');
                if(args[2]==='/usr/local/freeswitch/bin/fs_cli')return JSON.stringify({row_count:fixture.channels});
                if(args[2]==='timeout')return '';
                if(args[2]==='ip')return JSON.stringify(['10.1.0.0/16','46.225.31.248','91.99.188.145'].map(dst=>({type:'blackhole',dst})));
                assert.equal(args[2],'systemctl');return args[3]==='is-enabled'?'enabled':'active';
            }
        },'ecallmgr');
    }catch(e){error=e;}
    finally {
        cp.spawnSync=native;
        for(const name of fs.readdirSync(dir))fs.unlinkSync(path.join(dir,name));fs.rmdirSync(dir);
    }
    return {...fixture,error};
}
let result=run();assert.equal(result.error,undefined);assert.equal(result.peer.boot.status,'PASS');
assert(result.actions.includes('verify'));
assert(result.actions.some(a=>a.includes('--on-active=10m')));
assert(result.actions.some(a=>a.startsWith('systemctl:stop kz5-peer-boot-restore-')));
let rejected=0;
for(const change of [
    x=>{x.peer.phase='installing';},
    x=>{x.channels=1;},
    x=>{x.containers[x.peer.id].State.Paused=true;},
    x=>{x.containers[x.peer.id].Config.CreateCommand=[];},
    x=>{x.containers[x.peer.id].NetworkSettings.Networks['kz5-install-stage'].IPAddress='10.1.0.44';},
    x=>{x.containers[x.media.id].NetworkSettings.Networks['kz5-install-stage'].IPAddress='10.1.0.44';},
    x=>{x.containers[x.media.id].Config.Labels['io.talkchief.kazoo.acceptance']='foreign';}
]) {result=run(change);assert(result.error);assert(!result.actions.includes('stop'));assert(!result.peer.boot);rejected++;}
result=run(()=>{},1);assert(result.error);assert.equal(result.peer.boot.status,'FAIL');
assert.equal(result.containers[result.peer.id].State.Running,true);
console.log('PASS actual peer reboot orchestration: success, '+rejected+' pre-stop refusals and verifier failure retained; no native services touched');
