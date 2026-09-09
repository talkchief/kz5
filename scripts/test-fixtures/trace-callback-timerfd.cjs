'use strict';
// Read-only development diagnostic. No service changes, calls or provider use.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { execFileSync, spawn } = require('node:child_process');
const [mode, pidText, secondsText] = process.argv.slice(2);
assert.equal(process.argv.length, 5);
assert(['--dry-run', '--trace'].includes(mode));
assert(/^[1-9][0-9]*$/.test(pidText));
assert(/^[1-9][0-9]*$/.test(secondsText));
const seconds = Number(secondsText);
assert(seconds >= 5 && seconds <= 300);
assert.equal(process.getuid(), 0);
assert(Object.values(os.networkInterfaces()).flat().some(x => x.address === '10.1.0.44'),
    'Only the designated development server is allowed');
const run = (name, args) => execFileSync(name, args, { encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
assert.equal(run('systemctl', ['show', 'kazoo-freeswitch', '-p', 'MainPID', '--value']).trim(), pidText);
assert.equal(JSON.parse(run('/usr/local/freeswitch/bin/fs_cli', ['-x', 'show calls as json'])).row_count, 0);
const library = fs.realpathSync('/usr/local/freeswitch/lib/libfreeswitch.so.1');
const stat = fs.statSync(library);
assert(fs.readFileSync(`/proc/${pidText}/maps`, 'utf8').split('\n').some(line => {
    const fields = line.trim().split(/\s+/);
    return fields[4] === String(stat.ino) && fields[5] === library && fields.length === 6;
}), 'Running process must map the exact nondeleted library');
const source = '/usr/local/src/kazoo5-installer/freeswitch-1.11.3/src';
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
assert.equal(sha(path.join(source, 'switch_time.c')), 'ca714f0454f02b1bc57713a70fbb2d3d0aac2bfcf2fd868163c85e5f8b286284');
assert.equal(sha(path.join(source, 'switch_rtp.c')), 'a0a0b95ece6342d9089660f3b242aa25cd97d6956136c10f030b30038f542f87');
const fields = {
    RTP_TIMER: ['switch_rtp', 'write_timer'], RTP_LAST: ['switch_rtp', 'last_write_ts'],
    RTP_TS: ['switch_rtp', 'ts'], RTP_SSRC: ['switch_rtp', 'ssrc'],
    RTP_INTERVAL: ['switch_rtp', 'samples_per_interval'],
    TIMER_TICK: ['switch_timer', 'tick'], TIMER_COUNT: ['switch_timer', 'samplecount'],
    TIMER_PRIVATE: ['switch_timer', 'private_info'], INTERVAL_FD: ['interval_timer', 'fd']
};
const gdbArgs = ['-nx', '-batch', '-iex', 'set auto-load off', '-iex', 'set debuginfod enabled off', library];
for (const [key, [type, member]] of Object.entries(fields)) {
    gdbArgs.push('-ex', `printf "${key}=%lu\\n", (unsigned long)&((struct ${type}*)0)->${member}`);
}
const layout = run('/usr/bin/gdb', gdbArgs);
const defines = [];
for (const key of Object.keys(fields)) {
    const matches = [...layout.matchAll(new RegExp(`^${key}=([0-9]+)$`, 'gm'))];
    assert.equal(matches.length, 1, `Missing unambiguous DWARF layout for ${key}`);
    assert(Number(matches[0][1]) < 1024 * 1024);
    defines.push(`#define ${key} ${matches[0][1]}`);
}
console.log(JSON.stringify({ diagnostic: 'CALLBACK-RTP-01', pid: Number(pidText), seconds,
    mode, library_sha256: sha(library), layout: layout.trim(),
    wall_time: new Date().toISOString(), uptime_seconds: os.uptime() }));
// -k also warns for ordinary absent correlation-map entries on unrelated reads;
// that diagnostic noise would itself perturb timing. Keep default BPF warnings.
const args = ['-B', 'line'];
if (mode === '--dry-run') args.push('--dry-run');
const program = execFileSync('/usr/bin/cpp', ['-P', '-'], { encoding: 'utf8', timeout: 5000,
    input: defines.join('\n') + '\n' + fs.readFileSync(path.join(__dirname, 'trace-callback-timerfd.bt'), 'utf8').replace(/^#!.*\n/, '') });
args.push('-e', program, pidText);
const child = spawn('/usr/bin/bpftrace', args, { stdio: 'inherit' });
let timer;
let killTimer;
function stop() {
    child.kill('SIGINT');
    if (!killTimer) killTimer = setTimeout(() => child.kill('SIGKILL'), 10000);
}
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
timer = setTimeout(stop, seconds * 1000);
child.on('error', error => { console.error(error.message); clearTimeout(timer); process.exitCode = 1; });
child.on('exit', (code, signal) => {
    clearTimeout(timer); clearTimeout(killTimer);
    console.log(JSON.stringify({ trace_exit: code, signal }));
    process.exitCode = code === 0 ? 0 : 1;
});
