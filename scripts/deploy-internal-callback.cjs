#!/usr/bin/env node
'use strict';
// Focused development promotion; no account writes, synthesis or service restart.
// The production build manifest pins the existing live-disk baseline as well.
const fs = require('node:fs');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const ROOT = '/opt/kz5';
const DIRECTORY = ROOT + '/applications/acdc/ebin';
const MODULES = ['acdc_callback_internal', 'acdc_callback_policy', 'acdc_callback_store', 'acdc_callback_caller'];
const EXISTING = MODULES.slice(1);
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
function run(command, args, cwd = ROOT) {
    return cp.execFileSync(command, args, {cwd, encoding: 'utf8', timeout: 25000,
        maxBuffer: 2 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']}).trim();
}
const sup = (...args) => run('/usr/local/bin/sup', ['-n', 'kazoo_apps', '-t', '15', '-e', ...args]);
function bytes(file, limit = 4 * 1024 * 1024) {
    assert.equal(fs.realpathSync(file), file);
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
        const stat = fs.fstatSync(fd);
        assert(stat.isFile() && stat.uid === 0 && stat.nlink === 1 && !(stat.mode & 0o022)
            && stat.size > 0 && stat.size <= limit);
        return fs.readFileSync(fd);
    } finally { fs.closeSync(fd); }
}
function idle() {
    const value = JSON.parse(run('/usr/local/freeswitch/bin/fs_cli', ['-x', 'show channels as json']));
    assert(value.row_count === 0 && (!value.rows || value.rows.length === 0), 'Calls prevent promotion');
    run('/usr/bin/systemctl', ['is-active', '--quiet', 'kazoo-apps', 'kazoo-ecallmgr', 'kazoo-freeswitch']);
}
function diskDigest(file, module) {
    const expression = '{ok,{' + module + ',D}}=beam_lib:md5(' + JSON.stringify(file)
        + '),io:format("~w",[D]),halt().';
    return run('/usr/bin/erl', ['+S', '1:1', '+SDcpu', '1', '+SDio', '1', '+A', '1',
        '-no_dot_erlang', '-noshell', '-eval', expression]);
}
function replace(module, content) {
    const target = DIRECTORY + '/' + module + '.beam';
    const temporary = target + '.promotion-' + crypto.randomUUID();
    const fd = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL, 0o644);
    try { fs.writeFileSync(fd, content); fs.fchmodSync(fd, 0o644); fs.fsyncSync(fd); }
    finally { fs.closeSync(fd); }
    fs.renameSync(temporary, target);
    const directory = fs.openSync(DIRECTORY, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
    try { fs.fsyncSync(directory); } finally { fs.closeSync(directory); }
}
function atomic(modules, expected) {
    // code:get_object_code can retain an application directory listing that
    // predates a new module. Read exact protected files, verify their hashes in
    // the target VM, then use OTP's binary cohort API without refreshing paths.
    const files = modules.map(module => '{' + module + ',' + JSON.stringify(DIRECTORY + '/' + module + '.beam')
        + ',<<' + [...Buffer.from(expected[module].sha256, 'hex')].join(',') + '>>}').join(',');
    const expression = '(fun() -> Items=[begin {ok,B}=file:read_file(P),H=crypto:hash(sha256,B),{M,P,B} end || {M,P,H} <- ['
        + files + ']], code:atomic_load(Items) end)().';
    const ast = cp.execFileSync('/usr/bin/erl', ['+S','1:1','+SDcpu','1','+SDio','1','+A','1',
        '-no_dot_erlang','-noshell','-eval',
        '{ok,T,_}=erl_scan:string(os:getenv("KAZOO_PROMOTION_EXPRESSION")),{ok,E}=erl_parse:parse_exprs(T),io:format("~w",[E]),halt().'],
        {encoding:'utf8',env:{...process.env,KAZOO_PROMOTION_EXPRESSION:expression},timeout:15000,maxBuffer:1024*1024}).trim();
    const result = sup('erl_eval', 'exprs', ast, '[]').replace(/\s/g, '');
    if (/^[a-z_,{}\[\]\s]+$/.test(result)) receipt.atomic_result = result;
    assert.equal(result, '{value,ok,[]}');
}
const receipt = {modules: MODULES, deployed: false, service_restarts: 0, database_writes: 0,
    provider_requests: 0, before: {}, candidate: {}};
let phase = 'arguments', backup, changed = false, loaded = false;
const originals = {}, candidates = {};
try {
    const [mode, build] = process.argv.slice(2);
    assert(process.argv.length === 4 && ['--check', '--deploy'].includes(mode)
        && /^\/tmp\/kazoo-callback-media-build\.[A-Za-z0-9]+$/.test(build) && process.getuid() === 0);
    phase = 'candidate';
    const built = JSON.parse(bytes(build + '/receipt.json'));
    assert(built.exit_code === 0 && built.complete && built.inputs_stable
        && built.production_modules === 13 && built.tests === false && built.runtime_writes === false);
    bytes(build + '/inputs.sha256'); bytes(build + '/artifacts.sha256');
    run('/usr/bin/sha256sum', ['--status', '-c', build + '/inputs.sha256']);
    run('/usr/bin/sha256sum', ['--status', '-c', 'artifacts.sha256'], build);
    phase = 'runtime_preflight';
    idle();
    if (fs.existsSync(DIRECTORY + '/acdc_callback_internal.beam')) {
        assert.equal(sha(bytes(DIRECTORY + '/acdc_callback_internal.beam')),
            sha(bytes(build + '/ebin/acdc_callback_internal.beam')), 'Unrecognized existing new-module artifact');
    }
    assert.equal(sup('code', 'is_loaded', 'acdc_callback_internal'), 'false');
    for (const module of MODULES) {
        candidates[module] = bytes(build + '/ebin/' + module + '.beam');
        receipt.candidate[module] = {sha256: sha(candidates[module]), md5: diskDigest(build + '/ebin/' + module + '.beam', module)};
        if (!EXISTING.includes(module)) continue;
        const target = DIRECTORY + '/' + module + '.beam';
        originals[module] = bytes(target);
        const current = sup(module, 'module_info', 'md5');
        assert.equal(current.replace(/\s/g, ''), diskDigest(target, module).replace(/\s/g, ''));
        assert.equal(fs.realpathSync(JSON.parse(sup('code', 'which', module))), target);
        assert.equal(sup('erlang', 'check_old_code', module), 'false');
        receipt.before[module] = {sha256: sha(originals[module]), md5: current};
    }
    if (mode === '--deploy') {
        phase = 'backup';
        backup = fs.mkdtempSync('/var/lib/kazoo-internal-callback-deployment.');
        fs.chmodSync(backup, 0o700); receipt.backup = backup;
        for (const module of EXISTING) {
            const file = backup + '/' + module + '.beam';
            fs.writeFileSync(file, originals[module], {mode: 0o600, flag: 'wx'});
            const descriptor = fs.openSync(file, fs.constants.O_RDONLY);
            try { fs.fsyncSync(descriptor); } finally { fs.closeSync(descriptor); }
            assert.equal(sha(bytes(file)), receipt.before[module].sha256);
        }
        fs.writeFileSync(backup + '/before.json', JSON.stringify(receipt, null, 2), {mode: 0o600, flag: 'wx'});
        const backupDescriptor = fs.openSync(backup, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
        try { fs.fsyncSync(backupDescriptor); } finally { fs.closeSync(backupDescriptor); }
        phase = 'promote';
        idle(); run('/usr/bin/sha256sum', ['--status', '-c', build + '/inputs.sha256']);
        changed = true;
        for (const module of MODULES) replace(module, candidates[module]);
        // OTP loads the cohort together or returns an error; never force-purge.
        atomic(MODULES, receipt.candidate); loaded = true;
        phase = 'verify';
        for (const module of MODULES) {
            assert.equal(sup(module, 'module_info', 'md5').replace(/\s/g, ''), receipt.candidate[module].md5.replace(/\s/g, ''));
            assert.equal(sha(bytes(DIRECTORY + '/' + module + '.beam')), receipt.candidate[module].sha256);
            assert.equal(fs.realpathSync(JSON.parse(sup('code', 'which', module))), DIRECTORY + '/' + module + '.beam');
        }
        receipt.deployed = true;
    }
    receipt.result = 'PASS';
} catch (_) {
    receipt.result = 'FAIL'; receipt.phase = phase; process.exitCode = 1;
    if (changed) {
        try {
            // A SUP timeout can occur after atomic_load succeeded. Inspect the
            // actual code before choosing rollback; never trust the timeout.
            const current = EXISTING.map(module => sup(module, 'module_info', 'md5').replace(/\s/g, ''));
            const isBefore = current.every((digest, i) => digest === receipt.before[EXISTING[i]].md5.replace(/\s/g, ''));
            const isCandidate = current.every((digest, i) => digest === receipt.candidate[EXISTING[i]].md5.replace(/\s/g, ''));
            assert(isBefore || isCandidate, 'Unknown runtime cohort; preserve disk for operator recovery');
            loaded = isCandidate && !isBefore;
            if (loaded) for (const module of EXISTING) assert.equal(sup('code', 'soft_purge', module), 'true');
            for (const module of EXISTING) replace(module, originals[module]);
            if (loaded) atomic(EXISTING, receipt.before);
            for (const module of EXISTING) {
                assert.equal(sup(module, 'module_info', 'md5').replace(/\s/g, ''), receipt.before[module].md5.replace(/\s/g, ''));
                assert.equal(sha(bytes(DIRECTORY + '/' + module + '.beam')), receipt.before[module].sha256);
            }
            // Keep the unused new module for inspection; old callers cannot invoke it.
            receipt.rollback_verified = true;
        } catch (_) { receipt.rollback_verified = false; }
    }
}
if (backup) fs.writeFileSync(backup + '/receipt.json', JSON.stringify(receipt, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
console.log(JSON.stringify(receipt, null, 2));
