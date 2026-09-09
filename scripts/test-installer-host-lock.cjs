'use strict';
// Executes the actual installer function with only its fixed /run path relocated.
// No package, service, configuration, database or network access.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawn, spawnSync} = require('node:child_process');
const {once} = require('node:events');
const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const fn = source.match(/^acquire_installer_lock\(\) \{\n[\s\S]*?^\}/m)?.[0];
assert(fn);
assert(source.includes('parse_arguments "$@"\n    acquire_installer_lock\n    push_bridge_preflight\n    preflight'));
assert.equal(process.getuid(), 0, 'Root-owned lock controls require root fixture');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-installer-lock-'));
const lock = path.join(dir, 'lock');
const script = `set -Eeuo pipefail\nDRY_RUN=false\ndie(){ echo "$*" >&2; exit 1; }\n${fn.replace('/run/kazoo5-installer', lock)}\n`;
function run(tail = 'acquire_installer_lock') {
    const r = spawnSync('bash', ['-s'], {input: script + '\n' + tail, encoding: 'utf8', timeout: 5000});
    assert.ifError(r.error);
    return r;
}
async function main() {
    let holder;
    try {
        assert.equal(run('DRY_RUN=true; acquire_installer_lock').status, 0);
        assert(!fs.existsSync(lock), 'dry run must not create a lock');
        holder = spawn('bash', ['-c', script + '\nacquire_installer_lock; echo locked; read -r release'], {stdio: ['pipe', 'pipe', 'pipe']});
        const ready = await Promise.race([once(holder.stdout, 'data'), new Promise((_, reject) => {
            const timer = setTimeout(() => reject(new Error('Lock holder did not start')), 5000); timer.unref();
        })]);
        assert.equal(ready[0].toString().trim(), 'locked');
        const contended = run();
        assert.equal(contended.status, 1);
        assert.match(contended.stderr, /Another Kazoo installer/);
        assert.equal(run('DRY_RUN=true; acquire_installer_lock').status, 0);
        const exited = once(holder, 'exit');
        holder.kill('SIGTERM');
        await exited;
        holder = null;
        assert.equal(run().status, 0, 'signal termination must release lock without deletion');
        assert.equal(run('acquire_installer_lock; exit 7').status, 7);
        assert.equal(run().status, 0, 'failed installation must release lock');
        const inode = fs.statSync(path.join(lock, 'host.lock')).ino;
        assert.equal(run().status, 0);
        assert.equal(fs.statSync(path.join(lock, 'host.lock')).ino, inode, 'lock inode must remain stable');
        fs.chmodSync(lock, 0o777);
        assert.equal(run().status, 1, 'unsafe directory must be refused, not repaired');
        fs.chmodSync(lock, 0o700);
        fs.renameSync(path.join(lock, 'host.lock'), path.join(dir, 'original'));
        fs.symlinkSync(path.join(dir, 'original'), path.join(lock, 'host.lock'));
        assert.equal(run().status, 1, 'symlink lock must be refused');
        fs.unlinkSync(path.join(lock, 'host.lock'));
        fs.linkSync(path.join(dir, 'original'), path.join(lock, 'host.lock'));
        assert.equal(run().status, 1, 'hardlinked lock must be refused');
        console.log('PASS installer host lock: contention, dry run, signal/failure release, stable inode, unsafe paths and preflight ordering');
    } finally {
        if (holder) holder.kill('SIGKILL');
        fs.rmSync(dir, {recursive: true, force: true});
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
