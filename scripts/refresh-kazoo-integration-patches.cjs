#!/usr/bin/env node
'use strict';
// The upstream component checkouts are intentionally ignored by the parent
// repository. These generated patches carry their source changes in a fresh
// clone; never confuse a dirty local component with a published deployment.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const components = ['acdc', 'crossbar', 'ecallmgr'];
const mode = process.argv[2];
assert(process.argv.length === 3 && ['--check', '--write'].includes(mode),
    'Usage: node scripts/refresh-kazoo-integration-patches.cjs --check|--write');
function git(cwd, args, diff = false) {
    const result = cp.spawnSync('git', args, {cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
    assert(!result.error && (result.status === 0 || (diff && result.status === 1)),
        `Git operation failed for ${path.basename(cwd)}: ${args[0]}`);
    return result.stdout;
}
for (const component of components) {
    const cwd = path.join(root, 'applications', component);
    assert.equal(fs.realpathSync(cwd), cwd, 'Refusing a symlinked component checkout');
    assert.equal(git(cwd, ['rev-parse', '--show-toplevel']).trim(), cwd,
        'Expected an independent upstream component checkout');
    const prefix = ['src', 'priv', 'test'];
    const tracked = git(cwd, ['diff', '--binary', 'HEAD', '--', ...prefix]);
    const untracked = git(cwd, ['ls-files', '--others', '--exclude-standard', '-z', '--', ...prefix])
        .split('\0').filter(Boolean).sort();
    let generated = tracked;
    for (const file of untracked) {
        assert(/^(?:src|priv|test)\/[A-Za-z0-9_./-]+\.(?:erl|hrl|json)$/.test(file) &&
            !file.split('/').includes('..'), `Unexpected untracked component artifact: ${file}`);
        assert(fs.lstatSync(path.join(cwd, file)).isFile(), 'Refusing a non-regular source file');
        generated += git(cwd, ['diff', '--no-index', '--binary', '--', '/dev/null', file], true);
    }
    assert(generated.startsWith('diff --git ') && generated.endsWith('\n'), 'Empty or malformed source patch');
    const output = path.join(__dirname, 'patches', `${component}-kazoo5-integration.patch`);
    if (fs.existsSync(output)) assert(fs.lstatSync(output).isFile(), 'Refusing a non-regular patch target');
    if (mode === '--write') {
        // A bulk mechanical source-diff artifact, not a source rewrite.
        const temporary = `${output}.${process.pid}.tmp`;
        fs.writeFileSync(temporary, generated, {encoding: 'utf8', mode: 0o644, flag: 'wx'});
        fs.renameSync(temporary, output);
    } else {
        assert.equal(fs.readFileSync(output, 'utf8'), generated,
            `Unpackaged ${component} source changes; regenerate the integration patch`);
    }
    git(cwd, ['apply', '--reverse', '--check', output]);
    console.log(`PASS ${component}: complete source patch, reverse-check, ${Buffer.byteLength(generated)} bytes`);
}
