'use strict';
// Real SUP completion generator over existing BEAMs; no SUP calls or services.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const fixtureEnv = {PATH: '/usr/bin:/bin', LANG: 'C.UTF-8',
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'};
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-sup-completion.'));
fs.chmodSync(dir, 0o700);
const helperFile = 'sup/priv/build-autocomplete.escript';
const replay = path.join(dir, 'replay');
fs.mkdirSync(path.join(replay, 'sup/priv'), {recursive: true});
const ref = '5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72';
const before = cp.execFileSync('git', ['show', ref + ':' + helperFile], {cwd: path.join(root, 'core'), env: fixtureEnv});
const target = path.join(replay, helperFile);
fs.writeFileSync(target, before, {mode: 0o755});
const installer = fs.readFileSync(path.join(root, 'scripts/install-kazoo5.sh'), 'utf8');
const applyHelper = installer.match(/^apply_required_source_patch\(\) \{\n[\s\S]*?^\}/m);
assert(applyHelper);
assert(installer.includes('apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-sup-completion-local-build.patch"'));
const patch = path.join(root, 'scripts/patches/kazoo-sup-completion-local-build.patch');
function applyPatch() {
    cp.execFileSync('/usr/bin/bash', ['--noprofile', '--norc', '-euc', 'DRY_RUN=false\nlog() { :; }\ndie() { exit 65; }\n' + applyHelper[0] + '\napply_required_source_patch "$1" "$2"', 'fixture', replay, patch], {env: fixtureEnv});
}
applyPatch(); applyPatch();
assert.deepEqual(fs.readFileSync(target), fs.readFileSync(path.join(root, 'core', helperFile)));
cp.execFileSync('git', ['apply', '--reverse', patch], {cwd: replay, env: fixtureEnv});
assert.deepEqual(fs.readFileSync(target), before);
fs.writeFileSync(target, 'conflicting fixture source\n');
assert.throws(applyPatch, e => e.status === 65);
const output = path.join(dir, 'sup.bash');
const result = cp.spawnSync('/usr/bin/make', ['--no-print-directory', 'sup_completion', 'sup_completion_file=' + output], {
    cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 2 * 1024 * 1024,
    env: {...fixtureEnv,
        ERL_FLAGS: '+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang',
        ERL_CRASH_DUMP: path.join(dir, 'erl_crash.dump')}
});
fs.writeFileSync(path.join(dir, 'stdout.log'), result.stdout || '', {mode: 0o600});
fs.writeFileSync(path.join(dir, 'stderr.log'), result.stderr || '', {mode: 0o600});
console.log('Retained SUP completion evidence: ' + dir);
assert(!result.error && !result.signal, 'completion target did not finish normally');
assert.equal(result.status, 0, 'real completion target failed; see private logs');
const completion = fs.readFileSync(output, 'utf8');
for (const text of ['complete -F _sup sup', 'kapps_controller', 'kapps', 'kazoo_maintenance', 'syslog_level']) {
    assert(completion.includes(text), 'required completion entry missing: ' + text);
}
cp.execFileSync('/usr/bin/bash', ['-n', output]);
assert(!fs.existsSync(path.join(dir, '.erlang.cookie')));
console.log('PASS pinned installer fresh/repeat/reverse/conflict patch replay; actual make sup_completion without HOME; valid Bash with maintenance and kapps commands');
