'use strict';
// Build only the isolated announcement caller. Normal queue/stress scenarios
// retain their RTP echo-pattern check. This caller sends PCMU silence and its
// received speech is independently checked against installed prompts in pcap.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
function once(source, before, after) {
    assert.equal(source.split(before).length, 2, 'Unexpected source scenario shape');
    return source.replace(before, after);
}
function buildScenario(source, mediaPath) {
    assert(typeof source === 'string' && source.length < 32768);
    assert(path.isAbsolute(mediaPath) && /^[-A-Za-z0-9_./]+$/.test(mediaPath), 'Unsafe media path');
    let result = once(source, 'Kazoo authenticated caller to ACDC queue with RTP check',
        'Isolated ACDC announcement caller with independently captured received media');
    result = once(result, '<exec rtp_stream="apattern,1,0,PCMU/8000"/>',
        '<exec rtp_stream="' + mediaPath + ',-1,0,PCMU/8000"/>');
    result = once(result, '<exec rtp_stream="pauseapattern"/>', '<exec rtp_stream="pause"/>');
    assert(!/apattern|vpattern|audiotolerance|rtp_echo/.test(result), 'Echo verifier must not grade queue prompts');
    return result;
}
function createFiles(runDir, sourcePath) {
    assert(path.isAbsolute(runDir) && /^[-A-Za-z0-9_./]+$/.test(runDir), 'Unsafe run directory');
    assert.equal(fs.realpathSync(runDir), path.resolve(runDir), 'Symlinked run directory');
    const directory = fs.lstatSync(runDir), source = fs.lstatSync(sourcePath);
    assert(directory.isDirectory() && directory.uid === 0 && (directory.mode & 511) === 448, 'Run directory must be private root-owned');
    assert(source.isFile() && !source.isSymbolicLink() && source.size < 32768, 'Unsafe source scenario');
    const media = path.join(runDir, 'offer-silence.ulaw'), scenario = path.join(runDir, 'offer-caller.xml');
    assert(!fs.existsSync(media) && !fs.existsSync(scenario), 'Never overwrite scenario evidence');
    const xml = buildScenario(fs.readFileSync(sourcePath, 'utf8'), media);
    // One second of G.711 PCMU silence, looped until the existing finite pause.
    fs.writeFileSync(media, Buffer.alloc(8000, 255), {flag: 'wx', mode: 0o600});
    fs.writeFileSync(scenario, xml, {flag: 'wx', mode: 0o600});
    return {scenario: 'isolated-file-mode', silence_samples: 8000, echo_pattern_assertion: false,
        received_media_proof: 'strict-negotiated-pcap-required'};
}
module.exports = {buildScenario, createFiles};
if (require.main === module) {
    try {
        assert.equal(process.argv.length, 4, 'Expected run directory and source scenario');
        console.log(JSON.stringify(createFiles(process.argv[2], process.argv[3])));
    } catch (error) {
        console.error('Offer scenario preparation failed: ' + error.message);
        process.exitCode = 1;
    }
}
