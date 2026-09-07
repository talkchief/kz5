#!/usr/bin/env node
'use strict';
// Internal1001 test only. No API writes, credential output or new registrations.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const {baseState} = require('../test-channel-monitor-live.cjs');
const ACCOUNT = '7807ad61761269a1ccec833dde63f621';
function target(transport = 'external') {
    assert(['external', 'internal'].includes(transport), 'Unsupported callback test transport');
    return transport === 'internal' ? 'acceptance1001' : '\\+12025550101';
}
function endpointIp(transport='external') { target(transport);return transport==='internal'?'127.0.0.20':'127.0.0.30'; }
function derive(source, kind) {
    assert(['returned','unanswered'].includes(kind), 'Unsupported internal scenario');
    const before = '\\+12025550101@';
    assert.equal(source.split(before).length, 2, 'Expected one exact original destination assertion');
    let output=source.replace(before, 'acceptance1001@');
    if(kind==='unanswered') {
        output=output.replace('127\\.0\\.0\\.30','127\\.0\\.0\\.20');
        const marker='<action>';
        // Extract the current received header explicitly. last_* substitution
        // inside this recv action refers to the previous message in SIPp.
        output=output.replace(marker,marker+'\n      <ereg regexp=".*" search_in="hdr" header="Via:" occurrence="2" check_it="true" assign_to="invite_upstream_via"/>');
        assert.equal(output.split('Via: [$invite_via]').length,4,'Expected original INVITE response Via fields');
        output=output.replaceAll('Via: [$invite_via]','Via: [$invite_via]\n      Via: [$invite_upstream_via]');
    }
    return output;
}
function privateFile(file) {
    const s = fs.lstatSync(file);
    assert(s.isFile() && !s.isSymbolicLink() && s.uid === 0 && (s.mode & 0o077) === 0 && s.size < 1024*1024,
        'Unsafe internal fixture input');
    return fs.readFileSync(file, 'utf8');
}
function registrationAbsent(result) {
    // This installed Kamailio RPC reports an absent AOR as500 while kamcmd
    // exits0. Accept only that exact known semantic reply, not arbitrary500,
    // a missing RPC method, empty/malformed output or a transport failure.
    return result.status === 0 && typeof result.stdout === 'string' && typeof result.stderr === 'string'
        && /^error:\s*500\s*-\s*AOR not found in location table\s*$/.test(result.stdout.trim()) && !result.stderr.trim();
}
function preflight(file) {
    assert.equal(file, '/etc/kazoo/acceptance-secrets.env', 'Only canonical isolated state allowed');
    const s = baseState(privateFile(file));
    assert.equal(s.ACCEPTANCE_ACCOUNT_ID, ACCOUNT);
    assert.equal(s.ACCEPTANCE_CALLER_SIP_USERNAME, 'acceptance1001');
    const result = cp.spawnSync('kamcmd', ['ul.lookup', 'location', s.ACCEPTANCE_CALLER_SIP_USERNAME+'@'+s.ACCEPTANCE_REALM],
        {encoding:'utf8',timeout:5000,maxBuffer:65536});
    // A successful lookup means some registration already exists. Never take it
    // over, even if it appears to be a previous fixture. Keep raw output private.
    assert(registrationAbsent(result),
        'Fixture registration is not proven absent; refusing takeover');
    console.log('PASS isolated1001 identity and absent registration; no writes');
}
function generate(kind, directory) {
    const stat = fs.lstatSync(directory);
    assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0,
        'Unsafe internal scenario directory');
    const file = path.join(directory, kind === 'returned' ? 'callback-returned.xml' : 'callback-unanswered-internal.xml');
    const source = kind === 'returned' ? privateFile(file)
        : fs.readFileSync(path.join(__dirname, '../sip-tests/callback-unanswered.xml'),'utf8');
    const output = derive(source, kind);
    if (kind === 'returned') fs.writeFileSync(file, output, {mode:0o600});
    else fs.writeFileSync(file, output, {mode:0o600,flag:'wx'});
}
module.exports = {target, endpointIp, derive, registrationAbsent};
if (require.main === module) {
    try {
        assert.equal(process.argv.length, 4);
        if (process.argv[2] === 'preflight') preflight(process.argv[3]);
        else generate(process.argv[2],process.argv[3]);
    } catch (_) { console.error('Internal callback fixture preflight/scenario failed; no raw state emitted'); process.exitCode=1; }
}
