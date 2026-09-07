'use strict';
// Native protocol source contract; these extensions are not HTTP mutations.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
function queueLiveBlackholeContract() {
    const ref = name => ({$ref: '#/components/schemas/' + name});
    const closed = properties => ({type: 'object', properties, required: Object.keys(properties), additionalProperties: false});
    const id = {type: 'string', pattern: '^[a-f0-9]{32}$'};
    const binding = {type: 'string', pattern: '^queue_live\\.changed\\.[a-f0-9]{32}$'};
    const route = {type: 'string', pattern: '^acdc\\.dashboard\\.changed\\.[a-f0-9]{32}\\.[a-f0-9]{32}$'};
    const schemas = {};
    for (const action of ['subscribe', 'unsubscribe']) {
        schemas[action === 'subscribe' ? 'BlackholeQueueLiveSubscribe' : 'BlackholeQueueLiveUnsubscribe'] = closed({
            action: {type: 'string', enum: [action]},
            auth_token: {type: 'string', minLength: 1, maxLength: 16384, writeOnly: true},
            request_id: {type: 'string', minLength: 1, maxLength: 128, 'x-max-utf8-bytes': 128},
            data: {oneOf: [closed({account_id: id, binding}),
                closed({account_id: id, bindings: {type: 'array', items: binding, minItems: 1, maxItems: 1}})]}
        });
    }
    schemas.BlackholeQueueLiveHint = closed({version: {type: 'integer', enum: [1]}, account_id: id, queue_id: id});
    schemas.BlackholeQueueLiveEvent = closed({action: {type: 'string', enum: ['event']},
        name: {type: 'string', enum: ['changed']}, subscribed_key: binding, subscription_key: route, routing_key: route,
        data: ref('BlackholeQueueLiveHint')});
    schemas.BlackholeQueueLiveEvent.description = 'Closed invalidation only. Runtime/client must match data.account_id and data.queue_id to the exact subscription and all routing fields; regex shape alone is not correlation or authorization. No counts, caller/agent fields, timestamps, revision or sequence.';
    return {schemas, extension: {
        implementation_status: 'implemented-in-source; deployment-specific acceptance required', runtime_verification: 'Not established by this catalog',
        selector: 'queue_live.changed.QUEUE_ID', account: 'Explicit data.account_id; both IDs are 32 lowercase hexadecimal characters; no wildcard.',
        client_messages: {subscribe: ref('BlackholeQueueLiveSubscribe'), unsubscribe: ref('BlackholeQueueLiveUnsubscribe')},
        server_event: ref('BlackholeQueueLiveEvent'),
        authorization: 'Fresh token through local active Crossbar authority at subscribe and each coalesced delivery; live, queues/stats and selected tenant-owned queue scopes, not merely account hierarchy. Native token caches remain; no instant global revocation guarantee. Ordinary call namespace authentication is separate.',
        admission: 'Send one binding per frame and wait for its matching success request_id before the next subscribe. One authorization worker per socket, 3-second result deadline, at most 100 subscriptions and 100 coalesced dirty scopes. Busy/error is not success. Unsubscribe explicit tracked bindings; close cleans session ownership. Subscribe ACK is not a broker-ready barrier.',
        reconciliation_seconds: 15,
        delivery: 'Lossy invalidations, not deltas. Refetch the authorized HTTP snapshot on a scoped hint and on reconnect, and reconcile overview inventory and snapshots at least every 15 seconds. Overflow, broker/federation, binding-readiness and mutation coverage gaps can lose hints. No replay, sequence, durable cursor or atomic snapshot/event boundary.',
        capability: 'Public websocket_updates readiness is separate; do not enable clients solely from this source contract or an HTTP101 response.'
    }};
}
function applyBlackhole({spec, root}) {
    const files = ['scripts/api-docs-blackhole.cjs', 'scripts/install-kazoo5.sh',
        'scripts/patches/blackhole-kazoo5-integration.patch',
        'scripts/patches/blackhole-token-redaction.patch',
        'scripts/patches/blackhole-redaction-to-integration.patch',
        'scripts/patches/blackhole-queue-live.patch',
        'scripts/patches/blackhole-pre-queue-live-integration.patch',
        'scripts/patches/crossbar-kazoo5-integration.patch',
        'scripts/patches/crossbar-kazoo5-before-frame.patch',
        'scripts/patches/crossbar-blackhole-frame-schema.patch',
        'applications/crossbar/priv/couchdb/schemas/system_config.blackhole.json',
        'applications/crossbar/src/modules/cb_websockets.erl',
        'applications/blackhole/src/blackhole_socket_handler.erl',
        'applications/blackhole/src/blackhole_init.erl',
        'applications/blackhole/src/blackhole_socket_callback.erl',
        'applications/blackhole/src/blackhole_bindings.erl',
        'applications/blackhole/src/blackhole_data_emitter.erl',
        'applications/blackhole/src/bh_context.erl', 'applications/blackhole/src/bh_events.erl',
        'applications/blackhole/src/modules/bh_ping.erl',
        'applications/blackhole/src/modules/bh_call.erl',
        'applications/blackhole/src/modules/bh_token_auth.erl',
        'applications/blackhole/src/modules/bh_queue_live.erl',
        'applications/acdc/src/acdc_live_auth.erl',
        'applications/acdc/src/kapi_acdc_dashboard_events.erl',
        'applications/blackhole/src/modules/bh_authz_subscribe.erl'];
    const queueSource = fs.readFileSync(path.join(root, 'applications/blackhole/src/modules/bh_queue_live.erl'), 'utf8');
    for (const expected of ['-define(AUTH_MS, 3000).', '-define(MAX_QUEUES, 100).',
        'acdc_live_auth:fresh_token(Token,A,Q)', '<<"queue_live.changed.",Q/binary>>',
        '<<"acdc.dashboard.changed.",A/binary,".",Q/binary>>', 'kapi_acdc_dashboard_events:changed_v(J)',
        '{<<"version">>,1},{<<"account_id">>,A},{<<"queue_id">>,Q}']) {
        assert(queueSource.includes(expected), 'Queue-live Blackhole source contract drift: ' + expected);
    }
    const inputs = files.map(file => ({file, sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')}));
    const ref = name => ({$ref: '#/components/schemas/' + name});
    const str = {type: 'string'}, strings = {type: 'array', items: str};
    const obj = (properties, required = []) => ({type: 'object', properties, ...(required.length ? {required} : {})});
    const schemas = spec.components.schemas;
    const queueLive = queueLiveBlackholeContract();
    Object.assign(schemas, queueLive.schemas);
    const request = action => obj({action: {type: 'string', enum: [action]}, auth_token: {...str, writeOnly: true, description: 'Secret Crossbar auth_token. Send in the JSON message, never in the URL or a WebSocket subprotocol.'}, request_id: {...str, minLength: 1, description: 'Client correlation ID; use a fresh ID per command, and match replies.'}}, ['action', 'auth_token', 'request_id']);
    for (const action of ['subscribe', 'unsubscribe']) {
        const shape = request(action);
        shape.properties.data = {...obj({account_id: {...str, description: 'Company scope is the Kazoo ACCOUNT_ID, not a company name. Defaults to the authenticated account; subject to server account-hierarchy authorization. This does not implement queue/agent dashboard permissions.'}, binding: {...str, minLength: 1, description: 'Native selector such as call.CHANNEL_ANSWER.* for account call answers, or call.CHANNEL_ANSWER.<CALL_ID> for one call. The last segment is a call ID, never a queue or agent ID. Arbitrary queue_id/agent_id fields do not create dashboard filters.'}, bindings: {...strings, minItems: 1}}),
            oneOf: [{required: ['binding'], not: {required: ['bindings']}}, {required: ['bindings'], not: {required: ['binding']}}]};
        shape.required.push('data');
        shape.description = 'Generic call-namespace frontend command profile; queue_live uses its stricter BlackholeQueueLiveSubscribe/Unsubscribe schemas and fresh scope authorization. Explicitly send token and correlation ID, and exactly one of binding or bindings. Server fields are more permissive. In the generic path a supplied bindings array takes precedence over binding; do not rely on upstream documentation claiming the reverse. Omitted account_id defaults to the authenticated account. Empty unsubscribe is rejected; unsubscribe the explicit tracked bindings or close the socket.';
        schemas[action === 'subscribe' ? 'BlackholeSubscribe' : 'BlackholeUnsubscribe'] = shape;
    }
    schemas.BlackholePing = request('ping');
    schemas.BlackholeReply = obj({action: {type: 'string', enum: ['reply']}, request_id: str,
        status: {type: 'string', enum: ['success', 'error']}, data: {type: 'object', description: 'Action-specific reply. Do not treat receipt as a delivered call or successful supervision connection.'}}, ['action', 'request_id', 'data']);
    schemas.BlackholeReply.description = 'General reply envelope. status can be omitted by the generic emitter; subscribe/unsubscribe/ping through the normal command path include success, while errors include error. The frontend should require success before advancing a pending subscription.';
    schemas.BlackholeSubscriptionResult = obj({subscribed: strings, unsubscribed: strings, subscriptions: strings}, ['subscriptions']);
    schemas.BlackholeSubscriptionResult.description = 'Subscribe returns subscribed; unsubscribe returns unsubscribed. Both are arrays, including an empty subscribed array for an already present binding. subscriptions is the current client-binding list on this socket, not durable replay state.';
    schemas.BlackholeErrorData = obj({errors: {type: 'array', items: str}}, ['errors']);
    schemas.BlackholePingResult = obj({response: {type: 'string', enum: ['pong']}}, ['response']);
    schemas.BlackholeEvent = obj({action: {type: 'string', enum: ['event']}, subscribed_key: str, subscription_key: str,
        name: str, routing_key: str, data: {type: 'object', description: 'Event-specific normalized payload. Do not assume every event supplies an ID, timestamp, queue ID or sequence.'}}, ['action', 'subscribed_key', 'subscription_key', 'name', 'routing_key', 'data']);
    schemas.BlackholeEvent.description = 'Native event envelope; no global sequence, durable cursor, delivery acknowledgement or replay guarantee is defined here. routing_key and subscription_key are routing metadata, not account authorization evidence.';
    const externalDocs = {url: '/apis/blackhole.html', description: 'Blackhole protocol and Next.js frontend integration'};
    spec['x-blackhole'] = {protocol: 'websocket', url: '/websocket', externalDocs,
        'x-contract-review': 'source-reviewed; not live acceptance',
        client_messages: {subscribe: ref('BlackholeSubscribe'), unsubscribe: ref('BlackholeUnsubscribe'), ping: ref('BlackholePing')},
        server_messages: {reply: ref('BlackholeReply'), event: ref('BlackholeEvent')},
        subscription_result: ref('BlackholeSubscriptionResult'), error_data: ref('BlackholeErrorData'), ping_result: ref('BlackholePingResult'),
        delivery: 'Best effort, socket-local subscriptions. Native emitter can drop messages under pressure. No durable replay or atomic snapshot/event boundary.',
        inbound_limits: {config_key: 'blackhole.max_frame_size_bytes', default_bytes: 65536, maximum_configured_bytes: 1048576,
            applies_to: 'New connections; individual frames and reassembled fragmented messages. Invalid configuration falls back to the default.',
            close_codes: {'1003': 'Unsupported binary frame or non-object JSON', '1007': 'Malformed or ambiguous JSON', '1009': 'Frame or reassembled message exceeds the configured limit'},
            acceptance: 'Source implementation; consult deployment evidence before assuming the running server has this patch.'},
        filtering: {company: 'data.account_id selects a Kazoo account, checked against the authenticated account hierarchy.',
            call: 'call.<EVENT>.<CALL_ID>; use * in the final segment for account-wide call events.',
            queue_and_agent: 'queue_live.changed.QUEUE_ID is the dedicated account-and-queue invalidation source contract below; no agent selector is provided. Never use a queue/agent ID in the call-ID position or rely on client-side filtering for authorization.'},
        acdc_dashboard: 'Implemented in source; deployment-specific acceptance required: exact account/queue invalidation with fresh authorization, sequential ACK admission and mandatory 15-second HTTP reconciliation. No historical or durable event contract.',
        queue_live: queueLive.extension};
    spec.tags ||= [];
    spec.tags.push({name: 'Blackhole WebSocket', description: 'Native event transport; see x-blackhole and Blackhole* schemas for frame contracts. HTTP OpenAPI generators do not generate WebSocket clients.', externalDocs});
    spec.paths['/websocket'] = {servers: [{url: '/', description: 'Same-origin proxy path, NOT /v2/websocket. Use wss on HTTPS; a separate frontend needs its explicitly configured trusted WSS endpoint.'}], get: {
        operationId: 'get_blackhole_websocket_upgrade', tags: ['Blackhole WebSocket'], summary: 'Upgrade to the native Blackhole WebSocket transport', security: [], externalDocs,
        description: 'HTTP Upgrade handshake only, not a REST subscription operation. A browser WebSocket may connect without an Authorization header; send auth_token in subsequent JSON commands. No Sec-WebSocket-Protocol is supported in this source. HTTP101 does not prove authentication or event delivery. Native listener defaults to 5555; expose the reverse-proxied WSS route, not a new event server.',
        responses: {'101': {description: 'Switching Protocols; continue with Blackhole JSON frames'}, '400': {description: 'Invalid handshake or unsupported subprotocol'}, '403': {description: 'Supplied handshake authentication rejected'}, '429': {description: 'Configured connection limit exceeded'}},
        'x-contract-review': 'source-reviewed', 'x-source-file': 'applications/blackhole/src/blackhole_socket_handler.erl', 'x-runtime-verification': 'Not live-verified by this catalog'}};
    spec.paths['/websockets'] = {get: {operationId: 'get_blackhole_available_bindings', tags: ['Blackhole WebSocket'], summary: 'Discover configured Blackhole binding patterns', security: [], externalDocs,
        description: 'Crossbar GET /v2/websockets. The exact top-level GET is public in cb_websockets. data is the configured blackhole.bindings object and may be missing when unavailable. Discovery is not proof that a listener/module is healthy, or that this caller can subscribe. Account-scoped /accounts/{ACCOUNT_ID}/websockets paths describe active sessions instead and retain their separate upstream review status.',
        responses: {'200': {description: 'Configured binding families; optional data if configuration is absent', content: {'application/json': {schema: obj({status: str, request_id: str, data: {type: 'object', additionalProperties: strings}})}}}},
        'x-contract-review': 'source-reviewed', 'x-source-file': 'applications/crossbar/src/modules/cb_websockets.erl', 'x-runtime-verification': 'Not live-verified by this catalog'}};
    for (const [url, item] of Object.entries(spec.paths)) if (url.includes('/websockets')) for (const op of Object.values(item)) if (op && typeof op === 'object' && op.operationId) op.externalDocs = externalDocs;
    return {inputs};
}
module.exports = {applyBlackhole, queueLiveBlackholeContract};
