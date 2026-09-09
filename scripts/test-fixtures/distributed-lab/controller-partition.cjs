'use strict';
// Test-only, exact original lab controller. Never main44 or production routes.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os');
const DIR='/var/lib/kazoo5-install-lab',BROKER='172.30.253.12';
function command(args) {
    try {return cp.execFileSync(args[0],args.slice(1),{encoding:'utf8',timeout:15000,maxBuffer:65536,stdio:['ignore','pipe','pipe']}).trim();}
    catch {throw Error('Scoped controller partition command failed');}
}
function admit(s,inspect) {
    assert.equal(s.owner,'distributed-install-v1');
    const selected=[['ecallmgr',s.roles?.ecallmgr,'172.30.253.16','installed-service-verified'],
        ['ecallmgr-peer',s.ecallmgrPeer,'172.30.253.21','installed']];
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
    constructor(nodes,run=command) {
        assert.equal(nodes.length,2);this.nodes=nodes;this.run=run;
        this.routeAdded=false;this.watchdog=null;this.proof={};
    }
    exec(n,...args){return this.run(['podman','exec',n.id,...args]);}
    available(n){const value=this.exec(n,'sup','-n','ecallmgr','-e','kz_amqp_connections','is_available');
        assert(['true','false'].includes(value),'Invalid native broker status');return value==='true';}
    async wait(fn,seconds) {
        const end=Date.now()+seconds*1000;
        while(Date.now()<end){if(fn())return;await new Promise(r=>setTimeout(r,200));}
        throw Error('Scoped controller partition observation timed out');
    }
    async start() {
        assert(!this.routeAdded&&!this.watchdog,'Partition already armed');
        const [target,peer]=this.nodes;
        for(const n of this.nodes) {
            assert.equal(this.exec(n,'systemctl','is-active','kazoo-ecallmgr'),'active');
            n.pid=this.exec(n,'systemctl','show','--value','-p','MainPID','kazoo-ecallmgr');
            assert(/^[1-9][0-9]*$/.test(n.pid));assert(this.available(n));
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
        this.proof.partitioned_controller=target.ip;this.proof.healthy_controller=peer.ip;
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
            for(const n of this.nodes)assert.equal(this.exec(n,'systemctl','show','--value','-p','MainPID','kazoo-ecallmgr'),n.pid);
            this.proof.same_controller_vms=true;this.proof.registered_broker_recovered=true;
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
function prepare() {
    assert.equal(process.getuid(),0);assert.equal(os.hostname(),'dev-testing');
    assert(Object.values(os.networkInterfaces()).flat().some(n=>n.address==='10.1.0.44'));
    const st=fs.lstatSync(DIR+'/lab.json');
    assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);
    const s=JSON.parse(fs.readFileSync(DIR+'/lab.json'));
    return new Partition(admit(s,id=>JSON.parse(command(['podman','inspect',id]))[0]));
}
module.exports={admit,Partition,prepare};
