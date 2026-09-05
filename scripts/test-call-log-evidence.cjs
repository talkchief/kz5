#!/usr/bin/env node
'use strict';
// Run the actual file-log counter against private fixtures; no live log edits.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'test-kazoo-calls.sh'), 'utf8');
const fn = source.match(/^new_error_log_matches\(\) \{[\s\S]*?^\}/m)?.[0];
assert(fn, 'Missing actual file-log counter');
const journalFn = source.match(/^count_journal_error_messages\(\) \{[\s\S]*?^\}/m)?.[0];
assert(journalFn, 'Missing actual journal counter');
assert(source.includes('count_journal_error_messages)'), 'Acceptance must use the journal counter');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-call-log-evidence.'));
const cases = [
    ['subscription_event_names', '[info] binding call: CHANNEL_EXECUTE_ERROR, CHANNEL_BRIDGE', 0],
    ['lowercase_event_name', '[debug] subscribe channel_execute_error', 0],
    ['erlang_error_level', '14:00:00 [error] queue worker failed', 1],
    ['native_error_level', '14:00:00 [ERR] media failure', 1],
    ['native_critical_level', '14:00:00 [CRIT] media unavailable', 1],
    ['kamailio_error', '1(123) ERROR: auth: consume_credentials(): No authorized credentials found', 1],
    ['plain_error', 'Error: connection refused', 1],
    ['error_inside_info', '[info] worker returned error: timeout', 1],
    ['fatal', '[critical] FATAL startup failure', 1],
    ['crash_report', '=CRASH REPORT====\nworker terminated', 1],
    ['segfault', 'kernel: beam.smp segfault at address', 1],
    ['core_dump', 'process exited (core dumped)', 1],
    ['event_and_real_error', '[error] cannot bind CHANNEL_EXECUTE_ERROR', 1],
    ['multiple_lines', '[info] CHANNEL_EXECUTE_ERROR\n[error] failed\nCRASH REPORT', 2]
];
try {
    for (const [name, contents, expected] of cases) {
        const log = path.join(scratch, name + '.log');
        fs.writeFileSync(log, '[error] old error before test baseline\n' + contents + '\n', {mode: 0o600});
        fs.writeFileSync(path.join(scratch, 'fixture-log-baseline.tsv'), log + '\t1\n', {mode: 0o600});
        const run = cp.spawnSync('bash', ['-c', 'set -Eeuo pipefail\n' + fn + '\nnew_error_log_matches fixture'], {
            encoding: 'utf8', timeout: 5000, env: {...process.env, RUN_DIR: scratch}
        });
        assert.ifError(run.error);
        assert.equal(run.status, 0, name + ': counter failed');
        assert.equal(Number(run.stdout.trim()), expected, name + ': incorrect new-error count');
        const journal = cp.spawnSync('bash', ['-c', 'set -Eeuo pipefail\n' + journalFn + '\ncount_journal_error_messages'], {
            encoding: 'utf8', timeout: 5000, input: contents + '\n'
        });
        assert.ifError(journal.error);
        assert.equal(journal.status, 0, name + ': journal counter failed');
        assert.equal(Number(journal.stdout.trim()), expected, name + ': incorrect journal-error count');
        console.log('PASS ' + name);
    }
    for (const message of ['badmatch', 'no AMQP connection available', 'timeout after 100ms receiving route response', 'no available handlers']) {
        const journal = cp.spawnSync('bash', ['-c', 'set -Eeuo pipefail\n' + journalFn + '\ncount_journal_error_messages'], {
            encoding: 'utf8', timeout: 5000, input: message + '\n'
        });
        assert.ifError(journal.error);
        assert.equal(journal.status, 0);
        assert.equal(Number(journal.stdout.trim()), 1, 'Lost existing journal routing/AMQP failure check');
    }
    console.log('PASS ' + cases.length + ' file/journal pairs plus 4 journal-routing cases; baseline excluded; no live changes');
} finally {
    assert(scratch.startsWith(path.join(os.tmpdir(), 'kazoo-call-log-evidence.')));
    fs.rmSync(scratch, {recursive: true});
}
