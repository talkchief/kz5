'use strict';
// SPDX-License-Identifier: MPL-2.0
// Execute the actual extracted EXIT handler with stubs. No files, processes,
// registrations, calls, services, API resources or credentials are touched.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'test-acdc-callback-calls.sh'), 'utf8');
const match = /^callback_cleanup\(\) \{\n[\s\S]*?^\}/m.exec(source);
assert(match, 'Cannot find exact callback cleanup function');
const definition = match[0];
const callId = '1-777@127.0.0.20';
function run(options = {}) {
    const script = `
set -Eeuo pipefail
exec 3>&1
trace() { printf '%s\\n' "$*" >&3; }
kill() { trace "kill $*"; return 0; }
wait() { trace "wait $*"; return 0; }
best_effort_clear_acceptance_calls() { trace 'clear-owned-calls'; }
best_effort_deregister_agents() { trace "deregister-owned-agents $*"; }
best_effort_deregister_caller() { trace "deregister-owned-caller $*"; }
agent_status() { trace "agent-status $*"; }
warn() { trace "warning $*"; }
find() { trace "find $*"; }
callback_fixture() {
    trace "fixture $*"
    if [[ $1 == cancel-original ]]; then return "$CANCEL_RESULT"; fi
    if [[ $1 == cleanup ]]; then return "$CLEANUP_RESULT"; fi
    trace 'unexpected-fixture-action'; return 91
}
ACTIVE_PIDS=(777 not-a-pid)
CALLBACK_FIXTURE_HELPER=/private/owned-fixture-helper
CALLER_PORT=15064
${definition}
trap callback_cleanup EXIT
exit "$INITIAL_RESULT"
`;
    const result = cp.spawnSync('bash', ['--noprofile', '--norc', '-s'], {input: script, encoding: 'utf8', timeout: 10000,
        env: {PATH: '/usr/bin:/bin', LANG: 'C', INITIAL_RESULT: String(options.initial || 0),
            CANCEL_RESULT: String(options.cancel || 0), CLEANUP_RESULT: String(options.cleanup || 0),
            CALLBACK_CLEANING: String(options.cleaning || false), CALLBACK_LIVE: String(options.live !== false),
            RUN_DIR: options.runDir === undefined ? '/private/fixture-run' : options.runDir,
            AGENTS_REGISTERED: '2', CALLER_REGISTERED: 'true', STATUS_AGENT_MAX: '2',
            FIXTURE_CREATED: String(options.fixture !== false), KEEP_FIXTURE: String(options.keep || false),
            CALLBACK_ORIGINAL_CALL_ID: options.callId === undefined ? callId : options.callId}});
    assert.equal(result.signal, null, 'Private shell unexpectedly signalled or timed out');
    assert.equal(result.error, undefined, 'Private shell could not run');
    return {status: result.status, actions: result.stdout.trim().split('\n').filter(Boolean), stderr: result.stderr};
}
let passed = 0;
function test(name, body) { body(); passed++; console.log('PASS: ' + name); }
test('A successful call gate exits0 only after exact cancellation and owned fixture cleanup succeed', () => {
    const item = run(); assert.equal(item.status, 0, item.stderr);
    assert(item.actions.includes('fixture cancel-original ' + callId));
    assert(item.actions.includes('fixture cleanup'));
    assert(item.actions.indexOf('fixture cancel-original ' + callId) < item.actions.indexOf('fixture cleanup'));
    assert(item.actions.includes('deregister-owned-agents 2'));
    assert(item.actions.includes('deregister-owned-caller 15064 callback-cleanup-caller'));
    assert(item.actions.includes('agent-status logout 1 2'));
    assert.deepEqual(item.actions.filter(action => action.startsWith('kill ')), ['kill -0 777', 'kill 777']);
    assert.deepEqual(item.actions.filter(action => action.startsWith('wait ')), ['wait 777']);
    assert(item.actions.includes('find /private/fixture-run -maxdepth 1 -type f -name *-input.csv -delete'));
});
test('Cancellation failure changes successful exit to1 and retains resources for safe settlement', () => {
    const item = run({cancel: 7}); assert.equal(item.status, 1);
    assert(item.actions.includes('fixture cancel-original ' + callId));
    assert(!item.actions.includes('fixture cleanup'));
    assert(item.actions.some(action => action.includes('unresolved settlement')));
});
test('Owned fixture cleanup failure changes successful exit to1 instead of warning-only success', () => {
    const item = run({cleanup: 9}); assert.equal(item.status, 1);
    assert(item.actions.includes('fixture cleanup'));
    assert(item.actions.some(action => action.includes('Fixture cleanup needs attention')));
});
test('Existing nonzero call-gate failures are preserved regardless of cleanup outcome', () => {
    for (const initial of [3, 42, 130, 143]) for (const failures of [{}, {cancel: 7}, {cleanup: 9}]) {
        const item = run({initial, ...failures}); assert.equal(item.status, initial);
    }
});
test('Explicit fixture retention skips removal but does not hide cancellation failure', () => {
    const retained = run({keep: true}); assert.equal(retained.status, 0);
    assert(retained.actions.includes('fixture cancel-original ' + callId));
    assert(!retained.actions.includes('fixture cleanup'));
    const failed = run({keep: true, cancel: 7}); assert.equal(failed.status, 1);
    assert(!failed.actions.includes('fixture cleanup'));
    assert.equal(run({keep: true, cleanup: 9}).status, 0, 'Unrequested cleanup is not a failure');
});
test('Nonlive, missing-run, absent-fixture and no-original-call paths retain exact no-op scopes', () => {
    for (const options of [{live: false}, {runDir: ''}, {fixture: false}]) {
        const item = run({...options, cancel: 7, cleanup: 9}); assert.equal(item.status, 0);
        assert(!item.actions.some(action => action.startsWith('fixture ')));
    }
    const noCall = run({callId: '', cancel: 7}); assert.equal(noCall.status, 0);
    assert(!noCall.actions.some(action => action.startsWith('fixture cancel-original ')));
    assert(noCall.actions.includes('fixture cleanup'));
    assert.equal(run({callId: '', cleanup: 9}).status, 1);
});
test('Reentrant cleanup returns without duplicate actions or losing the original failure', () => {
    for (const initial of [0, 42]) {
        const item = run({cleaning: true, initial}); assert.equal(item.status, initial); assert.deepEqual(item.actions, []);
    }
});
console.log('PASS: ' + passed + ' private extracted-handler groups; real EXIT statuses tested, no mutations');
