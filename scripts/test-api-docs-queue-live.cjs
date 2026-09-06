#!/usr/bin/env node
'use strict';
// Pure contract fixtures; no HTTP, AMQP, media, credentials or generated output.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const Ajv = require('./api-docs-tooling/node_modules/ajv');
const Parser = require('./api-docs-tooling/node_modules/@apidevtools/swagger-parser');
const {OVERVIEW, DETAIL, REASONS, METRICS, queueLiveContract, applyQueueLive} = require('./api-docs-queue-live.cjs');
const clone = value => JSON.parse(JSON.stringify(value));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const id = '0'.repeat(32), queue = '1'.repeat(32);
const contract = queueLiveContract();
const schemas = {...contract.schemas, CrossbarError: {type: 'object', properties: {status: {type: 'string'},
    error: {type: 'string'}, message: {type: 'string'}, data: {}}}};
const spec = {openapi: '3.0.3', info: {title: 'Synthetic queue-live contract fixture — not deployment proof', version: '1.0.0'},
    paths: contract.paths, components: {schemas, securitySchemes: {CrossbarToken: {type: 'apiKey', in: 'header', name: 'X-Auth-Token'}}}};
const ajv = new Ajv({strict: false, validateFormats: false});
const compile = schema => ajv.compile({components: spec.components, ...schema});
const validate = name => compile({$ref: '#/components/schemas/' + name});
let groups = 0, cases = 0;
function group(name, fn) { fn(); groups++; console.log('PASS ' + name); }
function accepts(test, value) { cases++; assert(test(value), JSON.stringify(test.errors)); }
function rejects(test, value) { cases++; assert.equal(test(value), false, 'Invalid queue-live schema fixture accepted'); }
function snapshot() {
    return {version: 1, account_id: id, generated_at: 1700003600,
        window: {from: 1700000000, to: 1700003600, seconds: 3600},
        queues: [{id: queue, name: 'Synthetic queue', strategy: 'round_robin', metrics_available: true,
            metrics: {current_waiting: 0, current_handled: 0, max_current_wait_seconds: null, records_entered: 0,
                waiting_in_cohort: 0, handled_in_cohort: 0, processed_in_cohort: 0, abandoned_in_cohort: 0,
                average_answered_wait_seconds: null, average_processed_talk_seconds: null}}],
        calls: null, pagination: {page_size: 50, next_start_queue_id: null, has_more: false},
        source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true,
            atomic_snapshot: false, status: 'available', reason: 'consensus',
            observation_started_at: 1700003599, observation_finished_at: 1700003600},
        capabilities: {live_call_details: false, agent_runtime: false, websocket_updates: false, historical_reporting: false}};
}
function calls() {
    return {available: true, complete: true, truncated: false, limit: 200, observed_count: 0,
        order: 'queue_id_entered_call_id', rows: []};
}
function callRow() {
    return {call_id: 'synthetic-call', queue_id: queue, status: 'waiting', entered_at: 1700000000, handled_at: null};
}
async function main() {
    group('two GET routes use account token security, bounded overview cursor and query-free detail', () => {
        assert.deepEqual(Object.keys(contract.paths), [OVERVIEW, DETAIL]);
        for (const url of [OVERVIEW, DETAIL]) {
            assert.deepEqual(Object.keys(contract.paths[url]), ['get']);
            const op = contract.paths[url].get;
            assert.deepEqual(op.security, [{CrossbarToken: []}]);
            assert.equal(op['x-reject-unknown-query-parameters'], true);
            assert.equal(op['x-implementation-status'], 'implemented-in-source; not-live-deployed');
            assert(op.description.includes('lookahead')); assert(op.description.includes('queues/stats'));
            assert.equal(op.requestBody, undefined);
            assert(!op['x-live-verification']);
        }
        const query = contract.paths[OVERVIEW].get.parameters.filter(p => p.in === 'query');
        assert.deepEqual(query.map(p => p.name), ['page_size', 'start_queue_id']);
        const page = compile(query[0].schema), cursor = compile(query[1].schema);
        accepts(page, 1); accepts(page, 100); assert.equal(query[0].schema.default, 50);
        for (const value of [0, 101, 1.5, '50', null]) rejects(page, value);
        accepts(cursor, queue);
        for (const value of ['', queue.toUpperCase().replace('1', 'A'), '2'.repeat(31), '../x', null]) rejects(cursor, value);
        assert.equal(contract.paths[DETAIL].get.parameters.filter(p => p.in === 'query').length, 0);
    });
    group('all ten metric fields are exact and explicit null differs from zero', () => {
        const test = validate('QueueLiveMetrics'), base = snapshot().queues[0].metrics;
        assert.equal(METRICS.length, 10); accepts(test, base);
        accepts(test, {...base, current_waiting: 2, max_current_wait_seconds: 90,
            average_answered_wait_seconds: 0, average_processed_talk_seconds: 2.5});
        for (const key of METRICS) {
            const absent = {...base}; delete absent[key]; rejects(test, absent);
            rejects(test, {...base, [key]: -1}); rejects(test, {...base, [key]: '0'});
            if (!key.startsWith('average_') && key !== 'max_current_wait_seconds') {
                rejects(test, {...base, [key]: null}); rejects(test, {...base, [key]: 1.5});
            }
        }
        rejects(test, {...base, max_current_wait_seconds: 1.5}); rejects(test, {...base, service_level: 95});
    });
    group('unavailable queue metrics must be null and never a plausible zero object', () => {
        const test = validate('QueueLiveQueue'), base = snapshot().queues[0];
        accepts(test, base); accepts(test, {...base, metrics_available: false, metrics: null});
        accepts(test, {...base, strategy: null}); rejects(test, {...base, name: null});
        rejects(test, {...base, name: ''}); rejects(test, {...base, name: 'x'.repeat(257)});
        rejects(test, {...base, metrics_available: false}); rejects(test, {...base, metrics: null});
        rejects(test, {...base, metrics_available: 'true'}); rejects(test, {...base, ready_agents: 10});
        rejects(test, {...base, id: 'foreign'});
    });
    group('pagination uses first-unreturned inclusive identity and consistent has_more/null shape', () => {
        const test = validate('QueueLivePagination');
        accepts(test, {page_size: 1, next_start_queue_id: null, has_more: false});
        accepts(test, {page_size: 100, next_start_queue_id: queue, has_more: true});
        rejects(test, {page_size: 50, next_start_queue_id: null, has_more: true});
        rejects(test, {page_size: 50, next_start_queue_id: queue, has_more: false});
        rejects(test, {page_size: 101, next_start_queue_id: null, has_more: false});
        assert(schemas.QueueLivePagination.description.includes('first unreturned'));
    });
    group('source coverage and route-scoped capability exclude node identities, scan counters and invented features', () => {
        const sourceTest = validate('QueueLiveSource'), source = snapshot().source;
        accepts(sourceTest, source);
        for (const reason of REASONS) {
            const available = ['consensus', 'empty_scope'].includes(reason);
            accepts(sourceTest, {...source, reason, status: available ? 'available' : reason === 'source_unavailable' ? 'unavailable' : 'partial',
                all_known_sources_responded: available, consistent: available});
        }
        accepts(sourceTest, {...source, status: 'partial', reason: 'source_timeout', all_known_sources_responded: false,
            consistent: false, observation_started_at: null, observation_finished_at: null});
        rejects(sourceTest, {...source, reason: 'source_timeout'});
        rejects(sourceTest, {...source, consistent: false});
        rejects(sourceTest, {...source, status: 'unavailable', reason: 'source_unavailable'});
        for (const field of ['source_ids', 'nodes', 'node', 'input_rows', 'scan_count']) rejects(sourceTest, {...source, [field]: []});
        rejects(sourceTest, {...source, atomic_snapshot: true}); rejects(sourceTest, {...source, coverage: 'cluster_complete'});
        rejects(sourceTest, {...source, reason: 'invented'});
        const capTest = validate('QueueLiveCapabilities'), caps = snapshot().capabilities; accepts(capTest, caps);
        accepts(capTest, {...caps, live_call_details: true});
        for (const key of Object.keys(caps)) {
            if (key !== 'live_call_details') rejects(capTest, {...caps, [key]: true});
            rejects(capTest, {...caps, [key]: null});
            const missing = {...caps}; delete missing[key]; rejects(capTest, missing);
        }
    });
    group('Unix seconds, fixed window, required envelope fields and maximum page are documented and typed', () => {
        const test = validate('QueueLiveEnvelope'), data = snapshot(); accepts(test, {data});
        accepts(test, {status: 'success', request_id: 'synthetic', data});
        accepts(test, {data: {...data, queues: []}});
        for (const key of Object.keys(data)) { const missing = clone(data); delete missing[key]; rejects(test, {data: missing}); }
        for (const generated_at of [null, 0, -1, '1700003600', 0.5]) rejects(test, {data: {...data, generated_at}});
        rejects(test, {data: {...data, version: 2}}); rejects(test, {data: {...data, window: {...data.window, seconds: 86400}}});
        rejects(test, {data: {...data, queues: Array(101).fill(data.queues[0])}});
        rejects(test, {data: {...data, agents: []}}); rejects(test, {data: {...data, calls: []}});
        assert(schemas.QueueLiveSnapshot.properties.generated_at.description.includes('Unix epoch seconds'));
        assert(schemas.QueueLiveSnapshot.properties.generated_at.description.includes('not proof of source freshness'));
    });
    group('selected detail has exactly one queue, page_size one and no cursor', () => {
        const test = validate('QueueLiveDetailEnvelope'), data = snapshot();
        data.pagination.page_size = 1; data.calls = calls(); data.capabilities.live_call_details = true;
        accepts(test, {data});
        rejects(test, {data: {...data, calls: null}});
        rejects(test, {data: {...data, capabilities: {...data.capabilities, live_call_details: false}}});
        rejects(validate('QueueLiveEnvelope'), {data});
        const overview = snapshot();
        rejects(validate('QueueLiveEnvelope'), {data: {...overview, calls: calls()}});
        rejects(validate('QueueLiveEnvelope'), {data: {...overview, capabilities: {...overview.capabilities, live_call_details: true}}});
        rejects(test, {data: {...data, queues: []}}); rejects(test, {data: {...data, queues: [data.queues[0], data.queues[0]]}});
        rejects(test, {data: {...data, pagination: {...data.pagination, page_size: 50}}});
        rejects(test, {data: {...data, pagination: {page_size: 1, next_start_queue_id: queue, has_more: true}}});
    });
    group('call rows are exact, status-dependent and signed Unix timestamps are retained', () => {
        const test = validate('QueueLiveCall'), row = callRow(); accepts(test, row);
        for (const entered_at of [-62167219199, -1, 0, 1]) accepts(test, {...row, entered_at});
        accepts(test, {...row, status: 'handled', entered_at: -100, handled_at: -10});
        accepts(test, {...row, status: 'handled', handled_at: 0});
        for (const field of ['caller_id_name', 'caller_id_number', 'agent_id', 'position', 'entered_timestamp']) rejects(test, {...row, [field]: 'private'});
        for (const key of Object.keys(row)) { const missing = {...row}; delete missing[key]; rejects(test, missing); }
        for (const status of ['processed', 'abandoned', 'ringing', null]) rejects(test, {...row, status});
        for (const entered_at of [null, 0.5, '1700000000']) rejects(test, {...row, entered_at});
        rejects(test, {...row, handled_at: 1}); rejects(test, {...row, status: 'handled'});
        rejects(test, {...row, status: 'handled', handled_at: 1.5});
        for (const call_id of ['', 'x'.repeat(257), 'bad\ncall', null]) rejects(test, {...row, call_id});
        rejects(test, {...row, queue_id: 'foreign'});
    });
    group('calls availability, null count, complete empty and capped observations cannot be conflated', () => {
        const test = validate('QueueLiveCalls'), complete = calls(); accepts(test, complete);
        const unavailable = {...complete, available: false, complete: false, observed_count: null};
        accepts(test, unavailable);
        const rows = Array.from({length: 200}, (_, i) => ({...callRow(), call_id: 'synthetic-' + i}));
        const capped = {...complete, complete: false, truncated: true, observed_count: 201, rows}; accepts(test, capped);
        accepts(test, {...capped, observed_count: 10000});
        accepts(test, {...complete, observed_count: 200, rows});
        for (const limit of [0, 199, 201, null]) rejects(test, {...complete, limit});
        for (const observed_count of [-1, 0.5, '0', null, 201]) rejects(test, {...complete, observed_count});
        for (const observed_count of [0, 200, 10001, null]) rejects(test, {...capped, observed_count});
        rejects(test, {...capped, rows: rows.slice(1)}); rejects(test, {...capped, rows: [...rows, callRow()]});
        rejects(test, {...capped, rows: Array(200).fill(callRow())});
        rejects(test, {...complete, complete: false}); rejects(test, {...complete, truncated: true});
        rejects(test, {...unavailable, observed_count: 0}); rejects(test, {...unavailable, rows: [callRow()]});
        rejects(test, {...unavailable, truncated: true}); rejects(test, {...unavailable, complete: true});
        rejects(test, {...complete, order: 'queue_position'}); rejects(test, {...complete, agent_ids: []});
        for (const key of Object.keys(complete)) { const missing = {...complete}; delete missing[key]; rejects(test, missing); }
        assert(schemas.QueueLiveCalls.description.includes('Runtime invariants'));
        assert(schemas.QueueLiveCalls.description.includes('NOT actual queue position'));
        const data = snapshot(); data.pagination.page_size = 1; data.calls = unavailable; data.capabilities.live_call_details = true;
        accepts(validate('QueueLiveDetailEnvelope'), {data});
    });
    group('handler cache policy and explicit HTTP errors do not change pre-handler authentication claims', () => {
        for (const url of [OVERVIEW, DETAIL]) {
            const op = contract.paths[url].get;
            for (const code of ['200', '400', '403', '404', '503']) assert.deepEqual(op.responses[code].headers['Cache-Control'].schema.enum, ['no-store']);
            assert.equal(op.responses['401'].headers, undefined);
            for (const code of ['400', '401', '403', '404', '503']) assert.equal(op.responses[code].content['application/json'].schema.$ref, '#/components/schemas/CrossbarError');
        }
    });
    group('focused overlay preserves unrelated operations and records exact source input bytes', () => {
        const target = {paths: {'/preserved': {get: {summary: 'Unrelated route'}}}, components: {schemas: {Preserved: {type: 'string'}}}};
        const result = applyQueueLive({spec: target, root});
        assert.deepEqual(target.paths['/preserved'], {get: {summary: 'Unrelated route'}});
        assert.deepEqual(target.components.schemas.Preserved, {type: 'string'});
        for (const input of result.inputs) assert.equal(input.sha256, hash(fs.readFileSync(path.join(root, input.file))));
        assert(result.inputs.some(input => input.file === 'scripts/api-docs-queue-live.cjs'));
        assert.equal(result.inputs.length, 9);
        assert(result.inputs.some(input => input.file === 'applications/acdc/src/acdc_live_auth.erl'));
        assert.equal(target.paths[DETAIL].get['x-runtime-source-sha256'], hash(fs.readFileSync(path.join(root, 'applications/acdc/src/cb_acdc_live.erl'))));
        assert.throws(() => applyQueueLive({spec: target, root}), /already exists/);
    });
    group('source timeout/route drift is refused instead of publishing stale claims', () => {
        const file = path.join(__dirname, 'api-docs-queue-live.cjs');
        for (const [changed, needle] of [['cb_acdc_live.erl', 'Until,3000)'],
            ['cb_queues.erl', 'cb_acdc_live:get(Context, Id)'],
            ['cb_acdc_live.erl', 'public_calls(false,_) -> null'],
            ['cb_acdc_live.erl', 'acdc_live_auth:authorize(C)'],
            ['acdc_live_auth.erl', 'andalso scopes(C,Resource).'],
            ['acdc_live_auth.erl', 'kz_auth_scope:all(cb_context:auth_token(C),Required)'],
            ['cb_acdc_live.erl', '{<<"agent_runtime">>,false},{<<"websocket_updates">>,false},{<<"historical_reporting">>,false}'],
            ['cb_acdc_live.erl', '{<<"rows">>,[public_call(R) || R<-val(<<"rows">>,C)]}'],
            ['cb_acdc_live.erl', '{<<"call_id">>,val(<<"call_id">>,R)},{<<"queue_id">>,val(<<"queue_id">>,R)}'],
            ['cb_acdc_live.erl', 'unix(N) when is_integer(N) -> N-?EPOCH'],
            ['cb_acdc_live.erl', 'normalized_calls(kz_json:get_value(<<"active_calls">>,S,null))'],
            ['acdc_dashboard_collector.erl', '-define(MAX_ACTIVE_CALLS, 200).'],
            ['kapi_acdc_dashboard.erl', 'calls_scope(true, [_]) -> true'],
            ['acdc_dashboard_snapshot.erl', 'fields(Row,[call_id,queue_id,status,']]) {
            const module = {exports: {}};
            const fakeFs = {...fs, readFileSync(file, ...args) {
                const value = fs.readFileSync(file, ...args);
                if (!String(file).endsWith('/' + changed)) return value;
                return Buffer.from(value.toString().replace(needle, 'REMOVED_BY_NEGATIVE_FIXTURE'));
            }};
            vm.runInNewContext(fs.readFileSync(file, 'utf8'), {module, exports: module.exports, __filename: file,
                require: name => name === 'node:fs' ? fakeFs : require(name)});
            assert.throws(() => module.exports.applyQueueLive({spec: {paths: {}, components: {schemas: {}}}, root}), /Queue-live (source contract|route hook) changed/);
        }
        assert(fs.readFileSync(path.join(__dirname, 'api-docs-overlays.cjs'), 'utf8')
            .includes("inputs.push(...require('./api-docs-queue-live.cjs').applyQueueLive({spec, root}).inputs)"));
    });
    await Parser.validate(clone(spec), {resolve: {http: false}, dereference: {circular: 'ignore'}});
    groups++; console.log('PASS OpenAPI 3.0.3 fragment with network resolution disabled');
    console.log(JSON.stringify({result: 'PASS', groups, schema_cases: cases, network: false, runtime: false, generated_assets: false}));
}
main().catch(error => {console.error(error.stack); process.exitCode = 1;});
