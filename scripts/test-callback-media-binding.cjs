#!/usr/bin/env node
'use strict';
// Pinned SIPp source + real private loopback bind regression. No packets, SIP,
// account mutations or service operations; sockets are closed before exit.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), dgram = require('node:dgram');
const assert = require('node:assert/strict');
const read = name => fs.readFileSync(path.join(__dirname, name), 'utf8');
const source = read('test-acdc-callback-calls.sh'), common = read('test-kazoo-calls.sh');
const definition = (text, name) => {
    const match = text.match(new RegExp('^' + name + '\\(\\) \\{\\n[\\s\\S]*?^\\}', 'm'));
    assert(match, 'Missing actual function ' + name); return match[0];
};
const pinned = process.env.KAZOO_SIPP_SOURCE_ROOT || '/usr/local/src/kazoo5-tests/sipp-3.7.7';
const sipp = fs.readFileSync(path.join(pinned, 'src/sipp.cpp'), 'utf8');
const stream = fs.readFileSync(path.join(pinned, 'src/rtpstream.cpp'), 'utf8');
assert(/\{"mp",[^\n]+SIPP_OPTION_INT, &min_rtp_port/.test(sipp));
assert(sipp.includes('media_port = min_rtp_port;'));
assert(sipp.includes('create_socket(media_sa, try_port, last_attempt, "audio")'));
assert(sipp.includes('create_socket(media_sa, try_port + 2, last_attempt, "video")'));
assert(stream.includes('next_rtp_port += 2;') && stream.includes('next_rtp_port > (max_rtp_port - 1)'));
assert(stream.includes('WARNING("Could not bind port for RTP streaming after %d tries", tries)'));
console.log('PASS pinned SIPp -mp alias, echo min/+2 binding and independent streaming range semantics');
for (const [name, variable, scenario] of [
    ['start_returned_carrier', 'CARRIER_MEDIA_PORT', 'callback-returned.xml'],
    ['start_callback_request', 'CALLBACK_ORIGINAL_MEDIA_PORT', 'callback-request.xml'],
    ['start_sentinel_caller', 'SENTINEL_MEDIA_PORT', 'caller-to-queue.xml']
]) {
    const fn = definition(source, name).replace(/^\s*#.*$/gm, '');
    assert(!fn.includes('-rtp_echo'), name + ' must not reserve its streaming sockets for echo');
    assert(fn.includes('-min_rtp_port "$' + variable + '"'));
    assert(fn.includes('-max_rtp_port "$((' + variable + ' + 3))"'));
    const xml = read('sip-tests/' + scenario);
    assert(xml.includes('m=audio [media_port]') && xml.includes('rtp_stream="apattern'));
}
assert(definition(common, 'start_agent_uas').includes('-rtp_echo'));
assert(!read('sip-tests/agent-answer.xml').includes('rtp_stream='));
console.log('PASS three active generators retain exact advertised ranges; agent remains echo-only');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-callback-media-log-test.'));
try {
    const names = ['original', 'carrier', 'agent-1', 'sentinel'];
    const guard = definition(source, 'assert_callback_media_logs');
    const run = text => {
        for (const name of names) fs.writeFileSync(path.join(scratch, 'callback-' + name + '.log'),
            name === 'carrier' ? text : 'SIPp SuccessfulCall1 FailedCall0\n', {mode: 0o600});
        return cp.spawnSync('bash', ['-c', 'set -Eeuo pipefail\ndie() { exit 1; }\n' + guard + '\nassert_callback_media_logs'],
            {encoding: 'utf8', timeout: 5000, env: {PATH: '/usr/bin:/bin', LANG: 'C', RUN_DIR: scratch}});
    };
    assert.equal(run('SIPp SuccessfulCall1 FailedCall0\n').status, 0);
    for (const warning of ['Could not bind port for RTP streaming after 3 tries',
        'Could not open socket for RTP streaming: unavailable', 'Could not set up media IP for RTP streaming']) {
        assert.notEqual(run('SIPp SuccessfulCall1 FailedCall0\nWARNING: ' + warning + '\n').status, 0);
    }
    const main = definition(source, 'run_callback_acceptance');
    assert(main.indexOf('assert_callback_media_logs') < main.indexOf('assert_callback_rtp'));
    assert(main.indexOf('assert_callback_media_logs') > main.indexOf('stop_monitor'));
    console.log('PASS actual log guard rejects three streaming failures even when SIP reports success');
} finally {
    assert(scratch.startsWith(path.join(os.tmpdir(), 'kazoo-callback-media-log-test.')));
    fs.rmSync(scratch, {recursive: true});
}
const held = new Set();
function bind(port) {
    return new Promise((resolve, reject) => {
        const socket = dgram.createSocket('udp4');
        socket.once('error', error => { socket.close(); reject(error); });
        socket.bind(port, '127.0.0.60', () => { held.add(socket); resolve(socket); });
    });
}
async function close(socket) {
    if (held.delete(socket)) await new Promise(resolve => socket.close(resolve));
}
async function testBindings() {
    let audio, video, base;
    try {
        for (let attempt = 0; attempt < 20; attempt++) {
            const probe = await bind(0); base = probe.address().port & ~1; await close(probe);
            if (base + 3 > 65535) continue;
            try { audio = await bind(base); video = await bind(base + 2); break; }
            catch (error) { if (audio) await close(audio); audio = null; assert.equal(error.code, 'EADDRINUSE'); }
        }
        assert(audio && video, 'Could not establish private four-port regression range');
        // Reproduce SIPp's actual candidate sequence for max=min+3: min,+2,min.
        for (const port of [base, base + 2, base]) {
            await assert.rejects(bind(port), error => error.code === 'EADDRINUSE');
        }
        await close(audio); await close(video);
        const generatedAudio = await bind(base), generatedRtcp = await bind(base + 1);
        assert.equal(generatedAudio.address().port, base);
        await close(generatedAudio); await close(generatedRtcp);
        console.log('PASS kernel binding reproduces old echo/stream collision and corrected exact-port allocation; zero packets sent');
    } finally { for (const socket of [...held]) await close(socket); }
}
testBindings().catch(error => { console.error('Callback media binding regression failed: ' + error.message); process.exitCode = 1; });
