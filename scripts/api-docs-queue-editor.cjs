'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
function applyQueueEditor({spec, operation, request, response, envelope, object, ref, hex, root}) {
    const source = 'applications/acdc/src/cb_acdc_queue_editor.erl';
    const bytes = fs.readFileSync(path.join(root, source));
    const routes = fs.readFileSync(path.join(root, 'applications/acdc/src/cb_queues.erl'), 'utf8');
    for (const needle of ['get(Context, QueueId)', 'validate_write(Context, QueueId)', 'operation_public(Receipt)', 'editor_body_requires_exact_fields', 'reserve_extensions(Context, Plans, Receipt0)', 'finalize_extensions(Context, Claims, SavedRoute, Receipt0)']) {
        if (!bytes.toString().includes(needle)) throw new Error('Queue editor contract source is missing expected guard: ' + needle);
    }
    if (!routes.includes('cb_acdc_queue_editor:get(Context, Id)') || !routes.includes('cb_acdc_queue_editor:execute(Context)')) throw new Error('Queue editor routes are not wired');
    const schemas = spec.components.schemas, str = {type: 'string'}, list = items => ({type: 'array', items, maxItems: 500});
    const strict = (fields, required = Object.keys(fields)) => ({...object(fields, required), additionalProperties: false});
    schemas.QueueEditorRevisions = strict({queue: {type: 'string', nullable: true}, users: {type: 'object', additionalProperties: str}, callflows: {type: 'object', additionalProperties: str}});
    schemas.QueueEditorRevisions.description = 'Copy the entire revisions object from a fresh GET editor snapshot. users and callflows map every returned catalog document ID to its revision, not only selected items. queue is null when creating. The backend compares the applicable maps before writes.';
    schemas.QueueEditorCatalogState = strict({complete: {type: 'boolean'}, reason: str, count: {type: 'integer', minimum: 0}, limit: {type: 'integer', enum: [500]},
        missing_prompt_ids: {type: 'array', maxItems: 57, uniqueItems: true, items: str}}, ['complete', 'reason', 'count', 'limit']);
    schemas.QueueEditorCatalogState.description = 'Incomplete catalogs must not be treated as empty selections. A limit-exceeded catalog returns an empty list with complete=false and reason=limit_exceeded, never a silently truncated list. Other reasons include forbidden, invalid_scope, unavailable and unverified_language_manifest.';
    schemas.QueueEditorCatalogState.description += ' In legacy English mode, missing or provenance-invalid media returns complete=false, reason=english_media_prerequisites_incomplete, and exact missing_prompt_ids. The bounded prerequisites are 32 immutable Gemini fixed records, ten immutable telephone-digit recordings, 12 official queue phrases and three official callback auxiliary prompts, fetched in one batch. The ten digits are required by canonical built-in callbacks; fixed-only proof is insufficient. This does not verify resolver caches, downloaded audio bytes, native position speech or external routing.';
    schemas.QueueEditorUser = strict({id: hex, name: str, first_name: str, last_name: str, enabled: {type: 'boolean'}}, ['id']);
    schemas.QueueEditorMedia = strict({id: str, name: str, language: str, media_type: str, media_source: str}, ['id']);
    schemas.QueueEditorSystemMedia = strict({id: str, name: str, language: str, has_attachments: {type: 'boolean', enum: [true]},
        prompt_id: str, canonical_prompt_id: str, source_type: {type: 'string', enum: ['kazoo5_acdc_gemini_voice_installer']},
        source_map_sha256: {type: 'string', pattern: '^[a-f0-9]{64}$'}, sha256: {type: 'string', pattern: '^[a-f0-9]{64}$'},
        import_metadata_verified: {type: 'boolean', enum: [true]}}, ['id', 'language', 'has_attachments']);
    schemas.QueueEditorSystemMedia.description = 'id is always the actual stored media document ID, never a fabricated canonical alias. Immutable Gemini records additionally carry the canonical playback purpose and fixed-map/hash provenance after exact attachment/document metadata checks. These fields prove metadata only, not fresh audio bytes, caches, native-number completeness or all-Gemini readiness.';
    schemas.QueueEditorRouteSummary = strict({id: hex, name: str, numbers: {type: 'array', items: str}, patterns: {type: 'array', items: str}, flags: {type: 'array', items: str}}, ['id']);
    schemas.QueueEditorRoute = {...schemas.QueueEditorRouteSummary, properties: {...schemas.QueueEditorRouteSummary.properties, flow: {type: 'object', description: 'Full callflow tree only for routes referencing this queue.'}}};
    schemas.QueueEditorLanguageCapabilities = {type: 'object', nullable: true, description: 'Verified deployment language manifest, schema_version=1, or null if unavailable. Do not infer readiness from language names or source files. Each locale reports ready/position/wait_time/callback/native_speaker_review independently. Native speaker review is not implied by automated media verification.',
        properties: {schema_version: {type: 'integer', enum: [1]}, generated_at: str, languages: {type: 'object', properties: Object.fromEntries(['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr'].map(locale => [locale, object({ready: {type: 'boolean'}, position: {type: 'boolean'}, wait_time: {type: 'boolean'}, callback: {type: 'boolean'}, native_speaker_review: {type: 'boolean'}, required_prompt_ids: {type: 'array', items: str}, number_range: {type: 'array', items: {type: 'integer'}, minItems: 2, maxItems: 2}, numbers: {type: 'string', enum: ['native_say', 'prerecorded']}, numeric_prompt_count: {type: 'integer'}, source_catalog_sha256: str, installed_media_sha256: str})]))}}};
    schemas.QueueEditorLanguageCapabilities.properties.backend_mode = {type: 'string', enum: ['legacy'], description: 'Present only for the explicitly declared English baseline. Its full-pack language flags remain false. Explicit en-us selection additionally requires a complete system_media catalog and every required English baseline prompt with an attachment; this is not multilingual or all-Gemini readiness. Missing proof rejects the selection.'};
    schemas.QueueEditorLanguageCapabilitiesV1 = schemas.QueueEditorLanguageCapabilities;
    const cardinalCounts = {'en-us': 31, 'ar-sa': 208, 'he-il': 131, 'es-es': 53, 'fr-fr': 161};
    const proofHash = {type: 'string', pattern: '^[a-f0-9]{64}$'};
    const cardinalFlags = ['ready', 'selection_ready', 'position', 'wait_time', 'callback', 'native_speaker_review',
        'position_installed_verified', 'callback_installed_verified', 'position_runtime_verified',
        'callback_runtime_verified', 'wait_time_runtime_verified'];
    schemas.QueueEditorLanguageCapabilitiesV2 = strict({schema_version: {type: 'integer', enum: [2]},
        backend_mode: {type: 'string', enum: ['prerecorded-cardinal-v1']},
        generated_at: {type: 'string', format: 'date-time'},
        languages: strict(Object.fromEntries(Object.entries(cardinalCounts).map(([locale, count]) => [locale, strict({
            ...Object.fromEntries(cardinalFlags.map(flag => [flag, {type: 'boolean'}])),
            numbers: {type: 'string', enum: ['prerecorded-cardinal']},
            number_range: {type: 'array', items: {type: 'integer'}, minItems: 2, maxItems: 2, enum: [[0, 999999999]]},
            numeric_prompt_count: {type: 'integer', enum: [count]}, callback_prompt_count: {type: 'integer', enum: [42]},
            source_catalog_sha256: proofHash, cardinal_map_sha256: proofHash, fixed_map_sha256: proofHash,
            installed_media_sha256: {...proofHash, nullable: true}, runtime_evidence_sha256: {...proofHash, nullable: true},
            native_review_sha256: {...proofHash, nullable: true}
        })]))) });
    schemas.QueueEditorLanguageCapabilitiesV2.description = 'Explicit prerecorded cardinal contract: exact584 position roles across five locales, plus42 fixed/callback-digit records per locale and the pinned position intro. Counts describe required inventories, not proof of installation. Installed flags require pinned byte-readback evidence. Runtime flags require independent deployed-code, mapping and live-function evidence. position/callback/wait_time are the conjunction of their installed and runtime facts. selection_ready requires all three functions and permits development voice testing without inventing native review; ready additionally requires native_speaker_review and its real listening-evidence hash. Source-only or installed-only records cannot enable selection. Backend checks exact compiled map/catalog pins and fresh metadata for only runtime-claimed locales through the bounded bulk datapath; it can only downgrade runtime flags. No readiness, live deployment or native review is inferred from audio generation.';
    schemas.QueueEditorLanguageCapabilities = {type: 'object', nullable: true,
        oneOf: [ref('QueueEditorLanguageCapabilitiesV1'), ref('QueueEditorLanguageCapabilitiesV2')],
        description: 'Legacy schema1 remains compatible. Schema2 distinguishes installed evidence, development selection readiness, deployed runtime verification and native listening review. Null/absent remains unavailable. See each versioned contract; do not treat selection_ready as full production certification.'};
    schemas.QueueEditorSnapshot = strict({queue: {...schemas.QueuePatch, properties: {...schemas.QueuePatch.properties, agents: list(hex)}}, roster: list(hex), users: list(ref('QueueEditorUser')), media: list(ref('QueueEditorMedia')), system_media: list(ref('QueueEditorSystemMedia')), numbers: list(strict({number: str, state: {type: 'string', enum: ['in_service']}})),
        language_capabilities: ref('QueueEditorLanguageCapabilities'), callflows: strict({summaries: list(ref('QueueEditorRouteSummary')), routes: list(ref('QueueEditorRoute'))}), revisions: ref('QueueEditorRevisions'),
        catalogs: strict(Object.fromEntries(['users', 'media', 'callflows', 'numbers', 'system_media'].map(name => [name, ref('QueueEditorCatalogState')])))});
    // Crossbar can remove null fields from its public envelope on an unavailable
    // capability catalog. Absence must not be mistaken for successful readiness.
    schemas.QueueEditorSnapshot.required = schemas.QueueEditorSnapshot.required.filter(key => key !== 'language_capabilities');
    schemas.QueueEditorSettings = {...schemas.QueuePatch, description: 'Queue settings only (encoded JSON at most 65536 bytes). Do not include id, agents, keys beginning with pvt_, or keys beginning with _. Identity and roster are server-owned. A create request must satisfy the ordinary queues create schema; PATCH merges the supplied settings.',
        not: {anyOf: [{required: ['id']}, {required: ['agents']}]}, 'x-max-encoded-json-bytes': 65536, 'x-forbidden-key-prefixes': ['_', 'pvt_']};
    schemas.QueueEditorCreateSettings = {...schemas.QueueEditorSettings, required: schemas.queues.required,
        description: 'New queue settings; satisfy the ordinary queues create schema. For built-in voice defaults select announcements.language and omit announcements.media and callback.media. Null prompt deletion markers apply to PATCH, not creation.'};
    const patchProperties = JSON.parse(JSON.stringify(schemas.QueueEditorSettings.properties));
    for (const section of ['announcements', 'callback']) {
        patchProperties[section].properties.media.nullable = true;
        patchProperties[section].properties.media.description += ' For PATCH only, null removes this entire override map from the persisted queue. Omission preserves it; an empty object does not remove existing nested overrides. No media documents or recordings are deleted.';
    }
    patchProperties.callback.properties.return_confirmation_prompt = {type: 'string', nullable: true,
        minLength: 1, maxLength: 256, deprecated: true,
        description: 'Legacy returned-call prompt override. Send null in PATCH when adopting built-in queue voices, so this field is absent in storage. A stored explicit null is not a valid runtime prompt.'};
    schemas.QueueEditorSettings.properties = patchProperties;
    schemas.QueueEditorSettings.description += ' Built-in language adoption uses announcements.language plus announcements.media=null, callback.media=null and callback.return_confirmation_prompt=null. The server consumes null as a deletion marker before validating/saving the merged queue. Use a supported ready locale from GET editor; changing references does not certify playback readiness.';
    schemas.QueueEditorWrite = strict({queue: ref('QueueEditorSettings'), roster: {type: 'array', nullable: true, uniqueItems: true, maxItems: 500, items: hex, description: 'Desired full roster; null preserves current membership.'},
        route: {...strict({extension: {type: 'string', pattern: '^(?:\\+?[0-9*#]+)?$', maxLength: 32}}), nullable: true, description: 'null preserves routing. A nonempty extension creates/updates a managed route. Empty string requests removal of the eligible managed route, subject to ownership/conflict checks; it does not authorize broad callflow deletion.'}, revisions: ref('QueueEditorRevisions'), request_id: hex});
    schemas.QueueEditorWrite.description = 'All five fields are required for both PUT and PATCH. The request_id is a fresh client-generated 32-character lowercase hexadecimal idempotency key, stable for retries of this exact operation. Never reuse it with different content, account, verb, target, or authenticated owner.';
    schemas.QueueEditorCreateWrite = {...schemas.QueueEditorWrite,
        properties: {...schemas.QueueEditorWrite.properties, queue: ref('QueueEditorCreateSettings')}};
    const operationId = {type: 'string', pattern: '^acdc_queue_editor_[a-f0-9]{64}$'};
    schemas.QueueEditorSuccess = strict({queue_id: hex, operation_id: operationId, state: {type: 'string', enum: ['complete']}, atomic: {type: 'boolean', enum: [false]}, roster_preserved: {type: 'boolean'}, route_preserved: {type: 'boolean'}, reload_required: {type: 'boolean', enum: [true]}});
    const extensionPhases = ['reserve_extensions', 'queue', 'roster', 'route', 'finalize_extensions'];
    schemas.QueueEditorExtensionClaim = strict({id: {type: 'string', pattern: '^acdc_queue_extension_[a-f0-9]{64}$'}, extension: {type: 'string', pattern: '^\\+?[0-9*#]+$', maxLength: 32}, revision: str});
    schemas.QueueEditorExtensionClaim.description = 'A confirmed extension claim recorded by this operation. revision is the claimed revision, not a guarantee of the current document revision after finalization. Never use this receipt alone to release, overwrite or take over a reservation.';
    schemas.QueueEditorRecovery = strict({queue_id: hex, operation_id: operationId, state: {type: 'string', enum: ['running', 'partial', 'complete']}, phase: {type: 'string', enum: ['prepared', ...extensionPhases, 'complete']},
        committed: {type: 'array', items: strict({phase: {type: 'string', enum: [...extensionPhases, 'roster_partial']}, ids: {type: 'array', items: str}})}, in_flight: {type: 'array', items: str}, remaining: {type: 'array', items: {type: 'string', enum: extensionPhases}},
        extension_claims: {type: 'array', maxItems: 2, items: ref('QueueEditorExtensionClaim')}, atomic: {type: 'boolean', enum: [false]}, reload_required: {type: 'boolean', enum: [true]}});
    schemas.QueueEditorRecovery.description = 'A lost final receipt-write reply can produce HTTP409 with a reread state/phase of complete; inspect the exact operation before deciding whether to retry. Missing acknowledgements do not prove a write failed. Roster completion requires exactly one successful acknowledgement with a nonempty revision for every planned user; malformed, extra, duplicate or incomplete acknowledgements cannot advance to the route phase. After an ambiguous outcome, in_flight may contain users whose changes actually committed; reload the editor to obtain current roster and revisions, without automatically resending the operation. Extension claims may remain reserved after partial or ambiguous failures and require explicit recovery, without expiry or automatic takeover.';
    const description = 'The queue editor rechecks authorization and token scope for each embedded queues/users/media/phone_numbers/callflows operation. Access to queues alone does not grant access to those other resources. Roster writes use the existing queues/{QUEUE_ID}/roster POST authority. GET returns safe bounded catalogs for dropdowns and a revision snapshot. Never clear selections because a catalog is incomplete. Writes coordinate separate CouchDB documents using an operation receipt; they are explicitly NON-ATOMIC. Managed route operations CAS-reserve at most the old and target extensions before settings writes, and finalize reservations only after a confirmed route write. These reservations prevent two aggregate writers claiming one extension; direct legacy callflow writers do not participate and remain outside that guarantee. Reservations never expire or permit automatic takeover. There is no automatic rollback or automatic resume. After a partial or ambiguous failure, reload with GET editor and inspect committed/in_flight/remaining/extension_claims; do not blindly retry or generate a new request_id. An identical completed request replays its recorded result; an incomplete replay returns 409, and changed content under the same key returns 409. A create queue ID is deterministic from tenant, authenticated owner and request_id. After success reload the editor. This contract exists in the current source; deployment and live end-to-end acceptance must be checked separately.';
    for (const [url, writeMethod] of [['/accounts/{ACCOUNT_ID}/queues/editor', 'put'], ['/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/editor', 'patch']]) {
        const get = operation(url, 'get', writeMethod === 'put' ? 'Load create-queue editor catalogs' : 'Load queue settings, roster, routes and safe catalogs', source, {description, responses: {200: response('Editor snapshot', envelope(ref('QueueEditorSnapshot'))), 401: response('Invalid authentication', ref('CrossbarError')), 403: response('Forbidden by account or resource permissions', ref('CrossbarError')), 404: response('Queue not found', ref('CrossbarError')), 503: response('Editor unavailable', ref('CrossbarError'))}});
        get['x-implementation-status'] = 'implemented-in-source; latest-revision-not-live-verified';
        get['x-live-verification'] = {host: 'kz5.talkchief.io', date: '2026-09-05', coverage: 'Historical checkpoint, not certification of the latest source revision. Authenticated live browser: one editor GET, zero catalog fanout, zero JS/HTTP errors. This records one host/date, not every deployment.'};
        const write = operation(url, writeMethod, writeMethod === 'put' ? 'Create queue, roster and extension with an operation receipt' : 'Update queue, roster and extension with revision checks', source, {description, requestBody: request(ref(writeMethod === 'put' ? 'QueueEditorCreateWrite' : 'QueueEditorWrite')), responses: {
            200: response('Complete operation receipt; reload editor', envelope(ref('QueueEditorSuccess'))), 400: response('Invalid body, queue settings, or selections', ref('CrossbarError')), 401: response('Invalid authentication', ref('CrossbarError')), 403: response('Embedded resource operation forbidden', ref('CrossbarError')), 404: response('Queue not found', ref('CrossbarError')),
            409: response('Revision/idempotency conflict or incomplete operation. Recovery details are present when an operation receipt exists.', object({status: str, error: str, message: str, data: {oneOf: [ref('QueueEditorRecovery'), {type: 'object', maxProperties: 0}]}, request_id: str})),
            503: response('Catalog, storage, or receipt unavailable. Some writes may already have committed; reload before recovery.', ref('CrossbarError'))}});
        if (writeMethod === 'put') write.responses['201'] = response('Created complete operation receipt; reload editor', envelope(ref('QueueEditorSuccess')));
        if (writeMethod === 'patch') write.requestBody.content['application/json'].examples = {
            builtinQueueLanguage: {
                summary: 'Adopt the ready built-in queue language without deleting recordings',
                description: 'Replace revisions with the entire fresh GET editor snapshot and generate a new request_id for this operation. Empty revision maps below are illustrative only. Null roster/route preserves those resources; null prompt maps removes overrides. Check language readiness before saving.',
                value: {data: {queue: {announcements: {language: 'en-us', media: null},
                    callback: {media: null, return_confirmation_prompt: null}},
                    roster: null, route: null,
                    revisions: {queue: '3-0123456789abcdef0123456789abcdef', users: {}, callflows: {}},
                    request_id: '0123456789abcdef0123456789abcdef'}}
            }
        };
        write['x-implementation-status'] = 'implemented-in-source; latest-revision-not-live-verified';
        write['x-live-verification'] = {host: 'kz5.talkchief.io', date: '2026-09-05', coverage: 'Historical checkpoint, not certification of the latest source revision or the later bulk-acknowledgement repair. Isolated test tenant: create/edit including explicit English selection, exact replay, changed-request-ID conflict, stale revision rejection, managed route removal and exact-CAS fixture cleanup. No agent changes. Restricted-token, cross-node and partial-write recovery coverage remain separate.'};
    }
    return {inputs: [{file: source, sha256: crypto.createHash('sha256').update(bytes).digest('hex')}]};
}
module.exports = {applyQueueEditor};
