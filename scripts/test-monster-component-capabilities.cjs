'use strict';
// SPDX-License-Identifier: MPL-2.0
// Execute the actual deployer against an in-memory filesystem. No live writes.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const validator = require('./validate-acdc-language-capabilities.cjs');
const source = fs.readFileSync(path.join(__dirname, 'deploy-monster-standalone-component.cjs'), 'utf8');
const web = '/var/www/html/monster-ui', stage = '/private/stage', backup = '/private/backup';
const artifact = web + '/apps/acdc/language-capabilities.json';
const valid = JSON.stringify({schema_version: 1, generated_at: new Date().toISOString(), languages:
    Object.fromEntries(validator.locales.map(locale => [locale, {
        ready: false, position: false, wait_time: false, callback: false, native_speaker_review: false
    }]))}, null, 2) + '\n';

function fixture(options = {}) {
    const nodes = new Map(), writes = [], logs = [];
    function mkdir(name) {
        if (nodes.has(name)) return;
        if (name !== '/') mkdir(path.dirname(name));
        nodes.set(name, {kind: 'directory', uid: 0, mode: 0o755});
    }
    function put(name, value, properties = {}) {
        mkdir(path.dirname(name));
        nodes.set(name, {kind: 'file', data: Buffer.from(value), uid: 0, mode: 0o644, ...properties});
    }
    const info = name => {
        const node = nodes.get(name); assert(node, 'Unexpected missing memory path: ' + name);
        return {uid: node.uid, mode: node.mode, size: node.data ? node.data.length : 0,
            isFile: () => node.kind === 'file', isDirectory: () => node.kind === 'directory', isSymbolicLink: () => node.kind === 'symlink'};
    };
    function copy(from, to) {
        const node = nodes.get(from); assert(node, 'Missing copy source');
        nodes.set(to, {...node, ...(node.data ? {data: Buffer.from(node.data)} : {})});
        for (const [name, value] of Array.from(nodes)) if (name.startsWith(from + '/')) {
            nodes.set(to + name.slice(from.length), {...value, ...(value.data ? {data: Buffer.from(value.data)} : {})});
        }
    }
    mkdir(backup); mkdir('/usr/local/share/kazoo5-installer');
    put(web + '/js/main.js', 'define("apps/other/app",[],function(){return "unchanged";});');
    put(web + '/build-config.json', JSON.stringify({preloadApps: ['other', 'callflows']}));
    put(web + '/apps/other/app.js', 'other application must remain unchanged');
    put(web + '/apps/acdc/app.js', 'define("apps/acdc/app",[],function(){return "old";});');
    put(stage + '/dist/apps/acdc/app.js', 'define("apps/acdc/app",[],function(){return "new";});');
    put(stage + '/dist/apps/acdc/app-build-config.json', '{}');
    if (options.artifact !== undefined) put(artifact, options.artifact, options.properties);
    if (options.buildArtifact) put(stage + '/dist/apps/acdc/language-capabilities.json', valid);
    let artifactReads = 0, artifactExists = 0;
    const memoryFs = {
        statSync: info, lstatSync: info,
        existsSync(name) {
            if (name === artifact && ++artifactExists === 2 && options.appearDuringStage) put(artifact, valid);
            return nodes.has(name);
        },
        readdirSync(name) {
            assert(info(name).isDirectory());
            return Array.from(nodes.keys()).filter(key => key !== name && path.dirname(key) === name).map(key => path.basename(key));
        },
        readFileSync(name, encoding) {
            if (name === artifact && ++artifactReads === 2 && options.changeDuringStage) put(artifact, valid + ' ');
            const data = Buffer.from(nodes.get(name).data);
            return encoding ? data.toString(encoding) : data;
        },
        copyFileSync(from, to) { writes.push(['copy', to]); copy(from, to); },
        cpSync(from, to) { writes.push(['copyTree', to]); copy(from, to); },
        mkdtempSync(prefix) { const name = prefix + 'memory'; mkdir(name); writes.push(['mkdir', name]); return name; },
        chmodSync(name, mode) { nodes.get(name).mode = mode; writes.push(['chmod', name]); },
        writeFileSync(name, value, options = {}) { put(name, value, {mode: options.mode || 0o644}); writes.push(['write', name]); },
        renameSync(from, to) {
            assert(nodes.has(from) && !nodes.has(to), 'Invalid memory rename');
            copy(from, to);
            for (const name of Array.from(nodes.keys())) if (name === from || name.startsWith(from + '/')) nodes.delete(name);
            writes.push(['rename', from, to]);
        }
    };
    function run() {
        vm.runInNewContext(source, {require(name) {
            if (name === 'node:fs') return memoryFs;
            if (name === './validate-acdc-language-capabilities.cjs') return validator;
            return require(name);
        }, process: {argv: ['node', 'deployer', 'acdc', stage, backup]}, console: {log: value => logs.push(value)}, Buffer, JSON, Object});
        return JSON.parse(logs[0]);
    }
    return {run, writes, nodes, read: name => nodes.get(name).data.toString()};
}

for (const text of [undefined, valid]) {
    const test = fixture({artifact: text});
    assert.equal(test.run().result, 'PASS');
    assert.equal(test.read(web + '/apps/other/app.js'), 'other application must remain unchanged');
    if (text !== undefined) {
        assert.equal(test.read(artifact), text, 'Runtime capability must be preserved byte-for-byte');
        assert.equal(test.read(backup + '/acdc-original/language-capabilities.json'), text);
        const manifest = JSON.parse(test.read('/usr/local/share/kazoo5-installer/monster-ui-acdc-component.json'));
        assert.equal(Object.keys(manifest.runtime_files_preserved).length, 1);
    }
}
for (const options of [{artifact: '{}'}, {artifact: valid, properties: {uid: 1000}},
    {artifact: valid, properties: {mode: 0o666}}, {buildArtifact: true}]) {
    const test = fixture(options);
    assert.throws(test.run);
    assert.equal(test.writes.length, 0, 'Invalid runtime/build claims must fail before filesystem mutations');
}
for (const options of [{artifact: valid, changeDuringStage: true}, {appearDuringStage: true}]) {
    const test = fixture(options);
    assert.throws(test.run);
    assert(!test.writes.some(write => write[0] === 'rename'), 'Concurrent publisher changes must abort before live replacement');
    assert.equal(test.read(web + '/apps/other/app.js'), 'other application must remain unchanged');
}
console.log('PASS 8 memory-only component preservation gates: absent/valid runtime, corrupt/unprotected/build claim rejection, concurrent publisher change/appearance');
