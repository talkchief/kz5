#!/usr/bin/env node
'use strict';
// Isolated contracts and extracted shell functions: never contacts Kazoo/SIP.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {scenarios, expectedDigits, modeReceipt} = require('./test-fixtures/create-callback-retry-scenarios.cjs');
const {lifecycle, retryTiming, registrationModeProof, GREGORIAN_UNIX_OFFSET} = require('./test-fixtures/assert-callback-retry.cjs');
let checks = 0;
const generated = scenarios();
assert(generated['callback-retry-request.xml'].includes('<pause milliseconds="4200"/>'));
assert(generated['callback-retry-request.xml'].includes('~780ms DTMF warmup'));
assert(!generated['callback-retry-request.xml'].includes('<pause milliseconds="4000"/>'));
assert(!generated['callback-retry-request.xml'].includes('rtp_stream='));
assert.equal((generated['callback-retry-request.xml'].match(/play_dtmf=/g) || []).length, 2);
assert(generated['callback-busy-caller.xml'].includes('<recv request="BYE" timeout="120000"/>'));
assert(!generated['callback-busy-caller.xml'].includes('start_txn="bye"'));
assert(generated['callback-busy-caller.xml'].includes('<Reference variables="hold_ms"/>'));
for (const xml of Object.values(generated)) {
    assert(xml.includes('[$challenge_via]') && xml.includes('ack_txn="invite1"'));
    assert(xml.includes('branch=[branch]') && xml.includes('[routes]'));
}
checks++;
const account = require('./test-fixtures/callback-fixture-account.cjs').selectedAccount();
const entryOnly = scenarios(undefined, 'entry-only');
assert.equal((entryOnly['callback-retry-request.xml'].match(/play_dtmf=/g) || []).length, 1);
assert(entryOnly['callback-retry-request.xml'].includes('play_dtmf="[field5],200"'));
assert(!entryOnly['callback-retry-request.xml'].includes('play_dtmf="1,200"'));
assert(!entryOnly['callback-retry-request.xml'].includes('milliseconds="2500"'));
assert(entryOnly['callback-retry-request.xml'].includes('milliseconds="4200"'));
assert(entryOnly['callback-retry-request.xml'].includes('<recv request="BYE" timeout="30000"'));
assert.equal(entryOnly['callback-busy-caller.xml'], generated['callback-busy-caller.xml']); checks++;
assert.throws(() => scenarios(undefined, 'auto')); checks++;
{
    const xml=scenarios(undefined,'invalid-reject')['callback-retry-request.xml'];
    assert.deepEqual(expectedDigits('invalid-reject'),[6]);
    assert.equal(modeReceipt('invalid-reject').allow_alternate_number,false);
    assert(xml.includes('start_txn="caller_bye"')&&xml.includes('milliseconds="12000"'));
    assert(!xml.includes('<recv request="BYE"'));checks++;
}
{
    const mode='invalid-alternate', xml=scenarios(undefined,mode)['callback-retry-request.xml'];
    assert.deepEqual(expectedDigits(mode),[6,11,1,0,0,1,11,1]);
    assert.equal((xml.match(/play_dtmf=/g)||[]).length,4);
    assert(xml.includes('play_dtmf="1001#,200"') && xml.includes('milliseconds="10000"'));
    assert.equal(scenarios(undefined,mode)['callback-busy-caller.xml'],generated['callback-busy-caller.xml']);
    const receipt=modeReceipt(mode), policy={registration_mode:mode,account_id:account,entry_key:'6',allow_alternate_number:true,fixture_verified:true};
    const audio={result:'PASS',registration_mode:mode,expected_registration_digits:expectedDigits(mode),
        observed_registration_digits:expectedDigits(mode),original_number:'invalid-caller',alternate_number:'1001',
        invalid_entry:{result:'PASS',complete_after_empty_entry_before_number:true}};
    registrationModeProof(mode,receipt,policy,audio); checks++;
    for(const mutate of [x=>x.policy.allow_alternate_number=false,x=>x.audio.invalid_entry.result='FAIL',
        x=>delete x.audio.invalid_entry,x=>x.audio.invalid_entry.complete_after_empty_entry_before_number=false,
        x=>x.audio.original_number='1001',x=>x.audio.alternate_number='1002',x=>x.audio.observed_registration_digits=[6,1]]) {
        const x=structuredClone({receipt,policy,audio});mutate(x);
        assert.throws(()=>registrationModeProof(mode,x.receipt,x.policy,x.audio));checks++;
    }
}
for (const mode of ['entry-only', 'confirm-current']) {
    const receipt = modeReceipt(mode), policy = {registration_mode: mode, account_id: account,
        entry_key: '6', allow_alternate_number: false, fixture_verified: true};
    const audio = {result: 'PASS', registration_mode: mode, expected_registration_digits: expectedDigits(mode),
        observed_registration_digits: expectedDigits(mode)};
    assert.deepEqual(registrationModeProof(mode, receipt, policy, audio), {
        registration_mode: mode, expected_registration_digits: expectedDigits(mode), observed_registration_digits: expectedDigits(mode)}); checks++;
    for (const mutate of [
        r => {r.receipt.registration_mode = mode === 'entry-only' ? 'confirm-current' : 'entry-only';},
        r => {r.receipt.input_sha256['../test-acdc-callback-fixture.sh'] = '0'.repeat(64);},
        r => {r.receipt.scenario_sha256['callback-retry-request.xml'] = '0'.repeat(64);},
        r => {r.policy.allow_alternate_number = true;}, r => {r.policy.fixture_verified = false;},
        r => {r.policy.account_id = 'other';}, r => {r.policy.entry_key = '1';},
        r => {r.audio.result = 'FAIL';}, r => {r.audio.registration_mode = 'auto';},
        r => {r.audio.expected_registration_digits = [];}, r => {r.audio.observed_registration_digits = [6, 1, 1];}
    ]) {
        const copy = structuredClone({receipt, policy, audio}); mutate(copy);
        assert.throws(() => registrationModeProof(mode, copy.receipt, copy.policy, copy.audio)); checks++;
    }
}
const base = {id: 'acdc-callback-' + 'a'.repeat(64), account_id: account, queue_id: 'b'.repeat(32),
    original_call_id: '1-123@127.0.0.20', number: '+12025550101', enqueued_at: 100, enqueue_sequence: 1,
    max_attempts: 2, retry_delay: 15, reconciliation_required: false};
const good = {registered: {...base, status: 'queued', attempts: 0},
    first: {callback: {...base, status: 'originating', attempts: 1, caller_call_id: 'c'.repeat(32)},
        caller: {id: 'c'.repeat(32), account, callback_id: base.id, sip_call_id: 'first@fs', answered: '0', bridge_to: null}},
    backoff: {...base, status: 'retry_wait', attempts: 1, next_attempt_at: GREGORIAN_UNIX_OFFSET + 145, last_cause: 'NO_ANSWER'},
    bridged: {callback: {...base, status: 'completed', attempts: 2, caller_call_id: 'd'.repeat(32), agent_call_id: 'e'.repeat(32)},
        caller: {id: 'd'.repeat(32), account, bridge_to: 'e'.repeat(32), sip_call_id: 'second@fs'},
        agent: {id: 'e'.repeat(32), account, bridge_to: 'd'.repeat(32), sip_call_id: 'agent2@fs'}},
    busy: {caller: {id: 'busy', account, bridge_to: 'agent1', contact_host: '127.0.0.20', contact_port: '15066', answered: '100'},
        agent: {id: 'agent1', account, bridge_to: 'busy', contact_host: '127.0.0.20', contact_port: '15100', answered: '100'}},
    audio: {confirmation_end_epoch_seconds: 115, original_bye_epoch_seconds: 116}, release: 118};
assert.deepEqual(lifecycle(good), {callerCallId: 'second@fs', agentCallId: 'agent2@fs'}); checks++;
const native = structuredClone(good);
for (const doc of [native.registered, native.first.callback, native.backoff, native.bridged.callback]) {
    doc.number = '1001';
    doc.internal_target = {number:'1001',type:'user',id:'1'.repeat(32),flow_id:'2'.repeat(32)};
}
assert.deepEqual(lifecycle(native, 'internal'), {callerCallId:'second@fs',agentCallId:'agent2@fs'}); checks++;
assert.throws(() => lifecycle(native)); checks++;
assert.throws(() => lifecycle(good, 'internal')); checks++;
assert.throws(() => lifecycle(good, 'automatic')); checks++;
for (const change of [e=>{e.registered.internal_target=null;},e=>{e.backoff.internal_target.id='3'.repeat(32);},
    e=>{e.bridged.callback.number='+12025550101';},e=>{e.first.callback.internal_target.flow_id='4'.repeat(32);}]) {
    const modified=structuredClone(native);change(modified);assert.throws(()=>lifecycle(modified,'internal'));checks++;
}
const failures = [
    e => {e.registered.status = 'completed';}, e => {e.registered.attempts = 1;},
    e => {e.first.callback.id = 'other';}, e => {e.first.caller.account = 'wrong';},
    e => {e.first.caller.callback_id = 'wrong';}, e => {e.first.caller.answered = '1';},
    e => {e.first.caller.bridge_to = 'some-call';}, e => {e.backoff.status = 'cancelling';},
    e => {e.backoff.reconciliation_required = true;}, e => {e.backoff.last_cause = '';},
    e => {e.backoff.next_attempt_at = 0;}, e => {e.bridged.callback.attempts = 1;},
    e => {e.bridged.callback.max_attempts = 3;}, e => {e.bridged.callback.retry_delay = 5;},
    e => {e.bridged.callback.enqueue_sequence = 2;}, e => {e.bridged.caller.sip_call_id = 'first@fs';},
    e => {e.bridged.agent.bridge_to = 'wrong';}, e => {e.busy.caller.contact_port = '15064';},
    e => {e.busy.agent.account = 'wrong';}, e => {e.busy.agent.answered = '0';},
    e => {e.release = 116;}, e => {e.audio.confirmation_end_epoch_seconds = 119;}
];
for (const alter of failures) {const value = structuredClone(good); alter(value); assert.throws(() => lifecycle(value)); checks++;}
const first = {offerAt: 115, cancelAt: 130, endAt: 131};
assert.deepEqual(retryTiming(first, 145, good.backoff), {configured_backoff_seconds: 15,
    second_invite_epoch_seconds: 145, cancel_to_second_invite_seconds: 15,
    first_ack_to_second_invite_seconds: 14, first_ack_to_durable_due_seconds: 14,
    second_invite_after_durable_due_seconds: 0}); checks++;
for (const at of [130, 143, 144.9, 166]) {assert.throws(() => retryTiming(first, at, good.backoff)); checks++;}
assert.throws(() => retryTiming(first, 145, {...good.backoff, next_attempt_at: 145})); checks++;
const earlyCleanup = {offerAt: 125, cancelAt: 130, endAt: 131};
assert.throws(() => retryTiming(earlyCleanup, 145, good.backoff)); checks++;
retryTiming(earlyCleanup, 145, good.backoff, {worker_loss: true, epoch_ms: 128000}); checks++;
for (const loss of [{worker_loss:false,epoch_ms:128000},{worker_loss:true,epoch_ms:124000},
    {worker_loss:true,epoch_ms:131000},{worker_loss:true,epoch_ms:NaN}]) {
    assert.throws(() => retryTiming(earlyCleanup,145,good.backoff,loss)); checks++;
}
assert.throws(() => retryTiming({offerAt:100,cancelAt:130,endAt:131},145,good.backoff,
    {worker_loss:true,epoch_ms:110000})); checks++;
const script = path.join(__dirname, 'test-acdc-callback-retry.sh');
function shell(code) {
    const result = spawnSync('bash', ['-c', 'KAZOO_CALLBACK_RETRY_LIBRARY=true source "$1"\n' + code, 'test', script], {encoding: 'utf8'});
    return result;
}
for (const [input, accepted] of [[{row_count: 0}, true], [{row_count: 0, rows: null}, true],
    [{row_count: 0, rows: []}, true], [{row_count: 1}, false], [{row_count: 0, rows: [{}]}, false],
    [{row_count: 1, rows: [{uuid: 'u', direction: 'inbound'}]}, true],
    [{row_count: 1, rows: [{}]}, false], [{row_count: 1, rows: [{uuid: ''}]}, false],
    [{row_count: 2, rows: [{uuid: 'u'}, {uuid: 'u'}]}, false]]) {
    const result = shell('timeout() { printf \'%s\\n\' \' ' + JSON.stringify(input).trim() + '\'; }; retry_snapshot');
    assert.equal(result.status === 0, accepted, 'Native snapshot shape ' + JSON.stringify(input)); checks++;
}
for (const [incoming, clearResult, expected] of [[0, 0, 0], [0, 1, 1], [7, 0, 7], [7, 1, 7]]) {
    const result = shell(`retry_clear_busy() { return ${clearResult}; }
callback_cleanup() { local code=$?; trap - EXIT; exit "$code"; }
trap retry_cleanup EXIT
exit ${incoming}`);
    assert.equal(result.status, expected, 'Retry cleanup must not mask ownership or original failures'); checks++;
}
const source = fs.readFileSync(script, 'utf8');
assert(/retry_start_original\(\)[\s\S]*?-rtp_echo/.test(source));
assert(source.indexOf('callback_fixture cancel-original "$CALLBACK_ORIGINAL_CALL_ID" >')
    < source.indexOf("if ! retry_clear_busy; then"));
for (const [signal, status] of [['INT', 130], ['TERM', 143]]) {
    const traps = source.match(/    trap retry_cleanup EXIT\n    trap 'exit 130' INT\n    trap 'exit 143' TERM/);
    assert(traps, 'Signals must set failure before EXIT cleanup');
    const result = shell('retry_clear_busy() { return 0; }\n'
        + 'callback_cleanup() { local code=$?; trap - EXIT; exit "$code"; }\n'
        + traps[0] + '\ntrue\nkill -' + signal + ' $$');
    assert.equal(result.status, status, 'Actual ' + signal + ' must not report a successful diagnostic'); checks++;
}
assert(source.includes('[[ $reply == \'+OK\' ]]'));
assert(!source.includes('uuid_kill all') && !source.includes('hupall') && !source.includes('callback_fixture cleanup'));
assert(source.includes('callback_fixture setup-retry') && source.includes('flock -n 9'));
assert(source.includes('RETRY_REGISTRATION_MODE=confirm-current'));
assert(source.includes('--registration-mode)'));
assert(source.includes('create-callback-retry-scenarios.cjs" "$RUN_DIR" "$RETRY_REGISTRATION_MODE"'));
assert(source.includes('"$CALLBACK_ORIGINAL_MEDIA_PORT" "$RETRY_REGISTRATION_MODE"'));
assert(source.includes('assert-callback-retry.cjs" "$RUN_DIR" "$RETRY_REGISTRATION_MODE"'));
assert(source.indexOf('callback_fixture verify') < source.indexOf('retry-registration-policy.json'));
assert(source.indexOf('assert-callback-registration-audio.cjs" \\\n') < source.indexOf("log 'Busy call bridged"));
assert(source.includes('sleep 2\n    retry_clear_busy'));
assert(source.includes('retry_capture returned\n    # Start the answering endpoint'));
assert(source.includes('retry_wait_backoff || die') && source.includes('retry_wait_first_attempt || die'));
assert(source.includes('tcpdump --immediate-mode -B 16384 -q -n -i any -U'));
for (const port of [15064, 15066, 15100, 43000, 43020, 40000, 16060, 44000]) {
    assert(source.includes('src port ' + port) && source.includes('dst port ' + port));
}
checks++;
const os = require('node:os');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-retry-private-tests.'));
fs.chmodSync(temporary, 0o700);
try {
    const pcap = path.join(temporary, 'retry-original.pcap');
    const captureLog = path.join(temporary, 'retry-original-capture.log');
    fs.writeFileSync(captureLog, '0 packets dropped by kernel\n', {mode: 0o600});
    fs.writeFileSync(pcap, 'synthetic private test only', {mode: 0o640});
    fs.chownSync(pcap, 65534, 65534);
    const normalize = name => shell('RUN_DIR=' + JSON.stringify(temporary) + '\nRTP_PCAP=' + JSON.stringify(path.join(temporary, name))
        + '\nRTP_CAPTURE_LOG=' + JSON.stringify(captureLog) + '\nstop_rtp_capture() { :; }\nretry_stop_capture');
    assert.equal(normalize('retry-original.pcap').status, 0);
    assert.equal(fs.statSync(pcap).uid, 0); assert.equal(fs.statSync(pcap).mode & 0o777, 0o600); checks++;
    fs.symlinkSync(pcap, path.join(temporary, 'retry-unanswered.pcap'));
    assert.notEqual(normalize('retry-unanswered.pcap').status, 0); checks++;
    fs.writeFileSync(path.join(temporary, 'wrong.pcap'), 'private');
    assert.notEqual(normalize('wrong.pcap').status, 0); checks++;
    fs.linkSync(pcap, path.join(temporary, 'retry-returned.pcap'));
    assert.notEqual(normalize('retry-returned.pcap').status, 0); checks++;
    fs.unlinkSync(path.join(temporary, 'retry-returned.pcap'));
    fs.writeFileSync(captureLog, '1 packets dropped by kernel\n');
    assert.notEqual(normalize('retry-original.pcap').status, 0); checks++;
    if (process.argv.includes('--parse')) {
        const parsing = {...generated, 'entry-only-callback-retry-request.xml': entryOnly['callback-retry-request.xml']};
        for (const [index, [name, xml]] of Object.entries(Object.entries(parsing))) {
            const file = path.join(temporary, name), csv = path.join(temporary, name + '.csv');
            fs.writeFileSync(file, xml, {mode: 0o600});
            fs.writeFileSync(csv, 'SEQUENTIAL\ndummy;[authentication username=dummy password=dummy];example.invalid;2000;120000;0\n', {mode: 0o600});
            const result = spawnSync('sipp', ['-ci','127.0.0.1','127.0.0.62:9', '-sf', file, '-inf', csv,
                '-i', '127.0.0.62', '-p', String(18562 + Number(index)), '-m', '0', '-nostdin'],
            {encoding: 'utf8', timeout: 5000});
            assert.equal(result.status, 0, 'Actual SIPp rejected generated ' + name + ': ' + result.stderr);
            assert(!/parse error|Unknown element|Variable .* referenced/i.test(result.stdout + result.stderr)); checks++;
        }
    }
    for (const status of [0, 97]) {
        const result = shell('RUN_DIR=' + JSON.stringify(temporary)
            + '\n(exit ' + status + ') &\npid=$!\nretry_wait_checked original "$pid"');
        assert.equal(result.status === 0, status === 0);
        assert(fs.readFileSync(path.join(temporary, 'retry-process-exits.tsv'), 'utf8').trim().endsWith('\t' + status)); checks++;
    }
    const order = shell('RUN_DIR=' + JSON.stringify(temporary) + '\nFIXTURE_CREATED=true\nCALLBACK_ORIGINAL_CALL_ID=1-123@127.0.0.20\n'
        + 'callback_fixture() { printf \'cancel\\n\' >> "$RUN_DIR/order"; }\n'
        + 'retry_clear_busy() { printf \'release\\n\' >> "$RUN_DIR/order"; }\n'
        + 'callback_cleanup() { local code=$?; trap - EXIT; exit "$code"; }\n'
        + 'trap retry_cleanup EXIT\nexit 0');
    assert.equal(order.status, 0);
    assert.equal(fs.readFileSync(path.join(temporary, 'order'), 'utf8'), 'cancel\nrelease\n'); checks++;
} finally {fs.rmSync(temporary, {recursive: true});}
console.log('PASS ' + checks + ' retry scenario/lifecycle/timing/native-snapshot/cleanup/scope groups; no API, SIP or service changes');
