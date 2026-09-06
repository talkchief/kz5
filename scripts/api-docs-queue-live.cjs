'use strict';
// Offline v1 queue-live contract. Source review is not deployment acceptance.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const OVERVIEW = '/accounts/{ACCOUNT_ID}/queues/live';
const DETAIL = '/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/live';
const REASONS = Object.freeze(['consensus', 'empty_scope', 'source_unavailable', 'source_timeout', 'source_error',
    'incomplete_source', 'inconsistent_sources', 'source_set_changed', 'invalid_response', 'response_limit']);
const METRICS = Object.freeze(['current_waiting', 'current_handled', 'max_current_wait_seconds', 'records_entered',
    'waiting_in_cohort', 'handled_in_cohort', 'processed_in_cohort', 'abandoned_in_cohort',
    'average_answered_wait_seconds', 'average_processed_talk_seconds']);
const ref = name => ({$ref: '#/components/schemas/' + name});
const strict = properties => ({type: 'object', properties, required: Object.keys(properties), additionalProperties: false});
const id = {type: 'string', pattern: '^[a-f0-9]{32}$'};
const time = {type: 'integer', format: 'int64', minimum: 1,
    description: 'Unix epoch seconds. Not Kazoo Gregorian seconds or milliseconds.'};
const count = {type: 'integer', minimum: 0};
const fixedFalse = {type: 'boolean', enum: [false]};
const nullObject = {type: 'object', nullable: true, enum: [null]};
const noStore = {'Cache-Control': {description: 'Queue-live handler responses must not be cached.',
    schema: {type: 'string', enum: ['no-store']}}};
const response = (description, schema, cache = true) => ({description,
    ...(cache ? {headers: noStore} : {}), content: {'application/json': {schema}}});
function queueLiveContract() {
    const metrics = Object.fromEntries(METRICS.map(key => [key,
        key.startsWith('average_') ? {type: 'number', minimum: 0, nullable: true}
            : key === 'max_current_wait_seconds' ? {...count, nullable: true} : count]));
    const text = {type: 'string', minLength: 1, maxLength: 256, 'x-max-utf8-bytes': 256};
    const queueFields = {id, name: text, strategy: {...text, nullable: true}};
    const schemas = {
        QueueLiveMetrics: {...strict(metrics), description:
            'Observed current record states and the last-hour entered-record cohort. current_waiting/current_handled are observed states, not telephony channel verification. The seven count fields are nonnegative integers. Maximum wait and averages are null without an applicable observation or denominator; never replace null with zero. records_entered counts call/queue identities, not distinct queue visits. Service level, abandonment rate and handling-time KPIs are not provided.'},
        QueueLiveQueue: {oneOf: [
            strict({...queueFields, metrics_available: {type: 'boolean', enum: [true]}, metrics: ref('QueueLiveMetrics')}),
            strict({...queueFields, metrics_available: fixedFalse, metrics: nullObject})
        ], description: 'An authorized configured queue. Unavailable metrics are an explicit null object, not a zero-valued queue. The name and strategy describe configuration, not staffing or readiness.'},
        QueueLiveWindow: {...strict({from: time, to: time, seconds: {type: 'integer', enum: [3600]}}),
            description: 'Last-hour cohort window in Unix seconds. Current observations and entered-record cohort measures have different meanings; this is not historical reporting.'},
        QueueLivePagination: {oneOf: [
            strict({page_size: {type: 'integer', minimum: 1, maximum: 100}, next_start_queue_id: id, has_more: {type: 'boolean', enum: [true]}}),
            strict({page_size: {type: 'integer', minimum: 1, maximum: 100}, next_start_queue_id: {type: 'string', nullable: true, enum: [null]}, has_more: fixedFalse})
        ], description: 'next_start_queue_id is the first unreturned queue, not the last returned queue. Send it unchanged as the next inclusive start_queue_id. Null means no further page, not a partial-source error.'},
        QueueLiveSource: {...strict({coverage: {type: 'string', enum: ['observed_replicas']},
            all_known_sources_responded: {type: 'boolean'}, consistent: {type: 'boolean'}, atomic_snapshot: fixedFalse,
            status: {type: 'string', enum: ['available', 'partial', 'unavailable']}, reason: {type: 'string', enum: [...REASONS]},
            observation_started_at: {...time, nullable: true}, observation_finished_at: {...time, nullable: true}}),
            oneOf: [
                {properties: {status: {enum: ['available']}, reason: {enum: ['consensus', 'empty_scope']},
                    all_known_sources_responded: {enum: [true]}, consistent: {enum: [true]}}},
                {properties: {status: {enum: ['unavailable']}, reason: {enum: ['source_unavailable']},
                    all_known_sources_responded: {enum: [false]}, consistent: {enum: [false]}}},
                {properties: {status: {enum: ['partial']}, reason: {enum: REASONS.filter(reason => !['consensus', 'empty_scope', 'source_unavailable'].includes(reason))},
                    consistent: {enum: [false]}}}
            ],
            description: 'Consensus/coverage metadata for observed replicas, not an atomic cluster snapshot. available means consensus or an empty configured scope; unavailable means source_unavailable; every other listed reason is partial. consistent is true only for available. Source IDs, node names and internal scan counts are intentionally absent. A response timestamp is not source observation time. Partial/unavailable observations must not be presented as complete occupancy.'},
        QueueLiveCapabilities: {...strict({live_call_details: fixedFalse, agent_runtime: fixedFalse,
            websocket_updates: fixedFalse, historical_reporting: fixedFalse}),
            description: 'All four capabilities are false in v1. No caller/agent detail rows, runtime agent readiness, WebSocket update protocol or historical reporting are supplied by this route.'}
    };
    schemas.QueueLiveSnapshot = strict({version: {type: 'integer', enum: [1]}, account_id: id,
        generated_at: {...time, description: time.description + ' Response generation time, not proof of source freshness.'},
        window: ref('QueueLiveWindow'), queues: {type: 'array', maxItems: 100, items: ref('QueueLiveQueue')},
        pagination: ref('QueueLivePagination'), source: ref('QueueLiveSource'), capabilities: ref('QueueLiveCapabilities')});
    schemas.QueueLiveEnvelope = {type: 'object', properties: {status: {type: 'string', enum: ['success']},
        data: ref('QueueLiveSnapshot'), request_id: {type: 'string'}}, required: ['data']};
    schemas.QueueLiveDetailEnvelope = {allOf: [ref('QueueLiveEnvelope'), {type: 'object', properties: {
        data: {type: 'object', properties: {queues: {type: 'array', items: ref('QueueLiveQueue'), minItems: 1, maxItems: 1},
            pagination: {type: 'object', properties: {page_size: {enum: [1]}, has_more: {enum: [false]},
                next_start_queue_id: {type: 'string', nullable: true, enum: [null]}}}}}
    }}], description: 'A successful selected-queue response contains exactly one queue and never another page.'};
    const paths = {};
    for (const [url, selected] of [[OVERVIEW, false], [DETAIL, true]]) {
        paths[url] = {get: {
            operationId: selected ? 'getAccountQueueLiveSnapshot' : 'getAccountQueuesLiveSnapshot', tags: ['ACDC queues'],
            summary: selected ? 'Read an observed live snapshot for one queue' : 'Read a page of observed live queue snapshots',
            description: 'Implemented in source; not live-deployed. Read-only and account-scoped. Existing queues permissions AND the underlying queues/stats scope must allow the request. Each queue in the selected page, including the lookahead queue, must be authorized before data is returned. No configuration, roster or agent state is changed. Responses describe observed replicas, never an atomic global occupancy proof. Partial/unavailable source state is explicit and unavailable metrics are null. All v1 capability flags are false; do not fabricate call details, ready counts, SLA, historical reports or WebSocket updates. ' +
                (selected ? 'This selected-queue route accepts no query parameters; every unexpected query parameter is HTTP 400.'
                    : 'page_size defaults to 50, maximum 100. start_queue_id is an inclusive lower-case hexadecimal queue ID. The next page begins at next_start_queue_id, the first unreturned lookahead queue. Unknown query parameters are rejected.'),
            parameters: [{name: 'ACCOUNT_ID', in: 'path', required: true, schema: id}, ...(selected
                ? [{name: 'QUEUE_ID', in: 'path', required: true, schema: id}]
                : [{name: 'page_size', in: 'query', schema: {type: 'integer', minimum: 1, maximum: 100, default: 50}},
                    {name: 'start_queue_id', in: 'query', schema: id, description: 'Inclusive first queue ID. Use the preceding page’s next_start_queue_id; omit for the first page.'}])],
            security: [{CrossbarToken: []}],
            responses: {
                200: response('Version 1 observation envelope; inspect source status and metrics_available before displaying metrics', ref(selected ? 'QueueLiveDetailEnvelope' : 'QueueLiveEnvelope')),
                400: response('Invalid page size, start_queue_id cursor, duplicate or unexpected query parameter', ref('CrossbarError')),
                401: response('Missing or invalid authentication; pre-handler authentication behavior is unchanged', ref('CrossbarError'), false),
                403: response('Account, queues/stats scope, selected queue or lookahead authorization denied', ref('CrossbarError')),
                404: response('Selected queue identifier invalid, absent, deleted, wrong type or wrong account', ref('CrossbarError')),
                503: response('Queue inventory or snapshot dependency unavailable; no fabricated empty inventory', ref('CrossbarError'))
            },
            'x-reject-unknown-query-parameters': true,
            'x-contract-review': 'source-reviewed', 'x-implementation-status': 'implemented-in-source; not-live-deployed',
            'x-runtime-verification': 'Offline source/schema contract only. No broker, HTTP, browser, authorization or deployment acceptance is asserted by this catalog.'
        }};
    }
    return {paths, schemas};
}
function applyQueueLive({spec, root}) {
    const handler = 'applications/acdc/src/cb_acdc_live.erl';
    const sourceFiles = ['applications/acdc/src/cb_queues.erl', handler,
        'applications/acdc/src/acdc_dashboard_collector.erl', 'applications/acdc/src/acdc_dashboard_projection.erl',
        'applications/acdc/src/acdc_dashboard_snapshot.erl', 'applications/acdc/src/kapi_acdc_dashboard.erl',
        'applications/acdc/src/acdc_stats.erl'];
    const bytes = Object.fromEntries(sourceFiles.map(file => [file, fs.readFileSync(path.join(root, file))]));
    const source = bytes[handler].toString();
    for (const expected of ['-define(EPOCH, 62167219200).', '<<"cache-control">>, <<"no-store">>',
        'permit(Context, [<<"stats">>])', 'lists:foreach(fun(D) -> permit(Context, [kz_doc:id(D)]) end, Docs)',
        'Size = size_value(kz_json:get_value(<<"page_size">>,Query,50))', '{1,undefined}',
        'N>=1,N=<100', 'case QueueId of undefined -> [<<"page_size">>,<<"start_queue_id">>]; _ -> [] end',
        'kz_doc:id(lists:nth(Size+1, Docs))', '{startkey,Cursor}', 'Now-?EPOCH-3600',
        '<<"generated_at">>,ResponseTime-?EPOCH', '<<"atomic_snapshot">>,false', '<<"observed_replicas">>',
        'safe_text(kz_json:get_value(<<"strategy">>,D),null)', 'byte_size(B)=<256',
        'kz_amqp_worker:call_collect(Req,fun kapi_acdc_dashboard:publish_snapshot_req/1,Until,3000)',
        '<<"consensus">>-> <<"available">>', '<<"empty_scope">>-> <<"available">>',
        '<<"source_unavailable">>-> <<"unavailable">>; _-> <<"partial">>',
        '[{K,false} || K <- [<<"live_call_details">>,<<"agent_runtime">>',
        '<<"websocket_updates">>,<<"historical_reporting">>]']) {
        assert(source.includes(expected), 'Queue-live source contract changed: ' + expected);
    }
    for (const reason of REASONS) assert(source.includes('<<"' + reason + '">>'), 'Queue-live reason missing from source: ' + reason);
    const routes = bytes[sourceFiles[0]].toString();
    for (const hook of ['-define(LIVE_PATH_TOKEN, <<"live">>).', "cb_acdc_live:get(Context, 'undefined')", 'cb_acdc_live:get(Context, Id)']) {
        assert(routes.includes(hook), 'Queue-live route hook changed: ' + hook);
    }
    const inputs = sourceFiles.map(file => ({file, sha256: crypto.createHash('sha256').update(bytes[file]).digest('hex')}));
    const contract = queueLiveContract();
    for (const [url, item] of Object.entries(contract.paths)) {
        assert(!spec.paths[url], 'Queue-live route already exists; review instead of overwriting');
        item.get['x-source-file'] = handler; item.get['x-source-files'] = sourceFiles;
        item.get['x-runtime-source-sha256'] = inputs.find(input => input.file === handler).sha256;
        spec.paths[url] = item;
    }
    for (const [name, schema] of Object.entries(contract.schemas)) {
        assert(!spec.components.schemas[name], 'Queue-live schema already exists; review instead of overwriting');
        spec.components.schemas[name] = schema;
    }
    inputs.push({file: 'scripts/api-docs-queue-live.cjs', sha256: crypto.createHash('sha256')
        .update(fs.readFileSync(__filename)).digest('hex')});
    return {inputs};
}
module.exports = {OVERVIEW, DETAIL, REASONS, METRICS, queueLiveContract, applyQueueLive};
