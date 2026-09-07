#!/usr/bin/env node
'use strict';
// Development-only, one-module promotion. Run inside run-kazoo-validation.sh.
// No build, provider, database, roster or installer-wide service mutation.
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const ROOT = '/opt/kz5';
const MODULE = 'acdc_callback_menu';
const TARGET = ROOT + '/applications/acdc/ebin/' + MODULE + '.beam';
const BASELINE = 'd0fd907a7bce337b184e78da75405510';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const digest = text => {
    const match = /^<<([0-9,\s]+)>>$/.exec(text);
    assert(match, 'Invalid module digest response');
    const bytes = match[1].split(',').map(s => Number(s.trim()));
    assert(bytes.length === 16 && bytes.every(n => Number.isInteger(n) && n >= 0 && n <= 255));
    return Buffer.from(bytes).toString('hex');
};
function run(command, args, cwd = ROOT) {
    return cp.execFileSync(command, args, {cwd, encoding: 'utf8', timeout: 20000,
        maxBuffer: 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']}).trim();
}
function sup(...args) {
    return run('/usr/local/bin/sup', ['-n', 'kazoo_apps', '-t', '10', '-e', ...args]);
}
function safeBytes(file, maximum = 1024 * 1024) {
    assert.equal(fs.realpathSync(file), file);
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
        const stat = fs.fstatSync(fd);
        assert(stat.isFile() && stat.uid === 0 && stat.nlink === 1 && !(stat.mode & 0o022)
            && stat.size > 0 && stat.size <= maximum, 'Unprotected artifact');
        return fs.readFileSync(fd);
    } finally { fs.closeSync(fd); }
}
function fileDigest(file) {
    // The service user must not traverse the private root-owned build directory.
    // Inspect metadata locally without loading candidate code into the service.
    assert(file === TARGET || /^\/tmp\/kazoo-callback-media-build\.[A-Za-z0-9]+\/ebin\/acdc_callback_menu\.beam$/.test(file));
    const result = run('/usr/bin/erl', ['+S', '1:1', '+SDcpu', '1', '+SDio', '1', '+A', '1',
        '-no_dot_erlang', '-noshell', '-eval',
        'io:format("~w",[beam_lib:md5(' + JSON.stringify(file) + ')]),halt().']);
    const match = /^\{ok,\{acdc_callback_menu,(<<[0-9,\s]+>>)\}\}$/.exec(result);
    assert(match, 'Unexpected candidate module');
    return digest(match[1]);
}
function idle() {
    const channels = JSON.parse(run('/usr/local/freeswitch/bin/fs_cli', ['-x', 'show channels as json']));
    assert.equal(channels.row_count, 0, 'Live channels prevent this deployment');
    assert(!channels.rows || Array.isArray(channels.rows) && channels.rows.length === 0);
    run('/usr/bin/systemctl', ['is-active', '--quiet', 'kazoo-apps', 'kazoo-ecallmgr', 'kazoo-freeswitch']);
}
function replace(bytes) {
    const temporary = TARGET + '.promotion-' + crypto.randomUUID();
    let renamed = false;
    try {
        const fd = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL, 0o644);
        try {
            fs.writeFileSync(fd, bytes);
            // The validation unit uses umask077; runtime BEAMs must remain
            // readable by the unprivileged kazoo service after atomic rename.
            fs.fchmodSync(fd, 0o644);
            fs.fsyncSync(fd);
        } finally { fs.closeSync(fd); }
        fs.renameSync(temporary, TARGET); renamed = true;
        const dir = fs.openSync(path.dirname(TARGET), fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
        try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); }
    } finally { if (!renamed && fs.existsSync(temporary)) fs.unlinkSync(temporary); }
}
function load() {
    // Never force-purge or kill a process referencing old code.
    assert.equal(sup('code', 'soft_purge', MODULE), 'true', 'Old code still in use');
    assert.equal(sup('code', 'load_file', MODULE), '{module,acdc_callback_menu}');
}
let phase = 'arguments', backup, changed = false, original, candidate;
const receipt = {schema_version: 1, module: MODULE, node: 'kazoo_apps', target: TARGET,
    database_writes: 0, provider_requests: 0, service_restarts: 0, deployed: false};
try {
    const [mode, build] = process.argv.slice(2);
    assert(process.argv.length === 4 && ['--check', '--deploy'].includes(mode)
        && /^\/tmp\/kazoo-callback-media-build\.[A-Za-z0-9]+$/.test(build)
        && process.getuid() === 0, 'Use --check|--deploy reviewed-build');
    phase = 'candidate';
    assert.equal(fs.realpathSync(build), build);
    const stat = fs.statSync(build);
    assert(stat.isDirectory() && stat.uid === 0 && (stat.mode & 0o777) === 0o700);
    const built = JSON.parse(safeBytes(build + '/receipt.json'));
    assert(built.exit_code === 0 && built.complete === true && built.inputs_stable === true
        && built.production_modules === 8 && built.runtime_writes === false);
    safeBytes(build + '/inputs.sha256', 4 * 1024 * 1024);
    safeBytes(build + '/artifacts.sha256');
    run('/usr/bin/sha256sum', ['--status', '-c', build + '/inputs.sha256']);
    run('/usr/bin/sha256sum', ['--status', '-c', 'artifacts.sha256'], build);
    candidate = safeBytes(build + '/ebin/' + MODULE + '.beam');
    original = safeBytes(TARGET);
    phase = 'runtime_preflight';
    idle();
    phase = 'runtime_path';
    assert.equal(fs.realpathSync(JSON.parse(sup('code', 'which', MODULE))), TARGET);
    phase = 'runtime_md5';
    receipt.before_md5 = digest(sup(MODULE, 'module_info', 'md5'));
    phase = 'baseline_disk_md5';
    assert.equal(fileDigest(TARGET), receipt.before_md5, 'Disk/runtime mismatch');
    phase = 'baseline_identity';
    assert.equal(receipt.before_md5, BASELINE, 'Not the reviewed pre-single-key baseline');
    phase = 'old_code_slot';
    assert.equal(sup('erlang', 'check_old_code', MODULE), 'false', 'Unexpected old code slot');
    phase = 'candidate_md5';
    receipt.candidate_md5 = fileDigest(build + '/ebin/' + MODULE + '.beam');
    assert.notEqual(receipt.candidate_md5, BASELINE);
    receipt.before_sha256 = sha(original);
    receipt.candidate_sha256 = sha(candidate);
    receipt.build = build;
    if (mode === '--deploy') {
        phase = 'backup';
        backup = fs.mkdtempSync('/tmp/kazoo-single-key-deployment.');
        fs.chmodSync(backup, 0o700);
        receipt.backup = backup;
        fs.writeFileSync(backup + '/acdc_callback_menu.beam', original, {mode: 0o600, flag: 'wx'});
        const backupFile = fs.openSync(backup + '/acdc_callback_menu.beam', fs.constants.O_RDONLY);
        try { fs.fsyncSync(backupFile); } finally { fs.closeSync(backupFile); }
        const backupDir = fs.openSync(backup, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
        try { fs.fsyncSync(backupDir); } finally { fs.closeSync(backupDir); }
        assert.equal(sha(safeBytes(backup + '/acdc_callback_menu.beam')), receipt.before_sha256);
        phase = 'promote';
        idle();
        run('/usr/bin/sha256sum', ['--status', '-c', build + '/inputs.sha256']);
        assert.equal(sha(safeBytes(TARGET)), receipt.before_sha256);
        changed = true;
        replace(candidate);
        load();
        phase = 'loaded_verification';
        assert.equal(sha(safeBytes(TARGET)), receipt.candidate_sha256);
        assert.equal(digest(sup(MODULE, 'module_info', 'md5')), receipt.candidate_md5);
        assert.equal(fs.realpathSync(JSON.parse(sup('code', 'which', MODULE))), TARGET);
        receipt.old_code_released = sup('code', 'soft_purge', MODULE) === 'true';
        receipt.deployed = true;
    }
    receipt.result = 'PASS';
    if (backup) fs.writeFileSync(backup + '/receipt.json', JSON.stringify(receipt, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
    console.log(JSON.stringify(receipt));
} catch (_) {
    receipt.result = 'FAIL'; receipt.failed_phase = phase;
    if (changed) {
        try {
            const current = digest(sup(MODULE, 'module_info', 'md5'));
            if (current === BASELINE) {
                // Promotion did not load: restoring the file needs no code load.
                replace(original);
            } else {
                assert.equal(current, receipt.candidate_md5, 'Unexpected current code');
                // Do not put baseline on disk while a blocked rollback leaves the
                // candidate running. Never force-purge a live old-code frame.
                assert.equal(sup('code', 'soft_purge', MODULE), 'true', 'Rollback old code still in use');
                replace(original); load();
            }
            assert.equal(digest(sup(MODULE, 'module_info', 'md5')), BASELINE);
            assert.equal(sha(safeBytes(TARGET)), receipt.before_sha256);
            receipt.rollback_verified = true;
            receipt.deployed = false;
        } catch (_) {
            receipt.rollback_verified = false;
            try {
                const current = digest(sup(MODULE, 'module_info', 'md5'));
                const matching = current === BASELINE ? original :
                    current === receipt.candidate_md5 ? candidate : undefined;
                assert(matching, 'Unknown current code; manual recovery required');
                replace(matching);
                receipt.disk_runtime_reconciled = sha(safeBytes(TARGET)) === sha(matching);
                receipt.deployed = current === receipt.candidate_md5;
            } catch (_) { receipt.disk_runtime_reconciled = false; }
        }
    }
    if (backup) {
        try { fs.writeFileSync(backup + '/failure.json', JSON.stringify(receipt, null, 2) + '\n', {mode: 0o600, flag: 'wx'}); }
        catch (_) { /* Preserve original failure and backup; never emit raw exceptions. */ }
    }
    console.error(JSON.stringify(receipt)); process.exitCode = 1;
}
