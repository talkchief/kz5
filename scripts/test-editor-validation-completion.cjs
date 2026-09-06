#!/usr/bin/env node
'use strict';
// Exercise the actual runner completion/EXIT/signal bookkeeping, not Erlang
// behavior. Only the source-pin checker is substituted; no build or live I/O.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const runners = [
    ['test-acdc-queue-editor.sh', 'editor'],
    ['test-acdc-queue-editor-real-auth.sh', 'auth_editor']
];
let cases = 0;
for (const [name, prefix] of runners) {
    const source = fs.readFileSync(path.join(__dirname, name), 'utf8');
    const finish = /^finish\(\) \{\n[\s\S]*?^\}/m.exec(source);
    assert(finish, name + ': missing real finish handler');
    const traps = /^trap finish EXIT\ntrap 'exit 130' INT\ntrap 'exit 143' TERM$/m.exec(source);
    assert(traps, name + ': missing real completion/signal traps');
    assert(source.includes(prefix + '_completed=0\n'), name + ': completion must start false');
    assert(source.trimEnd().endsWith(prefix + '_completed=1'), name + ': mark complete only after final test command');
    for (const test of [
        { name: 'completed', completed: 1, command: 'exit 0', expected: 0 },
        { name: 'incomplete zero exit', completed: 0, command: 'exit 0', expected: 99 },
        { name: 'test failure', completed: 0, command: 'exit 7', expected: 7 },
        { name: 'SIGTERM before completion', completed: 0, command: 'kill -TERM "$$"', expected: 143 },
        { name: 'SIGINT before completion', completed: 0, command: 'kill -INT "$$"', expected: 130 },
        { name: 'SIGTERM after completion', completed: 1, command: 'kill -TERM "$$"', expected: 143 },
        { name: 'changed pins after completion', completed: 1, pins: 1, command: 'exit 0', expected: 99 },
        { name: 'changed pins with test failure', completed: 0, pins: 1, command: 'exit 7', expected: 99 }
    ]) {
        const script = [
            'set -euo pipefail',
            prefix + '_output=/tmp/kazoo-editor-completion-no-files-created',
            prefix + '_completed=' + test.completed,
            'sha256sum() { return ' + (test.pins || 0) + '; }',
            finish[0], traps[0], test.command
        ].join('\n');
        const result = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', script], {
            encoding: 'utf8', timeout: 5000, maxBuffer: 65536,
            env: { PATH: '/usr/bin:/bin', LANG: 'C' }
        });
        assert(!result.error && !result.signal, name + ': unexpected fixture interruption');
        assert.equal(result.status, test.expected, name + ': ' + test.name);
        assert(result.stdout.includes('exit=' + test.expected + ';'), name + ': misleading cleanup status');
        ++cases;
    }
}
console.log('PASS ' + cases + ' actual editor runner completion/signal bookkeeping cases; no Erlang or live I/O');
