'use strict';
// Opt-in private-lab call acceptance only. No production hosts or PSTN dial strings.
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const HELPER='/usr/local/libexec/kazoo5-maintenance-media',CLI='/usr/local/freeswitch/bin/fs_cli';
const HEX=/^[a-f0-9]{32}$/,UUID=/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
function validate(r,owner,media){
    assert(r&&r.schema_version===1&&r.owner===owner&&typeof owner==='string'&&HEX.test(owner));
    assert(typeof r.generation==='string'&&HEX.test(r.generation)&&r.media===media&&typeof media==='string'&&/^[a-f0-9]{64}$/.test(media));
    assert(typeof r.source==='string'&&/^[a-f0-9]{40}$/.test(r.source)&&typeof r.manifest_sha256==='string'&&/^[a-f0-9]{64}$/.test(r.manifest_sha256));
    assert(['eavesdrop','whisper','barge','join'].includes(r.mode));
    assert(['preparing','closing','closed','releasing'].includes(r.phase));
    assert(Array.isArray(r.probes)&&r.probes.length<=3&&new Set(r.probes).size===r.probes.length&&r.probes.every(id=>typeof id==='string'&&UUID.test(id)));
    return r;
}
function probeCommand(id,generation){
    assert(typeof id==='string'&&UUID.test(id)&&typeof generation==='string'&&HEX.test(generation));
    return `originate {origination_uuid=${id},kazoo_maintenance_test=${generation},originate_timeout=3}null/kazoo-maintenance &park()`;
}
function context(c){
    const pod=args=>c.command('podman',['exec',c.distributed.media,...args]).trim();
    const cli=command=>c.command(CLI,['-x',command]).trim();
    const helper=args=>JSON.parse(pod(['node',HELPER,...args]));
    function admit(){
        assert(c.distributed&&c.fixture.account_id==='45e827067baf078029d0ca16a489fa8a');
        const s=JSON.parse(fs.readFileSync('/var/lib/kazoo5-install-lab/lab.json','utf8')),m=s.roles.freeswitch;
        assert.equal(s.owner,'distributed-install-v1');assert.equal(m.id,c.distributed.media);
        assert.equal(m.phase,'installed-service-verified');assert.equal(m.source,m.installedSource);assert(!m.installUnit);
        const x=JSON.parse(c.command('podman',['inspect',m.id]))[0];
        assert.equal(x.Config.Labels['io.talkchief.kazoo.acceptance'],s.owner);
        assert.equal(x.Config.Labels['io.talkchief.kazoo.role'],'freeswitch');
        assert(x.State.Running&&!x.State.Paused&&!x.HostConfig.Privileged);
        assert.equal(x.NetworkSettings.Networks['kz5-install-stage'].IPAddress,'172.30.253.15');
        assert.equal(Object.keys(x.NetworkSettings.Networks).length,1);
        return m;
    }
    const record=()=>validate(c.fixture.media_fence,c.fixture.deployment_id,c.distributed.media);
    async function cleanupProbes(r){
        for(const id of r.probes){
            if(cli('uuid_exists '+id)==='false')continue;
            assert.equal(cli('uuid_getvar '+id+' kazoo_maintenance_test'),r.generation,'Unowned probe call');
            assert(cli('uuid_kill '+id+' NORMAL_CLEARING').startsWith('+OK'));
            await c.until(()=>cli('uuid_exists '+id)==='false',5);
        }
    }
    async function probe(expected){
        const r=record(),id=crypto.randomUUID();assert.equal(cli('uuid_exists '+id),'false');
        r.probes.push(id);c.saveFixture();
        const out=cli(probeCommand(id,r.generation));
        if(expected==='open'){
            assert.equal(out,'+OK '+id,'The identical internal endpoint must work without the fence');
            assert.equal(cli('uuid_getvar '+id+' kazoo_maintenance_test'),r.generation);
            const call=JSON.parse(cli('uuid_dump '+id+' json'));
            assert.equal(call['Unique-ID'],id);assert(Number(call['Caller-Channel-Answered-Time']||0)>0,'Probe must actually answer');
        }else{assert(out.startsWith('-ERR '),'Fenced internal originate was not rejected');assert.equal(cli('uuid_exists '+id),'false');}
        await cleanupProbes(r);
    }
    async function begin(mode){
        const m=admit();assert(!c.fixture.media_fence);c.originalAlive();
        const before=helper(['--status']);assert.equal(before.state,'open');assert.equal(before.native.sessions,3);
        const generation=crypto.randomBytes(16).toString('hex');
        const manifest=crypto.createHash('sha256').update(JSON.stringify({owner:c.fixture.deployment_id,media:m.id,source:m.source,mode,process:before.native.process})).digest('hex');
        const r={schema_version:1,owner:c.fixture.deployment_id,media:m.id,source:m.source,mode,generation,
            manifest_sha256:manifest,phase:'preparing',probes:[],before};
        c.fixture.media_fence=r;c.saveFixture();
        await probe('open');c.originalAlive();
        const spec=c.writePrivate('media-'+mode+'-spec.json',JSON.stringify({schema_version:1,generation,manifest_sha256:manifest})+'\n');
        const dir='/var/lib/kazoo-stage/media-fence-'+generation;
        pod(['mkdir','-m','0700',dir]);c.command('podman',['cp',spec,m.id+':'+dir+'/spec.json']);
        r.phase='closing';c.saveFixture();
        r.closed=helper(['--close',dir+'/spec.json']);r.closed_at=Date.now()/1000;
        assert.equal(r.closed.state,'closed');assert.equal(r.closed.generation,generation);assert.equal(r.closed.native.sessions,3);
        assert.deepEqual(r.closed.native.process,before.native.process);assert.equal(r.closed.native.core_uuid,before.native.core_uuid);
        r.phase='closed';c.saveFixture();await probe('closed');c.originalAlive();
        assert.equal(helper(['--verify',generation]).native.sessions,3);
        c.log(mode+' native media fence closed; internal originate rejected; existing three legs retained');
    }
    async function release(cleanup=false){
        const m=admit(),r=record();assert.equal(r.source,m.installedSource);await cleanupProbes(r);
        if(r.phase==='preparing'){
            // No close was dispatched in this persisted phase.
            assert.equal(helper(['--status']).state,'open');delete c.fixture.media_fence;c.saveFixture();return;
        }
        if(!cleanup){c.originalAlive();assert.equal(helper(['--verify',r.generation]).native.sessions,3);}
        r.phase='releasing';r.released_at=Date.now()/1000;c.saveFixture();
        r.released=helper(['--release',r.generation]);assert.equal(r.released.state,'open');
        assert.equal(r.released.generation,r.generation);
        assert.deepEqual(r.released.native.process,r.before.native.process);assert.equal(r.released.native.core_uuid,r.before.native.core_uuid);
        if(!cleanup){await probe('open');c.originalAlive();assert.equal(helper(['--status']).native.sessions,3);}
        const proof={...r};delete c.fixture.media_fence;c.saveFixture();return proof;
    }
    return {begin,release};
}
module.exports={context,validate,probeCommand};
