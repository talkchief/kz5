'use strict';
// Run the real release escript and relx in a private output tree, without HOME.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-release-nondistributed.'));
fs.chmodSync(out, 0o700);
const config = path.join(out, 'fixture.config');
fs.writeFileSync(config, '{release,{fixture_release,"1.0.0"},[kernel,stdlib]}.\n{dev_mode,false}.\n{include_erts,false}.\n{extended_start_script,false}.\n');
fs.writeFileSync(config + '.script', 'nonode@nohost = node(),\nundefined = whereis(net_kernel),\nfalse = os:getenv("HOME"),\nCONFIG.\n');
const result = cp.spawnSync('/usr/bin/escript', [path.join(root, 'scripts/build-release.escript'),
    '--config', config, '--output_dir', path.join(out, 'release')], {
    cwd: root, encoding: 'utf8', timeout: 90000, maxBuffer: 1024 * 1024,
    env: {PATH: '/usr/bin:/bin', LANG: 'C.UTF-8',
        ERL_LIBS: [root + '/deps', root + '/core'].join(':'),
        ERL_FLAGS: '+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang',
        ERL_CRASH_DUMP: path.join(out, 'erl_crash.dump')}
});
fs.writeFileSync(path.join(out, 'stdout.log'), result.stdout || '', {mode: 0o600});
fs.writeFileSync(path.join(out, 'stderr.log'), result.stderr || '', {mode: 0o600});
console.log('Retained release-build evidence: ' + out);
assert(!result.error && !result.signal, 'release helper did not finish normally');
assert.equal(result.status, 0, 'real release escript failed; see private logs');
assert(fs.existsSync(path.join(out, 'release/fixture_release/releases/1.0.0/start.boot')), 'real relx boot output missing');
assert(!fs.existsSync(path.join(out, '.erlang.cookie')), 'build created a cookie');
console.log('PASS real relx release generation without HOME, distributed node or cookie; boot file exists');
