#!/usr/bin/env node
'use strict';
// Exercise the real bridge polling function with private, non-network fixtures.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(__dirname, 'test-acdc-callback-calls.sh'), 'utf8');
const fn = source.match(/^wait_callback_bridge\(\) \{[\s\S]*?^\}/m)?.[0];
assert(fn, 'Missing real bridge polling function');
assert(!source.includes('CALLBACK_CONFIRMING_OBSERVED'), 'Transient status must not masquerade as proof of the DTMF wait');
assert(source.includes('assert-callback-confirmation-pcap.cjs" "$RTP_PCAP"'), 'Strict negotiated DTMF-before-agent packet gate must remain mandatory');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-callback-lifecycle-test.'));
const account = '11111111111111111111111111111111';
const registration = {id: 'fixture-ticket', enqueued_at: 100, enqueue_sequence: 42};
const completed = {...registration, status: 'completed', attempts: 1, caller_call_id: 'caller', agent_call_id: 'agent'};
const channels = {
    caller: {id: 'caller', account, bridge_to: 'agent', sip_call_id: 'caller-sip'},
    agent: {id: 'agent', account, bridge_to: 'caller', sip_call_id: 'agent-sip'},
    '1-123@127.0.0.20': {id: '1-123@127.0.0.20', account, bridge_to: null}
};
const cases = [
    ['completed_without_transient_confirming', completed, channels, true],
    ['wrong_caller_account', completed, {...channels, caller: {...channels.caller, account: 'other'}}, false],
    ['wrong_agent_account', completed, {...channels, agent: {...channels.agent, account: 'other'}}, false],
    ['nonreciprocal_caller', completed, {...channels, caller: {...channels.caller, bridge_to: 'other'}}, false],
    ['nonreciprocal_agent', completed, {...channels, agent: {...channels.agent, bridge_to: 'other'}}, false],
    ['sentinel_already_bridged', completed, {...channels, '1-123@127.0.0.20': {...channels['1-123@127.0.0.20'], bridge_to: 'other'}}, false],
    ['changed_callback_identity', {...completed, id: 'other-ticket'}, channels, false],
    ['changed_enqueue_sequence', {...completed, enqueue_sequence: 43}, channels, false],
    ['multiple_attempts', {...completed, attempts: 2}, channels, false],
    ['unsettled_reconciliation', {...completed, reconciliation_required: true}, channels, false],
    ['cancelled_not_completed', {...completed, status: 'cancelled'}, channels, false]
];
try {
    const script = 'set -Eeuo pipefail\n' + fn + '\n' + `
declare -A STATE=([ACCEPTANCE_ACCOUNT_ID]="${account}")
CARRIER_PID=$$
SENTINEL_PID=123
LOCAL_IP=127.0.0.20
callback_document() { printf '%s\\n' "$TEST_DOCUMENT"; }
callback_channel() { jq -ce --arg id "$1" '.[$id]' <<< "$TEST_CHANNELS"; }
die() { printf '%s\\n' "$*" >&2; exit 1; }
wait_callback_bridge
`;
    for (const [name, document, snapshots, pass] of cases) {
        const directory = path.join(scratch, name); fs.mkdirSync(directory, {mode: 0o700});
        const run = cp.spawnSync('bash', ['-c', script], {cwd: root, encoding: 'utf8', timeout: 5000,
            env: {...process.env, RUN_DIR: directory, TEST_DOCUMENT: JSON.stringify(document),
                TEST_CHANNELS: JSON.stringify(snapshots), CALLBACK_REGISTRATION_EVIDENCE: JSON.stringify(registration)}});
        assert(!run.error, name + ': timed out or failed to execute');
        assert.equal(run.status === 0, pass, name + ': unexpected result');
        const receipt = path.join(directory, 'callback-bridge-evidence.json');
        assert.equal(fs.existsSync(receipt), pass, name + ': unexpected bridge receipt');
        if (pass) {
            const evidence = JSON.parse(fs.readFileSync(receipt, 'utf8'));
            assert.deepEqual(evidence.callback, completed);
            assert.deepEqual(evidence.caller, channels.caller);
            assert.deepEqual(evidence.agent, channels.agent);
        }
        console.log('PASS ' + name);
    }
    console.log('PASS 11 private callback lifecycle groups; no API/SIP traffic');
} finally {
    assert(scratch.startsWith(path.join(os.tmpdir(), 'kazoo-callback-lifecycle-test.')));
    fs.rmSync(scratch, {recursive: true});
}
