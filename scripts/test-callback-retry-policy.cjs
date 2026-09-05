#!/usr/bin/env node
'use strict';
// Exercise the real queue policy builder without credentials, API or SIP.
const fs = require('node:fs'), path = require('node:path');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'test-acdc-callback-fixture.sh'), 'utf8');
const fn = source.match(/^configure_acceptance_queue\(\) \{[\s\S]*?^\}/m)?.[0];
assert(fn);
const queue = {id: 'fixture-queue', name: 'Acceptance Queue 2000', agents: ['unchanged-agent'],
    strategy: 'round_robin', untouched: {value: true}};
for (const action of ['setup', 'setup-retry']) {
    const script = 'set -Eeuo pipefail\n' + fn + '\n' + `
ACCEPTANCE_ACCOUNT_ID=fixture-account
ACCEPTANCE_QUEUE_ID=fixture-queue
ACCEPTANCE_CALLER_DEVICE_ID=fixture-device
OUTBOUND_CALLER_ID=+12025550100
FIXTURE_ORIGINAL_QUEUE=saved-original-snapshot
save_fixture_state() { exit 9; }
fixture_die() { exit 8; }
api_request() {
  if [[ $1 == GET ]]; then printf '%s\\n' "$QUEUE_ENVELOPE";
  elif [[ $1 == POST ]]; then printf '%s\\n' "$3" >&3;
  else exit 7; fi
}
configure_acceptance_queue 3>&1
[[ $FIXTURE_ORIGINAL_QUEUE == saved-original-snapshot ]]
`;
    const run = cp.spawnSync('bash', ['-c', script], {encoding: 'utf8', timeout: 5000,
        env: {...process.env, ACTION: action, QUEUE_ENVELOPE: JSON.stringify({data: queue})}});
    assert.ifError(run.error); assert.equal(run.status, 0);
    const changed = JSON.parse(run.stdout).data, policy = changed.callback;
    delete changed.callback; assert.deepEqual(changed, queue, 'Do not change roster or other queue fields');
    assert.equal(policy.max_attempts, action === 'setup-retry' ? 2 : 1);
    assert.equal(policy.originate_timeout, action === 'setup-retry' ? 15 : 45);
    assert.equal(policy.retry_delay, 15); assert.equal(policy.ttl, 600);
    assert.deepEqual(policy.outbound_authority, {id: 'fixture-device', type: 'device'});
    assert.equal(policy.use_local_resources, true); assert.equal(policy.allow_alternate_number, false);
    console.log('PASS actual ' + action + ' policy; original snapshot and unrelated queue fields preserved');
}
assert(source.includes('setup|setup-retry) setup_fixture'));
assert(source.includes('Busy-agent retry policy was not persisted exactly'));
console.log('PASS isolated retry action dispatch and read-back guard; no API/SIP traffic');
