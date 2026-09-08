#!/usr/bin/env node
'use strict';
// Five fixed release recordings. Generation is explicit authoring only.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const samples = require('./generate-acdc-gemini-samples.cjs');
const fixed = require('./generate-acdc-gemini-fixed-pack.cjs');
const {couchClient} = require('./import-acdc-language-packs.cjs');
const OWNER = 'kazoo5_call_forward_confirmation_v1';
const PACK = path.join(__dirname, 'assets/call-forward-confirmation-20260908');
const CATALOG = [
    {locale: 'en-us', language: 'American English', transcript: 'This is a forwarded call. Press one to accept, or hang up to ignore.'},
    {locale: 'he-il', language: 'Israeli Hebrew', transcript: 'זוהי שיחה שהועברה אליכם. לקבלת השיחה, הקישו אחת. כדי להתעלם מהשיחה, נתקו.'},
    {locale: 'ar-sa', language: 'Modern Standard Arabic', transcript: 'هذه مكالمة مُحوَّلة. لقبول المكالمة، اضغط واحدًا. لتجاهل المكالمة، أغلق الخط.'},
    {locale: 'es-es', language: 'Spanish', transcript: 'Esta es una llamada transferida. Pulse uno para aceptar, o cuelgue para ignorar la llamada.'},
    {locale: 'fr-fr', language: 'French', transcript: 'Ceci est un appel transféré. Appuyez sur un pour accepter, ou raccrochez pour ignorer cet appel.'}
];
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const catalogHash = sha(JSON.stringify(CATALOG));
const name = (locale, attempt, kind) => `${locale}.attempt-${attempt}.${kind}.wav`;
function body(entry) {
    return {contents: [{parts: [{text: `Read only the following transcript, exactly once, in native ${entry.language}. ` +
        'Use a warm, clear, natural adult female telephone operator voice. No introduction, commentary, music or sound effects. ' +
        'Speak at a comfortable pace and finish the complete message within 12 seconds.\n\nTranscript:\n' + entry.transcript}]}],
    generationConfig: {responseModalities: ['AUDIO'], speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: samples.VOICE}}}}};
}
function readManifest(directory) {
    assert(path.isAbsolute(directory) && fs.realpathSync(directory) === directory && fs.lstatSync(directory).isDirectory());
    const m = JSON.parse(fixed.regularBytes(path.join(directory, 'manifest.json')));
    assert(m.owner === OWNER && m.schema_version === 1 && m.catalog_sha256 === catalogHash);
    assert(m.model === samples.MODEL && m.voice === samples.VOICE && m.provider === 'google-gemini');
    assert.deepEqual(m.transcripts, CATALOG);
    assert(m.native_speaker_review === false && m.runtime_verified === false && m.automatic_retries === 0);
    assert(Array.isArray(m.attempts) && m.attempts.length <= CATALOG.length * 2 && m.requests_reserved === m.attempts.length);
    const seen = new Set();
    for (const e of m.attempts) {
        const expected = CATALOG.find(p => p.locale === e.locale);
        assert(expected && [1, 2].includes(e.attempt) && !seen.has(`${e.locale}/${e.attempt}`));
        seen.add(`${e.locale}/${e.attempt}`);
        assert(e.transcript_sha256 === sha(expected.transcript) && e.request_sha256 === sha(JSON.stringify(body(expected))));
        assert(['REQUESTING', 'FAILED', 'GENERATED'].includes(e.status));
        if (e.attempt === 2) assert(m.attempts.some(p => p.locale === e.locale && p.attempt === 1 && p.status === 'FAILED'));
        if (e.status === 'GENERATED') verifyEntry(directory, e);
    }
    return m;
}
function verifyEntry(directory, e) {
    for (const [kind, rate] of [['master', 24000], ['telephony', 8000]]) {
        assert(e[kind]?.file === name(e.locale, e.attempt, kind));
        const metrics = fixed.metrics(fixed.regularBytes(path.join(directory, e[kind].file)), rate, {maximum_duration_seconds: 12});
        assert.deepEqual(metrics, e[kind].metrics);
    }
    assert(Math.abs(e.master.metrics.duration_seconds - e.telephony.metrics.duration_seconds) <= 1 / 8000);
}
function loadPlan(directory = PACK) {
    const m = readManifest(directory);
    return CATALOG.map(expected => {
        const found = m.attempts.filter(e => e.locale === expected.locale && e.status === 'GENERATED');
        assert(found.length === 1, 'A packaged locale recording is missing');
        const e = found[0], bytes = fixed.regularBytes(path.join(directory, e.telephony.file));
        const hash = sha(bytes), prompt = `cfwd-confirm-v1-sulafat-${hash.slice(0, 16)}`;
        return {locale: e.locale, prompt_id: prompt, id: `${e.locale}/${prompt}`, attachment: prompt + '.wav',
            sha256: hash, md5: 'md5-' + crypto.createHash('md5').update(bytes).digest('base64'),
            transcript_sha256: e.transcript_sha256, duration_seconds: e.telephony.metrics.duration_seconds, bytes};
    });
}
function document(a) {
    return {_id: a.id, name: a.id, prompt_id: a.prompt_id, language: a.locale, pvt_type: 'media',
        pvt_account_db: 'system_media', pvt_vsn: '1', source_type: OWNER, content_type: 'audio/wav',
        content_length: a.bytes.length, streamable: true,
        source_voice: {provider: 'google-gemini', model: samples.MODEL, voice: samples.VOICE,
            sha256: a.sha256, transcript_sha256: a.transcript_sha256},
        _attachments: {[a.attachment]: {content_type: 'audio/wav', data: a.bytes.toString('base64')}}};
}
function verifyDocument(a, doc) {
    assert(doc && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(doc._rev) && !doc._deleted && !doc.pvt_deleted);
    assert(!doc._conflicts || (Array.isArray(doc._conflicts) && doc._conflicts.length === 0));
    const expected = document(a);
    for (const k of ['_id', 'prompt_id', 'language', 'pvt_type', 'pvt_account_db', 'source_type', 'content_type', 'content_length', 'streamable'])
        assert.deepEqual(doc[k], expected[k], 'Installed confirmation media identity differs');
    assert.deepEqual(doc.source_voice, expected.source_voice);
    assert.deepEqual(Object.keys(doc._attachments || {}), [a.attachment]);
    const att = doc._attachments[a.attachment];
    assert(att.content_type === 'audio/wav' && att.digest === a.md5 && typeof att.data === 'string');
    const bytes = Buffer.from(att.data, 'base64');
    assert(bytes.toString('base64') === att.data && bytes.length === a.bytes.length && sha(bytes) === a.sha256);
}
async function install(plan, client, write = false) {
    assert(plan.length === CATALOG.length && new Set(plan.map(a => a.id)).size === CATALOG.length);
    let created = 0;
    async function read(a) {
        const r = await client('POST', '_all_docs?include_docs=true&attachments=true&conflicts=true', {keys: [a.id]});
        assert(r.status === 200 && Array.isArray(r.body?.rows) && r.body.rows.length === 1);
        const row = r.body.rows[0]; assert(row.key === a.id);
        if (row.error !== undefined) {
            assert(row.error === 'not_found' && row.doc === undefined && row.value === undefined && row.id === undefined);
            return null;
        }
        assert(row.id === a.id && row.value && row.value.deleted !== true && row.value.rev === row.doc?._rev,
            'Deleted/unavailable media is not an absent asset');
        verifyDocument(a, row.doc); return row.doc;
    }
    // Preflight every existing identity before any writes.
    const existing = [];
    for (const a of plan) existing.push(await read(a));
    for (let i = 0; i < plan.length; i++) {
        if (existing[i]) continue;
        assert(write, 'Required confirmation recording is not installed');
        const a = plan[i], r = await client('PUT', encodeURIComponent(a.id), document(a));
        assert([201, 202, 409].includes(r.status));
        if (r.status !== 409) {
            assert(r.body?.ok === true && r.body.id === a.id && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(r.body.rev));
            created++;
        }
    }
    const prompts = [];
    for (const a of plan) {
        const doc = await read(a); assert(doc);
        prompts.push({locale: a.locale, document_id: a.id, revision: doc._rev, sha256: a.sha256});
    }
    return {owner: OWNER, verified: CATALOG.length, created, account_changes: false, prompts};
}
function erlangMap(plan) {
    return '%% Generated from byte-verified release recordings; do not edit.\n-define(CFWD_CONFIRMATION_ASSETS, [\n' +
        plan.map(a => `    {<<"${a.locale}">>, <<"${a.id}">>, <<"${a.prompt_id}">>, <<"${a.sha256}">>, <<"${a.md5}">>, ${a.bytes.length}, <<"${a.transcript_sha256}">>}`).join(',\n') + '\n]).\n';
}
async function generate(directory, keyFile, {resume = false, retry = false, deps = {}} = {}) {
    fixed.directoryTarget(directory, resume);
    if (!resume) fs.mkdirSync(directory, {mode: 0o700});
    const stat = fs.statSync(directory); assert(stat.uid === process.getuid() && (stat.mode & 0o077) === 0);
    const lockPath = path.join(directory, '.generation.lock');
    const lock = fs.openSync(lockPath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
    try {
        const m = resume ? readManifest(directory) : {owner: OWNER, schema_version: 1, catalog_sha256: catalogHash,
            provider: 'google-gemini', model: samples.MODEL, voice: samples.VOICE, automatic_retries: 0,
            native_speaker_review: false, runtime_verified: false, requests_reserved: 0, attempts: [],
            conversion: {tool: 'sox', version: fixed.conversionVersion()}, transcripts: CATALOG};
        const jobs = CATALOG.filter(p => !m.attempts.some(e => e.locale === p.locale) ||
            (retry && m.attempts.some(e => e.locale === p.locale && e.status === 'FAILED' && e.attempt === 1) &&
             !m.attempts.some(e => e.locale === p.locale && e.attempt === 2)));
        if (!jobs.length) return loadPlan(directory);
        let key = (deps.readKey || samples.readProtectedKey)(keyFile);
        try {
            for (const p of jobs) {
                const attempt = m.attempts.some(e => e.locale === p.locale) ? 2 : 1;
                const request = body(p), e = {locale: p.locale, attempt, status: 'REQUESTING',
                    transcript_sha256: sha(p.transcript), request_sha256: sha(JSON.stringify(request)), reserved_at: new Date().toISOString()};
                m.attempts.push(e); m.requests_reserved++; fixed.manifestWrite(directory, m);
                try {
                    const response = await (deps.request || samples.requestSpeech)(request, key);
                    const pcm = samples.extractPcm(response), master = samples.makeWave(pcm, 24000);
                    e.raw_pcm_sha256 = sha(pcm);
                    const masterFile = name(p.locale, attempt, 'master'), telephoneFile = name(p.locale, attempt, 'telephony');
                    e.master = {file: masterFile, metrics: fixed.metrics(master, 24000, {maximum_duration_seconds: 12})};
                    fs.writeFileSync(path.join(directory, masterFile), master, {flag: 'wx', mode: 0o644});
                    (deps.resample || fixed.resample)(path.join(directory, masterFile), path.join(directory, telephoneFile));
                    e.telephony = {file: telephoneFile, metrics: fixed.metrics(fixed.regularBytes(path.join(directory, telephoneFile)), 8000, {maximum_duration_seconds: 12})};
                    verifyEntry(directory, e); e.status = 'GENERATED';
                } catch (error) {
                    e.status = 'FAILED'; e.failure_code = error instanceof samples.SampleError ? error.code : 'LOCAL_OPERATION_FAILED';
                }
                fixed.manifestWrite(directory, m);
                (deps.output || console.log)(JSON.stringify({locale: e.locale, attempt, status: e.status, failure_code: e.failure_code}));
            }
        } finally { key = undefined; }
        return loadPlan(directory);
    } finally { fs.closeSync(lock); fs.unlinkSync(lockPath); }
}
async function main(argv) {
    const mode = argv[0];
    assert(['--plan', '--verify-only', '--import', '--generate', '--map'].includes(mode), 'Explicit mode required');
    const o = {}; for (let i = 1; i < argv.length; i++) {
        const key = argv[i]; assert(!Object.hasOwn(o, key));
        if (['--resume', '--retry-failed'].includes(key)) o[key] = true;
        else { assert(['--output', '--key-file'].includes(key) && argv[i + 1]); o[key] = argv[++i]; }
    }
    if (mode === '--generate') {
        assert(o['--output'] && o['--key-file'] && (!o['--retry-failed'] || o['--resume']));
        await generate(o['--output'], o['--key-file'], {resume: o['--resume'], retry: o['--retry-failed']}); return;
    }
    assert(!o['--key-file'] && !o['--resume'] && !o['--retry-failed']);
    const plan = loadPlan(o['--output'] || PACK);
    if (mode === '--map') { process.stdout.write(erlangMap(plan)); return; }
    assert.equal(fixed.regularBytes(path.join(o['--output'] || PACK, 'assets.hrl')).toString(), erlangMap(plan),
        'Recordings differ from the pinned release map');
    if (mode === '--plan') console.log(JSON.stringify({owner: OWNER, count: CATALOG.length, locales: CATALOG.map(p => p.locale), account_changes: false}));
    else console.log(JSON.stringify(await install(plan, couchClient(process.env), mode === '--import')));
}
module.exports = {OWNER, PACK, CATALOG, sha, body, readManifest, loadPlan, document, verifyDocument, install, erlangMap, generate};
if (require.main === module) main(process.argv.slice(2)).catch(() => {
    console.error('Call-forward confirmation pack operation failed; inspect the nonsecret manifest. No existing recording or account was overwritten.');
    process.exitCode = 1;
});
