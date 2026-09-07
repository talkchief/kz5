'use strict';
// Pure service-state gate. This module never contacts systemd or changes a unit.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const units = ['kazoo-apps.service', 'kazoo-ecallmgr.service', 'kazoo-freeswitch.service',
    'kazoo-kamailio.service', 'kazoo-live-test-agents.service'];
function inspect(source, allowPaused = false) {
    assert.equal(typeof allowPaused, 'boolean', 'Explicit paused-helper option must be boolean');
    assert(typeof source === 'string' && source.length > 0 && source.length <= 8192, 'Invalid service snapshot');
    const states = source.trim().split(/\n\n+/).map(block => {
        const state = {};
        for (const line of block.split('\n')) {
            const match = /^(Id|LoadState|ActiveState|SubState|MainPID|NRestarts)=(.*)$/.exec(line);
            assert(match && !Object.hasOwn(state, match[1]), 'Unknown or duplicate service field');
            state[match[1]] = match[2];
        }
        assert.equal(Object.keys(state).length, 6, 'Incomplete service snapshot');
        assert(units.includes(state.Id) && state.LoadState === 'loaded', 'Missing or foreign service');
        for (const field of ['MainPID', 'NRestarts']) {
            assert(/^(?:0|[1-9][0-9]*)$/.test(state[field]) && Number.isSafeInteger(Number(state[field])), 'Invalid service counter');
        }
        return state;
    });
    assert.deepEqual(states.map(state => state.Id).sort(), [...units].sort(), 'Service inventory differs');
    let paused = false;
    for (const state of states) {
        if (state.Id === 'kazoo-live-test-agents.service' && allowPaused
            && state.ActiveState === 'inactive' && state.SubState === 'dead' && state.MainPID === '0') {
            paused = true;
        } else {
            assert(state.ActiveState === 'active' && state.SubState === 'running' && Number(state.MainPID) > 0,
                'Required service is not active/running with a process');
        }
    }
    return {schema_version: 1, allow_paused_master_test_phones: allowPaused, master_test_phones_paused: paused,
        limitation: paused ? 'MASTER receive-only test phones were inactive; this run proves isolated-tenant callbacks, not MASTER phone availability.' : null,
        services: states};
}
module.exports = {inspect};
if (require.main === module) {
    assert(process.argv.length === 4 && ['true', 'false'].includes(process.argv[3]),
        'Usage: callback-retry-service-scope.cjs protected-snapshot allow-paused-boolean');
    const stat = fs.lstatSync(process.argv[2]);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0
        && stat.size > 0 && stat.size <= 8192, 'Unsafe service snapshot');
    process.stdout.write(JSON.stringify(inspect(fs.readFileSync(process.argv[2], 'utf8'), process.argv[3] === 'true')) + '\n');
}
