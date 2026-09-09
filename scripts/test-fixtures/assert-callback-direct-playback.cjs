'use strict';
// Read-only log evidence for the exact retained main-development callback.
// Run after the parent acceptance job is terminal. No calls or API requests.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const [run] = process.argv.slice(2);
assert.equal(process.argv.length, 3);
assert.equal(process.getuid(), 0);
assert(/^\/var\/log\/kazoo-acceptance\/[0-9]{8}T[0-9]{6}Z$/.test(run));
const read = name => JSON.parse(fs.readFileSync(path.join(run, name)));
assert.equal(read('retry-registration-policy.json').account_id, '8310dc3170a18de37f205d0da172df65');
const bridge = read('retry-bridge-evidence.json');
const id = bridge.caller.id;
assert(/^[A-Za-z0-9@._:-]{1,128}$/.test(id));
assert.equal(bridge.callback.status, 'completed');
assert.equal(bridge.callback.attempts, 2);
const pins = {}, events = [];
for (const name of fs.readdirSync('/var/log/freeswitch').filter(n => /^kazoo-debug\.log(?:\.[0-9]+)?$/.test(n))) {
    const file = path.join('/var/log/freeswitch', name), stat = fs.lstatSync(file);
    assert(stat.isFile() && stat.size <= 64 * 1024 * 1024);
    const bytes = fs.readFileSync(file);
    pins[name] = crypto.createHash('sha256').update(bytes).digest('hex');
    for (const line of bytes.toString().split('\n')) {
        if (!line.includes(id)) continue;
        const match = /EXECUTE \[depth=\d+\] \S+ ([A-Za-z0-9_]+)\(/.exec(line);
        if (!match) continue;
        const time = /20[0-9]{2}-[0-9-]+ [0-9:.]+/.exec(line);
        assert(time);
        events.push({ time: time[0], application: match[1] });
    }
}
events.sort((a, b) => a.time.localeCompare(b.time));
const count = name => events.filter(e => e.application === name).length;
assert.equal(count('park'), 1, 'Missing or ambiguous returned park');
assert.equal(count('playback'), 1, 'Missing or repeated returned prompt');
assert.equal(count('broadcast'), 0, 'Parked caller still routed through broadcast');
assert.equal(count('noop'), 1, 'Missing exact completion boundary');
assert.equal(count('kz_intercept'), 1, 'Missing subsequent agent handoff');
const index = name => events.findIndex(e => e.application === name);
assert(index('park') < index('playback') && index('playback') < index('noop') && index('noop') < index('kz_intercept'));
const result = { scope: 'returned-callback-direct-playback', direct_playback: true,
    broadcast_count: 0, events, log_snapshot_sha256: pins,
    strict_rtp_acceptance: 'see separate parent acceptance result', database_writes: 0 };
fs.writeFileSync(path.join(run, 'callback-direct-playback.json'), JSON.stringify(result, null, 2) + '\n',
    { flag: 'wx', mode: 0o600 });
console.log(JSON.stringify(result));
