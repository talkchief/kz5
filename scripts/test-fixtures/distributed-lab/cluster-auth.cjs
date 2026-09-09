'use strict';
// Armed, fixed-network native acceptance. Tokens and DB credentials stay private.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const cp=require('node:child_process'),crypto=require('node:crypto'),os=require('node:os');
const DIR='/var/lib/kazoo5-install-lab',OWNER='distributed-install-v1',BROKER='172.30.253.12';
function command(args) {
    const r=cp.spawnSync(args[0],args.slice(1),{encoding:'utf8',timeout:15000,maxBuffer:65536});
    assert.equal(r.status,0,'Scoped native command failed');assert(!r.error);return r.stdout.trim();
}
async function until(fn,ms=5000) {
    const end=Date.now()+ms;
    while(Date.now()<end){if(fn())return;await new Promise(r=>setTimeout(r,25));}
    throw Error('Native assertion deadline');
}
function owned(s,entry,role,ip) {
    assert(entry?.id&&/^[a-f0-9]{64}$/.test(entry.id));
    const c=JSON.parse(command(['podman','inspect',entry.id]))[0];
    assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
    assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);
    assert.equal(c.State.Running,true);assert.equal(c.State.Paused,false);
    assert.equal(command(['podman','exec',entry.id,'systemctl','is-active','kazoo-apps']),'active');
    return {...entry,ip,pid:command(['podman','exec',entry.id,'systemctl','show','--value','-p','MainPID','kazoo-apps'])};
}
async function main() {
    assert.equal(process.getuid(),0);assert.equal(typeof WebSocket,'function');
    assert(Object.values(os.networkInterfaces()).flat().some(i=>i.address==='10.1.0.44'));
    assert(process.argv.length===3&&['--revocation','--partition'].includes(process.argv[2]));
    const partition=process.argv[2]==='--partition';
    const st=fs.lstatSync(DIR+'/lab.json');
    assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&0o777)===0o600);
    const s=JSON.parse(fs.readFileSync(DIR+'/lab.json'));assert.equal(s.owner,OWNER);
    assert.equal(s.roles['kazoo-apps'].phase,'installed-service-verified');assert.equal(s.peer.phase,'installed');
    const nodes=[owned(s,s.roles['kazoo-apps'],'kazoo-apps','172.30.253.14'),
        owned(s,s.peer,'kazoo-apps-peer','172.30.253.20')];
    const rpc=(entry,...args)=>command(['podman','exec',entry.id,'/usr/bin/escript',
        '/var/lib/kazoo-stage/cluster-auth-rpc.escript',...args]);
    const result={status:'RUNNING',mode:process.argv[2],started:new Date().toISOString(),checks:[],nodes:nodes.map(n=>({ip:n.ip,pid:n.pid}))};
    const receipt=DIR+'/cluster-auth-'+Date.now()+'.json';
    const save=()=>fs.writeFileSync(receipt,JSON.stringify(result,null,2)+'\n',{mode:0o600});
    save();let routeAdded=false,watchdog=null;const sockets=[];
    try {
        result.phase='helper-admission';
        for(const n of nodes) {
            command(['podman','cp',path.join(__dirname,'cluster-auth-rpc.escript'),n.id+':/var/lib/kazoo-stage/cluster-auth-rpc.escript']);
            command(['podman','exec',n.id,'chmod','0600','/var/lib/kazoo-stage/cluster-auth-rpc.escript']);
        }
        result.phase='issue-fixture-token';const issued=JSON.parse(rpc(nodes[0],'issue'));
        assert(/^[a-f0-9]{32}$/.test(issued.account));
        assert.equal(issued.user,'ef64a90c34d5491881a48c58f0d63271');
        const status=n=>fetch('http://'+n.ip+':8000/v2/accounts/'+issued.account+'/users/'+issued.user,
            {headers:{'X-Auth-Token':issued.token},redirect:'error',signal:AbortSignal.timeout(7000)}).then(r=>r.status);
        result.phase='warm-both-caches';
        for(const n of nodes) {
            assert.equal(await status(n),200);
            const tag='cluster-auth-'+crypto.randomBytes(16).toString('hex');
            const w={socket:new WebSocket('ws://'+n.ip+':5555/websocket'),tag,events:[],closed:null};sockets.push(w);
            w.socket.onmessage=e=>{try{w.events.push(JSON.parse(e.data));}catch(_){}};
            w.socket.onclose=e=>{w.closed=e.code;};w.socket.onerror=()=>{};
            await until(()=>w.socket.readyState===WebSocket.OPEN);
            w.socket.send(JSON.stringify({action:'ping',auth_token:issued.token,request_id:tag}));
            await until(()=>w.events.some(e=>e.request_id===tag&&e.status==='success'));
            rpc(n,'emit',tag,'before-revocation');
            await until(()=>w.events.some(e=>e.data==='before-revocation'));
        }
        result.checks.push('both-native-http-and-websocket-caches-warmed');save();
        if(partition) {
            result.phase='isolate-peer-broker-only';
            const peer=nodes[1];
            assert.deepEqual(JSON.parse(command(['podman','exec',peer.id,'ip','-j','route','show','exact',BROKER+'/32'])),[]);
            watchdog='kz5-cluster-auth-restore-'+process.pid;
            command(['systemd-run','--unit',watchdog,'--on-active=3m','--timer-property=AccuracySec=1s',
                '/usr/bin/podman','exec',peer.id,'ip','route','del','blackhole',BROKER+'/32']);
            command(['podman','exec',peer.id,'ip','route','add','blackhole',BROKER+'/32']);routeAdded=true;
            command(['podman','exec',peer.id,'ss','-K','dst',BROKER,'dport','=','5672']);
            assert.equal(command(['podman','exec',peer.id,'ss','-Hnt','state','established','dst',BROKER,'dport','=','5672']),'');
            result.checks.push('only-peer-broker-route-isolated-no-established-amqp');save();
        }
        result.phase='revoke-on-primary';rpc(nodes[0],'revoke',issued.revision);
        result.checks.push('exact-fixture-user-revoked-by-primary-cas');
        await new Promise(r=>setTimeout(r,1000));
        result.phase='revoked-http-both-nodes';
        result.httpAfter=await Promise.all(nodes.map(status));save();
        // Capture both delivery outcomes before evaluating, retaining actual
        // leak/close evidence even if HTTP already exposed stale authorization.
        result.phase='revoked-delivery-both-nodes';
        for(let i=0;i<nodes.length;i++)rpc(nodes[i],'emit',sockets[i].tag,'after-revocation');
        await new Promise(r=>setTimeout(r,4000));
        result.deliveryAfter=sockets.map(w=>({closeCode:w.closed,leaked:w.events.some(e=>e.data==='after-revocation')}));save();
        assert(Date.now()<issued.expires*1000);
        assert.deepEqual(result.httpAfter,[401,401]);
        assert.deepEqual(result.deliveryAfter,[{closeCode:1008,leaked:false},{closeCode:1008,leaked:false}]);
        result.checks.push('both-nodes-deny-revoked-http-and-delivery-before-expiry');
        for(const n of nodes)assert.equal(command(['podman','exec',n.id,'systemctl','show','--value','-p','MainPID','kazoo-apps']),n.pid);
        result.status='PASS';
    } catch(_) {result.status='FAIL';process.exitCode=1;}
    finally {
        for(const w of sockets)w.socket.close();
        try {
            if(routeAdded) {
                command(['podman','exec',nodes[1].id,'ip','route','del','blackhole',BROKER+'/32']);
                await until(()=>command(['podman','exec',nodes[1].id,'ss','-Hnt','state','established',
                    'dst',BROKER,'dport','=','5672'])!=='',30000);
            }
            if(watchdog)command(['systemctl','stop',watchdog+'.timer']);
            result.networkRestored=true;
        } catch(_) {result.networkRestored=false;result.status='FAIL';process.exitCode=1;}
        result.finished=new Date().toISOString();save();
        console.log(JSON.stringify({...result,receipt}));
    }
}
if(require.main===module)main().catch(()=>{console.error('Cluster auth acceptance refused before setup');process.exitCode=1;});
