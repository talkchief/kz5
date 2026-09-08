'use strict';
// Execute the real legacy release wrapper with a synthetic local executable.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-wrapper-cookie.'));
const cookie = 'FIXTURE_ONLY_ERLANG_COOKIE_NOT_A_REAL_SECRET';
try {
    fs.mkdirSync(path.join(dir, 'bin'));
    fs.writeFileSync(path.join(dir, 'config.ini'), '; fixture only\n');
    fs.writeFileSync(path.join(dir, 'bin/kazoo'), '#!/bin/sh\n[ "$KAZOO_COOKIE" = "$EXPECTED_COOKIE" ] || exit 73\n[ "$KAZOO_NODE" = fixture_node ] || exit 74\n[ "$1" = foreground ] || exit 75\nprintf "fixture-release-started\\n"\n', {mode: 0o700});
    const result = cp.spawnSync('/usr/bin/bash', [path.join(root, 'scripts/dev/kazoo.sh'), 'foreground'], {
        encoding: 'utf8', timeout: 5000,
        env: {PATH: '/usr/bin:/bin', KAZOO_ROOT: dir, KAZOO_CONFIG: path.join(dir, 'config.ini'),
            KAZOO_NODE: 'fixture_node', COOKIE: cookie, EXPECTED_COOKIE: cookie}
    });
    assert.equal(result.status, 0, 'fixture release launch failed');
    assert(result.stdout.includes('fixture-release-started'), 'wrapper did not reach release executable');
    assert(!(result.stdout + result.stderr).includes(cookie), 'wrapper prints its Erlang cookie');
    console.log('PASS actual development release wrapper keeps cookie out of output and preserves child configuration');
} finally {fs.rmSync(dir, {recursive: true, force: true});}
