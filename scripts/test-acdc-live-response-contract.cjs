#!/usr/bin/env node
'use strict';
// Consumes actual production-handler DTOs retained by the Erlang route fixture.
// This verifies the data contract, not a live HTTP/authentication round trip.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const Ajv = require('./api-docs-tooling/node_modules/ajv');
const {queueLiveContract} = require('./api-docs-queue-live.cjs');
assert.equal(process.argv.length, 3, 'Expected one retained fixture NDJSON path');
const input = fs.readFileSync(process.argv[2]);
assert(input.length > 0 && input.length <= 5 * 1024 * 1024, 'Unexpected fixture size');
const records = input.toString('utf8').trim().split('\n');
assert(records.length >= 10 && records.length <= 1000, 'Expected bounded real-handler fixture coverage');
const schemas = queueLiveContract().schemas;
const ajv = new Ajv({strict: false, validateFormats: false});
const validators = Object.fromEntries([['overview', 'QueueLiveEnvelope'], ['detail', 'QueueLiveDetailEnvelope']]
    .map(([route, name]) => [route, ajv.compile({components: {schemas}, $ref: '#/components/schemas/' + name})]));
const seen = new Set();
for (const line of records) {
    const record = JSON.parse(line);
    assert(Object.hasOwn(validators, record.route), 'Unknown route fixture');
    const validate = validators[record.route];
    assert(validate({status: 'success', data: record.data}), JSON.stringify(validate.errors));
    const calls = record.data.calls;
    seen.add(record.route + ':' + record.data.source.reason);
    if (calls && calls.available) seen.add(calls.truncated ? 'capped' : calls.observed_count === 0 ? 'empty' : 'calls');
}
for (const key of ['overview:consensus', 'detail:consensus', 'detail:source_timeout',
    'detail:inconsistent_sources', 'detail:invalid_response', 'detail:source_unavailable', 'capped', 'empty', 'calls']) {
    assert(seen.has(key), 'Missing actual-handler coverage: ' + key);
}
console.log(JSON.stringify({result: 'PASS', handler_dtos: records.length, required_states: 9,
    scope: 'production-handler data against OpenAPI; controlled providers, no live HTTP'}));
