#!/usr/bin/env node
'use strict';
// Execute the actual installer snapshot function against only a private tree.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const fn = source.match(/^kazoo_build_snapshot\(\) \([\s\S]*?^\)/m);
assert(fn, 'actual installer snapshot function');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-build-snapshot.'));
function write(name, value) {
    const file = path.join(temp, name);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, value);
    return file;
}
function snapshot(extra = {}) {
    return cp.spawnSync('/usr/bin/bash', ['--noprofile', '--norc', '-s'], {
        input: 'set -euo pipefail\n' + fn[0] + '\nkazoo_build_snapshot\n',
        encoding: 'utf8', timeout: 10000,
        env: {PATH: '/usr/bin:/bin', KAZOO_ROOT: temp, ...extra}
    });
}
function good(extra) {
    const result = snapshot(extra);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^[a-f0-9]{64}\n$/);
    return result.stdout;
}
try {
    write('Makefile', 'fixture');
    write('erlang.mk', 'dependency build');
    write('VERSION', '5.0');
    write('.base_branch', 'master');
    write('scripts/next_version', 'version helper');
    write('core/example/src/generated.erl.src', 'template');
    write('core/example/mime.types', 'mime');
    write('core/example/dialcodes.json', 'dialcodes');
    write('make/kz.mk', 'fixture');
    const input = write('applications/acdc/src/example.erl', 'first');
    write('core/example/include/example.hrl', 'header');
    const beam = write('applications/acdc/ebin/example.beam', 'compiled');
    write('deps/example/ebin/example.beam', 'dependency');
    const original = good();
    fs.utimesSync(input, 1, 1); fs.utimesSync(beam, 2147483647, 2147483647);
    assert.equal(good(), original, 'timestamps must not define identity');
    write('applications/acdc/src/example.erl', 'second'); fs.utimesSync(input, 1, 1);
    assert.notEqual(good(), original, 'old-mtime changed source must be detected');
    write('applications/acdc/src/example.erl', 'first');
    assert.equal(good(), original);
    for (const name of ['applications/acdc/ebin/example.beam', 'deps/example/ebin/example.beam',
        'core/example/include/example.hrl', 'make/kz.mk', 'Makefile', 'erlang.mk',
        'core/example/src/generated.erl.src', 'core/example/mime.types',
        'core/example/dialcodes.json', 'scripts/next_version', 'VERSION', '.base_branch']) {
        const previous = fs.readFileSync(path.join(temp, name));
        write(name, 'changed'); assert.notEqual(good(), original, 'changed ' + name);
        write(name, previous); assert.equal(good(), original);
    }
    const added = write('applications/acdc/src/new module.erl', 'added');
    assert.notEqual(good(), original, 'inventory/path changes must be detected');
    fs.unlinkSync(added); assert.equal(good(), original);
    write('applications/acdc/priv/operator.log', 'unrelated runtime log');
    assert.equal(good(), original, 'logs must not invalidate a build');
    assert.notEqual(good({ERLC_OPTS: '-DTEST'}), original, 'changed compile options');
    const link = path.join(temp, 'applications/acdc/src/linked.erl');
    fs.symlinkSync('example.erl', link);
    const linked = good();
    write('applications/acdc/src/example.erl', 'linked target changed');
    assert.notEqual(good(), linked, 'linked compile input must not be ignored');
    fs.unlinkSync(link); write('applications/acdc/src/example.erl', 'first');
    fs.symlinkSync('missing.erl', link);
    assert.notEqual(snapshot().status, 0, 'dangling compile input must fail');
    fs.unlinkSync(link);
    const linkedDir = path.join(temp, 'core/linked');
    fs.symlinkSync('../applications/acdc', linkedDir);
    assert.notEqual(snapshot().status, 0, 'linked directory must not be silently skipped');
    fs.unlinkSync(linkedDir);
    fs.mkdirSync(path.join(temp, 'deps/.erlang.mk/rebar/_build'), {recursive: true});
    fs.symlinkSync(path.join(temp, 'applications/acdc'), path.join(temp, 'deps/.erlang.mk/rebar/_build/linked'));
    assert.equal(good(), original, 'fetch-tool private builds are not runtime source inventory');
    fs.unlinkSync(path.join(temp, 'Makefile'));
    assert.notEqual(snapshot().status, 0, 'missing build root inventory must fail');
    assert.notEqual(snapshot({KAZOO_ROOT: path.join(temp, 'absent')}).status, 0);
    console.log('PASS content-only build snapshot, source/header/BEAM/dependency/make drift, inventory, spaces, compile options, missing-root failures');
} finally {
    fs.rmSync(temp, {recursive: true, force: true});
}
