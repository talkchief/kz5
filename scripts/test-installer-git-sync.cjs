#!/usr/bin/env node
'use strict';
// Actual Git fetch/checkout using a new local fixture repository, never GitHub.
// No full installer sourcing, services, credentials, or live checkout writes.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
assert.equal(process.argv.length, 2, 'This regression takes no arguments');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-git-sync.'));
fs.chmodSync(out, 0o700);
const installer = path.join(__dirname, 'install-kazoo5.sh');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const pins = Object.fromEntries([__filename, installer].map(file => [file, hash(file)]));
const env = { PATH: '/usr/bin:/bin', LC_ALL: 'C', TMPDIR: out,
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null',
    GIT_TERMINAL_PROMPT: '0', GIT_NO_REPLACE_OBJECTS: '1',
    GIT_AUTHOR_NAME: 'Installer regression', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
    GIT_COMMITTER_NAME: 'Installer regression', GIT_COMMITTER_EMAIL: 'fixture@example.invalid' };
let sequence = 0, complete = false;
const passed = [];
function run(bin, args, extra = {}) {
    const result = spawnSync(bin, args, { cwd: out, env: { ...env, ...extra }, encoding: 'utf8',
        timeout: 15000, maxBuffer: 1024 * 1024 });
    fs.writeFileSync(path.join(out, `${++sequence}.json`), JSON.stringify({ bin, args,
        status: result.status, signal: result.signal, error: result.error?.code,
        stdout: result.stdout, stderr: result.stderr }, null, 2), { flag: 'wx', mode: 0o600 });
    assert(!result.error && !result.signal, 'subprocess did not complete normally');
    return result;
}
function ok(result) { assert.equal(result.status, 0, result.stderr); return result.stdout.trim(); }
const git = (...args) => ok(run('/usr/bin/git', args));
function test(label, fn) { fn(); passed.push(label); console.log(`PASS ${label}`); }
try {
    const source = fs.readFileSync(installer, 'utf8');
    const matches = source.match(/^sync_git\(\) (?:\{|\()\n[\s\S]*?^[})]\n/gm);
    assert.equal(matches?.length, 1);
    const helper = path.join(out, 'actual-helper.sh');
    fs.writeFileSync(helper, matches[0], { flag: 'wx', mode: 0o600 });
    const origin = path.join(out, 'origin'), target = path.join(out, 'target');
    fs.mkdirSync(origin, { mode: 0o700 });
    git('-C', origin, 'init', '--quiet', '--initial-branch=master');
    fs.writeFileSync(path.join(origin, 'tracked.txt'), 'first\n');
    git('-C', origin, 'add', 'tracked.txt'); git('-C', origin, 'commit', '--quiet', '-m', 'first');
    const first = git('-C', origin, 'rev-parse', 'HEAD');
    fs.writeFileSync(path.join(origin, 'tracked.txt'), 'second\n');
    git('-C', origin, 'commit', '--quiet', '-am', 'second');
    const second = git('-C', origin, 'rev-parse', 'HEAD');
    const invoke = (ref, destination = target, extra = {}) => run('/bin/bash', ['-c', `
set -euo pipefail
die(){ printf 'FIXTURE-DIE %s\\n' "$*" >&2; exit 65; }
log(){ printf '%s\\n' "$*"; }
run(){ if [[ $DRY_RUN == true ]]; then return 0; else "$@"; fi; }
source "$FIXTURE_HELPER"
# Conditional callers disable errexit inside functions: explicit failures matter.
if sync_git "$FIXTURE_ORIGIN" "$FIXTURE_TARGET" "$FIXTURE_REF"; then exit 0; else exit 65; fi
`], { FIXTURE_HELPER: helper, FIXTURE_ORIGIN: origin, FIXTURE_TARGET: destination,
        FIXTURE_REF: ref, DRY_RUN: 'false', ...extra });
    test('fresh checkout fetches and checks out the exact requested commit', () => {
        ok(invoke(first)); assert.equal(git('-C', target, 'rev-parse', 'HEAD'), first);
        assert.equal(fs.readFileSync(path.join(target, 'tracked.txt'), 'utf8'), 'first\n');
    });
    test('repeat same-pin checkout preserves tracked edits and untracked files', () => {
        fs.writeFileSync(path.join(target, 'tracked.txt'), 'local edit\n');
        fs.writeFileSync(path.join(target, 'untracked.txt'), 'preserved\n');
        ok(invoke(first));
        assert.equal(git('-C', target, 'rev-parse', 'HEAD'), first);
        assert.equal(fs.readFileSync(path.join(target, 'tracked.txt'), 'utf8'), 'local edit\n');
        assert.equal(fs.readFileSync(path.join(target, 'untracked.txt'), 'utf8'), 'preserved\n');
    });
    test('failed fetch cannot report success using a stale FETCH_HEAD', () => {
        const result = invoke('f'.repeat(40)); assert.equal(result.status, 65, result.stderr);
        assert.equal(git('-C', target, 'rev-parse', 'HEAD'), first);
        assert.equal(fs.readFileSync(path.join(target, 'tracked.txt'), 'utf8'), 'local edit\n');
        assert.equal(fs.readFileSync(path.join(target, 'untracked.txt'), 'utf8'), 'preserved\n');
    });
    test('failed fresh fetch cannot report an initialized directory as installed source', () => {
        const freshFailure = path.join(out, 'failed-fresh');
        assert.equal(invoke('f'.repeat(40), freshFailure).status, 65);
        assert.equal(fs.existsSync(path.join(freshFailure, 'tracked.txt')), false);
    });
    test('retry after a failed initial fetch installs the exact pin', () => {
        const retry = path.join(out, 'failed-fresh'); ok(invoke(first, retry));
        assert.equal(git('-C', retry, 'rev-parse', 'HEAD'), first);
        assert.equal(fs.readFileSync(path.join(retry, 'tracked.txt'), 'utf8'), 'first\n');
    });
    test('failed branch clone reports failure instead of success', () => {
        const destination = path.join(out, 'failed-branch');
        assert.equal(invoke('missing-fixture-branch', destination).status, 65);
        assert.equal(fs.existsSync(path.join(destination, 'tracked.txt')), false);
    });
    test('branch clone still installs the requested branch', () => {
        const destination = path.join(out, 'branch'); ok(invoke('master', destination));
        assert.equal(git('-C', destination, 'rev-parse', 'HEAD'), second);
        assert.equal(git('-C', destination, 'symbolic-ref', '--short', 'HEAD'), 'master');
    });
    test('conflicting upgrade fails without discarding local edits', () => {
        assert.equal(invoke(second).status, 65);
        assert.equal(git('-C', target, 'rev-parse', 'HEAD'), first);
        assert.equal(fs.readFileSync(path.join(target, 'tracked.txt'), 'utf8'), 'local edit\n');
        assert.equal(fs.readFileSync(path.join(target, 'untracked.txt'), 'utf8'), 'preserved\n');
    });
    test('clean source upgrades to the exact new pin', () => {
        const clean = path.join(out, 'clean'); ok(invoke(first, clean)); ok(invoke(second, clean));
        assert.equal(git('-C', clean, 'rev-parse', 'HEAD'), second);
        assert.equal(fs.readFileSync(path.join(clean, 'tracked.txt'), 'utf8'), 'second\n');
    });
    test('fresh dry run creates no checkout', () => {
        const absent = path.join(out, 'absent'); ok(invoke(first, absent, { DRY_RUN: 'true' }));
        assert.equal(fs.existsSync(absent), false);
    });
    complete = true;
} catch (error) { console.error(error.stack); process.exitCode = 1; }
finally {
    const stable = Object.entries(pins).every(([file, expected]) => hash(file) === expected);
    if (!stable) process.exitCode = 99;
    fs.writeFileSync(path.join(out, 'receipt.json'), JSON.stringify({
        status: complete && stable && !process.exitCode ? 'pass' : 'failed', complete,
        inputs_unchanged: stable, inputs: pins, passed, scope: 'actual Git, new local fixtures only'
    }, null, 2), { flag: 'wx', mode: 0o600 });
    console.log(`Retained evidence: ${out}`);
}
