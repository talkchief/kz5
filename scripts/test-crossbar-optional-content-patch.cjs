'use strict';
// Actual installer helper: pinned fresh tree, repeat install, rollback, conflict.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'crossbar-content-patch.'));
const ref = '2ac862830f9b626d2170d08daf1991b0ca33dba7';
const files = ['src/cb_apps_util.erl', ...['cb_apps_store', 'cb_vmboxes', 'cb_directories'].map(x => `src/modules/${x}.erl`)];
const patch = path.join(__dirname, 'patches/crossbar-optional-content-defaults.patch');
const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const helper = installer.match(/^apply_required_source_patch\(\) \{\n[\s\S]*?^\}/m);
assert(helper);
assert(installer.includes('apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \\\n        "$SCRIPT_DIR/patches/crossbar-optional-content-defaults.patch"'));
function run(command, args, cwd = out, input) {
    return cp.execFileSync(command, args, {cwd, input, stdio: ['pipe', 'pipe', 'pipe']});
}
function apply() {
    return run('/usr/bin/bash', ['-euc', 'DRY_RUN=false\nlog() { :; }\ndie() { exit 65; }\n' + helper[0] + '\napply_required_source_patch "$1" "$2"', 'fixture', out, patch]);
}
try {
    const archive = run('git', ['archive', ref, ...files], path.join(root, 'applications/crossbar'));
    run('tar', ['-xf', '-'], out, archive);
    const before = files.map(f => fs.readFileSync(path.join(out, f)));
    apply(); apply();
    files.forEach(f => assert.deepEqual(fs.readFileSync(path.join(out, f)), fs.readFileSync(path.join(root, 'applications/crossbar', f))));
    run('git', ['apply', '--reverse', patch]);
    files.forEach((f, i) => assert.deepEqual(fs.readFileSync(path.join(out, f)), before[i]));
    fs.writeFileSync(path.join(out, files[0]), 'conflicting fixture source\n');
    assert.throws(apply, e => e.status === 65);
    files.slice(1).forEach((f, i) => assert.deepEqual(fs.readFileSync(path.join(out, f)), before[i + 1]));
    console.log('PASS pinned fresh/repeated patch replay, exact runtime source, reverse, atomic conflict refusal and installer wiring');
} finally { fs.rmSync(out, {recursive: true, force: true}); }
