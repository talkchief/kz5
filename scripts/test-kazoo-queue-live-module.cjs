#!/usr/bin/env node
'use strict';
// Execute only the installer helpers with strict shell doubles. No installer
// environment sourcing, SUP, services, credentials, Erlang or network access.
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const installerPath = path.join(__dirname, 'install-kazoo5.sh');
const source = fs.readFileSync(installerPath, 'utf8');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function extract(name) {
    const start = source.indexOf(`\n${name}() {`);
    assert(start >= 0, name);
    const marker = name === 'kazoo_blackhole_module_output' ? '\nNODE\n}' : '\n}';
    const end = source.indexOf(marker, start);
    assert(end > start, name);
    return source.slice(start + 1, end + marker.length) + '\n';
}
const names = ['kazoo_queue_live_selected', 'kazoo_blackhole_module_output',
    'configure_kazoo_queue_live_module', 'verify_kazoo_queue_live_module'];
const helpers = names.map(extract).join('\n');
const proof = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-queue-live-module.'));
fs.chmodSync(proof, 0o700);
let groups = 0;
const cases = [];
const setup = `set -Eeuo pipefail
log() { printf 'LOG:%s\\n' "$*"; }
die() { printf 'FAIL:%s\\n' "$*" >&2; exit 77; }
monster_registration_available() { [[ $LOCAL_AUTHORITY == true ]]; }
verify_erlang_applications() {
    [[ $# == 2 && $1 == kazoo_apps && $2 == acdc,blackhole,crossbar ]] || exit 95
    printf 'apps\\n' >>"$TRACE"
    [[ $CASE != apps-failure ]]
}
timeout() {
    [[ $# -ge 4 && $1 == 30 && $2 == sup ]] || exit 95
    shift
    "$@"
}
sup() {
    printf '%s\\n' "$*" >>"$TRACE"
    case "$*" in
        'blackhole_config autoload_modules')
            [[ $CASE != pre-read-failure ]] || return 1
            if [[ -e $STATE ]]; then
                [[ $CASE != post-read-failure ]] || return 1
                printf '%s\\n' "$AFTER_AUTOLOAD"
            else printf '%s\\n' "$BEFORE_AUTOLOAD"; fi ;;
        'blackhole_bindings modules_loaded')
            if [[ -e $STATE ]]; then printf '%s\\n' "$AFTER_RUNNING"
            else printf '%s\\n' "$BEFORE_RUNNING"; fi
            [[ $CASE != running-exit-failure ]] || return 2 ;;
        'blackhole_maintenance running_modules')
            # Real SUP returns exit 2 for non-ok maintenance results even
            # though the delegate returns/prints a perfectly valid atom list.
            printf '%s\\n' "$BEFORE_RUNNING"
            return 2 ;;
        'blackhole_maintenance start_module bh_queue_live')
            [[ $CASE != start-exit-failure ]] || return 1
            : >"$STATE"
            printf '%s\\n' "$START_OUTPUT" ;;
        *) printf 'Forbidden SUP command\\n' >&2; exit 95 ;;
    esac
}
`;
const base = {
    KAZOO_APPS_LIST: 'acdc,blackhole,crossbar,callflow', DRY_RUN: 'false', LOCAL_AUTHORITY: 'true',
    BEFORE_AUTOLOAD: '[<<"bh_call">>, <<"bh_customer-custom">>]',
    BEFORE_RUNNING: "[bh_call,'bh_customer-custom']",
    AFTER_AUTOLOAD: '[<<"bh_queue_live">>,<<"bh_call">>,<<"bh_customer-custom">>]',
    AFTER_RUNNING: "[bh_call,'bh_customer-custom',bh_queue_live]",
    START_OUTPUT: 'starting bh_queue_live:\nnode kazoo_apps@fixture returned:\n  Started: true\n  Persisted: true\nok'
};
function run(name, overrides = {}, action = 'configure_kazoo_queue_live_module', want = 0, helperSource = helpers) {
    const dir = path.join(proof, name);
    fs.mkdirSync(dir, { mode: 0o700 });
    const trace = path.join(dir, 'trace');
    const result = cp.spawnSync('/bin/bash', ['--noprofile', '--norc', '-s'], {
        // Deliberately invoke in a conditional: helpers must not depend on
        // caller errexit to detect a failed prerequisite or readback.
        input: setup + helperSource + `\nif ${action}; then exit 0; else exit 78; fi\n`,
        env: { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', ...base, ...overrides,
            CASE: name, TRACE: trace, STATE: path.join(dir, 'started') },
        encoding: 'utf8', timeout: 5000, maxBuffer: 1024 * 1024
    });
    fs.writeFileSync(path.join(dir, 'stdout'), result.stdout || '');
    fs.writeFileSync(path.join(dir, 'stderr'), result.stderr || '');
    assert.ifError(result.error);
    assert.equal(result.status, want, `${name}: ${result.stderr}`);
    const calls = fs.existsSync(trace) ? fs.readFileSync(trace, 'utf8').trim().split('\n') : [];
    assert(!calls.some(call => /set_|stop_|flush|crossbar_maintenance/.test(call)), name);
    cases.push({ name, exit: result.status, calls });
    groups++;
    return calls;
}
let receipt = { passed: false, source_sha256: hash(source), proof };
try {
    const migrated = run('migration');
    assert.deepEqual(migrated, ['apps', 'blackhole_config autoload_modules',
        'blackhole_bindings modules_loaded', 'blackhole_maintenance start_module bh_queue_live',
        'blackhole_config autoload_modules', 'blackhole_bindings modules_loaded']);
    const repeated = run('idempotent', { BEFORE_AUTOLOAD: base.AFTER_AUTOLOAD, BEFORE_RUNNING: base.AFTER_RUNNING });
    assert.deepEqual(repeated, migrated.slice(0, 3));
    const maintenanceAlias = run('maintenance-exit-regression', {
        BEFORE_AUTOLOAD: base.AFTER_AUTOLOAD, BEFORE_RUNNING: base.AFTER_RUNNING
    }, undefined, 77, helpers.replaceAll('blackhole_bindings modules_loaded', 'blackhole_maintenance running_modules'));
    assert.deepEqual(maintenanceAlias, ['apps', 'blackhole_config autoload_modules', 'blackhole_maintenance running_modules']);
    run('running-exit-failure', {}, undefined, 77);
    run('already-effective-not-running', { BEFORE_AUTOLOAD: base.AFTER_AUTOLOAD });
    run('already-running-not-persisted', { BEFORE_RUNNING: base.AFTER_RUNNING });
    run('empty-old-list', { BEFORE_AUTOLOAD: '[]', BEFORE_RUNNING: '[]' });
    run('multiline-duplicates', { BEFORE_AUTOLOAD: '[<<"bh_call">>,\n <<"bh_call">>]',
        AFTER_AUTOLOAD: '[<<"bh_call">>,<<"bh_call">>,\n <<"bh_queue_live">>]' });
    for (const [name, apps] of [['no-acdc', 'blackhole,crossbar'], ['no-blackhole', 'acdc,crossbar'],
        ['no-crossbar', 'acdc,blackhole'], ['not-an-exact-app', 'acdc_other,blackhole,crossbar']]) {
        assert.deepEqual(run(name, { KAZOO_APPS_LIST: apps }), []);
    }
    assert.deepEqual(run('no-local-authority', { LOCAL_AUTHORITY: 'false' }), []);
    assert.deepEqual(run('dry-run', { DRY_RUN: 'true' }), []);
    for (const name of ['apps-failure', 'pre-read-failure', 'start-exit-failure', 'post-read-failure']) run(name, {}, undefined, 77);
    for (const [name, output] of [
        ['printed-error', 'failed to start module bh_queue_live: disconnected\nok'],
        ['printed-timeout', 'timed out waiting for responses\nok'],
        ['no-responses', 'starting bh_queue_live:\nok'],
        ['not-persisted', base.START_OUTPUT.replace('Persisted: true', 'Persisted: false')],
        ['not-started', base.START_OUTPUT.replace('Started: true', 'Started: false')],
        ['unexpected-response', base.START_OUTPUT.replace('\nok', '\n  Error: module unavailable\nok')],
        ['incomplete-second-node', base.START_OUTPUT.replace('\nok', '\nnode other@fixture returned:\n  Started: true\nok')]
    ]) run(name, { START_OUTPUT: output }, undefined, 77);
    run('two-successful-nodes', { START_OUTPUT: base.START_OUTPUT.replace('\nok',
        '\nnode other@fixture returned:\n  Persisted: true\n  Started: true\nok') });
    run('override-masks-default', { AFTER_AUTOLOAD: base.BEFORE_AUTOLOAD }, undefined, 77);
    run('running-missing-after-start', { AFTER_RUNNING: base.BEFORE_RUNNING }, undefined, 77);
    run('custom-autoload-lost', { AFTER_AUTOLOAD: '[<<"bh_queue_live">>,<<"bh_call">>]' }, undefined, 77);
    run('custom-running-lost', { AFTER_RUNNING: '[bh_queue_live,bh_call]' }, undefined, 77);
    for (const [name, output] of [['substring', '[<<"bh_queue_live_other">>]'],
        ['malformed', '[<<"bh_queue_live">>,]'], ['truncated', '[<<"bh_queue_live">>,...]'],
        ['error-term', '{error,unavailable}'], ['extra-output', '[<<"bh_queue_live">>]\nok']]) {
        run(`verify-${name}`, { BEFORE_AUTOLOAD: output }, 'verify_kazoo_queue_live_module', 77);
    }
    assert.deepEqual(run('verify-read-only', { BEFORE_AUTOLOAD: base.AFTER_AUTOLOAD, BEFORE_RUNNING: base.AFTER_RUNNING },
        'verify_kazoo_queue_live_module'), ['blackhole_config autoload_modules', 'blackhole_bindings modules_loaded']);
    run('verify-running-substring', { BEFORE_AUTOLOAD: base.AFTER_AUTOLOAD, BEFORE_RUNNING: '[bh_queue_live_other]' },
        'verify_kazoo_queue_live_module', 77);
    const config = extract('configure_kazoo_api_modules');
    assert(config.includes("log 'Registered and persisted ACDC and Monster UI Crossbar APIs'\n    configure_kazoo_queue_live_module"));
    assert(extract('verify_acdc_interfaces').includes('    verify_kazoo_queue_live_module\n'));
    assert(extract('install_kazoo_apps').includes('        configure_kazoo_api_modules\n'));
    assert(extract('register_monster_apps').includes('    configure_kazoo_api_modules\n'));
    // Pin the native migration semantics this installer relies upon. Changing
    // the native API requires explicit review, not a bulk config setter fallback.
    const nativeRoot = path.join(__dirname, '../applications/blackhole/src');
    const maintenance = fs.readFileSync(path.join(nativeRoot, 'blackhole_maintenance.erl'), 'utf8');
    const listener = fs.readFileSync(path.join(nativeRoot, 'blackhole_listener.erl'), 'utf8');
    const supSource = fs.readFileSync(path.join(__dirname, '../core/sup/src/sup.erl'), 'utf8');
    assert(maintenance.includes("start_module(Module) ->\n    start_module(Module, 'true')."));
    assert(maintenance.includes('running_modules() -> blackhole_bindings:modules_loaded().'));
    assert(supSource.includes('IsMaintenanceCommand = lists:suffix("_maintenance", props:get_value(\'module\', Options))'));
    assert(/Result when IsMaintenanceCommand ->\s+print_result\(Result, IsVerbose\),\s+Code = case 'ok' =:= Result of\s+'true' -> 0;\s+'false' -> 2\s+end,\s+halt\(Code\)/.test(supSource));
    assert(/Result ->\s+print_result\(Result, IsVerbose\),\s+halt\(0\)/.test(supSource));
    assert(!helpers.includes('blackhole_maintenance running_modules'));
    assert(listener.includes('Mods = blackhole_config:autoload_modules()'));
    assert(listener.includes("[kz_term:to_binary(Module)\n           | lists:delete(kz_term:to_binary(Module), Mods)"));
    assert.equal(fs.readFileSync(installerPath, 'utf8'), source);
    receipt = { ...receipt, passed: true, groups, cases, native_maintenance_sha256: hash(maintenance),
        native_listener_sha256: hash(listener), native_sup_sha256: hash(supSource),
        provider_calls: false, services: false, real_sup: false };
    console.log(`PASS ${groups} isolated queue-live installer cases; receipt ${path.join(proof, 'receipt.json')}`);
} finally {
    fs.writeFileSync(path.join(proof, 'receipt.json'), JSON.stringify({ ...receipt, groups, cases,
        source_stable: fs.readFileSync(installerPath, 'utf8') === source }, null, 2) + '\n');
}
