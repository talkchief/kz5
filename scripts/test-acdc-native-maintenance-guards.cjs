'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {assertInstalledSources,mergeNativeInventories} = require('./test-acdc-native-maintenance.cjs');
const old = 'a'.repeat(40), next = 'b'.repeat(40);
test('accept matching successfully collected install source', () => {
    assertInstalledSources({source: next, installedSource: next}, {source: next, installedSource: next});
});
test('source synchronization alone never proves deployment', () => {
    assert.throws(() => assertInstalledSources({source: next, installedSource: old}, {source: next, installedSource: next}));
    assert.throws(() => assertInstalledSources({source: next, installedSource: next}, {source: next, installedSource: old}));
});
test('missing install attestation and mismatched node sources fail closed', () => {
    assert.throws(() => assertInstalledSources({source: next}, {source: next, installedSource: next}));
    assert.throws(() => assertInstalledSources({source: old, installedSource: old}, {source: next, installedSource: next}));
    assert.throws(() => assertInstalledSources({source: 'invalid', installedSource: 'invalid'}, {source: 'invalid', installedSource: 'invalid'}));
});
function inventories(){
    const account='45e827067baf078029d0ca16a489fa8a',queue='cabcfb72812b530ccc32ffba30ef680d';
    const nodes=['kazoo_apps@kz5-stage-kazoo-apps','kazoo_apps@kz5-stage-kazoo-apps-peer'];
    const base=n=>({schema_version:2,node:n,epoch:'current-'+n.replace('@','-'),startup_token:'d'.repeat(64),captured_at_unix_ms:Date.now(),
        complete_cluster_drain_proven:false,admission_fence_proven:false});
    const agents=nodes.map(n=>({...base(n),all_agent_workers_observed:true,
        agents:[1,2,3].map(i=>({node:n,account_id:account,agent_id:String(i).repeat(32),state:'ready',
            pause_until_unix_ms:0,queues:[queue]})),
        document_revisions:[1,2,3].map(i=>({account_id:account,agent_id:String(i).repeat(32),revision:'1-'+'a'.repeat(32)}))}));
    const queues=nodes.map(n=>({...base(n),all_queue_workers_observed:true,queues:[{account_id:account,
        queue_id:queue,document_revision:'1-'+'b'.repeat(32),worker_count:3,broker_queues:['fixture-'+n],busy_agents:[]}]}));
    return {queues,agents};
}
test('native combined admission requires the exact two-node six-agent cohort',()=>{
    const {queues,agents}=inventories(),merged=mergeNativeInventories(queues,agents,next);
    assert.equal(merged.agents.length,6);assert.equal(merged.queues.length,2);
    assert.equal(merged.admission_fence_proven,false);assert.equal(merged.complete_cluster_drain_proven,false);
    const missing=inventories();missing.agents[0].agents.pop();missing.agents[0].document_revisions.pop();
    assert.throws(()=>mergeNativeInventories(missing.queues,missing.agents,next));
    const foreign=inventories();foreign.queues[0].node='kazoo_apps@foreign';
    assert.throws(()=>mergeNativeInventories(foreign.queues,foreign.agents,next));
});
test('combined native admission rejects node changes and stale queue/agent observations',()=>{
    for(const target of ['queues','agents'])for(const field of ['epoch','captured_at_unix_ms']){
        const v=inventories();v[target][0][field]=field==='epoch'?'restarted':Date.now()-31000;
        assert.throws(()=>mergeNativeInventories(v.queues,v.agents,next));
    }
});
