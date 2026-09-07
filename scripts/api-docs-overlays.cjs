'use strict';
// Reviewed contracts only. Keep planned APIs in their own document.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ref = name => ({$ref: '#/components/schemas/' + name});
const hex = {type: 'string', pattern: '^[a-f0-9]{32}$'};
const text = {type: 'string'};
const object = (properties, required = []) => ({type: 'object', properties, ...(required.length ? {required} : {})});
const envelope = data => object({status: {type: 'string'}, data, request_id: text}, ['data']);
const request = data => ({required: true, content: {'application/json': {schema: object({data}, ['data'])}}});
const response = (description, schema) => ({description, ...(schema ? {content: {'application/json': {schema}}} : {})});
const parameters = url => [...url.matchAll(/\{([^}]+)\}/g)].map(([, name]) => ({in: 'path', name, required: true, schema: name === 'UUID' ? {type: 'string', pattern: '^[A-Za-z0-9_.:@-]{1,128}$'} : name === 'CALLBACK_ID' ? {type: 'string', pattern: '^acdc-callback-[a-f0-9]{64}$'} : hex}));
const errorSchema = object({status: {type: 'string', enum: ['error']}, error: {type: 'string'}, message: text, data: {description: 'Error details vary by Crossbar validation and datastore layer.'}, request_id: text});
function applyOverlays(spec, root) {
    const schemas = spec.components.schemas;
    schemas.CrossbarError = errorSchema;
    schemas.QueuePatch = {...schemas.queues, required: undefined, description: 'Partial queue update; omitted fields are preserved. The queue resource schema describes allowed values.'};
    const queueSource = 'applications/acdc/src/cb_queues.erl';
    const monitorSource = 'applications/crossbar/src/cb_channel_monitor.erl';
    const agentSource = 'applications/acdc/src/cb_agents.erl';
    const inputs = [queueSource, monitorSource, agentSource, 'applications/acdc/src/acdc_callback_store.erl', 'applications/crossbar/src/modules/cb_channels.erl'].map(file => ({file, sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')}));
    const defaultErrors = {400: response('Invalid request', ref('CrossbarError')), 401: response('Missing or invalid authentication', ref('CrossbarError')), 403: response('Insufficient permissions', ref('CrossbarError')), 404: response('Resource not found in this account', ref('CrossbarError')), 409: response('Conflicting state or revision', ref('CrossbarError')), 503: response('Dependency unavailable; do not blindly retry mutations', ref('CrossbarError'))};
    function operation(url, method, summary, source, opts = {}) {
        spec.paths[url] ||= {};
        spec.paths[url][method] = {
            operationId: method + '_' + url.replace(/[^a-zA-Z0-9]+/g, '_'),
            tags: [url.includes('/channels') ? 'Call supervision' : url.includes('/agents') ? 'ACDC agents' : 'ACDC queues'],
            summary, parameters: parameters(url), security: [{CrossbarToken: []}],
            responses: {200: response('Success', envelope({description: 'Resource-specific data; optional envelope fields may also be returned.'})), ...defaultErrors},
            'x-contract-review': 'source-reviewed', 'x-source-file': source,
            'x-runtime-verification': 'Source review only unless explicitly noted in the operation description.', ...opts
        };
        return spec.paths[url][method];
    }
    const q = '/accounts/{ACCOUNT_ID}/queues', qi = q + '/{QUEUE_ID}';
    operation(q, 'get', 'List account queues', queueSource);
    operation(q, 'put', 'Create a queue', queueSource, {requestBody: request(ref('queues')), description: 'Creates the queue document. Agent roster and the extension callflow are separate resources. Use the unified editor contract when available to coordinate those writes; they are not atomic.'});
    operation(qi, 'get', 'Read a queue and its agents', queueSource, {responses: {200: response('Queue resource', envelope(ref('queues'))), ...defaultErrors}});
    for (const method of ['post', 'patch']) operation(qi, method, 'Update queue configuration', queueSource, {requestBody: request(ref(method === 'patch' ? 'QueuePatch' : 'queues')),
        description: 'Queue callback policy is under data.callback. Select outbound_authority.type=user and an enabled account-owned user ID; it is the outbound authorization identity, not the callback recipient. caller_id_source=inherit derives outbound caller ID from that user/account, subject to ownership and routing checks. callback.announcement is independent of announcements: enabled default true, initial_delay default 30 seconds (1–3600), interval default 60 seconds (15–3600). Disabling the spoken offer does not disable entry_key (default 6). callback.enabled=false disables callback itself. Offer language follows announcements.language or call locale. Available voice/language assets are a deployment prerequisite; source schema presence does not prove readiness. Queue routes use a callflow node module=acdc_member, data.id=queue ID. An ordinary internal extension alone is not an authorized outbound callback route.'});
    operation(qi, 'delete', 'Delete a queue', queueSource);
    const roster = {type: 'array', items: hex};
    operation(qi + '/roster', 'get', 'Read the queue agent roster', queueSource, {responses: {200: response('Agent IDs', envelope(roster)), ...defaultErrors}});
    operation(qi + '/roster', 'post', 'Replace the complete agent roster', queueSource, {requestBody: request(roster), description: 'The data array is the desired complete roster. Agents omitted from this list are removed. This is not an additive operation. Membership, agent availability, and SIP registration are separate states.'});
    operation(qi + '/roster', 'delete', 'Clear the entire queue roster', queueSource, {description: 'Removes all roster membership. A selective list in the body does not make this selective.'});
    operation(q + '/stats', 'get', 'Read queue statistics', queueSource, {description: 'Statistics payload depends on selected format and available ACDC statistics. A complete typed statistics response is not yet verified.'});
    inputs.push(...require('./api-docs-queue-live.cjs').applyQueueLive({spec, root}).inputs);
    for (const url of [q + '/eavesdrop', qi + '/eavesdrop']) operation(url, 'put', 'Legacy queue eavesdrop — unavailable', queueSource, {deprecated: true, description: 'Deliberately fails closed with HTTP 503. Use POST /accounts/{ACCOUNT_ID}/channels/{UUID} with an authorized supervision action.', responses: {503: response('Legacy monitoring unavailable', ref('CrossbarError'))}});
    schemas.CallbackPublic = {...object({id: {type: 'string', pattern: '^acdc-callback-[a-f0-9]{64}$'}, queue_id: hex,
        status: {type: 'string', enum: ['registering', 'queued', 'dialing', 'confirming', 'connecting', 'retry_wait', 'cancelling', 'completed', 'cancelled', 'failed', 'expired']},
        attempts: {type: 'integer', minimum: 0}, enqueued_at: {type: 'integer', description: 'Kazoo Gregorian timestamp in seconds, not Unix epoch.'}, enqueue_sequence: {type: 'integer'}, priority: {type: 'integer'}, language: text,
        next_attempt_at: {type: 'integer'}, expires_at: {type: 'integer'}, created: {type: 'integer'}, modified: {type: 'integer'}, last_cause: text,
        reconciliation_required: {type: 'boolean'}, reconciliation_reason: {type: 'string', enum: ['engine_restart', 'owner_lost', 'channel_snapshot_incomplete', 'originate_pending', 'cleanup_pending', 'bridge_proof_pending']}
    }), additionalProperties: false, description: 'Privacy-limited public projection. Caller numbers, original call IDs, leases, routing credentials and live leg IDs are deliberately excluded. Timestamp fields use Kazoo Gregorian seconds.'};
    const list = operation(qi + '/callbacks', 'get', 'List durable callback reservations', queueSource, {description: 'Bounded, queue-scoped list. No public callback-create endpoint exists: only a trusted live queued caller can register after confirmation. Follow next_cursor from the envelope; do not synthesize cursors.', responses: {200: response('Bounded page', object({status: text, data: {type: 'array', items: ref('CallbackPublic')}, page_size: {type: 'integer', maximum: 100}, next_cursor: {type: 'string', maxLength: 2048}, request_id: text}, ['data'])), ...defaultErrors}});
    list.parameters.push({in: 'query', name: 'page_size', schema: {type: 'integer', minimum: 1, maximum: 100}, description: 'Maximum returned page size is capped at 100; default comes from Crossbar pagination configuration.'}, {in: 'query', name: 'cursor', schema: {type: 'string', maxLength: 2048}, description: 'Opaque cursor from the preceding page, bound to this queue.'});
    operation(qi + '/callbacks/{CALLBACK_ID}', 'get', 'Read a callback reservation', queueSource, {responses: {200: response('Callback public projection', envelope(ref('CallbackPublic'))), ...defaultErrors}});
    operation(qi + '/callbacks/{CALLBACK_ID}', 'delete', 'Cancel a callback reservation', queueSource, {description: 'An in-flight callback enters cancelling until its live legs positively settle; a response is not proof that every leg has already ended. Terminal callbacks return 409. Re-read state after any ambiguous transport failure; never blindly retry mutations.', responses: {200: response('Callback cancellation state', envelope(ref('CallbackPublic'))), ...defaultErrors}});
    const agents = '/accounts/{ACCOUNT_ID}/agents';
    for (const suffix of ['', '/status', '/stats', '/{USER_ID}', '/{USER_ID}/status', '/{USER_ID}/queue_status']) operation(agents + suffix, 'get', 'Read agent ' + (suffix || 'summary'), agentSource);
    schemas.AgentStatusChange = object({status: {type: 'string', enum: ['login', 'logout', 'pause', 'resume', 'end_wrapup']}, timeout: {type: 'integer', minimum: 0, description: 'Optional pause duration in seconds.'}}, ['status']);
    operation(agents + '/{USER_ID}/status', 'post', 'Change agent availability', agentSource, {requestBody: request(ref('AgentStatusChange')), description: 'Asynchronous availability update. Poll status to observe the resulting state. This does not register a SIP device and is separate from queue membership.'});
    operation(agents + '/{USER_ID}/queue_status', 'post', 'Log an agent into or out of queue membership', agentSource, {requestBody: request(object({action: {type: 'string', enum: ['login', 'logout']}, queue_id: hex}, ['action', 'queue_id']))});
    inputs.push(...require('./api-docs-agent-queue-login.cjs').applyAgentQueueLogin({spec, root}).inputs);
    operation(agents + '/{USER_ID}/restart', 'post', 'Restart an agent worker (platform admin)', agentSource, {description: 'Requires the platform/superduper administrator privilege; ordinary account administrators cannot restart workers.'});
    operation('/accounts/{ACCOUNT_ID}/acdc_call_stats', 'get', 'Read historical ACDC call statistics', 'applications/acdc/src/cb_acdc_call_stats.erl', {description: 'Account-scoped historical statistics streamed from the monthly database view. JSON or CSV is supported. Exact time-range and pagination query behavior follows Crossbar MODB configuration and is not fully typed here. Returned statistics may contain caller personal data; the documentation includes no live samples.', responses: {200: {description: 'Historical statistics', content: {'application/json': {schema: envelope({type: 'array', items: object({id: text, handled_timestamp: {type: 'integer'}, caller_id_number: text, caller_id_name: text, entered_position: {type: 'integer'}, status: text, agent_id: text, wait_time: {type: 'integer'}, talk_time: {type: 'integer'}, queue_id: text})})}, 'text/csv': {schema: {type: 'string'}}}}, ...defaultErrors}});
    // allowed_methods advertises POST on this alias but validate has no matching clause.
    if (spec.paths[agents + '/status/{USER_ID}']?.post) {
        spec.paths[agents + '/status/{USER_ID}'].post.deprecated = true;
        spec.paths[agents + '/status/{USER_ID}'].post.description = 'Known source contract gap: allowed_methods advertises POST but validate has no matching alias clause. Do not use; use /agents/{USER_ID}/status.';
        spec.paths[agents + '/status/{USER_ID}'].post['x-implementation-status'] = 'known-invalid-alias';
    }
    schemas.MonitorStart = {...object({action: {type: 'string', enum: ['eavesdrop', 'whisper', 'barge', 'join'], description: 'eavesdrop=listen only; whisper speaks to the targeted agent leg only; barge and join speak to both parties. There is no action named listen.'}, device_id: hex, timeout: {type: 'integer', minimum: 5, maximum: 60, default: 20}}, ['action', 'device_id']), additionalProperties: false};
    schemas.MonitorStop = {...object({action: {type: 'string', enum: ['stop_monitoring']}, request_id: hex}, ['action', 'request_id']), additionalProperties: false};
    schemas.MonitorAccepted = object({status: {type: 'string', enum: ['accepted']}, action: {type: 'string', enum: ['eavesdrop', 'whisper', 'barge', 'join', 'stop_monitoring']}, request_id: hex, target_call_id: text, supervisor_call_id: text}, ['status', 'action', 'request_id', 'target_call_id', 'supervisor_call_id']);
    const channels = '/accounts/{ACCOUNT_ID}/channels/{UUID}';
    const channel = operation(channels, 'post', 'Listen, whisper, barge, join, or stop supervision', monitorSource, {
        description: 'For start actions UUID is the original target leg; choose the agent leg for whisper. The authenticated account must exactly equal ACCOUNT_ID and the user must be an account administrator, including for resellers. device_id must identify an enabled account-owned sip_device or softphone using the account SIP realm. The server builds the registrar-resolved route; extra endpoints, dial strings, IP routes, headers, FreeSWITCH node names and raw commands are rejected. Cluster ownership discovery is fail-closed and must be corroborated by the live media worker. HTTP 202 means accepted, not that the supervisor answered or audio connected. For stop_monitoring use the returned supervisor_call_id as UUID plus the same request_id: it cannot stop the original agent/customer leg. No DTMF escalation is enabled. All four modes passed isolated same-host synthetic SIP/RTP and authorization checks on 2026-09-05; cross-node failover and production traffic are not certified by those tests. The same POST endpoint also accepts legacy non-monitoring actions; those remain a separate, incompletely typed contract.',
        requestBody: request({oneOf: [ref('MonitorStart'), ref('MonitorStop'), ref('LegacyChannelAction')]}),
        responses: {200: response('Legacy action response; not a monitoring acknowledgement'), 202: response('Monitoring request accepted; connection not confirmed', envelope(ref('MonitorAccepted'))),
            400: response('Invalid fields, identifiers, timeout, or supervisor device', ref('CrossbarError')), 401: defaultErrors[401],
            403: response('Wrong authenticated account, non-admin, or stop target is not the correlated supervisor leg', ref('CrossbarError')),
            404: response('No target in this account, or supervisor device missing', ref('CrossbarError')),
            409: response('Ambiguous target ownership', ref('CrossbarError')),
            503: response('Ownership, live target, route, execution, or termination could not be verified', ref('CrossbarError'))}
    });
    schemas.LegacyChannelAction = object({action: {type: 'string', enum: ['transfer', 'hangup', 'break', 'callflow', 'intercept', 'move', 'start_record', 'stop_record']}}, ['action']);
    schemas.LegacyChannelAction.description = 'Only the action selector is catalogued here; additional per-action fields and privileges require the legacy cb_channels source contract. This schema is intentionally permissive and not a complete validation contract.';
    channel.requestBody.content['application/json'].examples = {
        listen: {summary: 'Listen only (eavesdrop)', value: {data: {action: 'eavesdrop', device_id: '00000000000000000000000000000000', timeout: 20}}},
        whisper: {summary: 'Whisper to targeted agent', value: {data: {action: 'whisper', device_id: '00000000000000000000000000000000'}}},
        barge: {summary: 'Speak to both parties', value: {data: {action: 'barge', device_id: '00000000000000000000000000000000'}}},
        join: {summary: 'Join both parties (same full-audio mode as barge)', value: {data: {action: 'join', device_id: '00000000000000000000000000000000'}}},
        stop: {summary: 'Use supervisor_call_id in path; never the original leg', value: {data: {action: 'stop_monitoring', request_id: '00000000000000000000000000000000'}}}
    };
    for (const url of ['/user_auth', '/api_auth']) {
        const op = spec.paths[url]?.put;
        if (!op) throw new Error('Missing authentication endpoint ' + url);
        op.security = [];
        op.requestBody = request(ref(url.slice(1)));
        op.description = 'Send the authentication data inside the Crossbar data envelope over HTTPS. The returned auth_token is a credential; send it as X-Auth-Token on subsequent requests. Never save tokens in this portal or share them in URLs. ' + (url === '/user_auth' ? 'credentials is a hash of username:password using method md5 (default) or sha, not a clear-text password. Supply the account locator required by your deployment.' : 'api_key is the account API credential and is secret.');
        op.responses = {200: response('Authenticated; auth_token is returned in the response envelope', object({status: text, auth_token: {type: 'string', writeOnly: true, description: 'Secret token returned by authentication; intentionally no example value.'}, data: object({account_id: hex, owner_id: hex})})), 401: defaultErrors[401]};
    }
    // The queue-editor agent supplies an independently reviewed overlay once the handler exists.
    const editor = path.join(__dirname, 'api-docs-queue-editor.cjs');
    if (fs.existsSync(editor)) {
        const result = require(editor).applyQueueEditor({spec, operation, request, response, envelope, object, ref, hex, root});
        if (result?.inputs) inputs.push(...result.inputs);
    }
    inputs.push(...require('./api-docs-members-devices.cjs').applyMembersDevices({spec, root}).inputs);
    inputs.push(...require('./api-docs-blackhole.cjs').applyBlackhole({spec, root}).inputs);
    const scopeFile = 'applications/crossbar/src/modules/cb_scope_restrictions.erl';
    const scopeBytes = fs.readFileSync(path.join(root, scopeFile));
    if (!/management_guard_version\(\)\s*->\s*1\./.test(scopeBytes.toString())) {
        throw new Error('Scope management access contract requires the guarded source');
    }
    const scopeHash = crypto.createHash('sha256').update(scopeBytes).digest('hex');
    inputs.push({file: scopeFile, sha256: scopeHash});
    for (const [url, verbs] of [
        ['/accounts/{ACCOUNT_ID}/scope_restrictions', ['get', 'put']],
        ['/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}', ['get', 'post', 'delete']]
    ]) for (const verb of verbs) {
        const op = spec.paths[url]?.[verb];
        if (!op) throw new Error('Missing scope management operation');
        op.security = [{CrossbarToken: []}];
        op.description = 'Scope-policy management requires a native account administrator or superadmin. Existing account hierarchy and token restrictions still apply; this guard does not grant cross-company access. Ordinary nonadmin users receive 403 before policy reads or writes. Policies are mutable authorization inputs: do not delete an assigned policy while its issued tokens may still authenticate. ' + (op.description || '');
        op.responses['403'] = defaultErrors[403];
        op['x-auth-review'] = 'Source-reviewed management role guard v1; full route and restricted-principal acceptance remain separate.';
        op['x-auth-source-file'] = scopeFile;
        op['x-auth-source-sha256'] = scopeHash;
        if (verb === 'post') op.description += ' POST replaces public policy fields while preserving private metadata. Send the complete desired public policy, not a partial PATCH fragment.';
        // Do not promote the other inherited request/response schemas to a
        // fully reviewed contract based only on this access-control overlay.
    }
    return {inputs};
}
function plannedSpec() {
    return {openapi: '3.0.3', info: {title: 'PLANNED Kazoo APIs — NOT IMPLEMENTED', version: '0.0.0',
        description: 'No remaining API proposals are listed here. Implemented members/devices is in the main source catalog; runtime acceptance remains a separate gate.'},
        servers: [{url: '/v2'}], paths: {}};
}
module.exports = {applyOverlays, plannedSpec};
