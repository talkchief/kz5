'use strict';
// SPDX-License-Identifier: MPL-2.0
// Private source/extracted-function regression: no SIP, API, files, credentials,
// live processes or agent state are changed by the mocked shell executions.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const read = name => fs.readFileSync(path.join(__dirname, name), 'utf8');
const source = read('test-acdc-callback-calls.sh'), common = read('test-kazoo-calls.sh');
const carrier = read('sip-tests/callback-returned.xml'), sentinel = read('sip-tests/caller-to-queue.xml');
const agent = read('sip-tests/agent-answer.xml');
const queue = read('../applications/acdc/src/acdc_queue_fsm.erl');
function definition(text, name) {
    const match = new RegExp('^' + name + '\\(\\) \\{\\n[\\s\\S]*?^\\}', 'm').exec(text);
    assert(match, 'Missing function: ' + name); return match[0];
}
function shell(input) {
    const result = cp.spawnSync('bash', ['--noprofile', '--norc', '-s'], {
        input: 'set -Eeuo pipefail\n' + input, encoding: 'utf8', timeout: 10000,
        env: {PATH: '/usr/bin:/bin', LANG: 'C'}});
    assert.equal(result.error, undefined); assert.equal(result.signal, null); return result;
}
const names = ['CALLBACK_SENTINEL_HOLD_MS', 'CALLBACK_CARRIER_CONFIRM_DELAY_MS',
    'CALLBACK_BRIDGE_HOLD_MS', 'CALLBACK_CARRIER_TIMEOUT_S'];
const declarations = names.map(name => {
    const match = source.match(new RegExp('^readonly ' + name + '=[^\\n]+$', 'm'));
    assert(match, 'Missing timing declaration'); return match[0];
}).join('\n');
const evaluated = shell(declarations + '\nprintf "%s\\n" ' + names.map(name => '"$' + name + '"').join(' '));
assert.equal(evaluated.status, 0, evaluated.stderr);
const [sentinelHold, confirmDelay, bridgeHold, processSeconds] = evaluated.stdout.trim().split('\n').map(Number);
let passed = 0;
function test(name, body) { body(); passed++; console.log('PASS: ' + name); }
test('Callback hold derives from sentinel plus10s; the former30s hold violates the invariant', () => {
    assert.equal(sentinelHold, 90000); assert.equal(confirmDelay, 8000);
    assert.equal(bridgeHold, sentinelHold + 10000);
    const preservesOrder = hold => hold >= sentinelHold + 10000 && confirmDelay + hold > sentinelHold;
    assert(preservesOrder(bridgeHold)); assert(!preservesOrder(30000));
    for (const answerToReturnedAck of [0, 1, 300, 10000, 70000]) {
        assert(answerToReturnedAck + confirmDelay + bridgeHold >= sentinelHold + 10000);
    }
});
test('Carrier process budget includes the complete XML waits, dynamic holds and teardown', () => {
    const invite = Number(carrier.match(/<recv request="INVITE"[^>]*timeout="(\d+)"/)[1]);
    const answer = Number(carrier.match(/<pause milliseconds="(\d+)"/)[1]);
    const ack = Number(carrier.match(/<recv request="ACK"[^>]*timeout="(\d+)"/)[1]);
    const minimum = invite + answer + ack + confirmDelay + bridgeHold + 10000;
    assert.equal(processSeconds, Math.ceil(minimum / 1000)); assert.equal(processSeconds, 219);
    assert(120000 < minimum); assert(208000 < minimum);
    assert(definition(source, 'start_returned_carrier').includes('-timeout "${CALLBACK_CARRIER_TIMEOUT_S}s" -timeout_error'));
    const csv = definition(source, 'write_returned_carrier_csv');
    assert(csv.includes('"$CALLBACK_CARRIER_CONFIRM_DELAY_MS" "$CALLBACK_BRIDGE_HOLD_MS"'));
});
test('Sentinel, agent and registration deadlines outlive their required successful lifetimes', () => {
    const sentinelSeconds = Number(definition(source, 'start_sentinel_caller').match(/-timeout (\d+)s/)[1]);
    const answerSeconds = Number(definition(common, 'wait_answered_calls').match(/SECONDS \+ (\d+)/)[1]);
    assert(sentinelSeconds * 1000 >= answerSeconds * 1000 + sentinelHold + 10000);
    const agentBye = Number(agent.match(/<recv request="BYE" timeout="(\d+)"/)[1]);
    const agentSeconds = Number(definition(common, 'start_agent_uas').match(/-timeout (\d+)s/)[1]);
    assert(agentBye > processSeconds * 1000); assert(agentSeconds > processSeconds);
    assert(definition(source, 'run_callback_acceptance').includes('register_agents callback 1 600'));
    assert(600 > processSeconds);
});
test('Both normal BYEs occur after the established-dialog hold and the strict packet check is retained', () => {
    const ordered = (text, terms) => {
        let previous = -1;
        for (const term of terms) { const next = text.indexOf(term, previous + 1); assert(next > previous, term); previous = next; }
    };
    ordered(carrier, ['<recv request="ACK"', '<pause variable="confirm_delay_ms"',
        'CALLBACK_NEGOTIATED_DTMF', '<pause variable="bridge_hold_ms"', 'BYE [next_url]']);
    ordered(sentinel, ['<label id="media"', '<pause variable="hold_ms"', 'BYE [next_url]']);
    assert(read('test-fixtures/assert-callback-confirmation-pcap.cjs')
        .includes("assert(message.callId === proof.agentCallId, 'Unrelated agent INVITE cannot prove callback ordering')"));
});
function validateSourceOrdering(text, backend) {
    const run = definition(text, 'run_callback_acceptance');
    const steps = ['agent_status logout 1 "$STATUS_AGENT_MAX"', 'start_sentinel_caller',
        'wait_answered_calls "$RUN_DIR/callback-sentinel-stats.csv" 1', 'start_agent_uas callback 1 0',
        'agent_status login 1 1', 'wait_callback_bridge'];
    let previous = -1;
    for (const step of steps) { const next = run.indexOf(step); assert(next > previous, 'Lifecycle dependency: ' + step); previous = next; }
    const gate = backend.slice(backend.indexOf('\ncallback_maybe_dial(Doc,'), backend.indexOf('\ncallback_start_caller(Doc,'));
    assert(gate.includes('andalso acdc_queue_manager:ready_agent_count(Manager) > 0'));
    assert(gate.indexOf('ready_agent_count') < gate.indexOf("'true' ->"));
    assert(gate.indexOf("'true' ->") < gate.indexOf('callback_start_caller(Claimed, State)'));
    assert.deepEqual(run.match(/^    agent_status [^\n]+/gm), [
        '    agent_status logout 1 "$STATUS_AGENT_MAX"', '    agent_status login 1 1', '    agent_status verify 1 1']);
}
test('Source dependencies require sentinel answer before login and ready-agent proof before originate', () => {
    validateSourceOrdering(source, queue);
    const earlyLogin = source.replace('    start_sentinel_caller\n', '    agent_status login 1 1\n    start_sentinel_caller\n');
    assert.throws(() => validateSourceOrdering(earlyLogin, queue));
    assert.throws(() => validateSourceOrdering(source, queue.replace('andalso acdc_queue_manager:ready_agent_count(Manager) > 0', 'andalso true')));
});
test('Extracted prepare-only entrypoint returns before any run directory, traps or live work', () => {
    const prepare = shell(`
trace() { printf '%s\\n' "$*"; }
die() { exit 91; }
load_state() { trace load-state; }
validate_state() { trace validate-state; }
ensure_sipp() { trace ensure-sipp; }
validate_callback_scenarios() { trace validate-scenarios; }
resolve_local_ip() { trace resolve-local; }
callback_capture_filter() { :; }
create_run_dir() { exit 92; }
callback_cleanup() { exit 93; }
run_callback_acceptance() { exit 94; }
log() { trace prepared; }
CALLBACK_PREPARE=false CALLBACK_LIVE=false KEEP_FIXTURE=false
${definition(source, 'parse_callback_args')}
${definition(source, 'main_callback')}
main_callback --prepare-only
`);
    assert.equal(prepare.status, 0, prepare.stderr);
    assert.deepEqual(prepare.stdout.trim().split('\n'), ['load-state', 'validate-state', 'ensure-sipp',
        'validate-scenarios', 'resolve-local', 'prepared']);
});
console.log('PASS: ' + passed + ' private callback timing groups; old30s/120s/208s bounds rejected, no mutations');
