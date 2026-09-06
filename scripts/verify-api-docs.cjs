#!/usr/bin/env node
'use strict';
// Deployment-time verification needs only Node built-ins, no npm/network access.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const expected = ['blackhole.html', 'coverage.json', 'index.html', 'openapi.json', 'planned.openapi.json', 'portal.css', 'portal.js', 'vendor/LICENSE', 'vendor/NOTICE', 'vendor/swagger-ui-bundle.js', 'vendor/swagger-ui.css'].sort();
function checkTarget(directory) {
    const base = path.resolve(directory);
    for (const relative of ['', 'manifest.json', ...expected]) {
        const file = relative ? path.join(base, relative) : base;
        for (let current = file; ; current = path.dirname(current)) {
            try {
                const stat = fs.lstatSync(current);
                assert(!stat.isSymbolicLink(), 'Refusing a symlink in documentation target');
                assert(current === file && relative && !['vendor'].includes(relative) ? stat.isFile() : stat.isDirectory(), 'Invalid documentation target type');
                if (stat.isFile()) assert.equal(stat.nlink, 1, 'Refusing a hardlinked documentation target');
            } catch (error) {if (error.code !== 'ENOENT') throw error;}
            if (current === path.dirname(current)) break;
        }
    }
    return {target: 'safe'};
}
function verify(directory) {
    const base = path.resolve(directory);
    checkTarget(base);
    const manifestFile = path.join(base, 'manifest.json');
    assert(fs.lstatSync(base).isDirectory() && !fs.lstatSync(base).isSymbolicLink(), 'Portal root must be a real directory');
    assert(fs.lstatSync(manifestFile).isFile() && !fs.lstatSync(manifestFile).isSymbolicLink(), 'Manifest must be a regular file');
    const manifest = JSON.parse(fs.readFileSync(manifestFile));
    for (const dir of [base, path.join(base, 'vendor')]) assert.equal(fs.statSync(dir).mode & 0o777, 0o755, 'Public documentation directory must be 0755');
    assert.equal(fs.statSync(manifestFile).mode & 0o777, 0o644, 'Public documentation manifest must be 0644');
    assert.equal(manifest.format_version, 1);
    assert.equal(manifest.swagger_ui.version, '5.32.15');
    assert.deepEqual(manifest.files.map(item => item.file).sort(), expected, 'Unexpected asset manifest');
    for (const item of manifest.files) {
        const file = path.join(base, item.file);
        for (let current = file; current !== base; current = path.dirname(current)) assert(!fs.lstatSync(current).isSymbolicLink(), 'Symlink in portal asset path');
        assert(fs.lstatSync(file).isFile(), 'Asset must be a regular file');
        assert.equal(fs.statSync(file).mode & 0o777, 0o644, 'Public documentation asset must be 0644: ' + item.file);
        const bytes = fs.readFileSync(file);
        assert.equal(bytes.length, item.bytes, 'Wrong byte length: ' + item.file);
        assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), item.sha256, 'Wrong SHA-256: ' + item.file);
    }
    const script = fs.readFileSync(path.join(base, 'portal.js'), 'utf8');
    for (const required of ['supportedSubmitMethods: []', 'validatorUrl: null', 'persistAuthorization: false', 'queryConfigEnabled: false', "request.credentials = 'omit'", 'This documentation viewer cannot execute API requests.']) assert(script.includes(required), 'Missing viewer safeguard');
    const spec = JSON.parse(fs.readFileSync(path.join(base, 'openapi.json')));
    const coverage = JSON.parse(fs.readFileSync(path.join(base, 'coverage.json')));
    assert.equal(spec.openapi, '3.0.3');
    assert.equal(coverage.unresolved_reference_count, 0);
    assert.equal(Object.keys(spec.paths).length, coverage.path_count);
    assert(spec.paths['/accounts/{ACCOUNT_ID}/channels/{UUID}'].post.responses['202']);
    return {files: manifest.files.length, paths: coverage.path_count, operations: coverage.operation_count, swagger_ui: manifest.swagger_ui.version};
}
if (require.main === module) {
    const targetOnly = process.argv[2] === '--check-target';
    if (process.argv.length !== (targetOnly ? 4 : 3)) {console.error('Usage: node scripts/verify-api-docs.cjs [--check-target] PORTAL_DIRECTORY'); process.exit(2);}
    try {console.log(JSON.stringify(targetOnly ? checkTarget(process.argv[3]) : verify(process.argv[2])));} catch (e) {console.error('API documentation verification failed: ' + e.message); process.exit(1);}
}
module.exports = {verify, checkTarget};
