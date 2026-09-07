#!/usr/bin/env node
'use strict';
// Offline patch replay, wire-template fixtures and isolated -c syntax check.
// No installed config, deployment secrets, service actions or provider calls.
// Optional positional arguments: config checkout, Kamailio source, binary.
// The -c check does not execute routes: arithmetic below is explicitly modeled.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');

const configRoot = process.argv[2] || '/usr/local/src/kazoo5-installer/kazoo-configs-kamailio';
const sourceRoot = process.argv[3] || '/tmp/kamailio-6.1.4.TojAod';
const binary = process.argv[4] || '/usr/sbin/kamailio';
assert(process.argv.length <= 5, 'unexpected arguments');
const revision = '9d61bded9890325182f1783aeb4bd2182eb2d846';
const target = 'kamailio/pusher-role.cfg';
const originalHash = '0a27014d9582e4e7af00d027b5e68ff61e2298a694444bd3e31f828f5cfd1350';
const patchFile = path.join(__dirname, 'patches/kamailio-push-freshness.patch');
const env = {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'};
function command(program, args, cwd, status = 0) {
    const result = spawnSync(program, args, {cwd, env, encoding: 'utf8', timeout: 15000, maxBuffer: 512 * 1024});
    assert.ifError(result.error);
    if (status === 0) assert.equal(result.status, 0, `${program} failed: ${result.stderr}`);
    else assert.notEqual(result.status, 0, 'negative fixture unexpectedly succeeded');
    return result;
}
const original = command('git', ['-C', configRoot, 'show', `${revision}:${target}`]).stdout;
assert.equal(crypto.createHash('sha256').update(original).digest('hex'), originalHash, 'pinned input drift');
const patch = fs.readFileSync(patchFile, 'utf8');
assert.deepEqual([...patch.matchAll(/^diff --git a\/(\S+) b\/(\S+)$/gm)].map(m => [m[1], m[2]]), [[target, target]]);

// Verify the actual pinned C data path, not merely the architecture of Node.
const source = file => fs.readFileSync(path.join(sourceRoot, 'src', file), 'utf8');
assert.match(source('Makefile.defs'), /^VERSION = 6$/m);
assert.match(source('Makefile.defs'), /^PATCHLEVEL = 1$/m);
assert.match(source('Makefile.defs'), /^SUBLEVEL = 4$/m);
assert.match(source('core/pvar.h'), /long ri;\s*\/\*!< long value/);
assert.match(source('core/usr_avp.h'), /typedef union\s*\{\s*long n;/);
assert.match(source('core/usr_avp.h'), /typedef numstr_ut int_str;/);
assert.match(source('modules/pv/pv_svar.h'), /int_str value;/);
assert.match(source('modules/pv/pv_core.c'), /avp_val\.n = val->ri;/);
assert.match(source('modules/pv/pv_core.c'), /res->ri = sv->v\.value\.n;/);
assert.match(source('core/rvalue.h'), /long l;/);
assert.match(source('core/ut.h'), /char \*sint2str\(long l, int \*len\)/);
const timeSource = source('modules/pv/pv_time.c');
assert.match(timeSource, /case 2:\s*if\(gettimeofday\(&_timeval_ts, NULL\)/);
assert.match(timeSource, /case 3:\s*return pv_get_uintval\(\s*msg, param, res, \(unsigned long\)_timeval_ts\.tv_usec\);/);
assert.match(timeSource, /strncmp\(in->s, "sn", 2\) == 0\)\s*sp->pvp.pvn.u.isname.name.n = 2;/);
assert.match(timeSource, /strncmp\(in->s, "un", 2\) == 0\)\s*sp->pvp.pvn.u.isname.name.n = 3;/);
const elf = fs.readFileSync(binary);
assert.equal(elf.subarray(0, 4).toString('hex'), '7f454c46');
assert.equal(elf[4], 2, '64-bit ELF required: script-variable long must hold Unix milliseconds');
assert.equal(elf[5], 1, 'expected little-endian x86-64 Linux target');
assert.equal(elf.readUInt16LE(18), 62, 'expected x86-64 LP64 target');
const version = command(binary, ['-v']);
assert.match(version.stdout + version.stderr, /kamailio 6\.1\.4\b/);

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-kamailio-freshness.'));
let checks = 0;
try {
    fs.mkdirSync(path.join(fixtureRoot, 'kamailio'));
    const fixtureFile = path.join(fixtureRoot, target);
    fs.writeFileSync(fixtureFile, original, {flag: 'wx', mode: 0o600});
    command('git', ['apply', '--check', patchFile], fixtureRoot);
    command('git', ['apply', patchFile], fixtureRoot);
    const patched = fs.readFileSync(fixtureFile, 'utf8');
    command('git', ['apply', '--reverse', '--check', patchFile], fixtureRoot);
    command('git', ['apply', '--check', patchFile], fixtureRoot, 1);
    checks += 3;
    const route = (text, name) => {
        const match = text.match(new RegExp(`^route\\[${name}\\]\\n\\{[\\s\\S]*?^\\}`, 'm'));
        assert(match, `missing ${name}`);
        return match[0];
    };
    const prepare = route(patched, 'PUSHER_PREPARE_PUSH_PAYLOAD');
    const oldPrepare = route(original, 'PUSHER_PREPARE_PUSH_PAYLOAD');
    const capture = `   # Capture once before preparing the transaction's immutable payload.
   # Kamailio 6.1 on LP64 keeps PV/script-variable arithmetic as signed long.
   # TV(sn) samples wall time; TV(un) reads microseconds from that SAME sample.
   # Sending/retrying the saved AVP must never renew this 60-second deadline.
   $var(PushCreatedSeconds) = $TV(sn);
   $var(PushCreatedAtMs) = ($var(PushCreatedSeconds) * 1000) + ($TV(un) / 1000);
   $var(PushDeadlineMs) = $var(PushCreatedAtMs) + 60000;

`;
    const field = ', "Push-Freshness" : { "version" : 1, "created_at_ms" : $var(PushCreatedAtMs), "deadline_ms" : $var(PushDeadlineMs) }';
    assert.equal(patched.replace(capture, '').replace(field, ''), original, 'non-additive producer change');
    assert.equal((patched.match(/\$TV\(sn\)/g) || []).length, 1, 'sample wall clock exactly once');
    assert.equal((patched.match(/\$TV\(un\)/g) || []).length, 1, 'read same-sample microseconds exactly once');
    assert(prepare.includes(capture));
    assert(prepare.indexOf(capture) < prepare.indexOf('$var(Payload) ='));
    assert.equal(route(patched, 'PUSHER_SEND_PUSH_NOTIFICATION'), route(original, 'PUSHER_SEND_PUSH_NOTIFICATION'));
    assert.match(prepare, /\$avp\(push_payload\) = \$var\(Payload\);/);
    assert.equal(patched.replace(prepare, ''), original.replace(oldPrepare, ''), 'send/retry/other routes changed');
    assert.equal((patched.match(/kazoo_publish\("pushes", \$avp\(push_routing_key\), \$avp\(push_payload\)\);/g) || []).length, 1);
    checks += 9;

    const payloadLine = text => text.split('\n').find(line => line.startsWith('   $var(Payload) = $_s('));
    const substitutions = {'$ci': 'synthetic-call', '$var(TokenID)': 'synthetic-token', '$var(TokenType)': 'apns',
        '$var(TokenApp)': 'invalid.example.fixture', '$var(from)': 'synthetic-caller',
        '$var(PushPayload)': JSON.stringify({'call-id': 'synthetic-call', proxy: 'fixture.invalid',
            'caller-id-number': 'synthetic-number', 'caller-id-name': 'synthetic-name',
            'registration-token': 'synthetic-registration', 'account-ref': 'synthetic-account'})};
    function expand(line, seconds, usec) {
        // BigInt models the confirmed C signed-long path; no 32-bit JS bitwise
        // operators or floating point conversions before JSON serialization.
        const created = seconds * 1000n + usec / 1000n;
        const deadline = created + 60000n;
        let json = line.slice(line.indexOf('$_s(') + 4, -2);
        for (const [key, value] of Object.entries({...substitutions,
            '$var(PushCreatedAtMs)': String(created), '$var(PushDeadlineMs)': String(deadline)})) json = json.replaceAll(key, value);
        assert(!json.includes('$'), 'unexpanded fixture pseudo-variable');
        return {wire: json, value: JSON.parse(json), created, deadline};
    }
    for (const seconds of [1n, 1788787200n, 2147483647n, 2147483648n, 4294967296n]) {
        for (const usec of [0n, 999n, 1000n, 999999n]) {
            const result = expand(payloadLine(patched), seconds, usec);
            const fresh = result.value['Push-Freshness'];
            assert.deepEqual(fresh, {version: 1, created_at_ms: Number(result.created), deadline_ms: Number(result.deadline)});
            assert.equal(typeof fresh.version, 'number');
            assert(Number.isSafeInteger(fresh.created_at_ms) && Number.isSafeInteger(fresh.deadline_ms));
            assert.equal(fresh.deadline_ms - fresh.created_at_ms, 60000);
            const previousFields = {...result.value}; delete previousFields['Push-Freshness'];
            assert.deepEqual(previousFields, expand(payloadLine(original), seconds, usec).value);
            assert(!Object.hasOwn(previousFields.Payload, 'Push-Freshness'), 'freshness belongs at top level');
            const savedAvp = result.wire;
            for (const elapsed of [0, 59999, 60000, 120000]) {
                const retry = JSON.parse(savedAvp)['Push-Freshness'];
                assert.equal(retry.deadline_ms, fresh.deadline_ms, 'retry must reuse saved AVP, not resample time');
                assert.equal(retry.deadline_ms > fresh.created_at_ms + elapsed, elapsed < 60000);
            }
            checks++;
        }
    }
    // Deliberately quoted metadata must not satisfy numeric wire expectations.
    const quoted = payloadLine(patched).replace('$var(PushCreatedAtMs)', '"$var(PushCreatedAtMs)"');
    assert.equal(typeof expand(quoted, 1788787200n, 0n).value['Push-Freshness'].created_at_ms, 'string');
    checks++;

    const syntaxFile = path.join(fixtureRoot, 'freshness-syntax.cfg');
    const arithmetic = capture.split('\n').filter(line => line.trim().startsWith('$var(')).join('\n');
    fs.writeFileSync(syntaxFile, `#!KAMAILIO
listen=udp:127.0.0.1:50999
loadmodule "pv.so"
request_route {
${arithmetic}
${payloadLine(patched)}
    exit;
}
`, {flag: 'wx', mode: 0o600});
    command(binary, ['-c', '-f', syntaxFile], fixtureRoot);
    checks++;
    command('git', ['apply', '--reverse', patchFile], fixtureRoot);
    assert.equal(fs.readFileSync(fixtureFile, 'utf8'), original);
    checks++;
    console.log(`PASS Kamailio Push-Freshness: ${checks} offline patch/wire checks; pinned 6.1.4 LP64 source and -c syntax confirmed`);
    console.log('No route execution, broker delivery, deployed freshness or runtime consumer acceptance claimed.');
} finally {
    fs.rmSync(fixtureRoot, {recursive: true, force: true});
}
