'use strict';
const assert=require('node:assert/strict');
const {native,summary}=require('./test-main-media-soak.cjs');
const uuid='12345678-1234-1234-1234-123456789abc';
const before={state:'open',native:{admission:'open',sessions:0,core_uuid:uuid,process:{pid:123,start_ticks:'1234',boot_id:uuid}}};
native(before,null,true);native({...before,native:{...before.native,sessions:60}},before);
for(const change of [{admission:'closed'},{sessions:-1},{sessions:1.5},{core_uuid:'bad'},
    {core_uuid:'22345678-1234-1234-1234-123456789abc'},{process:{...before.native.process,pid:124}}])
    assert.throws(()=>native({...before,native:{...before.native,...change}},before));
assert.throws(()=>native({...before,state:'closed'},before));
assert.throws(()=>native({...before,native:{...before.native,sessions:1}},before,true));
const head=['stage','answered_target/total_calls','caller_success','caller_failed','agent_success','agent_failed','peak_cpu_pct','min_mem_available_kb','error_logs','new_cores','verified_concurrent_hold_s'];
const row=['answered-30','30/30','30','0','30','0','72','17476668','0/0','0','1800'];
const text=r=>head.join('\t')+'\n'+r.join('\t')+'\n';
assert.equal(summary(text(row)).verified_hold_seconds,1800);
for(const [index,value] of [[0,'answered-1'],[1,'30/35'],[2,'29'],[3,'1'],[4,'29'],[5,'1'],[6,'NaN'],[7,'1000'],[8,'1/0'],[9,'1'],[10,'1799']]){
    const changed=[...row];changed[index]=value;assert.throws(()=>summary(text(changed)));
}
assert.throws(()=>summary(text(row)+row.join('\t')+'\n'));
assert.throws(()=>summary(text(row).replace('error_logs','unrelated_column')));
console.log('PASS native media epoch/admission and full 30-call/1800s/error/resource receipt guards');
