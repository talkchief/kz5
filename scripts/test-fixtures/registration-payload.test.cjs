#!/usr/bin/env node
'use strict';
// Kamailio syntax validation does not execute $_s() interpolation. In the
// pinned installer KAZOO_PROXY_NODE is a quoted configuration macro, so adding
// JSON quotes around $def(...) produces invalid wire JSON despite `-c` passing.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const patch = fs.readFileSync(path.join(__dirname, '../patches/kamailio-registration-sequences.patch'), 'utf8');
const payloads = patch.split('\n').filter(line => line.startsWith('+') && line.includes('"Registrar-Node"'));
assert.equal(payloads.length, 4, 'Both summary/detail partial and final messages need registrar metadata');
function expand(line, count) {
    const start = line.indexOf('$_s(');
    assert(start >= 0 && line.endsWith(');'), 'Expected a runtime-interpolated payload');
    return line.slice(start + 4, -2)
        .replaceAll('$def(KAZOO_PROXY_NODE)', JSON.stringify('kamailio@kz5-testing'))
        .replaceAll('$(kzE{kz.json,Msg-ID})', 'correlated-request')
        .replaceAll('$var(Msg-ID)', 'correlated-request')
        .replaceAll('$var(RegistrarSequence)', String(count))
        .replaceAll('$var(Registrations)', JSON.stringify('agent@example.invalid'))
        .replaceAll('$var(Registration)', JSON.stringify({AOR: 'agent@example.invalid'}));
}
for (const payload of payloads) {
    for (const count of [0, 1, 31]) {
        const parsed = JSON.parse(expand(payload, count));
        assert.equal(parsed['Registrar-Node'], 'kamailio@kz5-testing');
        assert.equal(parsed['Msg-ID'], 'correlated-request');
        const partial = parsed['Event-Name'] === 'search_partial_resp';
        assert.equal(parsed[partial ? 'Registrar-Sequence' : 'Registrar-Parts'], count);
        assert.equal(parsed.Registrations.length, partial ? 1 : 0);
    }
    const broken = payload.replace('"Registrar-Node" : $def(KAZOO_PROXY_NODE)',
        '"Registrar-Node" : "$def(KAZOO_PROXY_NODE)"');
    assert.throws(() => JSON.parse(expand(broken, 1)), SyntaxError,
        'The original double-quoted macro regression must be rejected');
}
console.log('PASS 12 registrar wire-payload expansion checks and 4 double-quote regression checks');
