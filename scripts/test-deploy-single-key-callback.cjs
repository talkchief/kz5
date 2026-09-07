#!/usr/bin/env node
'use strict';
// Offline control-flow fixture for the actual deployment helper. All filesystem
// operations inside the VM, subprocesses, SUP calls and process state are doubles.
// This does not validate Erlang loading semantics or replace the live preflight.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');

const script = fs.readFileSync(path.join(__dirname, 'deploy-single-key-callback.cjs'), 'utf8');
const ROOT = '/opt/kz5';
const TARGET = ROOT + '/applications/acdc/ebin/acdc_callback_menu.beam';
const BUILD = '/tmp/kazoo-callback-media-build.Fixture123';
const CANDIDATE = BUILD + '/ebin/acdc_callback_menu.beam';
const BASELINE_MD5 = 'd0fd907a7bce337b184e78da75405510';
const CANDIDATE_MD5 = 'f2395173bdf3183659ac45fc0b7fa6c5';
const baselineBytes = Buffer.from('fixture-baseline-beam');
const candidateBytes = Buffer.from('fixture-candidate-beam');
const binaryDigest = hex => '<<' + [...Buffer.from(hex, 'hex')].join(',') + '>>';

function exercise(mode, faults = {}) {
    const nodes = new Map();
    const descriptors = new Map();
    const writes = [];
    const targetVersions = [];
    const commands = [];
    const output = [];
    const errors = [];
    let nextDescriptor = 10;
    let current = BASELINE_MD5;
    let loaded = 0;
    let verificationFailed = false;
    let purges = 0;

    function file(name, bytes, modeBits = 0o644) {
        nodes.set(name, {bytes: Buffer.from(bytes), mode: 0o100000 | modeBits,
            uid: 0, nlink: 1, directory: false});
    }
    function directory(name, modeBits = 0o755) {
        nodes.set(name, {mode: 0o040000 | modeBits, uid: 0, nlink: 1, directory: true});
    }
    function node(name) {
        assert(nodes.has(name), 'fixture path does not exist');
        return nodes.get(name);
    }
    function stat(value) {
        return {mode: value.mode, uid: value.uid, nlink: value.nlink,
            size: value.bytes ? value.bytes.length : 0,
            isFile: () => !value.directory, isDirectory: () => value.directory};
    }
    function knownDigest(bytes) {
        if (bytes.equals(baselineBytes)) return BASELINE_MD5;
        if (bytes.equals(candidateBytes)) return CANDIDATE_MD5;
        throw new Error('unknown fixture artifact');
    }
    directory(BUILD, 0o700);
    directory(BUILD + '/ebin');
    directory(path.dirname(TARGET));
    file(TARGET, baselineBytes);
    file(CANDIDATE, candidateBytes);
    file(BUILD + '/receipt.json', JSON.stringify({exit_code: 0, complete: true,
        inputs_stable: true, production_modules: 8, runtime_writes: false}), 0o600);
    file(BUILD + '/inputs.sha256', 'fixture input manifest', 0o600);
    file(BUILD + '/artifacts.sha256', 'fixture artifact manifest', 0o600);

    const fakeFs = {
        constants: fs.constants,
        realpathSync(name) {
            const canonical = path.resolve(name);
            node(canonical);
            return canonical;
        },
        statSync(name) { return stat(node(name)); },
        openSync(name, flags, modeBits) {
            if (name === CANDIDATE && faults.unreadableCandidate) throw new Error('fixture access denied');
            if (flags & fs.constants.O_CREAT) {
                assert(flags & fs.constants.O_EXCL, 'temporary writes must be exclusive');
                assert(!nodes.has(name), 'fixture exclusive create collision');
                file(name, Buffer.alloc(0), modeBits & ~0o077);
                writes.push({operation: 'create', path: name});
            }
            const value = node(name);
            if (flags & fs.constants.O_DIRECTORY) assert(value.directory);
            const fd = nextDescriptor++;
            descriptors.set(fd, {name, value, flags});
            return fd;
        },
        fstatSync(fd) { return stat(descriptors.get(fd).value); },
        readFileSync(fd) {
            assert.equal(typeof fd, 'number', 'helper reads must use guarded descriptors');
            return Buffer.from(descriptors.get(fd).value.bytes);
        },
        writeFileSync(target, bytes, options) {
            if (typeof target === 'number') {
                const descriptor = descriptors.get(target);
                assert(descriptor.flags & fs.constants.O_WRONLY);
                descriptor.value.bytes = Buffer.from(bytes);
                writes.push({operation: 'write', path: descriptor.name});
            } else {
                if (faults.failSuccessReceipt && target.endsWith('/receipt.json')) {
                    throw new Error('fixture receipt write failure');
                }
                assert.equal(options.flag, 'wx');
                assert(!nodes.has(target), 'backup or receipt must not overwrite');
                file(target, bytes, options.mode);
                writes.push({operation: 'write', path: target});
            }
        },
        fsyncSync(fd) { assert(descriptors.has(fd)); },
        fchmodSync(fd, modeBits) {
            const descriptor = descriptors.get(fd);
            assert(descriptor.name.startsWith(TARGET + '.promotion-'));
            assert.equal(modeBits, 0o644);
            descriptor.value.mode = (descriptor.value.mode & ~0o777) | modeBits;
        },
        closeSync(fd) { assert(descriptors.delete(fd)); },
        renameSync(from, to) {
            assert.equal(to, TARGET, 'only the named callback module may be replaced');
            assert(from.startsWith(TARGET + '.promotion-'));
            const value = node(from);
            targetVersions.push(knownDigest(value.bytes));
            nodes.set(to, value);
            nodes.delete(from);
            writes.push({operation: 'rename', path: to});
        },
        existsSync(name) { return nodes.has(name); },
        unlinkSync(name) {
            assert(name.startsWith(TARGET + '.promotion-'), 'no broad deletion');
            assert(nodes.delete(name));
            writes.push({operation: 'unlink', path: name});
        },
        mkdtempSync(prefix) {
            assert.equal(prefix, '/tmp/kazoo-single-key-deployment.');
            const name = prefix + 'FixtureBackup';
            assert(!nodes.has(name));
            directory(name, 0o700);
            writes.push({operation: 'mkdir', path: name});
            return name;
        },
        chmodSync(name, modeBits) {
            const value = node(name);
            value.mode = (value.mode & ~0o777) | modeBits;
            writes.push({operation: 'chmod', path: name});
        }
    };

    function execFileSync(command, args, options) {
        // Arguments originate in another VM realm; normalize before strict
        // comparisons so prototype identity cannot masquerade as a failure.
        args = Array.from(args);
        commands.push({command, args: [...args]});
        assert.equal(options.timeout, 20000);
        assert.equal(options.encoding, 'utf8');
        if (command === '/usr/bin/sha256sum') {
            assert.equal(args[0], '--status');
            assert.equal(args[1], '-c');
            assert(args[2] === BUILD + '/inputs.sha256' || args[2] === 'artifacts.sha256');
            return '';
        }
        if (command === '/usr/local/freeswitch/bin/fs_cli') {
            assert.deepEqual(args, ['-x', 'show channels as json']);
            return JSON.stringify({row_count: 0, rows: []});
        }
        if (command === '/usr/bin/systemctl') {
            assert.deepEqual(args, ['is-active', '--quiet', 'kazoo-apps', 'kazoo-ecallmgr', 'kazoo-freeswitch']);
            return '';
        }
        if (command === '/usr/bin/erl') {
            assert(args.includes('-no_dot_erlang') && args.includes('-noshell'));
            const expression = args[args.indexOf('-eval') + 1];
            const match = /beam_lib:md5\(("[^"]+")\)/.exec(expression);
            assert(match, 'only local metadata inspection is allowed');
            const filename = JSON.parse(match[1]);
            assert(filename === TARGET || filename === CANDIDATE);
            return '{ok,{acdc_callback_menu,' + binaryDigest(knownDigest(node(filename).bytes)) + '}}';
        }
        assert.equal(command, '/usr/local/bin/sup', 'unexpected subprocess');
        assert.deepEqual(args.slice(0, 5), ['-n', 'kazoo_apps', '-t', '10', '-e']);
        const call = args.slice(5).join(' ');
        switch (call) {
        case 'code which acdc_callback_menu':
            return JSON.stringify(ROOT + '/scripts/../applications/acdc/ebin/acdc_callback_menu.beam');
        case 'acdc_callback_menu module_info md5':
            if (faults.failLoadedVerification && loaded > 0 && !verificationFailed) {
                verificationFailed = true;
                return binaryDigest('00000000000000000000000000000000');
            }
            return binaryDigest(current);
        case 'erlang check_old_code acdc_callback_menu':
            return 'false';
        case 'code soft_purge acdc_callback_menu':
            purges++;
            return faults.blockRollback && verificationFailed ? 'false' : 'true';
        case 'code load_file acdc_callback_menu':
            loaded++;
            if (faults.failLoad) return '{error,badfile}';
            current = knownDigest(node(TARGET).bytes);
            return '{module,acdc_callback_menu}';
        default:
            throw new Error('unexpected SUP operation: fixture rejects scope expansion');
        }
    }

    const fakeProcess = {argv: ['/usr/bin/node', '/fixture/deploy-single-key-callback.cjs', mode, BUILD],
        getuid: () => 0, exitCode: undefined};
    const permitted = {'node:fs': fakeFs, 'node:child_process': {execFileSync},
        'node:path': path, 'node:crypto': crypto, 'node:assert/strict': assert};
    const context = vm.createContext({
        require(name) { assert(Object.hasOwn(permitted, name)); return permitted[name]; },
        process: fakeProcess, Buffer,
        console: {log(value) { output.push(value); }, error(value) { errors.push(value); }}
    });
    vm.runInContext(script, context, {filename: 'deploy-single-key-callback.cjs', timeout: 1000});
    assert.equal(descriptors.size, 0, 'all fixture file descriptors must close');
    assert.equal(output.length + errors.length, 1, 'one structured terminal receipt expected');
    return {receipt: JSON.parse((output.length ? output : errors)[0]), nodes, writes,
        targetVersions, commands, current, loaded, purges, exitCode: fakeProcess.exitCode};
}

const tests = [
    ['check performs no writes or code loads', () => {
        const result = exercise('--check');
        assert.equal(result.receipt.result, 'PASS');
        assert.equal(result.receipt.deployed, false);
        assert.equal(result.writes.length, 0);
        assert.equal(result.loaded, 0);
        assert.equal(result.purges, 0);
        assert.equal(result.current, BASELINE_MD5);
    }],
    ['successful promotion stays within the single module and preserves backup', () => {
        const result = exercise('--deploy');
        assert.equal(result.receipt.result, 'PASS');
        assert.equal(result.receipt.deployed, true);
        assert.equal(result.receipt.old_code_released, true);
        assert.equal(result.current, CANDIDATE_MD5);
        assert.equal(result.nodes.get(TARGET).mode & 0o777, 0o644);
        assert.deepEqual(result.targetVersions, [CANDIDATE_MD5]);
        const backup = result.nodes.get(result.receipt.backup + '/acdc_callback_menu.beam');
        assert(backup.bytes.equals(baselineBytes));
        assert.equal(backup.mode & 0o777, 0o600);
        assert.equal(result.nodes.get(result.receipt.backup).mode & 0o777, 0o700);
        assert.equal(result.receipt.service_restarts, 0);
    }],
    ['unreadable candidate fails before writes or service inspection', () => {
        const result = exercise('--deploy', {unreadableCandidate: true});
        assert.equal(result.receipt.result, 'FAIL');
        assert.equal(result.receipt.failed_phase, 'candidate');
        assert.equal(result.exitCode, 1);
        assert.equal(result.writes.length, 0);
        assert.equal(result.loaded, 0);
        assert(result.commands.every(call => call.command === '/usr/bin/sha256sum'));
    }],
    ['load failure restores baseline without loading another version', () => {
        const result = exercise('--deploy', {failLoad: true});
        assert.equal(result.receipt.result, 'FAIL');
        assert.equal(result.receipt.rollback_verified, true);
        assert.equal(result.current, BASELINE_MD5);
        assert(result.nodes.get(TARGET).bytes.equals(baselineBytes));
        assert.deepEqual(result.targetVersions, [CANDIDATE_MD5, BASELINE_MD5]);
        assert.equal(result.loaded, 1);
        assert.equal(result.exitCode, 1);
    }],
    ['blocked rollback leaves candidate matching current code without force purge', () => {
        const result = exercise('--deploy', {failLoadedVerification: true, blockRollback: true});
        assert.equal(result.receipt.result, 'FAIL');
        assert.equal(result.receipt.rollback_verified, false);
        assert.equal(result.receipt.disk_runtime_reconciled, true);
        assert.equal(result.current, CANDIDATE_MD5);
        assert(result.nodes.get(TARGET).bytes.equals(candidateBytes));
        assert.deepEqual(result.targetVersions, [CANDIDATE_MD5, CANDIDATE_MD5]);
        assert.equal(result.loaded, 1);
        assert.equal(result.exitCode, 1);
    }],
    ['failure identifies protected backup and writes matching failure receipt', () => {
        const result = exercise('--deploy', {failLoadedVerification: true, blockRollback: true});
        assert.match(result.receipt.backup, /^\/tmp\/kazoo-single-key-deployment\./);
        const failure = result.nodes.get(result.receipt.backup + '/failure.json');
        assert.equal(failure.mode & 0o777, 0o600);
        assert.deepEqual(JSON.parse(failure.bytes.toString()), result.receipt);
        assert(result.nodes.get(result.receipt.backup + '/acdc_callback_menu.beam').bytes.equals(baselineBytes));
    }],
    ['late receipt failure reports verified rollback as not deployed', () => {
        const result = exercise('--deploy', {failSuccessReceipt: true});
        assert.equal(result.receipt.result, 'FAIL');
        assert.equal(result.receipt.rollback_verified, true);
        assert.equal(result.receipt.deployed, false);
        assert.equal(result.current, BASELINE_MD5);
        assert(result.nodes.get(TARGET).bytes.equals(baselineBytes));
        assert.equal(result.loaded, 2);
    }]
];

for (const [name, check] of tests) {
    check();
    console.log('PASS ' + name);
}
console.log('PASS 7 offline single-key deployment control-flow cases; no real writes, subprocesses or services.');
