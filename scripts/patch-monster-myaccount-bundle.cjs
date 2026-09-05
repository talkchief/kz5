'use strict';
// Mechanical rebuild of exactly the embedded MyAccount AMD definition. No
// app/template/style/config outside this one definition is replaced.
const fs = require('node:fs'), assert = require('node:assert/strict'), crypto = require('node:crypto');
const acorn = require('/usr/local/src/kazoo5-installer/monster-ui/node_modules/acorn');
const uglify = require('/usr/local/src/kazoo5-installer/monster-ui/node_modules/uglify-js');
const mainPath = '/var/www/html/monster-ui/js/main.js';
const sourcePath = '/usr/local/src/kazoo5-installer/monster-ui/src/apps/myaccount/app.js';
const backup = process.argv[2];
assert(backup && backup.startsWith('/var/backups/monster-myaccount-deploy.') && fs.readdirSync(backup).length === 0);
const source = fs.readFileSync(sourcePath, 'utf8'), main = fs.readFileSync(mainPath, 'utf8');
function findDefines(text, id) {
    const found = [], pending = [acorn.parse(text, {ecmaVersion: 2018})];
    while (pending.length) {
        const node = pending.pop();
        if (node.type === 'CallExpression' && node.callee.type === 'Identifier' && node.callee.name === 'define'
            && (id === null || node.arguments[0].value === id)) found.push(node);
        for (const child of Object.values(node)) {
            if (Array.isArray(child)) child.forEach(value => {if (value && value.type) pending.push(value);});
            else if (child && child.type) pending.push(child);
        }
    }
    return found;
}
const original = findDefines(main, 'apps/myaccount/app'), replacement = findDefines(source, null);
assert.equal(original.length, 1); assert.equal(replacement.length, 1);
const factory = replacement[0].arguments[0];
assert.equal(factory.type, 'FunctionExpression');
const dependencies = original[0].arguments[1];
assert.equal(dependencies.type, 'ArrayExpression');
assert.deepEqual(dependencies.elements.map(item => item.value), ['require', 'jquery', 'lodash', 'monster']);
const rebuilt = uglify.minify(`define("apps/myaccount/app",["require","jquery","lodash","monster"],${source.slice(factory.start, factory.end)});`);
if (rebuilt.error) throw rebuilt.error;
const code = rebuilt.code.replace(/;$/, '');
assert(code.includes('transitionend.myaccountOpen'), 'Transition fix omitted from compiled definition');
const prefix = main.slice(0, original[0].start), suffix = main.slice(original[0].end);
const next = prefix + code + suffix;
acorn.parse(next, {ecmaVersion: 2018});
assert.equal(fs.readFileSync(mainPath, 'utf8'), main, 'Shared bundle changed concurrently');
fs.writeFileSync(backup + '/main.js', main, {mode: 0o600});
fs.writeFileSync(backup + '/next-main.js', next, {mode: 0o600});
fs.writeFileSync(mainPath, next);
assert.equal(fs.readFileSync(mainPath, 'utf8'), next);
const sha = input => crypto.createHash('sha256').update(input).digest('hex');
const manifest = {component: 'myaccount', deployed_at: new Date().toISOString(), patched_module: 'apps/myaccount/app',
    source_sha256: sha(source), bundle_before_sha256: sha(main), bundle_after_sha256: sha(next),
    unchanged_prefix_sha256: sha(prefix), unchanged_suffix_sha256: sha(suffix), rollback_directory: backup};
fs.writeFileSync(backup + '/component-manifest.json', JSON.stringify(manifest, null, 2) + '\n', {mode: 0o600});
fs.writeFileSync('/usr/local/share/kazoo5-installer/monster-ui-myaccount-component.json', JSON.stringify(manifest, null, 2) + '\n', {mode: 0o644});
console.log(JSON.stringify({result: 'PASS', patched_module: manifest.patched_module, other_bundle_bytes_unchanged: true,
    rollback_directory: backup, bundle_sha256: manifest.bundle_after_sha256}));
