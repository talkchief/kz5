'use strict';
// Prepare once from exact original source/receipt pins; consume without a
// planner per call. No provider, SUP, media import, account or queue writes.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const crypto = require('node:crypto'), {spawnSync} = require('node:child_process');
const LOCALES = ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa'];
const OWNER = 'kazoo5-prerecorded-2098-reference-v1';
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const hash = h => typeof h === 'string' && h.length === 64 && /^[a-f0-9]{64}$/.test(h);
const sourceRoot = () => path.resolve(__dirname, '../..');
const helpers = root => ({probe: require(path.join(root, 'scripts/probe-acdc-prerecorded-runtime.cjs')),
    catalog: require(path.join(root, 'scripts/acdc-cardinal-catalog.cjs'))});
const exact = (x, fields) => assert(x && Object.getPrototypeOf(x) === Object.prototype
    && JSON.stringify(Object.keys(x).sort()) === JSON.stringify(fields.slice().sort()), 'Unexpected reference fields');
function selection(input, locale, catalog) {
    assert(LOCALES.includes(locale), 'Explicit supported locale required');
    const intro = ['he-il','ar-sa'].includes(locale) ? 'acdc-cardinal-intro-v1-current-position-number' : 'acdc-queue-your-current-position-is';
    const ids = ['acdc-callback-offer-6', intro, ...catalog.tokens(1, locale)];
    assert(ids.length >= 3 && ids.length <= 5 && new Set(ids).size === ids.length);
    return ids.map((id, i) => {
        const found = input.documents.filter(d => d.language === locale && d.source_voice?.canonical_prompt_id === id);
        assert(found.length === 1, 'Missing or ambiguous selected reference');
        return {key: i ? 'position-' + (i - 1) : 'offer', expected: found[0]};
    });
}
function verifyDocument(expected, doc) {
    assert(doc && [undefined,false].includes(doc._deleted) && [undefined,false].includes(doc.pvt_deleted)
        && (doc._conflicts === undefined || Array.isArray(doc._conflicts) && doc._conflicts.length === 0), 'Deleted/conflicted reference');
    for (const key of ['_id','_rev','prompt_id','language','source_type','content_length']) assert.deepEqual(doc[key], expected[key]);
    assert(doc.pvt_type === 'media' && doc.pvt_account_db === 'system_media'
        && [undefined, 'system_media'].includes(doc.pvt_account_id) && doc.content_type === 'audio/wav' && doc.streamable === true);
    for (const key of ['provider','model','voice','canonical_prompt_id','sha256','transcript_sha256'])
        assert.deepEqual(doc.source_voice?.[key], expected.source_voice[key], 'Reference voice/model differs');
    if (expected.source_cardinal_resolution === null) assert.equal(doc.source_cardinal_resolution, undefined);
    else assert.deepEqual(doc.source_cardinal_resolution, expected.source_cardinal_resolution, 'Reference selected lineage differs');
    assert.deepEqual(Object.keys(doc._attachments || {}), [expected.attachment]);
    const a = doc._attachments[expected.attachment];
    assert(a.content_type === 'audio/wav' && a.digest === expected.digest
        && (a.length === undefined || a.length === expected.content_length)
        && typeof a.data === 'string' && a.data.length <= 3 * 1024 * 1024 && /^[A-Za-z0-9+/]*={0,2}$/.test(a.data));
    const wav = Buffer.from(a.data, 'base64');
    assert(wav.toString('base64') === a.data && wav.length === expected.content_length && sha(wav) === expected.source_voice.sha256,
        'Installed reference bytes differ'); return wav;
}
function convert(wav) {
    const r = spawnSync('sox', ['-D','-t','wav','-','-t','raw','-r','8000','-c','1','-e','mu-law','-'],
        {input: wav, timeout: 15000, maxBuffer: 2 * 1024 * 1024});
    assert(!r.error && r.status === 0 && r.stdout.length >= 512 && r.stdout.length < 12 * 8000, 'Reference conversion/duration failed');
    return r.stdout;
}
function validateIndex(index, catalog) {
    exact(index, ['schema_version','owner','scope','source_probe_account','source_input_sha256','cardinal_receipt_sha256',
        'fixed_receipt_sha256','beam_manifest_sha256','locales','wait_time_verified','native_listening_approved','full_language_ready']);
    assert(index.schema_version === 1 && index.owner === OWNER && index.scope === 'position-one-and-offer-six'
        && typeof index.source_probe_account === 'string' && index.source_probe_account.length===32 && /^[a-f0-9]{32}$/.test(index.source_probe_account)
        && index.wait_time_verified === false && index.native_listening_approved === false && index.full_language_ready === false);
    for (const k of ['source_input_sha256','cardinal_receipt_sha256','fixed_receipt_sha256','beam_manifest_sha256']) assert(hash(index[k]));
    assert(Array.isArray(index.locales) && index.locales.length === 5);
    assert.deepEqual(index.locales.map(l => l.locale).sort(), LOCALES.slice().sort());
    for (const l of index.locales) {
        exact(l, ['locale','cardinal_map_sha256','fixed_map_sha256','assets']);
        assert(hash(l.cardinal_map_sha256) && hash(l.fixed_map_sha256) && Array.isArray(l.assets));
        const wanted = selection({documents: l.assets.map(a => a.expected)}, l.locale, catalog);
        assert.deepEqual(l.assets.map(a => a.key), wanted.map(a => a.key));
        assert.equal(l.assets.length, wanted.length);
        for (let i = 0; i < wanted.length; i++) {
            const a = l.assets[i], e = a.expected, voice = e.source_voice;
            exact(a, ['key','expected','file','ulaw_sha256','samples']);
            assert.deepEqual(e, wanted[i].expected);
            assert(a.file === l.locale + '/' + a.key + '.ulaw' && hash(a.ulaw_sha256)
                && Number.isSafeInteger(a.samples) && a.samples >= 512 && a.samples < 12 * 8000);
            assert(e.language === l.locale && e._id === l.locale + '/' + e.prompt_id
                && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(e._rev)
                && e.attachment === e.prompt_id + '.wav' && voice?.provider === 'google-gemini' && voice.voice === 'Sulafat'
                && hash(voice.sha256) && hash(voice.transcript_sha256)
                && e.prompt_id === voice.canonical_prompt_id + '-gemini-sulafat-' + voice.sha256.slice(0, 16));
            if (voice.model === 'gemini-3.1-flash-tts-preview') assert(voice.canonical_prompt_id.startsWith('acdc-cardinal-v1-')
                && e.source_cardinal_resolution?.source_kind === 'separate_model_trial'
                && e.source_cardinal_resolution.model === voice.model);
            else assert.equal(voice.model, 'gemini-2.5-pro-preview-tts');
            if (e.source_cardinal_resolution !== null) {
                const r = e.source_cardinal_resolution;
                assert(r.provider === voice.provider && r.voice === voice.voice && r.model === voice.model
                    && r.telephony_sha256 === voice.sha256 && r.transcript_sha256 === voice.transcript_sha256
                    && ['generated_cardinal','separate_model_trial'].includes(r.source_kind), 'Unexpected position-one resolution');
                assert(voice.model===(r.source_kind==='separate_model_trial'?'gemini-3.1-flash-tts-preview':'gemini-2.5-pro-preview-tts'));
            }
        }
        assert(l.assets.slice(1).reduce((n, a) => n + a.samples, 0) < 10 * 8000, 'Position one does not fit bounded independent schedule');
    }
    return index;
}
function protectedRead(file, digest, root) { return helpers(root).probe.readPinned(file, digest, 8 * 1024 * 1024); }
function client(root) {
    // Existing protected deployment values; never print them or pass them to
    // subprocesses. Reads stay on the local CouchDB endpoint, redirects denied.
    const file = '/etc/kazoo/deployment.env', s = fs.lstatSync(file);
    assert(s.isFile() && !s.isSymbolicLink() && s.uid === 0 && s.nlink === 1 && !(s.mode & 0o077) && s.size <= 65536);
    const env = Object.fromEntries(fs.readFileSync(file, 'utf8').split('\n').filter(l => l && !l.startsWith('#')).map(l => {
        const n = l.indexOf('='), b = Buffer.from(l.slice(n + 1), 'base64');
        assert(n > 0 && b.toString('base64') === l.slice(n + 1)); return [l.slice(0, n), b.toString()];
    }));
    const port = Number(env.KAZOO_COUCHDB_PORT || 5984);
    assert(['127.0.0.1','localhost'].includes(env.KAZOO_COUCHDB_HOST) && Number.isInteger(port) && port > 0 && port < 65536
        && env.KAZOO_COUCHDB_USER && !env.KAZOO_COUCHDB_USER.includes(':') && env.KAZOO_COUCHDB_PASSWORD);
    const authorization = 'Basic ' + Buffer.from(env.KAZOO_COUCHDB_USER + ':' + env.KAZOO_COUCHDB_PASSWORD).toString('base64');
    return async expected => {
        assert(LOCALES.includes(expected.language) && expected._id === expected.language + '/' + expected.prompt_id);
        const response = await fetch('http://127.0.0.1:' + port + '/system_media/' + encodeURIComponent(expected._id)
            + '?attachments=true&conflicts=true', {headers:{authorization, accept:'application/json'},
            redirect:'error', signal:AbortSignal.timeout(15000)});
        assert(response.status === 200 && /^application\/json(?:;|$)/i.test(response.headers.get('content-type') || ''));
        const chunks = []; let size = 0;
        for await (const chunk of response.body) { size += chunk.length; assert(size <= 4 * 1024 * 1024, 'Unbounded reference body'); chunks.push(chunk); }
        return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    };
}
async function prepare(optionsFile, optionsSha, directory, root = sourceRoot()) {
    const {probe, catalog} = helpers(root), config = JSON.parse(protectedRead(optionsFile, optionsSha, root));
    exact(config, ['schema_version','probe_args']); assert(config.schema_version === 1 && Array.isArray(config.probe_args));
    const args = probe.parseArgs(config.probe_args), input = probe.buildInput(args); // Never execute().
    const s = fs.lstatSync(directory); probe.protectedParents(directory);
    assert(path.isAbsolute(directory) && fs.realpathSync(directory) === directory && s.isDirectory()
        && s.uid === 0 && (s.mode & 0o777) === 0o700 && fs.readdirSync(directory).length === 0);
    const get = client(root), locales = [];
    for (const locale of LOCALES) {
        const assets = [], target = path.join(directory, locale); fs.mkdirSync(target, {mode:0o700});
        for (const selected of selection(input, locale, catalog)) {
            const wav = verifyDocument(selected.expected, await get(selected.expected)), raw = convert(wav);
            // Exact installed revision/hash again before publishing each reference.
            verifyDocument(selected.expected, await get(selected.expected));
            const relative = locale + '/' + selected.key + '.ulaw';
            probe.createEvidence(path.join(directory, relative), raw);
            assets.push({...selected, file:relative, ulaw_sha256:sha(raw), samples:raw.length});
        }
        const source = input.locales.find(l => l.locale === locale);
        locales.push({locale, cardinal_map_sha256:source.cardinal_map_sha256, fixed_map_sha256:source.fixed_map_sha256, assets});
    }
    protectedRead(optionsFile, optionsSha, root);
    const index = validateIndex({schema_version:1, owner:OWNER, scope:'position-one-and-offer-six',
        source_probe_account:input.account, source_input_sha256:sha(JSON.stringify(input)),
        cardinal_receipt_sha256:input.cardinal_receipt_sha256, fixed_receipt_sha256:input.fixed_receipt_sha256,
        beam_manifest_sha256:input.beam_manifest_sha256, locales,
        wait_time_verified:false, native_listening_approved:false, full_language_ready:false}, catalog);
    const bytes = Buffer.from(JSON.stringify(index, null, 2) + '\n'), file = path.join(directory, 'index.json');
    probe.createEvidence(file, bytes); return {index:file, sha256:sha(bytes), locales:LOCALES, provider_requests:0, wait_time_verified:false};
}
function load(indexFile, indexSha, locale, root = sourceRoot()) {
    const {catalog} = helpers(root);
    assert(LOCALES.includes(locale));
    const index = validateIndex(JSON.parse(protectedRead(indexFile, indexSha, root)), catalog);
    const selected = index.locales.find(l => l.locale === locale), directory = path.dirname(indexFile);
    const assets = selected.assets.map(a => {
        const raw = protectedRead(path.join(directory, a.file), a.ulaw_sha256, root);
        assert.equal(raw.length, a.samples); return {...a, raw};
    });
    return {index, selected, assets};
}
function verifyReceiptIndex(receipt, indexBytes, indexSha, locale, root = sourceRoot()) {
    assert(Buffer.isBuffer(indexBytes) && indexBytes.length > 0 && indexBytes.length <= 8 * 1024 * 1024
        && hash(indexSha) && sha(indexBytes) === indexSha, 'Reference index bytes do not match pin');
    const index = validateIndex(JSON.parse(indexBytes), helpers(root).catalog);
    assert(LOCALES.includes(locale) && receipt.locale === locale && receipt.reference_index_sha256 === indexSha);
    const selected = index.locales.find(l => l.locale === locale);
    assert.deepEqual(receipt.assets, selected.assets, 'Receipt assets differ from pinned position-one selection');
    assert.equal(receipt.cardinal_map_sha256, selected.cardinal_map_sha256);
    assert.equal(receipt.fixed_map_sha256, selected.fixed_map_sha256);
}
async function capture(run, indexFile, indexSha, locale, root = sourceRoot()) {
    const selected = load(indexFile, indexSha, locale, root), get = client(root), {probe} = helpers(root);
    for (const a of selected.assets) {
        const current = convert(verifyDocument(a.expected, await get(a.expected)));
        assert(current.equals(a.raw), 'Saved selected reference no longer matches installed audio');
        verifyDocument(a.expected, await get(a.expected));
        probe.createEvidence(path.join(run, a.key + '-reference.ulaw'), a.raw);
    }
    // Recheck saved bytes after all local database reads; never invoke a planner per call.
    load(indexFile, indexSha, locale, root);
    const receipt = {schema_version:1, audio_mode:'prerecorded', locale, reference_index_sha256:indexSha,
        scope:'position-one-and-offer-six', assets:selected.selected.assets,
        cardinal_map_sha256:selected.selected.cardinal_map_sha256, fixed_map_sha256:selected.selected.fixed_map_sha256,
        wait_time_verified:false, native_listening_approved:false, full_language_ready:false};
    // Keep exact index bytes with the run: final PCAP verification must bind
    // the selected identities/model/lineage, not merely compare hash strings.
    const indexBytes = protectedRead(indexFile, indexSha, root);
    verifyReceiptIndex(receipt, indexBytes, indexSha, locale, root);
    probe.createEvidence(path.join(run, 'offer-reference-index.json'), indexBytes);
    probe.createEvidence(path.join(run, 'offer-reference-receipt.json'), Buffer.from(JSON.stringify(receipt, null, 2) + '\n'));
    return receipt;
}
module.exports = {LOCALES, OWNER, selection, verifyDocument, validateIndex, verifyReceiptIndex, convert, load, prepare, capture};
if (require.main === module) {
    (async () => {
        const [action, options, digest, directory] = process.argv.slice(2);
        assert(['prepare','check'].includes(action) && process.argv.length === 6 && hash(digest), 'Use prepare OPTIONS_JSON OPTIONS_SHA256 EMPTY_PROTECTED_DIR or check INDEX INDEX_SHA256 LOCALE');
        if(action==='prepare') console.log(JSON.stringify(await prepare(options, digest, directory)));
        else {
            const selected=load(options,digest,directory);
            console.log(JSON.stringify({result:'PASS',locale:directory,assets:selected.assets.length,network_requests:0}));
        }
    })().catch(() => {console.error('Prerecorded reference preparation failed safely; no live call or readiness claimed.'); process.exitCode = 1;});
}
