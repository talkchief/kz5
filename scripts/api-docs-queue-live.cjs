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
const callTime = {type: 'integer', format: 'int64', description:
    'Signed Unix epoch seconds. A retained call can predate the Unix epoch; no positive minimum is imposed. Not Gregorian seconds or milliseconds.'};
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
    const callFields = {call_id: {...text, pattern: '^[^\\x00-\\x1f\\x7f]+$'}, queue_id: id, entered_at: callTime};
    const callsFields = {limit: {type: 'integer', enum: [200]},
        order: {type: 'string', enum: ['queue_id_entered_call_id']}};
    const callRows = {type: 'array', maxItems: 200, uniqueItems: true, items: ref('QueueLiveCall')};
    const agentRows = {type: 'array', maxItems: 200, uniqueItems: true, items: ref('QueueLiveAgent')};
    const agentIdentity = {agent_id: id, name: {...text, pattern: '^[^\\x00-\\x1f\\x7f]+$'}};
    const schemas = {
        QueueLiveAgent: {oneOf: [
            strict({...agentIdentity, observed: {type: 'boolean', enum: [true]}, queue_member: {type: 'boolean'},
                state: {type: 'string', enum: ['wait', 'sync', 'ready', 'ringing', 'answered', 'wrapup', 'paused', 'outbound']},
                reason: {type: 'string', enum: ['observed']}}),
            strict({...agentIdentity, observed: fixedFalse, queue_member: {type: 'boolean', nullable: true, enum: [null]},
                state: {type: 'string', nullable: true, enum: [null]},
                reason: {type: 'string', enum: ['not_observed', 'inconsistent_sources', 'source_unavailable']}})
        ], description: 'One authorized user from the selected queue persisted roster. name comes only from the authorized user document, never a broker payload. observed/state/queue_member are bounded runtime observations, not endpoint reachability, ready-to-ring eligibility, staffing capacity or an agent command. Unobserved is unknown, never implicitly logged out. No PID, runtime instance digest, device identity or private user fields are exposed.'},
        QueueLiveAgents: {...strict({limit: {type: 'integer', enum: [200]}, roster_complete: {type: 'boolean'},
            truncated: {type: 'boolean'}, runtime_complete: {type: 'boolean'}, endpoint_reachability_verified: fixedFalse,
            observation_started: {...time, nullable: true}, observation_finished: {...time, nullable: true}, rows: agentRows}),
            allOf: [
                {oneOf: [
                    {properties: {truncated: {enum: [false]}, roster_complete: {enum: [true]}}},
                    {properties: {truncated: {enum: [true]}, roster_complete: {enum: [false]},
                        runtime_complete: {enum: [false]}, rows: {...agentRows, minItems: 200}}}
                ]},
                {oneOf: [
                    {properties: {runtime_complete: {enum: [false]}}},
                    {properties: {runtime_complete: {enum: [true]}, truncated: {enum: [false]},
                        observation_started: time, observation_finished: time,
                        rows: {...agentRows, items: {allOf: [ref('QueueLiveAgent'),
                            {properties: {observed: {enum: [true]}}}]}}}}
                ]},
                {oneOf: [
                    {properties: {observation_started: time, observation_finished: time}},
                    {properties: {observation_started: {type: 'integer', nullable: true, enum: [null]},
                        observation_finished: {type: 'integer', nullable: true, enum: [null]}, runtime_complete: {enum: [false]},
                        rows: {...agentRows, items: {allOf: [ref('QueueLiveAgent'),
                            {properties: {observed: {enum: [false]}, reason: {enum: ['source_unavailable']}}}]}}}}
                ]}
            ], description: 'Selected queue only; overview returns agents=null. The sole roster query fetches at most 201 selected-queue user documents, authorizes every fetched agent and its status resource (including lookahead), then returns at most 200 unique ID-sorted rows. No global user listing. roster_complete is !truncated. runtime_complete requires an available runtime observation, every displayed row observed, and no roster truncation; an available empty roster can be complete, unavailable runtime cannot. Missing runtime rows are not_observed; unavailable runtime yields source_unavailable rows and null timestamps. Observation timestamps are Unix seconds; runtime enforces finish>=start and exact authorized row identities. These cross-value/runtime checks are not fully expressible in OpenAPI. Even complete runtime observations do not verify endpoints or prove agents can accept a call.'},
        QueueLiveCall: {oneOf: [
            strict({...callFields, status: {type: 'string', enum: ['waiting']},
                handled_at: {type: 'integer', nullable: true, enum: [null]}}),
            strict({...callFields, status: {type: 'string', enum: ['handled']}, handled_at: callTime})
        ], description: 'Observed active call/queue identity, not a distinct visit or verified telephony channel. Only these five fields are exposed; no caller name/number, agent ID or queue position. Waiting has handled_at=null; handled has an integer handled_at. Runtime validation requires entered_at <= handled_at <= observation time for handled rows and entered_at <= observation time for every row.'},
        QueueLiveCalls: {oneOf: [
            strict({...callsFields, available: fixedFalse, complete: fixedFalse, truncated: fixedFalse,
                observed_count: {type: 'integer', nullable: true, enum: [null]}, rows: {...callRows, maxItems: 0}}),
            strict({...callsFields, available: {type: 'boolean', enum: [true]}, complete: {type: 'boolean', enum: [true]},
                truncated: fixedFalse, observed_count: {...count, maximum: 200}, rows: callRows}),
            strict({...callsFields, available: {type: 'boolean', enum: [true]}, complete: fixedFalse,
                truncated: {type: 'boolean', enum: [true]}, observed_count: {type: 'integer', minimum: 201, maximum: 10000},
                rows: {...callRows, minItems: 200}})
        ], description: 'Selected-queue calls only. Unavailable means empty rows and null observed_count, never an observed zero. Complete available observations may legitimately have no active calls and count zero. A capped observation is available=true, complete=false, truncated=true with 200 rows and observed_count>200. Rows are ordered by queue_id, entered_at, call_id, oldest entered first within the selected queue; this is NOT actual queue position. Runtime invariants: row identities are unique and scoped to the selected queue, rows.length=min(observed_count,200), and observed_count equals the selected queue current_waiting+current_handled when the source is exhausted. OpenAPI does not express these cross-value comparisons. Completeness is local non-atomic observation coverage, not global occupancy proof.'},
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
        QueueLiveCapabilities: {...strict({live_call_details: {type: 'boolean'}, agent_runtime: {type: 'boolean'},
            websocket_updates: fixedFalse, historical_reporting: fixedFalse}),
            description: 'live_call_details and agent_runtime are true for selected detail and false for overview; they indicate supported DTOs, not current data availability or ready eligibility. websocket_updates and historical_reporting remain false.'}
    };
    schemas.QueueLiveSnapshot = strict({version: {type: 'integer', enum: [1]}, account_id: id,
        generated_at: {...time, description: time.description + ' Response generation time, not proof of source freshness.'},
        window: ref('QueueLiveWindow'), queues: {type: 'array', maxItems: 100, items: ref('QueueLiveQueue')},
        calls: {oneOf: [nullObject, ref('QueueLiveCalls')]},
        agents: {oneOf: [nullObject, ref('QueueLiveAgents')]},
        pagination: ref('QueueLivePagination'), source: ref('QueueLiveSource'), capabilities: ref('QueueLiveCapabilities')});
    const callScope = selected => ({type: 'object', properties: {calls: selected ? ref('QueueLiveCalls') : nullObject,
        agents: selected ? ref('QueueLiveAgents') : nullObject,
        capabilities: {type: 'object', properties: {live_call_details: {enum: [selected]}, agent_runtime: {enum: [selected]}}}}});
    schemas.QueueLiveSnapshot.oneOf = [callScope(false), callScope(true)];
    schemas.QueueLiveEnvelope = {type: 'object', properties: {status: {type: 'string', enum: ['success']},
        data: {allOf: [ref('QueueLiveSnapshot'), callScope(false)]}, request_id: {type: 'string'}}, required: ['data']};
    schemas.QueueLiveDetailEnvelope = {type: 'object', properties: {status: {type: 'string', enum: ['success']},
        request_id: {type: 'string'}, data: {allOf: [ref('QueueLiveSnapshot'), callScope(true),
        {type: 'object', properties: {queues: {type: 'array', items: ref('QueueLiveQueue'), minItems: 1, maxItems: 1},
            pagination: {type: 'object', properties: {page_size: {enum: [1]}, has_more: {enum: [false]},
                next_start_queue_id: {type: 'string', nullable: true, enum: [null]}}}}}]}}, required: ['data'],
        description: 'A successful selected-queue response contains exactly one queue, calls and agents objects, live_call_details=true, agent_runtime=true and never another queue page. Inspect calls.available/calls.complete and agents roster/runtime completeness separately; capabilities alone are not availability or eligibility.'};
    const paths = {};
    for (const [url, selected] of [[OVERVIEW, false], [DETAIL, true]]) {
        paths[url] = {get: {
            operationId: selected ? 'getAccountQueueLiveSnapshot' : 'getAccountQueuesLiveSnapshot', tags: ['ACDC queues'],
            summary: selected ? 'Read an observed live snapshot for one queue' : 'Read a page of observed live queue snapshots',
            description: 'Implemented in source; not live-deployed. Read-only and account-scoped. Existing queues permissions AND the underlying queues/stats scope must allow the request. Each queue in the selected page, including the lookahead queue, must be authorized before data is returned. Detail additionally requires selected queues/QUEUE_ID/roster and agents/AGENT_ID plus agents/AGENT_ID/status permissions for every fetched roster identity, including its lookahead. No configuration, roster or agent state is changed. Responses describe observed replicas, never an atomic global occupancy proof. Partial/unavailable source state is explicit and unavailable metrics are null. Selected call rows and metrics must agree across sources; disagreements withhold both, never sum replicas. Overview has calls=null, agents=null and both corresponding capabilities=false. Detail has bounded calls and agents objects and corresponding capabilities=true, independently of data availability. Agent names and IDs come only from the selected authorized roster; observed runtime is not endpoint reachability or ready-to-ring eligibility. No caller name/number, actual queue positions, ready counts, SLA, historical reports or WebSocket updates are supplied. ' +
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
                403: response('Account, queues/stats scope, selected queue, roster, agent/status resource or lookahead authorization denied', ref('CrossbarError')),
                404: response('Selected queue identifier invalid, absent, deleted, wrong type or wrong account', ref('CrossbarError')),
                503: response('Queue/agent inventory or snapshot dependency unavailable or malformed; no fabricated empty inventory', ref('CrossbarError'))
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
        'applications/acdc/src/acdc_live_auth.erl',
        'applications/acdc/src/cb_acdc_live_agents.erl',
        'applications/acdc/src/acdc_dashboard_agents.erl',
        'applications/acdc/priv/couchdb/views/queues.json',
        'applications/acdc/src/acdc_dashboard_collector.erl', 'applications/acdc/src/acdc_dashboard_projection.erl',
        'applications/acdc/src/acdc_dashboard_snapshot.erl', 'applications/acdc/src/kapi_acdc_dashboard.erl',
        'applications/acdc/src/acdc_stats.erl'];
    const bytes = Object.fromEntries(sourceFiles.map(file => [file, fs.readFileSync(path.join(root, file))]));
    const source = bytes[handler].toString();
    for (const expected of ['-define(EPOCH, 62167219200).', '<<"cache-control">>, <<"no-store">>',
        'permit(Context, [<<"stats">>])', 'lists:foreach(fun(D) -> permit(Context, [kz_doc:id(D)]) end, Docs)',
        'acdc_live_auth:permit(C,Params)', 'acdc_live_auth:authorize(C)',
        'Size = size_value(kz_json:get_value(<<"page_size">>,Query,50))', '{1,undefined}',
        'N>=1,N=<100', 'case QueueId of undefined -> [<<"page_size">>,<<"start_queue_id">>]; _ -> [] end',
        'kz_doc:id(lists:nth(Size+1, Docs))', '{startkey,Cursor}', 'Now-?EPOCH-3600',
        '<<"generated_at">>,ResponseTime-?EPOCH', '<<"atomic_snapshot">>,false', '<<"observed_replicas">>',
        'safe_text(kz_json:get_value(<<"strategy">>,D),null)', 'byte_size(B)=<256',
        'kz_amqp_worker:call_collect(Req,fun kapi_acdc_dashboard:publish_snapshot_req/1,Until,3000)',
        '<<"consensus">>-> <<"available">>', '<<"empty_scope">>-> <<"available">>',
        '<<"source_unavailable">>-> <<"unavailable">>; _-> <<"partial">>',
        'IncludeCalls = QueueId =/= undefined', '<<"calls">>,public_calls(IncludeCalls, ActiveCalls)',
        '<<"live_call_details">>,IncludeCalls',
        '{<<"agent_runtime">>,IncludeCalls},{<<"websocket_updates">>,false},{<<"historical_reporting">>,false}',
        'AgentScope = cb_acdc_live_agents:prepare(Context,QueueId)',
        '{<<"agents">>,cb_acdc_live_agents:public(AgentScope,RuntimeAgents)}',
        'case AgentIds of undefined -> []; _ -> [{<<"Agent-IDs">>,AgentIds}] end',
        'public_calls(false,_) -> null', 'public_calls(true,null)',
        '{<<"limit">>,200},{<<"observed_count">>,null}',
        '{<<"rows">>,[public_call(R) || R<-val(<<"rows">>,C)]}', 'public_call(R) ->',
        '{<<"call_id">>,val(<<"call_id">>,R)},{<<"queue_id">>,val(<<"queue_id">>,R)}',
        '{<<"status">>,val(<<"status">>,R)}',
        '{<<"observed_count">>,val(<<"observed_count">>,C)},{<<"order">>,val(<<"order">>,C)}',
        'normalized_calls(kz_json:get_value(<<"active_calls">>,S,null))',
        '(val(<<"Include-Calls">>,R)=:=true)=:=(props:get_value(<<"Include-Calls">>,Req)=:=true)',
        '<<"entered_at">>,unix(val(<<"entered_timestamp">>,R))',
        '<<"handled_at">>,unix(val(<<"handled_timestamp">>,R))',
        'unix(null) -> null', 'unix(N) when is_integer(N) -> N-?EPOCH']) {
        assert(source.includes(expected), 'Queue-live source contract changed: ' + expected);
    }
    for (const [file, needles] of [
        ['applications/acdc/src/cb_acdc_live_agents.erl', [
            '-define(LIMIT,200).', 'prepare(_,undefined) -> undefined',
            'acdc_live_auth:permit(C,<<"queues">>,[Q,<<"roster">>])',
            'acdc_live_auth:permit(C,<<"agents">>,[I])',
            'acdc_live_auth:permit(C,<<"agents">>,[I,<<"status">>])',
            '{startkey,[Q]},{endkey,[Q,kz_json:new()]},{reduce,false},include_docs,{limit,?LIMIT+1}',
            'kz_doc:type(D)=:= <<"user">> andalso kz_doc:account_id(D)=:=A',
            'not kz_doc:is_deleted(D) andalso not kz_doc:is_soft_deleted(D)',
            'selected(val(<<"queues">>,D),Q)', 'not maps:is_key(I,Seen)',
            'public(undefined,_) -> null', 'runtime(null,_) -> {#{},null,null,false}',
            'Start-?EPOCH,Finish-?EPOCH,true',
            'Complete=Available andalso not Truncated andalso lists:all',
            '{<<"endpoint_reachability_verified">>,false}',
            'lists:member(S,[<<"wait">>,<<"sync">>,<<"ready">>,<<"ringing">>',
            '<<"answered">>,<<"wrapup">>,<<"paused">>,<<"outbound">>]',
            'Parts=[V || K<-[<<"first_name">>,<<"last_name">>]',
            '[{<<"agent_id">>,kz_doc:id(D)},{<<"name">>,name(D)}']],
        ['applications/acdc/src/acdc_dashboard_agents.erl', [
            '-define(MAX_AGENTS,200).', 'endpoint_reachability_verified=>false',
            'Start=wall(),Deadline=erlang:monotonic_time(millisecond)+?BUDGET_MS']],
        ['applications/acdc/priv/couchdb/views/queues.json', ['"agents_listing"',
            "doc.pvt_type !== 'user'", 'emit([doc.queues[i], doc._id], null)']],
        ['applications/acdc/src/acdc_live_auth.erl', [
            'crossbar_bindings:pmap(api_util:create_event_name(C,<<"authorize">>),C)',
            '<<"authorize.",Resource/binary>>', 'lists:any(fun(true)->true;', 'andalso scopes(C,Resource).',
            '<<"allowed_scopes.",Resource/binary>>', 'kz_auth_scope:all(cb_context:auth_token(C),Required)',
            '{fun cb_context:set_req_verb/2,?HTTP_GET},{fun cb_context:set_query_string/2,kz_json:new()}',
            'throw({live_error,403,<<"queue_live_resource_forbidden">>})']],
        ['applications/acdc/src/acdc_dashboard_collector.erl', ['-define(MAX_ACTIVE_CALLS, 200).',
            'gb_trees:insert({Queue, Entered, Call}, Value, Tree)', 'order=>queue_id_entered_call_id']],
        ['applications/acdc/src/kapi_acdc_dashboard.erl', ['calls_scope(true, [_]) -> true',
            'bounded_integer(N,10000)', 'value(<<"limit">>,A)=:=200',
            'active_timeline(<<"waiting">>,_,null,_) -> true',
            'active_timeline(<<"handled">>,E,H,AsOf)',
            'active_count_matches(true,N,[Queue])', 'erlang:min(N,200)',
            'not maps:is_key(Identity,Seen)', 'Previous<Key']],
        ['applications/acdc/src/acdc_dashboard_snapshot.erl', ['fields(Row,[call_id,queue_id,status,',
            'entered_timestamp,handled_timestamp])', 'scalar(undefined) -> null']]
    ]) {
        for (const needle of needles) assert(bytes[file].toString().includes(needle),
            'Queue-live source contract changed: ' + file + ': ' + needle);
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
