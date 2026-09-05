#!/usr/bin/env node
'use strict';
// Offline, deterministic source catalog. Never contacts an API or reads credentials.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const YAML = require('./api-docs-tooling/node_modules/yaml');
const Parser = require('./api-docs-tooling/node_modules/@apidevtools/swagger-parser');
const {applyOverlays, plannedSpec} = require('./api-docs-overlays.cjs');
const root = path.resolve(__dirname, '..');
const methods = ['get', 'put', 'post', 'patch', 'delete', 'head', 'options'];
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const clone = x => JSON.parse(JSON.stringify(x));
const pointer = x => x.replace(/~/g, '~0').replace(/\//g, '~1');
function walk(value, fn) {
    if (!value || typeof value !== 'object') return;
    fn(value);
    for (const child of Object.values(value)) walk(child, fn);
}
function normalize(value, kind) {
    const copy = clone(value);
    walk(copy, obj => {
        if (obj.$ref) {
            const ref = obj.$ref;
            if (ref.startsWith('../oas3-schemas.yml#/')) obj.$ref = '#/components/schemas/' + ref.split('#/')[1];
            else if (ref.startsWith('../oas3-parameters.yml#/')) obj.$ref = '#/components/parameters/' + ref.split('#/')[1];
            else if (ref.startsWith('#/')) obj.$ref = '#/components/' + kind + '/' + ref.slice(2);
            else throw new Error('Nonlocal/unrecognized upstream reference: ' + ref);
        }
    });
    return copy;
}
function jsonSchema(value, changes, location = 'queues') {
    if (Array.isArray(value)) return value.map((v, i) => jsonSchema(v, changes, location + '/' + i));
    if (!value || typeof value !== 'object') return value;
    const out = {};
    for (const [key, item] of Object.entries(value)) {
        if (key === '$schema' || key === '_id') continue;
        if (key === '$ref') {
            if (typeof item !== 'string' || !/^[a-zA-Z0-9_.-]+$/.test(item)) throw new Error('Unexpected resource schema reference');
            out[key] = '#/components/schemas/' + pointer(item);
        } else if (key.startsWith('support_level') || key.startsWith('deprecated') && typeof item !== 'boolean') {
            out['x-kazoo-' + key] = item;
            changes.push({location, keyword: key, action: 'preserved as extension'});
        } else out[key] = jsonSchema(item, changes, location + '/' + key);
    }
    return out;
}
function operations(spec) {
    return Object.entries(spec.paths).flatMap(([url, item]) => methods.filter(m => item[m]).map(method => ({url, method, operation: item[method]})));
}
function openApiSchema(schema, changes, location) {
    if (!schema || typeof schema !== 'object' || Array.isArray(schema)) return schema;
    const allowed = new Set(['$ref', 'title', 'multipleOf', 'maximum', 'exclusiveMaximum', 'minimum', 'exclusiveMinimum', 'maxLength', 'minLength', 'pattern', 'maxItems', 'minItems', 'uniqueItems', 'maxProperties', 'minProperties', 'required', 'enum', 'type', 'allOf', 'oneOf', 'anyOf', 'not', 'items', 'properties', 'additionalProperties', 'description', 'format', 'default', 'nullable', 'discriminator', 'readOnly', 'writeOnly', 'xml', 'externalDocs', 'example', 'deprecated']);
    const out = {};
    for (const [key, value] of Object.entries(schema)) {
        if (value === undefined) continue;
        if (!allowed.has(key) && !key.startsWith('x-')) {
            out['x-kazoo-' + key] = value;
            changes.push({location, keyword: key, action: 'Unsupported/malformed upstream keyword retained as extension; not enforced by OpenAPI 3.0 validators'});
        } else if (key === 'properties') out[key] = Object.fromEntries(Object.entries(value).map(([n, s]) => [n, openApiSchema(s, changes, location + '/properties/' + n)]));
        else if (['allOf', 'anyOf', 'oneOf'].includes(key)) out[key] = value.map((s, i) => openApiSchema(s, changes, location + '/' + key + '/' + i));
        else if (['items', 'not', 'additionalProperties'].includes(key) && typeof value === 'object') out[key] = openApiSchema(value, changes, location + '/' + key);
        else out[key] = value;
    }
    if (out.$ref && Object.keys(out).some(k => k !== '$ref')) {
        const target = out.$ref;
        delete out.$ref;
        out.allOf = [{$ref: target}, ...(out.allOf || [])];
    }
    return out;
}
function validateRefs(spec) {
    let total = 0;
    walk(spec, obj => {
        if (!obj.$ref) return;
        total++;
        if (!obj.$ref.startsWith('#/')) throw new Error('External reference prohibited: ' + obj.$ref);
        let target = spec;
        for (const part of obj.$ref.slice(2).split('/')) {
            const name = part.replace(/~1/g, '/').replace(/~0/g, '~');
            if (!target || !Object.hasOwn(target, name)) throw new Error('Unresolved reference: ' + obj.$ref);
            target = target[name];
        }
    });
    return total;
}
function readSources() {
    const files = [];
    for (const dir of ['applications/crossbar/src', 'applications/crossbar/src/modules', 'applications/acdc/src']) {
        for (const name of fs.readdirSync(path.join(root, dir)).sort()) {
            if (!/^cb_.*\.erl$/.test(name)) continue;
            const file = dir + '/' + name, data = fs.readFileSync(path.join(root, file));
            const nouns = [...data.toString().matchAll(/\*\.allowed_methods\.([a-z0-9_]+)/g)].map(m => m[1]);
            files.push({file, sha256: sha(data), literal_binding_nouns: [...new Set(nouns)]});
        }
    }
    return files;
}
async function build(output) {
    const source = path.join(root, 'applications/crossbar/priv/oas3');
    const inputs = [];
    for (const file of ['scripts/build-api-docs.cjs', 'scripts/api-docs-overlays.cjs', 'scripts/api-docs-queue-editor.cjs',
        'scripts/api-docs-tooling/package.json', 'scripts/api-docs-tooling/package-lock.json']) {
        if (fs.existsSync(path.join(root, file))) inputs.push({file, sha256: sha(fs.readFileSync(path.join(root, file)))});
    }
    function readYaml(file) {
        const bytes = fs.readFileSync(path.join(source, file));
        inputs.push({file: 'applications/crossbar/priv/oas3/' + file, sha256: sha(bytes)});
        return YAML.parse(bytes.toString());
    }
    const original = readYaml('openapi.yml');
    const spec = {openapi: '3.0.3', info: {
        title: 'Kazoo 5 Crossbar API — source catalog', version: '2.0.0',
        description: 'Crossbar v2 API catalog generated from this repository. All local path files are included, not only the upstream index. Source-reviewed ACDC and monitoring contracts are labeled per operation. Other entries remain upstream-generated and may omit request envelopes, error details, and response schemas. This catalog is not proof that an endpoint or feature is enabled on your deployment. Obtain an account-scoped token through user_auth or api_auth and send it in X-Auth-Token over HTTPS. Never share tokens or put them in example URLs. The hosted viewer cannot execute API calls.',
        license: {name: 'Mozilla Public License 2.0', url: 'https://www.mozilla.org/MPL/2.0/'}
    }, servers: [{url: '/v2', description: 'Same-origin HTTPS Crossbar proxy; configure the server in your API client for separate-node deployments.'}],
    paths: {}, components: {
        schemas: normalize(readYaml('oas3-schemas.yml'), 'schemas'),
        parameters: normalize(readYaml('oas3-parameters.yml'), 'parameters'),
        securitySchemes: {CrossbarToken: {type: 'apiKey', in: 'header', name: 'X-Auth-Token', description: 'Account-scoped Crossbar auth_token. HTTPS required. Never commit credentials. Permissions are enforced by Crossbar, not by this documentation.'}}
    }};
    const origins = {};
    for (const file of fs.readdirSync(path.join(source, 'paths')).filter(f => f.endsWith('.yml')).sort()) {
        const doc = normalize(readYaml('paths/' + file), 'schemas');
        for (const [url, item] of Object.entries(doc.paths || {})) {
            if (spec.paths[url]) throw new Error('Duplicate upstream path: ' + url);
            spec.paths[url] = item;
            origins[url] = 'applications/crossbar/priv/oas3/paths/' + file;
        }
    }
    for (const {url, operation} of operations(spec)) {
        operation['x-contract-review'] = 'upstream-generated; not individually verified';
        operation['x-source-file'] = origins[url];
        operation['x-runtime-verification'] = 'not asserted by this catalog';
        const params = operation.parameters || [];
        const auth = params.some(p => p.$ref === '#/components/parameters/auth_token_header' || p.name === 'X-Auth-Token');
        operation.parameters = params.filter(p => p.$ref !== '#/components/parameters/auth_token_header' && p.name !== 'X-Auth-Token');
        if (auth) operation.security = [{CrossbarToken: []}];
        else operation['x-auth-review'] = 'No auth header in upstream entry; public access is not independently verified.';
    }
    const adjustments = [];
    const queueFile = 'applications/crossbar/priv/couchdb/schemas/queues.json';
    const queueBytes = fs.readFileSync(path.join(root, queueFile));
    inputs.push({file: queueFile, sha256: sha(queueBytes)});
    spec.components.schemas.queues = jsonSchema(JSON.parse(queueBytes), adjustments);
    const overlay = applyOverlays(spec, root);
    for (const item of overlay.inputs) inputs.push(item);
    for (const [name, schema] of Object.entries(spec.components.schemas)) spec.components.schemas[name] = openApiSchema(schema, adjustments, 'components/schemas/' + name);
    // Path files omitted from the upstream index also contain missing parameter
    // definitions. Preserve those routes with honest unconstrained string IDs.
    const synthesizedParameters = [];
    walk(spec.paths, obj => {
        const prefix = '#/components/parameters/';
        if (!obj.$ref?.startsWith(prefix)) return;
        const name = obj.$ref.slice(prefix.length);
        if (!Object.hasOwn(spec.components.parameters, name)) {
            if (!/^[A-Z0-9_]+$/.test(name)) throw new Error('Unexpected missing parameter');
            spec.components.parameters[name] = {name, in: 'path', required: true, schema: {type: 'string'}, description: 'Identifier referenced by upstream route but missing from its parameter catalog; exact identifier constraints are not yet verified.'};
            synthesizedParameters.push(name);
        }
    });
    const missingSchemas = [];
    walk(spec, obj => {
        const prefix = '#/components/schemas/';
        if (!obj.$ref?.startsWith(prefix)) return;
        const name = obj.$ref.slice(prefix.length);
        if (!Object.hasOwn(spec.components.schemas, name)) {
            if (!/^[a-zA-Z0-9_.-]+$/.test(name)) throw new Error('Unexpected missing schema');
            spec.components.schemas[name] = {description: 'Upstream references this schema but does not provide it. No request/response shape or implementation is verified.', 'x-contract-review': 'missing-upstream-schema'};
            missingSchemas.push(name);
        }
    });
    const referenceCount = validateRefs(spec);
    const templates = new Map();
    for (const url of Object.keys(spec.paths)) {
        const template = url.replace(/\{[^}]+\}/g, '{}');
        if (templates.has(template)) throw new Error('Equivalent path templates: ' + templates.get(template) + ' and ' + url);
        templates.set(template, url);
    }
    const ids = new Set();
    for (const {url, method, operation} of operations(spec)) {
        if (!operation.operationId) operation.operationId = method + '_' + url.replace(/[^a-zA-Z0-9]+/g, '_');
        if (ids.has(operation.operationId)) throw new Error('Duplicate operationId: ' + operation.operationId);
        ids.add(operation.operationId);
    }
    // Dereferencing cycles are permitted in resource schemas, not traversed by our builder.
    await Parser.validate(clone(spec), {resolve: {http: false}, dereference: {circular: 'ignore'}});
    const all = operations(spec), sources = readSources();
    const apiNouns = new Set(Object.keys(spec.paths).flatMap(p => p.split('/').filter(s => s && !s.startsWith('{'))));
    const coverage = {
        format_version: 1, classification: 'source catalog, not runtime certification',
        upstream_index_paths: Object.keys(original.paths).length,
        included_upstream_paths: Object.keys(origins).length,
        upstream_paths_missing_from_index: Object.keys(origins).filter(p => !original.paths[p]).sort(),
        path_count: Object.keys(spec.paths).length, operation_count: all.length,
        source_reviewed_operations: all.filter(x => x.operation['x-contract-review'] === 'source-reviewed').map(x => x.method.toUpperCase() + ' ' + x.url),
        upstream_operations_not_individually_reviewed: all.filter(x => x.operation['x-contract-review'] !== 'source-reviewed').map(x => x.method.toUpperCase() + ' ' + x.url),
        operations_without_response_content_schema: all.filter(x => !Object.values(x.operation.responses || {}).some(r => r.content)).map(x => x.method.toUpperCase() + ' ' + x.url),
        schema_count: Object.keys(spec.components.schemas).length, internal_reference_count: referenceCount, unresolved_reference_count: 0,
        schema_adjustments: adjustments,
        upstream_missing_parameters_documented_as_strings: synthesizedParameters.sort(),
        upstream_missing_schemas_explicitly_unknown: missingSchemas.sort(),
        source_inventory: sources,
        literal_binding_nouns_without_path_segment: sources.flatMap(s => s.literal_binding_nouns.filter(n => !apiNouns.has(n)).map(noun => ({file: s.file, noun}))),
        source_coverage_limits: [
            'All existing local paths/*.yml entries are included. This is not an exhaustive proof of every dynamically routed Crossbar endpoint.',
            'Literal binding comparison is a gap detector, not a routing parser; variable/macro bindings and aliases need manual review.',
            'Most upstream operations have generic responses and resource-only request schemas. Only source-reviewed overlays correct those contracts.',
            'Schemas include staged repository configuration; source presence does not imply deployment activation or tested telephony behavior.',
            'Local synthetic supervision acceptance does not certify cross-node failover, external trunks, production capacity, or every API.',
            'Planned contracts are published separately and must not be called until implemented and deployed.'
        ], inputs: inputs.sort((a, b) => a.file.localeCompare(b.file))
    };
    fs.mkdirSync(output, {recursive: true});
    const write = (file, value) => fs.writeFileSync(path.join(output, file), JSON.stringify(value, null, 2) + '\n');
    write('openapi.json', spec);
    write('coverage.json', coverage);
    const planned = plannedSpec();
    validateRefs(planned);
    await Parser.validate(clone(planned), {resolve: {http: false}, dereference: {circular: 'ignore'}});
    write('planned.openapi.json', planned);
    const templateRoot = path.join(__dirname, 'api-docs-tooling/portal');
    for (const name of fs.readdirSync(templateRoot).sort()) fs.copyFileSync(path.join(templateRoot, name), path.join(output, name));
    const vendor = path.join(__dirname, 'api-docs-tooling/node_modules/swagger-ui-dist');
    const vendorFiles = ['swagger-ui-bundle.js', 'swagger-ui.css', 'LICENSE', 'NOTICE'];
    fs.mkdirSync(path.join(output, 'vendor'), {recursive: true});
    for (const name of vendorFiles) fs.copyFileSync(path.join(vendor, name), path.join(output, 'vendor', name));
    const pkg = JSON.parse(fs.readFileSync(path.join(vendor, 'package.json')));
    const assetFiles = ['openapi.json', 'coverage.json', 'planned.openapi.json', ...fs.readdirSync(templateRoot), ...vendorFiles.map(n => 'vendor/' + n)].sort();
    write('manifest.json', {format_version: 1, swagger_ui: {version: pkg.version, license: pkg.license, package: 'swagger-ui-dist', lock_file: 'scripts/api-docs-tooling/package-lock.json'},
        files: assetFiles.map(file => ({file, bytes: fs.statSync(path.join(output, file)).size, sha256: sha(fs.readFileSync(path.join(output, file)))}))});
    // These contain public documentation only. Do not inherit a root shell's
    // restrictive umask into the nginx-served artifact tree.
    for (const dir of [output, path.join(output, 'vendor')]) fs.chmodSync(dir, 0o755);
    for (const file of [...assetFiles, 'manifest.json']) fs.chmodSync(path.join(output, file), 0o644);
    return {paths: coverage.path_count, operations: coverage.operation_count, reviewed: coverage.source_reviewed_operations.length, schemas: coverage.schema_count, references: referenceCount};
}
if (require.main === module) {
    const args = process.argv.slice(2);
    if (args.length !== 2 || args[0] !== '--output') {
        console.error('Usage: node scripts/build-api-docs.cjs --output DIRECTORY (offline; no deployment)'); process.exit(2);
    }
    build(path.resolve(args[1])).then(result => console.log(JSON.stringify(result))).catch(error => {console.error(error.stack); process.exit(1);});
}
module.exports = {build, validateRefs, operations, jsonSchema};
