#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict'), path = require('node:path'), fs = require('node:fs');
const {applyCallForwardConfirmation, ROUTE, locales} = require('./api-docs-call-forward-confirmation.cjs');
const root = path.resolve(__dirname, '..');
const Ajv = require('./api-docs-tooling/node_modules/ajv');
const accounts = JSON.parse(fs.readFileSync(path.join(root, 'applications/crossbar/priv/couchdb/schemas/accounts.json')));
const spec = {components: {schemas: {accounts: {type: 'object', required: ['name'], properties: {name: {type: 'string'}}}, CrossbarError: {type: 'object'}}},
    paths: {[ROUTE]: Object.fromEntries(['get', 'patch', 'post'].map(m => [m, {responses: {200: {description: 'before'}}}]))}};
const result = applyCallForwardConfirmation({spec, root}); assert(result.inputs.length >= 5);
const ajv = new Ajv({strict: false, allErrors: true});
const validate = schema => ajv.compile({components: spec.components, ...schema});
const patchBody = spec.paths[ROUTE].patch.requestBody.content['application/json'];
const patchValidate = validate(patchBody.schema), readValidate = validate(spec.components.schemas.ForwardedCallConfirmation);
assert.deepEqual(spec.components.schemas.ForwardedCallConfirmation.properties.language.enum, accounts.properties.call_forward_confirmation.properties.language.enum);
for (const language of [...locales, null]) assert(patchValidate({data: {call_forward_confirmation: {language}}}), JSON.stringify(patchValidate.errors));
for (const language of locales) assert(readValidate({language}));
assert(!readValidate({language: null}));
assert(patchValidate({data: {name: 'Unrelated update'}}));
for (const value of [null, 'he-il', {}, {language: 'de-de'}, {language: 'he-il', url: 'https://example.invalid'}])
    assert(!patchValidate({data: {call_forward_confirmation: value}}));
for (const example of Object.values(patchBody.examples)) assert(patchValidate(example.value));
assert(!validate(spec.paths[ROUTE].post.requestBody.content['application/json'].schema)({data: {call_forward_confirmation: {language: 'he-il'}}}));
assert(spec.paths[ROUTE].patch['x-codeSamples'][0].source.includes("method: 'PATCH'"));
console.log('PASS confirmation OpenAPI enum, persisted/reset distinction, partial PATCH, full POST requirements and frontend examples.');
