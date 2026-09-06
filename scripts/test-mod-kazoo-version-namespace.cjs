#!/usr/bin/env node
'use strict';
// Offline source regression: actual installer helpers, local Git objects only.
// Usage: node scripts/test-mod-kazoo-version-namespace.cjs /absolute/local/mod_kazoo
// No compiler, fetch, full-installer sourcing or live source mutation.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const ref = '0878e13e02db5db7bde765d61a9453b3cf279399';
const names = [
    'fetch-reply-ownership', 'thread-lifecycle', 'worker-shutdown-synchronization',
    'cookie-redaction', 'prefixes-serialization', 'fetch-channel-data', 'fetch-log-redaction',
    'originate-compatibility', 'reply-completeness', 'sync-command-protocol',
    'originate-reconcile', 'hold-dtmf-events', 'version-namespace', 'atomic-intercept'
].map(name => `mod-kazoo-${name}.patch`);
const aggregateNames = ['mod-kazoo-before-version.patch', 'mod-kazoo-kz5-integration.patch'];
const [sourceRepo, ...extra] = process.argv.slice(2);
assert(sourceRepo && path.isAbsolute(sourceRepo) && !extra.length,
    'Usage: node test-mod-kazoo-version-namespace.cjs /absolute/local/mod_kazoo');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-version-namespace.'));
fs.chmodSync(out, 0o700);
const env = { PATH: '/usr/bin:/bin', LC_ALL: 'C', TMPDIR: out,
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null',
    GIT_ATTR_NOSYSTEM: '1', GIT_NO_REPLACE_OBJECTS: '1', GIT_TERMINAL_PROMPT: '0' };
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const read = file => fs.readFileSync(file, 'utf8');
const write = (file, data) => fs.writeFileSync(file, data, { flag: 'wx', mode: 0o600 });
const inputs = [__filename, path.join(__dirname, 'install-kazoo5.sh'),
    ...[...names, ...aggregateNames].map(name => path.join(__dirname, 'patches', name))];
const pins = {}; const results = []; let commandId = 0, completed = false;
function run(bin, args, options = {}) {
    const result = spawnSync(bin, args, { cwd: out, env, encoding: 'utf8',
        timeout: 10000, maxBuffer: 4 * 1024 * 1024, ...options });
    const label = String(++commandId).padStart(3, '0');
    write(path.join(out, `${label}.stdout.log`), result.stdout || '');
    write(path.join(out, `${label}.stderr.log`), result.stderr || '');
    write(path.join(out, `${label}.command.json`), JSON.stringify({ bin, args,
        status: result.status, signal: result.signal, error: result.error?.code || null }, null, 2) + '\n');
    assert(!result.error && !result.signal, `command ${label} did not complete normally`);
    return result;
}
function success(result) { assert.equal(result.status, 0, result.stderr); return result.stdout; }
function git(...args) { return success(run('/usr/bin/git', args)); }
function test(name, fn) { fn(); results.push(name); console.log(`PASS ${name}`); }
function tree(root) {
    const value = {};
    function visit(dir) {
        for (const name of fs.readdirSync(dir).sort()) {
            const file = path.join(dir, name), st = fs.lstatSync(file), rel = path.relative(root, file);
            assert(!st.isSymbolicLink(), `unexpected fixture symlink: ${rel}`);
            if (st.isDirectory()) visit(file);
            else { assert(st.isFile()); value[rel] = { sha256: sha(file), mode: st.mode & 0o777 }; }
        }
    }
    visit(root); return value;
}
try {
    for (const file of inputs) {
        assert(fs.lstatSync(file).isFile() && !fs.lstatSync(file).isSymbolicLink());
        pins[file] = sha(file);
    }
    write(path.join(out, 'inputs-before.json'), JSON.stringify(pins, null, 2) + '\n');
    const installer = read(inputs[1]);
    function extract(name) {
        const matches = installer.match(new RegExp(`^${name}\\(\\) \\{\\n[\\s\\S]*?^\\}\\n`, 'gm'));
        assert.equal(matches?.length, 1, `exact actual helper ${name}`);
        return matches[0];
    }
    const prepare = extract('prepare_mod_kazoo_source'), fingerprint = extract('freeswitch_build_fingerprint');
    const integrations = installer.match(/^apply_kazoo_integration_patch\(\) \(\n[\s\S]*?^\)\n/gm);
    assert.equal(integrations?.length, 1, 'exact actual integration helper');
    const helper = path.join(out, 'actual-helpers.sh'); write(helper, integrations[0] + '\n' + prepare + '\n' + fingerprint);
    const patchDir = path.join(out, 'scripts/patches'); fs.mkdirSync(patchDir, { recursive: true, mode: 0o700 });
    for (const name of [...names, ...aggregateNames]) fs.copyFileSync(path.join(__dirname, 'patches', name), path.join(patchDir, name));
    test('actual helper requires all 14 patches and namespace/intercept fingerprints', () => {
        assert.deepEqual([...prepare.matchAll(/\$SCRIPT_DIR\/patches\/([^"\n]+)/g)].map(m => m[1]), names);
        assert.equal((fingerprint.match(/\+version-namespace-v1/g) || []).length, 1);
        assert.equal((fingerprint.match(/\+atomic-intercept-v1/g) || []).length, 1);
        assert(installer.includes(`MOD_KAZOO_REF=\${MOD_KAZOO_REF:-${ref}}`));
    });
    assert.equal(git('-C', sourceRepo, 'rev-parse', `${ref}^{commit}`).trim(), ref);
    const entries = git('-C', sourceRepo, 'ls-tree', '-r', ref).trim().split('\n');
    assert(entries.length > 0);
    for (const entry of entries) {
        const match = entry.match(/^100(?:644|755) blob [0-9a-f]{40}\t(.+)$/); assert(match);
        assert(!path.isAbsolute(match[1]) && !match[1].split('/').some(x => x === '..' || x === '.git'));
    }
    write(path.join(out, 'baseline-git-tree.txt'), entries.join('\n') + '\n');
    const archive = path.join(out, 'baseline.tar');
    git('-C', sourceRepo, 'archive', '--format=tar', `--output=${archive}`, ref);
    const fsRoot = path.join(out, 'freeswitch'), moduleDir = path.join(fsRoot, 'src/mod/outoftree/mod_kazoo');
    fs.mkdirSync(moduleDir, { recursive: true, mode: 0o700 });
    success(run('/usr/bin/tar', ['-xf', archive, '-C', moduleDir]));
    const baseline = tree(moduleDir);
    const shell = `set -euo pipefail
die(){ printf '%s\\n' "$*" >&2; exit 1; }
log(){ printf '%s\\n' "$*"; }
sync_git(){
 [[ $# == 3 && $1 == https://github.com/freeswitch/mod_kazoo.git && $2 == "$FIXTURE_MODULE" && $3 == "$MOD_KAZOO_REF" ]] || exit 90
 [[ -d $2 && $2 == "$FIXTURE_ROOT/src/mod/outoftree/mod_kazoo" ]] || exit 91
}
source "$FIXTURE_HELPER"
prepare_mod_kazoo_source "$FIXTURE_ROOT"
`;
    const helperEnv = { ...env, DRY_RUN: 'false', SCRIPT_DIR: path.dirname(patchDir), MOD_KAZOO_REF: ref,
        FIXTURE_MODULE: moduleDir, FIXTURE_ROOT: fsRoot, FIXTURE_HELPER: helper };
    const prepareRun = (targetRoot = fsRoot) => run('/usr/bin/bash', ['-c', shell], { env: {
        ...helperEnv, FIXTURE_ROOT: targetRoot, FIXTURE_MODULE: path.join(targetRoot, 'src/mod/outoftree/mod_kazoo')
    } });
    function completeIntercept(target) {
        const patch = read(path.join(patchDir, names.at(-1)));
        const first = patch.slice(patch.indexOf('@@ -0,0 +1,142 @@\n') + '@@ -0,0 +1,142 @@\n'.length,
            patch.indexOf('diff --git a/kazoo_dptools.c'));
        assert.equal(first.split('\n').filter(line => line.startsWith('+')).length, 142);
        assert.equal(read(path.join(target, 'kazoo_intercept.h')),
            first.split('\n').filter(line => line.startsWith('+')).map(line => line.slice(1)).join('\n') + '\n');
        const app = read(path.join(target, 'kazoo_dptools.c'));
        assert.equal((app.match(/#include "kazoo_intercept\.h"/g) || []).length, 1);
        assert.equal((app.match(/\tkz_intercept_start\(\);/g) || []).length, 1);
        assert.equal((app.match(/SWITCH_ADD_APP\(app_interface, "kz_intercept",/g) || []).length, 1);
        assert.equal((read(path.join(target, 'mod_kazoo.h')).match(/void remove_kz_dptools\(void\);/g) || []).length, 1);
        const module = read(path.join(target, 'mod_kazoo.c'));
        assert.equal((module.match(/\tremove_kz_dptools\(\);/g) || []).length, 1);
        assert(module.indexOf('remove_kz_dptools();') < module.indexOf('kz_cdr_stop();'));
        assert(!app.includes('switch_ivr_owned_audio'), 'baseline integration must not enable the private owned-audio path');
    }
    test('actual prepare helper applies every patch to the pinned local baseline', () => {
        const log = success(prepareRun());
        assert(log.includes('Applied mod_kazoo integration from clean after private preflight'));
        const independent = path.join(out, 'independent-series'); fs.mkdirSync(independent, { mode: 0o700 });
        success(run('/usr/bin/tar', ['-xf', archive, '-C', independent]));
        for (const name of names) git('-C', independent, 'apply', path.join(patchDir, name));
        assert.deepEqual(tree(moduleDir), tree(independent), 'aggregate must equal all 14 sequential source patches');
        completeIntercept(moduleDir);
    });
    const prepared = tree(moduleDir);
    test('repeat actual prepare preserves complete intercept header/registration/shutdown and all 14 patches', () => {
        const log = success(prepareRun());
        assert(log.includes('Required mod_kazoo integration is already current'));
        assert.deepEqual(tree(moduleDir), prepared);
        completeIntercept(moduleDir);
    });
    const versionOnly = path.join(out, 'before-atomic-intercept'); fs.cpSync(moduleDir, versionOnly, { recursive: true });
    git('-C', versionOnly, 'apply', '--reverse', path.join(patchDir, names.at(-1)));
    const namespaced = tree(versionOnly);
    const previous = path.join(out, 'before-version-namespace'); fs.cpSync(versionOnly, previous, { recursive: true });
    git('-C', previous, 'apply', '--reverse', path.join(patchDir, names.at(-2)));
    const beforeVersion = tree(previous);
    test('previous aggregate equals all 12 preceding source patches', () => {
        const independent = path.join(out, 'independent-previous'); fs.mkdirSync(independent, { mode: 0o700 });
        success(run('/usr/bin/tar', ['-xf', archive, '-C', independent]));
        for (const name of names.slice(0, -2)) git('-C', independent, 'apply', path.join(patchDir, name));
        assert.deepEqual(tree(previous), tree(independent));
        git('-C', independent, 'apply', '--reverse', '--check', path.join(patchDir, aggregateNames[0]));
        const aggregateOnly = path.join(out, 'previous-aggregate-only'); fs.mkdirSync(aggregateOnly, { mode: 0o700 });
        success(run('/usr/bin/tar', ['-xf', archive, '-C', aggregateOnly]));
        git('-C', aggregateOnly, 'apply', path.join(patchDir, aggregateNames[0]));
        assert.deepEqual(tree(aggregateOnly), tree(independent));
    });
    test('known previous integration upgrades and preserves an unrelated source edit', () => {
        const previousRoot = path.join(out, 'previous-freeswitch');
        const target = path.join(previousRoot, 'src/mod/outoftree/mod_kazoo');
        fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
        fs.cpSync(previous, target, { recursive: true });
        const extra = '\n/* preserved unrelated fixture annotation */\n';
        fs.appendFileSync(path.join(target, 'kazoo_api.c'), extra);
        const log = success(prepareRun(previousRoot));
        assert(log.includes('Applied mod_kazoo integration from previous after private preflight'));
        for (const file of Object.keys(prepared)) {
            assert.equal(read(path.join(target, file)), read(path.join(moduleDir, file)) + (file === 'kazoo_api.c' ? extra : ''));
        }
        const upgraded = tree(target);
        assert(success(prepareRun(previousRoot)).includes('Required mod_kazoo integration is already current'));
        assert.deepEqual(tree(target), upgraded);
        completeIntercept(target);
    });
    for (const kind of ['namespace-only', 'intercept-only']) {
        test(`known ${kind} integration upgrades only the missing delta and remains repeatable`, () => {
            const targetRoot = path.join(out, kind + '-freeswitch');
            const target = path.join(targetRoot, 'src/mod/outoftree/mod_kazoo');
            fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
            fs.cpSync(kind === 'namespace-only' ? versionOnly : previous, target, { recursive: true });
            if (kind === 'intercept-only') git('-C', target, 'apply', path.join(patchDir, names.at(-1)));
            const retainedFile = kind === 'namespace-only' ? 'kazoo_ei.h' : 'kazoo_intercept.h';
            const retainedHash = sha(path.join(target, retainedFile));
            assert(success(prepareRun(targetRoot)).includes('Applied mod_kazoo integration from previous after private preflight'));
            assert.equal(sha(path.join(target, retainedFile)), retainedHash);
            assert.deepEqual(tree(target), prepared); completeIntercept(target);
            assert(success(prepareRun(targetRoot)).includes('Required mod_kazoo integration is already current'));
            assert.deepEqual(tree(target), prepared);
        });
    }
    test('partial source integration is rejected without completing it implicitly', () => {
        const partialRoot = path.join(out, 'partial-freeswitch');
        const target = path.join(partialRoot, 'src/mod/outoftree/mod_kazoo');
        fs.mkdirSync(target, { recursive: true, mode: 0o700 });
        success(run('/usr/bin/tar', ['-xf', archive, '-C', target]));
        git('-C', target, 'apply', path.join(patchDir, names[0]));
        const partial = tree(target), result = prepareRun(partialRoot);
        assert.notEqual(result.status, 0);
        assert(result.stderr.includes('Source is neither the clean, current nor explicitly supported previous integration'));
        assert.deepEqual(tree(target), partial);
    });
    const consumers = ['kazoo_api.c', 'kazoo_fetch_agent.c', 'kazoo_node.c'];
    test('namespace patch changes only the four exact identifiers, preserving external bytes', () => {
        assert.deepEqual(Object.keys(namespaced), Object.keys(beforeVersion));
        assert.deepEqual(Object.keys(namespaced).filter(file => namespaced[file].sha256 !== beforeVersion[file].sha256).sort(),
            ['kazoo_ei.h', ...consumers].sort());
        for (const file of ['kazoo_ei.h', ...consumers]) {
            const before = read(path.join(previous, file)), after = read(path.join(versionOnly, file));
            assert.equal((before.match(/\bVERSION\b/g) || []).length, 1, file);
            assert.equal(after, before.replace(/\bVERSION\b/, 'KAZOO_MODULE_VERSION'), file);
            assert.equal(namespaced[file].mode, beforeVersion[file].mode);
        }
        assert(read(path.join(moduleDir, 'kazoo_ei.h')).includes('#define KAZOO_MODULE_VERSION "mod_kazoo v1.5.0-1 community"\n'));
    });
    test('generic package VERSION configuration remains untouched', () => {
        for (const file of ['configure.ac', 'Makefile.am']) assert.deepEqual(prepared[file], baseline[file], file);
        assert(!/^\s*#\s*(?:define|undef)\s+VERSION\b/m.test(read(path.join(moduleDir, 'kazoo_ei.h'))));
        // Source identity, not a synthetic C evaluator: configured package macros
        // remain independent; real-header compiler proof is a separate suite.
        assert(read(path.join(moduleDir, 'configure.ac')).startsWith(
            'AC_INIT([freeswitch_standalone_module], [1.7.0], bugs@freeswitch.org)\n'));
    });
    test('actual fingerprint changes only its mod_kazoo line for the new version namespace', () => {
        const fpEnv = { ...env, FREESWITCH_VERSION: 'fixture-version', FREESWITCH_REF: 'a'.repeat(40),
            MOD_KAZOO_REF: ref, SOFIA_SIP_REF: 'b'.repeat(40), SPANDSP_REF: 'c'.repeat(40) };
        const current = success(run('/usr/bin/bash', ['-c', `set -euo pipefail\n${fingerprint}\nfreeswitch_build_fingerprint`], { env: fpEnv }));
        const old = success(run('/usr/bin/bash', ['-c', `set -euo pipefail\n${fingerprint.replace('+version-namespace-v1', '')}\nfreeswitch_build_fingerprint`], { env: fpEnv }));
        assert.notEqual(current, old); assert.equal(current.replace('+version-namespace-v1', ''), old);
        assert.equal(current.split('\n').filter(line => line.includes('version-namespace-v1')).length, 1);
        assert(current.split('\n').find(line => line.includes('version-namespace-v1')).startsWith(`mod_kazoo=${ref}+`));
    });
    test('missing required namespace patch fails without changing the prepared source', () => {
        const patch = path.join(patchDir, names.at(-2)); fs.renameSync(patch, patch + '.held');
        try { const result = prepareRun(); assert.notEqual(result.status, 0); assert(result.stderr.includes('Required mod_kazoo patch is missing:')); }
        finally { fs.renameSync(patch + '.held', patch); }
        assert.deepEqual(tree(moduleDir), prepared);
    });
    test('atomic-intercept fingerprint changes the build marker without changing other components', () => {
        const fpEnv = { ...env, FREESWITCH_VERSION: 'fixture-version', FREESWITCH_REF: 'a'.repeat(40),
            MOD_KAZOO_REF: ref, SOFIA_SIP_REF: 'b'.repeat(40), SPANDSP_REF: 'c'.repeat(40) };
        const current = success(run('/usr/bin/bash', ['-c', `set -euo pipefail\n${fingerprint}\nfreeswitch_build_fingerprint`], { env: fpEnv }));
        const old = success(run('/usr/bin/bash', ['-c', `set -euo pipefail\n${fingerprint.replace('+atomic-intercept-v1', '')}\nfreeswitch_build_fingerprint`], { env: fpEnv }));
        assert.notEqual(current, old); assert.equal(current.replace('+atomic-intercept-v1', ''), old);
        assert.equal(current.split('\n').filter(line => line.includes('atomic-intercept-v1')).length, 1);
        assert(current.split('\n').find(line => line.includes('atomic-intercept-v1')).startsWith(`mod_kazoo=${ref}+`));
    });
    test('missing required atomic patch fails without changing current source', () => {
        const patch = path.join(patchDir, names.at(-1)); fs.renameSync(patch, patch + '.held');
        try { const result = prepareRun(); assert.notEqual(result.status, 0); assert(result.stderr.includes('Required mod_kazoo patch is missing:')); }
        finally { fs.renameSync(patch + '.held', patch); }
        assert.deepEqual(tree(moduleDir), prepared);
    });
    for (const kind of ['missing-header', 'missing-shutdown-cleanup']) {
        test(`partial intercept ${kind} fails with no implicit repair or target mutation`, () => {
            const targetRoot = path.join(out, kind + '-freeswitch');
            const target = path.join(targetRoot, 'src/mod/outoftree/mod_kazoo');
            fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
            fs.cpSync(moduleDir, target, { recursive: true });
            if (kind === 'missing-header') fs.unlinkSync(path.join(target, 'kazoo_intercept.h'));
            else {
                const file = path.join(target, 'mod_kazoo.c');
                fs.writeFileSync(file, read(file).replace('\tremove_kz_dptools();\n', ''));
            }
            const damaged = tree(target), result = prepareRun(targetRoot);
            assert.notEqual(result.status, 0); assert.deepEqual(tree(target), damaged);
        });
    }
    test('missing aggregate fails without changing the prepared source', () => {
        const patch = path.join(patchDir, aggregateNames[1]); fs.renameSync(patch, patch + '.held');
        try {
            const result = prepareRun(); assert.notEqual(result.status, 0);
            assert(result.stderr.includes('Required integration input is missing, linked or unsafe'));
            assert.deepEqual(tree(moduleDir), prepared);
        } finally { fs.renameSync(patch + '.held', patch); }
    });
    test('symlinked explicit module source is rejected without touching its target', () => {
        const linkedRoot = path.join(out, 'linked-freeswitch');
        const linkedModule = path.join(linkedRoot, 'src/mod/outoftree/mod_kazoo');
        fs.mkdirSync(path.dirname(linkedModule), { recursive: true, mode: 0o700 });
        fs.symlinkSync(moduleDir, linkedModule);
        const result = prepareRun(linkedRoot); assert.notEqual(result.status, 0);
        assert(result.stderr.includes('Unsafe Kazoo integration source directory'));
        assert.equal(fs.readlinkSync(linkedModule), moduleDir);
        assert.deepEqual(tree(moduleDir), prepared);
    });
    test('hardlinked source is rejected even when its patch state is current', () => {
        const target = path.join(moduleDir, 'kazoo_api.c'), alias = path.join(out, 'hardlink-sentinel.c');
        fs.linkSync(target, alias);
        try {
            const result = prepareRun(); assert.notEqual(result.status, 0);
            assert(result.stderr.includes('Required integration input is missing, linked or unsafe'));
            assert.equal(fs.statSync(target).nlink, 2);
            assert.equal(sha(alias), prepared['kazoo_api.c'].sha256);
            assert.deepEqual(tree(moduleDir), prepared);
        } finally { fs.unlinkSync(alias); }
    });
    test('out-of-inventory aggregate source path is rejected before writing', () => {
        const patch = path.join(patchDir, aggregateNames[1]), original = read(patch);
        fs.appendFileSync(patch, '\ndiff --git a/unexpected.c b/unexpected.c\nnew file mode 100644\n--- /dev/null\n+++ b/unexpected.c\n@@ -0,0 +1 @@\n+unexpected mutation\n');
        try {
            const result = prepareRun(); assert.notEqual(result.status, 0);
            assert(result.stderr.includes('Integration patch has an unexpected source path'));
            assert.deepEqual(tree(moduleDir), prepared);
        } finally { fs.writeFileSync(patch, original); }
    });
    test('a changed module version is not silently treated as already patched', () => {
        const header = path.join(moduleDir, 'kazoo_ei.h'), current = read(header);
        fs.writeFileSync(header, current.replace('"mod_kazoo v1.5.0-1 community"', '"fixture changed module version"'));
        const changed = tree(moduleDir); assert.notDeepEqual(changed, prepared);
        const result = prepareRun(); assert.notEqual(result.status, 0);
        assert(result.stderr.includes('Source is neither the clean, current nor explicitly supported previous integration'));
        assert.deepEqual(tree(moduleDir), changed);
    });
    completed = true;
} catch (error) {
    console.error(error.stack); process.exitCode = 1;
} finally {
    let unchanged = Object.keys(pins).length === inputs.length;
    for (const [file, expected] of Object.entries(pins)) {
        try { if (sha(file) !== expected) unchanged = false; } catch { unchanged = false; }
    }
    if (!unchanged) { console.error('FAIL shared input changed during regression'); process.exitCode = 99; }
    const receipt = { status: completed && unchanged && !process.exitCode ? 'pass' : 'failed',
        completed, cases: results.length, passed: results, inputs_unchanged: unchanged,
        baseline_ref: ref, baseline_repo: sourceRepo, scope: 'offline actual installer patch/source contracts',
        sync_git: 'fixture substitute; no fetch/reset', compiler: false, live_mutation: false, inputs: pins };
    write(path.join(out, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
    console.log(`Retained evidence: ${out}`);
}
