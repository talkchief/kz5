'use strict';
// Test-only, exact original lab controller/apps pairs. Never main44 or production routes.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os');
const DIR='/var/lib/kazoo5-install-lab',BROKER='172.30.253.12';
function command(args) {
    try {return cp.execFileSync(args[0],args.slice(1),{encoding:'utf8',timeout:15000,maxBuffer:65536,stdio:['ignore','pipe','pipe']}).trim();}
    catch {throw Error('Scoped controller partition command failed');}
}
function admit(s,inspect,profile='ecallmgr') {
    assert.equal(s.owner,'distributed-install-v1');
    assert(['ecallmgr','kazoo-apps'].includes(profile));
    const selected=profile==='ecallmgr'?[
        ['ecallmgr',s.roles?.ecallmgr,'172.30.253.16','installed-service-verified'],
        ['ecallmgr-peer',s.ecallmgrPeer,'172.30.253.21','installed']]:[
        ['kazoo-apps',s.roles?.['kazoo-apps'],'172.30.253.14','installed-service-verified'],
        ['kazoo-apps-peer',s.peer,'172.30.253.20','installed']];
    return selected.map(([role,r,ip,phase])=>{
        assert.equal(r?.phase,phase);assert(/^[a-f0-9]{64}$/.test(r.id));
        const c=inspect(r.id);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(c.Config.Labels['io.talkchief.kazoo.role'],role);
        assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress,ip);
        assert.equal(c.State.Running,true);assert.equal(c.State.Paused,false);
        return {id:r.id,ip};
    });
}
class Partition {
    constructor(nodes,run=command,profile='ecallmgr') {
        assert.equal(nodes.length,2);this.nodes=nodes;this.run=run;
        assert(['ecallmgr','kazoo-apps'].includes(profile));this.profile=profile;
        this.service=profile==='ecallmgr'?'kazoo-ecallmgr':'kazoo-apps';
        this.prefix=profile==='ecallmgr'?'ecallmgr':'kazoo_apps';
        this.routeAdded=false;this.watchdog=null;this.proof={};
    }
    exec(n,...args){return this.run(['podman','exec',n.id,...args]);}
    available(n){const value=this.exec(n,'sup','-n',this.prefix,'-e','kz_amqp_connections','is_available');
        assert(['true','false'].includes(value),'Invalid native broker status');return value==='true';}
    queryReady(n){
        if(this.profile!=='ecallmgr')return this.available(n);
        // A reconnecting listener can temporarily block its bounded status RPC.
        // Unknown is not ready, and can never satisfy the recovery gate.
        let value;try {value=this.exec(n,'sup','-n','ecallmgr','-e','gen_listener','is_consuming','ecallmgr_fs_channels');}
        catch {return false;}
        return value==='true';
    }
    async wait(fn,seconds) {
        const end=Date.now()+seconds*1000;
        while(Date.now()<end){if(fn())return;await new Promise(r=>setTimeout(r,200));}
        throw Error('Scoped controller partition observation timed out');
    }
    async start() {
        assert(!this.routeAdded&&!this.watchdog,'Partition already armed');
        const [target,peer]=this.nodes;
        for(const n of this.nodes) {
            assert.equal(this.exec(n,'systemctl','is-active',this.service),'active');
            n.pid=this.exec(n,'systemctl','show','--value','-p','MainPID',this.service);
            assert(/^[1-9][0-9]*$/.test(n.pid));assert(this.available(n));assert(this.queryReady(n));
        }
        assert.deepEqual(JSON.parse(this.exec(target,'ip','-j','route','show','exact',BROKER+'/32')),[]);
        this.watchdog='kz5-monitor-partition-restore-'+process.pid+'-'+Date.now();
        this.run(['systemd-run','--unit',this.watchdog,'--on-active=3m','--timer-property=AccuracySec=1s',
            '/usr/bin/podman','exec',target.id,'ip','route','del','blackhole',BROKER+'/32']);
        assert.equal(this.run(['systemctl','is-active',this.watchdog+'.timer']),'active');
        // Mark before mutation: an observation error must still attempt recovery.
        this.routeAdded=true;
        this.exec(target,'ip','route','add','blackhole',BROKER+'/32');
        this.exec(target,'ss','-K','dst',BROKER,'dport','=','5672');
        this.proof.started=Date.now()/1000;
        await this.wait(()=>!this.available(target),10);
        assert.equal(this.exec(target,'ss','-Hnt','state','established','dst',BROKER,'dport','=','5672'),'');
        assert(this.available(peer));
        this.proof.partitioned_node=target.ip;this.proof.healthy_node=peer.ip;
        if(this.profile==='ecallmgr') {
            this.proof.partitioned_controller=target.ip;this.proof.healthy_controller=peer.ip;
        }
        this.proof.disconnected_registry_verified=true;
    }
    async restore() {
        if(this.routeAdded) {
            const [target,peer]=this.nodes;
            const routes=JSON.parse(this.exec(target,'ip','-j','route','show','exact',BROKER+'/32'));
            assert.equal(routes.length,1);assert.equal(routes[0].type,'blackhole');
            this.proof.restored=Date.now()/1000;
            this.exec(target,'ip','route','del','blackhole',BROKER+'/32');
            this.routeAdded=false;
            await this.wait(()=>this.available(target),45);
            assert(this.available(peer));
            if(this.profile==='ecallmgr') {
                this.proof.query_consumer_at_broker_recovery=this.queryReady(target);
                // Broker registration precedes listener queue/binding recovery.
                // Require the installer's consumer readiness before a single stop;
                // never retry an ambiguous mutation.
                await this.wait(()=>this.queryReady(target)&&this.queryReady(peer),45);
                this.proof.query_consumers_recovered=true;
            }
            for(const n of this.nodes)assert.equal(this.exec(n,'systemctl','show','--value','-p','MainPID',this.service),n.pid);
            this.proof.same_node_vms=true;
            if(this.profile==='ecallmgr')this.proof.same_controller_vms=true;
            this.proof.registered_broker_recovered=true;
        }
        if(this.watchdog) {
            this.run(['systemctl','stop',this.watchdog+'.timer']);
            // systemd retains an elapsed transient unit after use; reset its
            // identity between modes instead of reusing an ambiguous timer.
            this.watchdog=null;
        }
        return this.proof;
    }
}
function prepare(profile='ecallmgr',targetIp) {
    assert.equal(process.getuid(),0);assert.equal(os.hostname(),'dev-testing');
    assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'));
    const st=fs.lstatSync(DIR+'/lab.json');
    assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);
    const s=JSON.parse(fs.readFileSync(DIR+'/lab.json'));
    const nodes=admit(s,id=>JSON.parse(command(['podman','inspect',id]))[0],profile);
    if(targetIp!==undefined) {
        assert(nodes.some(n=>n.ip===targetIp),'Unapproved partition target');
        if(nodes[0].ip!==targetIp)nodes.reverse();
    }
    return new Partition(nodes,command,profile);
}
module.exports={admit,Partition,prepare};
