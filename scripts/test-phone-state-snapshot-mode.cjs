'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {snapshotRuntime}=require('./snapshot-live-test-agent-state.cjs');
const state={queue_id:'a'.repeat(32),deployment_id:'b'.repeat(32)};
test('explicit state snapshot skips runtime and marker reads and records neither as observed',()=>{
 const forbidden=()=>{throw Error('A stopped-service snapshot must not inspect runtime or marker');};
 assert.deepEqual(snapshotRuntime('--snapshot-state',state,forbidden,forbidden),
  {runtime:{scope:'not_observed'},preserve_marker_matches:null});
});
test('ordinary snapshot retains checkpoint and exact marker gates; no implicit fallback',()=>{
 const runtime={main_pid:1234,zero_calls:true};let checkpoints=0,markers=0;
 const observe=s=>{assert.equal(s,state);checkpoints++;return runtime;};
 const read=path=>{assert.equal(path,'/run/kazoo-live-test-agents/preserve-agent-status');markers++;return state.deployment_id+'\n';};
 assert.deepEqual(snapshotRuntime('--snapshot',state,observe,read),{runtime,preserve_marker_matches:true});
 assert.equal(checkpoints,1);assert.equal(markers,1);
 assert.throws(()=>snapshotRuntime('--snapshot',state,()=>{throw Error('Missing live supervisor');},read));
 assert.equal(markers,1);
 assert.throws(()=>snapshotRuntime('--snapshot',state,observe,()=>''));
 assert.throws(()=>snapshotRuntime('--snapshot',state,observe,()=>{throw Error('Missing runtime marker');}));
 assert.throws(()=>snapshotRuntime('--other',state,observe,read));
 assert.throws(()=>snapshotRuntime('--snapshot-state',{...state,queue_id:'bad'},observe,read));
});
