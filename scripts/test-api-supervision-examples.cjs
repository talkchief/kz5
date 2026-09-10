'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const guide = require('./api-docs-supervision.cjs');

// Execute the documented shell syntax with a local function replacing curl.
// No HTTP calls, tokens, phones or external services are used by this test.
const examples = [...guide.description().matchAll(/```sh\n([\s\S]*?)\n```/g)].map(m => m[1]);
assert.equal(examples.length, 8);
for (const [i, snippet] of examples.entries()) {
    const mode = guide.modes[Math.floor(i / 2)], stopping = i % 2 === 1;
    test(`${mode.name} ${stopping ? 'stop' : 'start'} copied command has exact curl arguments`, () => {
        const script = 'curl() { printf "%s\\0" "$@"; }\n' + snippet;
        const out = execFileSync('/bin/bash', ['--noprofile', '--norc', '-eu', '-c', script], {
            env: {PATH: '/nonexistent', KAZOO_TOKEN: 'synthetic-documentation-token'},
            timeout: 2000, encoding: 'utf8'
        });
        const args = out.split('\0');
        assert.equal(args.pop(), '');
        assert.deepEqual(args.slice(0, 8), [
            '--request', 'POST',
            'https://YOUR_KAZOO_HOST/v2/accounts/ACCOUNT_ID/channels/' +
                (stopping ? 'SUPERVISOR_CALL_ID' : 'AGENT_CALL_ID'),
            '--header', 'X-Auth-Token: synthetic-documentation-token',
            '--header', 'Content-Type: application/json', '--data'
        ]);
        assert.equal(args.length, 9);
        assert.deepEqual(JSON.parse(args[8]), {data: stopping ?
            {action: 'stop_monitoring', request_id: 'MONITOR_REQUEST_ID'} :
            {action: mode.action, device_id: 'SUPERVISOR_DEVICE_ID', timeout: 20}});
    });
}
