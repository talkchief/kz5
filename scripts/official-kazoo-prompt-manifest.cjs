'use strict';
// Read names from the pinned Git object tree, never ignored working-tree audio.
const cp=require('node:child_process'),path=require('node:path'),assert=require('node:assert/strict');
const PREFIX='kazoo-core/en/us/';
function parseTree(bytes) {
    assert(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 1048576, 'Invalid pinned sound tree');
    const entries=bytes.toString('utf8').split('\0'); assert.equal(entries.pop(), '');
    const keys=[];
    for (const entry of entries) {
        const match=/^(\d{6}) (blob|tree) ([a-f0-9]{40})\t(.+)$/.exec(entry);
        assert(match, 'Malformed pinned sound entry');
        const [,mode,type,,file]=match;
        if (!file.startsWith(PREFIX) || file.slice(PREFIX.length).includes('/') || !file.endsWith('.wav')) continue;
        assert(type==='blob' && ['100644','100755'].includes(mode), 'Pinned prompt must be a regular Git blob');
        const name=file.slice(PREFIX.length);
        assert(/^[A-Za-z0-9_-]+\.wav$/.test(name), 'Invalid pinned prompt name');
        keys.push('en-us/'+name.slice(0,-4));
    }
    assert(keys.length > 0 && keys.length <= 1000 && new Set(keys).size===keys.length, 'Invalid pinned prompt inventory');
    return {keys: keys.sort()};
}
function manifest(sourceRoot, ref, execute=cp.execFileSync) {
    assert(typeof sourceRoot==='string' && path.isAbsolute(sourceRoot) && sourceRoot!=='/', 'Absolute sound repository required');
    assert(/^[a-f0-9]{40}$/.test(ref), 'Exact sound commit required');
    return parseTree(execute('git',['-C',sourceRoot,'ls-tree','-rz',ref,'--',PREFIX],
        {timeout:15000,maxBuffer:1048576,stdio:['ignore','pipe','pipe']}));
}
module.exports={parseTree,manifest};
if(require.main===module) {
    try {
        assert(process.argv.length===6 && process.argv[2]==='--source-root' && process.argv[4]==='--ref',
            'Usage: node official-kazoo-prompt-manifest.cjs --source-root /absolute/kazoo-sounds --ref COMMIT');
        console.log(JSON.stringify(manifest(process.argv[3],process.argv[5])));
    } catch (_) { console.error('Pinned official prompt manifest verification failed'); process.exitCode=1; }
}
