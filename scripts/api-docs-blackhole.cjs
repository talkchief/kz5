'use strict';
// Native protocol source contract; these extensions are not HTTP mutations.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
function applyBlackhole({spec, root}) {
    const files = ['scripts/api-docs-blackhole.cjs', 'scripts/install-kazoo5.sh',
        'applications/crossbar/src/modules/cb_websockets.erl',
        'applications/blackhole/src/blackhole_socket_handler.erl',
        'applications/blackhole/src/blackhole_init.erl',
        'applications/blackhole/src/blackhole_socket_callback.erl',
        'applications/blackhole/src/blackhole_data_emitter.erl',
        'applications/blackhole/src/bh_context.erl', 'applications/blackhole/src/bh_events.erl',
        'applications/blackhole/src/modules/bh_ping.erl',
        'applications/blackhole/src/modules/bh_call.erl',
        'applications/blackhole/src/modules/bh_token_auth.erl',
        'applications/blackhole/src/modules/bh_authz_subscribe.erl'];
    const inputs = files.map(file => ({file, sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')}));
    const ref = name => ({$ref: '#/components/schemas/' + name});
    const str = {type: 'string'}, strings = {type: 'array', items: str};
    const obj = (properties, required = []) => ({type: 'object', properties, ...(required.length ? {required} : {})});
    const schemas = spec.components.schemas;
    const request = action => obj({action: {type: 'string', enum: [action]}, auth_token: {...str, writeOnly: true, description: 'Secret Crossbar auth_token. Send in the JSON message, never in the URL or a WebSocket subprotocol.'}, request_id: {...str, minLength: 1, description: 'Client correlation ID; use a fresh ID per command, and match replies.'}}, ['action', 'auth_token', 'request_id']);
    for (const action of ['subscribe', 'unsubscribe']) {
        const shape = request(action);
        shape.properties.data = {...obj({account_id: str, binding: {...str, minLength: 1}, bindings: {...strings, minItems: 1}}),
            oneOf: [{required: ['binding'], not: {required: ['bindings']}}, {required: ['bindings'], not: {required: ['binding']}}]};
        shape.required.push('data');
        shape.description = 'Recommended frontend command profile: explicitly send token and correlation ID, and exactly one of binding or bindings. Server fields are more permissive. In this checkout a supplied bindings array takes precedence over binding; do not rely on upstream documentation claiming the reverse. Omitted account_id defaults to the authenticated account. Empty unsubscribe is rejected; unsubscribe the explicit tracked bindings or close the socket.';
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
        acdc_dashboard: 'Proposed: queue-scoped dashboard snapshots/events, permissions and gap/resync protocol are not yet implemented or published as callable contracts.'};
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
module.exports = {applyBlackhole};
