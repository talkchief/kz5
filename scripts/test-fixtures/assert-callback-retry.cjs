#!/usr/bin/env node
'use strict';
// This is a two-attempt diagnostic contract, separate from the strict existing
// single-attempt acceptance gate. No SIP credentials or raw audio are emitted.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {modeReceipt, expectedDigits} = require('./create-callback-retry-scenarios.cjs');
const media = require('./assert-callback-confirmation-pcap.cjs');
const ACCOUNT = '7807ad61761269a1ccec833dde63f621';
const GREGORIAN_UNIX_OFFSET = 62167219200;
const id = value => typeof value === 'string' && /^[A-Za-z0-9@._:-]{1,128}$/.test(value);
function lifecycle({registered, first, backoff, bridged, busy, audio, release}, transport = 'external') {
    require('./callback-internal-scenarios.cjs').target(transport);
    const number = transport === 'internal' ? '1001' : '+12025550101';
    const doc = bridged.callback, caller = bridged.caller, agent = bridged.agent;
    assert(registered.account_id === ACCOUNT && registered.status === 'queued' && registered.attempts === 0,
        'Original callback was not durably queued while agent was busy');
    for (const current of [first.callback, backoff, doc]) {
        assert(current.id === registered.id && current.account_id === ACCOUNT && current.queue_id === registered.queue_id
            && current.original_call_id === registered.original_call_id && current.number === number
            && current.enqueued_at === registered.enqueued_at && current.enqueue_sequence === registered.enqueue_sequence
            && current.max_attempts === 2 && current.retry_delay === 15 && current.reconciliation_required !== true,
        'Retry changed callback identity, ordering, policy, ownership or settlement');
    }
    if (transport === 'internal') {
        const target = registered.internal_target;
        assert(target && target.number === '1001' && target.type === 'user'
            && /^[a-f0-9]{32}$/.test(target.id) && /^[a-f0-9]{32}$/.test(target.flow_id),
            'Internal registration did not pin an account-local user route');
        for (const current of [first.callback, backoff, doc]) {
            assert.deepEqual(current.internal_target, target, 'Pinned internal route changed across attempts');
        }
    }
    assert(first.callback.attempts === 1 && id(first.caller.sip_call_id)
        && first.caller.id === first.callback.caller_call_id && first.caller.account === ACCOUNT
        && first.caller.callback_id === registered.id && !first.caller.bridge_to
        && (first.caller.answered === null || Number(first.caller.answered) === 0),
    'First attempted caller lacks exact unanswered native correlation');
    assert(backoff.status === 'retry_wait' && backoff.attempts === 1 && Number.isInteger(backoff.next_attempt_at)
        && backoff.next_attempt_at > 0 && typeof backoff.last_cause === 'string' && backoff.last_cause.length > 0,
    'Missing durable positive-settlement backoff after unanswered attempt');
    assert(doc.status === 'completed' && doc.attempts === 2 && caller.account === ACCOUNT && agent.account === ACCOUNT
        && caller.id === doc.caller_call_id && agent.id === doc.agent_call_id
        && caller.bridge_to === agent.id && agent.bridge_to === caller.id
        && id(caller.sip_call_id) && id(agent.sip_call_id) && caller.sip_call_id !== agent.sip_call_id
        && caller.id !== first.caller.id && caller.sip_call_id !== first.caller.sip_call_id,
    'Second attempt lacks distinct exact completed reciprocal native bridge');
    assert(busy.caller.account === ACCOUNT && busy.agent.account === ACCOUNT
        && busy.caller.bridge_to === busy.agent.id && busy.agent.bridge_to === busy.caller.id
        && busy.caller.contact_host === '127.0.0.20' && Number(busy.caller.contact_port) === 15066
        && busy.agent.contact_host === '127.0.0.20' && Number(busy.agent.contact_port) === 15100
        && Number(busy.caller.answered) > 0 && Number(busy.agent.answered) > 0,
    'First conversation lacks actual answered reciprocal local bridge');
    assert(Number.isFinite(release) && Number.isFinite(audio.confirmation_end_epoch_seconds)
        && Number.isFinite(audio.original_bye_epoch_seconds)
        && audio.confirmation_end_epoch_seconds <= audio.original_bye_epoch_seconds
        && release >= audio.confirmation_end_epoch_seconds + 2 && release >= audio.original_bye_epoch_seconds,
    'Initial call ended before complete received confirmation plus two seconds');
    return {callerCallId: caller.sip_call_id, agentCallId: agent.sip_call_id};
}
function firstOffer(buffer, expected, transport='external') {
    const endpointIp=require('./callback-internal-scenarios.cjs').endpointIp(transport);
    const found = media.packets(buffer).filter(packet => packet.dst === endpointIp && packet.dport === 16060
        && packet.payload.subarray(0, 7).toString('latin1') === 'INVITE ');
    assert(found.length > 0, 'No second returned INVITE');
    for (const packet of found) {
        const match = /\r\nCall-ID:\s*([^\r\n]+)\r\n/i.exec(packet.payload.toString('latin1'));
        assert(match && match[1] === expected, 'Unexpected second-phase returned dialog');
    }
    return Math.min(...found.map(packet => packet.time));
}
function retryTiming(first, secondAt, backoff) {
    assert(Number.isFinite(first.offerAt) && first.cancelAt - first.offerAt >= 14
        && first.cancelAt - first.offerAt <= 26,
    'Unanswered ringing did not respect the15s timeout plus bounded worker watchdog');
    assert(secondAt > first.endAt && secondAt >= first.cancelAt + 14,
        'Retry overlapped first transaction or skipped the configured backoff');
    // Durable wall-clock seconds have one-second granularity; compare directly
    // to next_attempt_at, not a guessed delay from a polled status sample.
    const nextAt = backoff.next_attempt_at - GREGORIAN_UNIX_OFFSET;
    assert(Number.isSafeInteger(backoff.next_attempt_at) && nextAt > 0
        && secondAt >= nextAt && secondAt <= nextAt + 20,
        'Second INVITE did not occur in the bounded durable retry window');
    return {configured_backoff_seconds: 15, second_invite_epoch_seconds: secondAt,
        cancel_to_second_invite_seconds: secondAt - first.cancelAt,
        first_ack_to_second_invite_seconds: secondAt - first.endAt,
        first_ack_to_durable_due_seconds: nextAt - first.endAt,
        second_invite_after_durable_due_seconds: secondAt - nextAt};
}
function safeRead(directory, name, limit = 64 * 1024 * 1024) {
    const file = path.join(directory, name), stat = fs.lstatSync(file);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0
        && stat.size > 0 && stat.size <= limit, 'Unsafe or missing protected retry evidence');
    return fs.readFileSync(file);
}
function registrationModeProof(mode, receipt, policy, audio, language) {
    if (language !== undefined) require('./callback-gemini-reference.cjs').language(language);
    const expected = expectedDigits(mode);
    assert.deepEqual(receipt, modeReceipt(mode), 'Registration mode or source inputs changed since scenario creation');
    assert.deepEqual(policy, {registration_mode: mode, account_id: ACCOUNT, entry_key: '6',
        allow_alternate_number: false, fixture_verified: true, ...(language === undefined ? {} : {language})}, 'Registration fixture policy does not match explicit mode');
    assert.equal(audio.result, 'PASS', 'Registration audio was not accepted');
    assert.equal(audio.registration_mode, mode, 'Registration audio belongs to another mode');
    assert.deepEqual(audio.expected_registration_digits, expected, 'Audio expected digits disagree with run mode');
    assert.deepEqual(audio.observed_registration_digits, expected, 'Audio observed digits disagree with run mode');
    return {registration_mode: mode, expected_registration_digits: expected, observed_registration_digits: expected};
}
function inspect(directory, mode = 'confirm-current', transport = 'external', language) {
    require('./callback-internal-scenarios.cjs').target(transport);
    const json = name => JSON.parse(safeRead(directory, name, 128 * 1024));
    const serviceScope = json('retry-service-scope.json');
    assert.deepEqual(serviceScope, require('./callback-retry-service-scope.cjs').inspect(
        safeRead(directory, 'retry-service-before.txt', 8192).toString(), serviceScope.allow_paused_master_test_phones),
        'Service scope receipt differs from the actual initial snapshot');
    const evidence = {registered: json('callback-registration-evidence.json'), first: json('retry-first-attempt.json'),
        backoff: json('retry-backoff-evidence.json'), bridged: json('retry-bridge-evidence.json'),
        busy: json('retry-busy-before-release.json'), audio: json('retry-registration-audio.json'),
        release: Number(safeRead(directory, 'retry-busy-release-epoch.txt', 128).toString().trim())};
    const selectionReceipt = json('retry-registration-mode.json');
    const selection = registrationModeProof(mode, selectionReceipt, json('retry-registration-policy.json'), evidence.audio, language);
    for (const [name, hash] of Object.entries(selectionReceipt.scenario_sha256)) {
        assert.equal(crypto.createHash('sha256').update(safeRead(directory, name, 128 * 1024)).digest('hex'), hash,
            'Scenario bytes differ from explicit registration-mode receipt');
    }
    const proof = lifecycle(evidence, transport);
    const busyDown = json('retry-busy-both-down.json');
    assert(Array.isArray(busyDown.rows) && busyDown.rows.every(row => typeof row.uuid === 'string'
        && row.uuid !== evidence.busy.caller.id && row.uuid !== evidence.busy.agent.id),
    'Missing fresh native proof both initial conversation legs ended');
    const receipt = json('retry-registration-reference-receipt.json');
    const rawHash = safeRead(directory, 'retry-registration-reference-sha256.txt', 128).toString().trim();
    const voiceFamily = require('./callback-gemini-reference.cjs').validateReceipt(receipt, rawHash, language);
    assert(evidence.audio.reference_sha256 === rawHash,
    'Received audio reference does not match installed-prompt receipt');
    const first = require('./assert-callback-unanswered.cjs').inspect(safeRead(directory, 'retry-unanswered.pcap'), undefined, transport);
    assert(first.firstCallerSipId === evidence.first.caller.sip_call_id, 'Unanswered packets belong to another native caller');
    assert(first.offerAt >= evidence.release, 'Callback originated while the only agent was still busy');
    const firstDown = json('retry-first-both-down.json');
    assert(Array.isArray(firstDown.rows) && firstDown.rows.every(row => typeof row.uuid === 'string'
        && row.uuid !== evidence.first.caller.id && row.uuid !== evidence.registered.original_call_id),
    'First returned caller did not have independent native absence proof before retry');
    const secondCapture = safeRead(directory, 'retry-returned.pcap');
    const timing = retryTiming(first, firstOffer(secondCapture, proof.callerCallId,transport), evidence.backoff);
    for (const name of ['callback-original.log', 'callback-carrier.log', 'callback-agent-1.log', 'retry-busy.log']) {
        assert(!/Could not (?:bind port for|open socket for|set up media IP for) RTP streaming/i.test(safeRead(directory, name).toString()),
            'SIP success masked an RTP streaming failure');
    }
    const second = media.inspect(secondCapture, proof,
        media.negotiatedPayload(safeRead(directory, 'callback-carrier-negotiation.log', 8192).toString()), transport);
    return {scenario: 'busy-agent-unanswered-first-callback-retry', account_id: ACCOUNT,
        ...selection, transport, registration_input_sha256: selectionReceipt.input_sha256,
        service_scope: serviceScope,
        retained_fixture: true, full_cleanup_acceptance: false, original_registration_audio: evidence.audio,
        confirmation_voice_family: voiceFamily,
        ...(language === undefined ? {} : {confirmation_language: language}),
        confirmation_prompt_id: receipt.document_id,
        first_attempt: {...first, unanswered_seconds: first.cancelAt - first.offerAt},
        durable_retry_wait: true, attempts: 2, retry_delay_seconds: 15,
        measured_retry_timing: timing,
        first_call_release_after_confirmation_seconds: evidence.release - evidence.audio.confirmation_end_epoch_seconds,
        second_attempt: second};
}
module.exports = {lifecycle, retryTiming, firstOffer, inspect, registrationModeProof, GREGORIAN_UNIX_OFFSET};
if (require.main === module) {
    try {
        assert([3, 4, 5, 6].includes(process.argv.length), 'Usage: assert-callback-retry.cjs protected-run-directory [entry-only|confirm-current] [external|internal] [explicit-language]');
        const result = inspect(process.argv[2], process.argv[3] || 'confirm-current', process.argv[4] || 'external', process.argv[5]);
        fs.writeFileSync(path.join(process.argv[2], 'retry-packet-evidence.json'), JSON.stringify(result, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
        console.log('PASS exact busy/confirmation/retry lifecycle and phase-scoped SIP/RTP evidence; fixture retained');
    } catch (error) {console.error('Callback retry evidence FAIL: ' + error.message); process.exitCode = 1;}
}
