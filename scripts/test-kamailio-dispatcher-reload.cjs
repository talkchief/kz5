#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Private source replay, real SQLite statements, extracted route control flow,
// and Kamailio -c parsing only. No SIP, API, live DB/config changes or reload.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const {spawnSync, execFileSync} = require('node:child_process');
const assert = require('node:assert/strict');
const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const patch = path.join(__dirname, 'patches/kamailio-dispatcher-reload-bookkeeping.patch');
const checkout = process.env.KAZOO_KAMAILIO_CONFIG_SOURCE
    || '/usr/local/src/kazoo5-installer/kazoo-configs-kamailio';
const revision = installer.match(/^KAMAILIO_CONFIG_REF=\$\{KAMAILIO_CONFIG_REF:-([a-f0-9]{40})\}$/m)?.[1];
assert(revision);
const original = file => execFileSync('git', ['-C', checkout, 'show', revision + ':kamailio/' + file], {encoding: 'utf8'});
const source = original('dispatcher-role-5.7.cfg');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-dispatcher-reload-test.'));
fs.chmodSync(scratch, 0o700);
let groups = 0;
const route = (text, name) => {
    const start = text.indexOf('route[' + name + ']');
    assert(start >= 0, 'Missing route ' + name);
    const next = text.indexOf('\n}\n', start);
    assert(next > start);
    return text.slice(start, next + 3);
};
const privateWrite = (file, content) => fs.writeFileSync(path.join(scratch, file), content, {mode: 0o600});
const bash = (script, ...args) => spawnSync('bash', ['-c', 'set -Eeuo pipefail\n' + script, 'test', ...args],
    {encoding: 'utf8', timeout: 10000});
try {
    fs.mkdirSync(path.join(scratch, 'kamailio'), {mode: 0o700});
    privateWrite('kamailio/dispatcher-role-5.7.cfg', source);
    const git = (...args) => spawnSync('git', ['-C', scratch, 'apply', ...args, patch], {encoding: 'utf8'});
    assert.equal(git('--check').status, 0, 'Pinned source forward check');
    assert.equal(git().status, 0, 'Pinned source forward replay');
    const fixed = fs.readFileSync(path.join(scratch, 'kamailio/dispatcher-role-5.7.cfg'), 'utf8');
    assert.notEqual(git('--check').status, 0, 'Repeated direct apply rejected');
    assert.equal(git('--reverse', '--check').status, 0);
    assert.equal(git('--reverse').status, 0);
    assert.equal(fs.readFileSync(path.join(scratch, 'kamailio/dispatcher-role-5.7.cfg'), 'utf8'), source);
    groups++;

    const patchHelper = installer.match(/^apply_required_source_patch\(\) \{[\s\S]*?^\}/m)?.[0];
    assert(patchHelper);
    const apply = dry => bash(patchHelper + '\nlog() { :; }\ndie() { exit 1; }\nDRY_RUN="$3"\n'
        + 'apply_required_source_patch "$1" "$2"\n', scratch, patch, String(dry));
    assert.equal(apply(true).status, 0);
    assert.equal(fs.readFileSync(path.join(scratch, 'kamailio/dispatcher-role-5.7.cfg'), 'utf8'), source);
    assert.equal(apply(false).status, 0); assert.equal(apply(false).status, 0);
    assert.equal(fs.readFileSync(path.join(scratch, 'kamailio/dispatcher-role-5.7.cfg'), 'utf8'), fixed);
    privateWrite('kamailio/dispatcher-role-5.7.cfg', fixed.replace('select changes()', 'select OPERATOR_QUERY()'));
    assert.notEqual(apply(false).status, 0, 'Operator edits fail closed');
    privateWrite('kamailio/dispatcher-role-5.7.cfg', fixed); groups++;

    // The only source changes are the count reader and its two call sites,
    // plus reload bookkeeping. Probing, routing, SQL and error gates stay intact.
    assert(fixed.includes('modparam("dispatcher", "ds_probing_mode", KZ_DISPATCHER_PROBE_MODE)'));
    assert.equal(fixed.slice(0, fixed.indexOf('# Read immediately after successful DML')),
        source.slice(0, source.indexOf('route[DISPATCHER_INSERT_DB]')));
    assert.equal(fixed.slice(fixed.indexOf('event_route[dispatcher:reloaded]')),
        source.slice(source.indexOf('event_route[dispatcher:reloaded]')));
    for (const name of ['DISPATCHER_INSERT_DB', 'MEDIA_SERVER_DOWN_DISPATCHER']) {
        const oldRoute = route(source, name), changed = route(fixed, name);
        const restored = changed.replace('        if (!route(DISPATCHER_READ_CHANGED_ROWS)) return;\n', '')
            .replaceAll('$var(dispatcher_changed_rows)', '$sqlrows(exec)');
        assert.equal(restored, oldRoute, 'Only immediate count read/check changes ' + name);
        assert.match(changed, /if \(sql_query\("exec", [^\n]+\) > 0\) \{\n        if \(!route\(DISPATCHER_READ_CHANGED_ROWS\)\) return;/);
    }
    groups++;

    // Run the actual compatibility transform on private pinned files only.
    for (const file of ['nodes-role.cfg', 'default.cfg', 'presence-reset.cfg']) privateWrite('kamailio/' + file, original(file));
    const compat = installer.match(/^rewrite_kamailio_61_compatibility\(\) \{[\s\S]*?^\}/m)?.[0];
    assert(compat);
    const runCompat = () => bash(compat + '\nDRY_RUN=false\ndie() { exit 1; }\nrewrite_kamailio_61_compatibility "$1"\n',
        path.join(scratch, 'kamailio'));
    assert.equal(runCompat().status, 0);
    const runtime = fs.readFileSync(path.join(scratch, 'kamailio/dispatcher-role-5.7.cfg'), 'utf8');
    assert(runtime.includes('$var(dispatcher_changed_rows) = $sqlrows(exec);'), 'Native DB fallback must not become1');
    assert(runtime.includes('sql_pvquery("exec", "select changes()", "$var(dispatcher_changed_rows)")'));
    assert(!runtime.includes('if(1 > 0)'), 'No forced positive dispatcher mutation');
    assert(!fs.readFileSync(path.join(scratch, 'kamailio/presence-reset.cfg'), 'utf8').includes('$sqlrows('),
        'Unrelated existing compatibility fallback stays unchanged');
    assert.equal(runCompat().status, 0);
    assert.equal(fs.readFileSync(path.join(scratch, 'kamailio/dispatcher-role-5.7.cfg'), 'utf8'), runtime); groups++;

    // Execute the actual fixed count reader body with bounded mock API results.
    // These are control-flow tests, NOT claims of a running Kamailio instance.
    const reader = route(runtime, 'DISPATCHER_READ_CHANGED_ROWS');
    const sqliteReader = reader.replace(/    #!ifdef KZ_DISPATCHER_SQLITE_AFFECTED_ROWS\n/, '')
        .replace(/    #!else\n[\s\S]*?    #!endif\n/, '');
    const nativeReader = reader.replace(/    #!ifdef KZ_DISPATCHER_SQLITE_AFFECTED_ROWS\n[\s\S]*?    #!else\n/, '')
        .replace(/    #!endif\n/, '');
    function compileReader(text) {
        const body = text.slice(text.indexOf('{') + 1, text.lastIndexOf('}')).replace(/^\s*#.*$/gm, '')
            .replaceAll('$var(dispatcher_changed_rows)', 'state.rows')
            .replaceAll('$shv(dispatcher_reload)', 'state.dirty')
            .replace('$sqlrows(exec)', 'state.nativeRows');
        return new Function('state', 'sql_pvquery', 'xlog', body);
    }
    const readSqlite = compileReader(sqliteReader), readNative = compileReader(nativeReader);
    for (const [rc, rows, expectedRc, expectedDirty] of [[1,0,1,0],[1,1,1,0],[1,2,1,0],[-1,undefined,-1,1],
        [0,undefined,-1,1],[2,undefined,-1,1],[1,-1,-1,1],[1,undefined,-1,1]]) {
        const state = {rows:999, dirty:0}, logs = [];
        const result = readSqlite(state, (connection, query, target) => {
            assert.equal(connection, 'exec'); assert.equal(query, 'select changes()');
            assert.equal(target, 'state.rows');
            if (rows !== undefined) state.rows = rows;
            return rc;
        }, (...args) => logs.push(args));
        assert.equal(result, expectedRc); assert.equal(state.dirty, expectedDirty);
        assert.equal(logs.length, expectedRc < 0 ? 1 : 0);
    }
    assert.equal(readNative({nativeRows:0, dirty:0}, () => assert.fail('Native driver must not execute SQLite SQL'), () => {}), 1);
    groups++;

    // Real SQLite demonstrates the exact INSERT macro can succeed with0changes,
    // and checks positive/zero DELETEs plus existing destination attributes.
    const macro = original('db_queries_kazoo.cfg').split('\n').find(line => line.includes('!KZQ_CHECK_MEDIA_SERVER_INSERT!'));
    assert(macro);
    const insert = macro.split('!')[3].replaceAll('$$var(SetId)', '1').replaceAll('$$var(MediaUrl)', 'sip:127.0.0.1:51100')
        .replaceAll('$$var(flags)', '9').replaceAll('$$var(attrs)', 'zone=local;profile=default;node=fixture');
    assert(!insert.includes('$$var'));
    const countQuery = /sql_pvquery\("exec", "([^"]+)",/.exec(reader)[1];
    const sql = 'CREATE TABLE dispatcher(setid INTEGER,destination TEXT,flags INTEGER,attrs TEXT,description TEXT);\n'
        + insert + ';\n' + countQuery + ';\n' + insert + ';\n' + countQuery + ';\n'
        + 'SELECT count(*) FROM dispatcher;\n'
        + "DELETE FROM dispatcher WHERE destination LIKE 'sip:127.0.0.1:51100%';\n" + countQuery + ';\n'
        + "DELETE FROM dispatcher WHERE destination LIKE 'sip:127.0.0.1:51100%';\n" + countQuery + ';\n';
    const sqlite = spawnSync('sqlite3', ['-batch', ':memory:'], {input:sql, encoding:'utf8', timeout:5000});
    assert.equal(sqlite.status, 0, sqlite.stderr); assert.equal(sqlite.stdout.trim(), '1\n0\n1\n1\n0'); groups++;

    // Execute the actual reload branch as JS after only translating Kamailio
    // PVs/comments. Inject a writer exactly DURING ds_reload to reproduce the
    // previous lost-dirty bug; no model-specific replacement of the branch.
    function compileReload(text) {
        const selected = route(text, 'DISPATCHER_RELOAD');
        const body = selected.slice(selected.indexOf('{') + 1, selected.lastIndexOf('}'))
            .replace(/^\s*#.*$/gm, '').replaceAll('$shv(dispatcher_reload)', 'state.dirty')
            .replace(/\$(?:var\(kz_log_id\)|ki) = \$uuid\(g\);/, '');
        return new Function('state', 'ds_reload', 'xlog', body);
    }
    const oldReload = compileReload(source), reload = compileReload(runtime);
    for (const during of [false,true]) for (const result of [-1,1]) for (const initial of [0,1]) {
        const state={dirty:initial}; let calls=0;
        reload(state, () => { calls++; if(during) state.dirty=1; return result; }, () => {});
        assert.equal(calls, initial);
        assert.equal(state.dirty, initial && (during || result < 0) ? 1 : 0);
    }
    const oldRace={dirty:1}; oldReload(oldRace, () => { oldRace.dirty=1; return 1; }, () => {});
    assert.equal(oldRace.dirty, 0, 'Reproduce old lost concurrent writer');
    const oldFailure={dirty:1}; oldReload(oldFailure, () => -1, () => {});
    assert.equal(oldFailure.dirty, 0, 'Reproduce old lost failed reload');
    const retry={dirty:1}; reload(retry, () => -1, () => {}); assert.equal(retry.dirty, 1);
    reload(retry, () => 1, () => {}); assert.equal(retry.dirty, 0); groups++;

    // Parse both real preprocessor branches with the installed stock binary.
    // -c exits after config validation: it does not start listeners or timers.
    const routes = ['DISPATCHER_READ_CHANGED_ROWS','DISPATCHER_INSERT_DB','MEDIA_SERVER_DOWN_DISPATCHER','DISPATCHER_RELOAD']
        .map(name => route(runtime, name)).join('\n');
    if (process.env.KAZOO_KAMAILIO_DISPATCHER_CANDIDATE) {
        const candidate = fs.readFileSync(process.env.KAZOO_KAMAILIO_DISPATCHER_CANDIDATE, 'utf8');
        for (const name of ['DISPATCHER_READ_CHANGED_ROWS','DISPATCHER_INSERT_DB','MEDIA_SERVER_DOWN_DISPATCHER','DISPATCHER_RELOAD']) {
            assert.equal(route(candidate, name), route(runtime, name), 'Private runtime candidate matches pinned patched route ' + name);
        }
        groups++;
    }
    for (const sqliteMode of [true, false]) {
        privateWrite('parse.cfg', (sqliteMode ? '#!define KZ_DISPATCHER_SQLITE_AFFECTED_ROWS\n' : '')
            + 'debug=1\nlog_stderror=yes\nfork=no\nlisten=udp:127.0.0.1:50999\n'
            + 'loadmodule "pv.so"\nloadmodule "xlog.so"\nloadmodule "uuid.so"\nloadmodule "sl.so"\nloadmodule "tm.so"\n'
            + 'loadmodule "db_sqlite.so"\nloadmodule "sqlops.so"\nloadmodule "dispatcher.so"\n'
            + 'modparam("sqlops","sqlcon","exec=>sqlite:///' + path.join(scratch, 'parse-only.db') + '")\n'
            + routes + '\nrequest_route { exit; }\n');
        const parsed = spawnSync('/usr/sbin/kamailio', ['-c','-f',path.join(scratch,'parse.cfg')],
            {encoding:'utf8', timeout:10000});
        assert.equal(parsed.status, 0, 'Private parser branch ' + sqliteMode + ': '
            + parsed.stderr.split('\n').filter(line => /error|ERROR|failed/.test(line)).join('\n'));
        assert(!fs.existsSync(path.join(scratch, 'parse-only.db')), 'Parser must not open a DB');
    }
    groups++;

    const configure = installer.match(/^configure_kazoo_kamailio\(\) \{[\s\S]*?^\}/m)?.[0];
    const hook = 'apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-dispatcher-reload-bookkeeping.patch"';
    assert.equal(configure.split(hook).length, 2);
    assert(configure.indexOf('sync_git ') < configure.indexOf(hook) && configure.indexOf(hook) < configure.indexOf('run rsync -a'));
    assert(installer.includes('loadmodule "db_sqlite.so"\n#!define KZ_DISPATCHER_SQLITE_AFFECTED_ROWS\n'));
    assert.equal(spawnSync('bash', ['-n', path.join(__dirname, 'install-kazoo5.sh')]).status, 0); groups++;
    console.log('PASS ' + groups + ' dispatcher groups: exact pinned replay/idempotence, real SQLite zero/positive changes, failure/concurrent-writer reload retention, installed parser both branches; no SIP/API/live mutations');
} finally {
    fs.rmSync(scratch, {recursive:true});
}
