const assert=require('node:assert/strict');
const {workerHeapMiB}=require('./build-monster-production.cjs');
const GiB=1024**3;
const fixture=(leaf,parent='max',root='max')=>file=>({
    '/proc/self/cgroup':'0::/system.slice/build.service\n',
    '/sys/fs/cgroup/system.slice/build.service/memory.max':String(leaf),
    '/sys/fs/cgroup/system.slice/memory.max':String(parent),
    '/sys/fs/cgroup/memory.max':String(root)
})[file];
assert.equal(workerHeapMiB(fixture(384*1024**2),8*GiB),256);
assert.equal(workerHeapMiB(fixture(2*GiB),23*GiB),512);
assert.equal(workerHeapMiB(fixture(2*GiB,384*1024**2),23*GiB),256);
assert.equal(workerHeapMiB(fixture('max',512*1024**2),23*GiB),256);
assert.equal(workerHeapMiB(fixture('max'),512*1024**2),256);
assert.equal(workerHeapMiB(fixture('invalid'),23*GiB),256);
assert.equal(workerHeapMiB(()=>{throw Error('unreadable');},23*GiB),256);
assert.equal(workerHeapMiB(()=> '1:memory:/legacy\n',23*GiB),256);
console.log('PASS 8 bounded build heap cases; parent limits and low-memory guard preserved');
