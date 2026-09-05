#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Pinned source/installer regressions only. Does not contact Kazoo/SIP, edit
// source checkouts or live configuration, or start/reload any service.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const {spawnSync, execFileSync} = require('node:child_process');
const assert = require('node:assert/strict');
const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const patch = path.join(__dirname, 'patches/kamailio-registered-source-credentials.patch');
const checkout = process.env.KAZOO_KAMAILIO_CONFIG_SOURCE
    || '/usr/local/src/kazoo5-installer/kazoo-configs-kamailio';
const revision = installer.match(/^KAMAILIO_CONFIG_REF=\$\{KAMAILIO_CONFIG_REF:-([a-f0-9]{40})\}$/m)?.[1];
assert(revision, 'Installer must pin the Kamailio configuration revision');
const original = file => execFileSync('git', ['-C', checkout, 'show', revision + ':kamailio/' + file], {encoding: 'utf8'});
const authorization = original('authorization.cfg'), main = original('default.cfg');
const registrar = original('registrar-role.cfg'), trusted = original('trusted.cfg');
const before = '    route(AUTHORIZATION_CHECK);\n    if (isflagset(FLAG_AUTHORIZED)) {\n'
    + '        consume_credentials();\n        route(MAIN);\n        exit;\n    }';
const after = before.replace('        consume_credentials();\n',
    '        # Registered/trusted-source authorization has no digest-authorized credential.\n'
    + '        # MAIN strips both credential headers after authorization, before forwarding.\n');
assert.equal(authorization.split(before).length, 2, 'Exactly one intended authorized-source branch');
const expected = authorization.replace(before, after);
const patchText = fs.readFileSync(patch, 'utf8');
assert.deepEqual(patchText.split('\n').filter(line => line.startsWith('diff --git ')),
    ['diff --git a/kamailio/authorization.cfg b/kamailio/authorization.cfg']);
assert.deepEqual(patchText.split('\n').filter(line => line.startsWith('-') && !line.startsWith('---')),
    ['-        consume_credentials();'], 'Only the proven redundant call may be removed');
let groups = 1;
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-kamailio-auth-source.'));
fs.chmodSync(scratch, 0o700);
try {
    fs.mkdirSync(path.join(scratch, 'kamailio'), {mode: 0o700});
    const file = path.join(scratch, 'kamailio/authorization.cfg');
    fs.writeFileSync(file, authorization, {mode: 0o600});
    const git = (...args) => spawnSync('git', ['-C', scratch, 'apply', ...args, patch], {encoding: 'utf8'});
    assert.equal(git('--check').status, 0, 'Pinned forward check');
    assert.equal(git().status, 0, 'Pinned forward application');
    assert.equal(fs.readFileSync(file, 'utf8'), expected, 'Exact expected bytes; all other auth code unchanged'); groups++;
    assert.notEqual(git('--check').status, 0, 'Already-applied patch cannot apply twice');
    assert.equal(git('--reverse', '--check').status, 0, 'Exact reverse check');
    assert.equal(git('--reverse').status, 0, 'Exact reverse application');
    assert.equal(fs.readFileSync(file, 'utf8'), authorization, 'Byte-identical pinned source restored'); groups++;

    // Run the actual installer patch helper against only our private fixture.
    const helper = installer.match(/^apply_required_source_patch\(\) \{[\s\S]*?^\}/m)?.[0];
    assert(helper);
    const apply = dry => spawnSync('bash', ['-c', 'set -Eeuo pipefail\n' + helper
        + '\nlog() { :; }\ndie() { exit 1; }\nDRY_RUN="$3"\napply_required_source_patch "$1" "$2"\n',
    'test', scratch, patch, String(dry)], {encoding: 'utf8', timeout: 5000});
    assert.equal(apply(true).status, 0); assert.equal(fs.readFileSync(file, 'utf8'), authorization); groups++;
    assert.equal(apply(false).status, 0); assert.equal(apply(false).status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), expected, 'Installer is byte-idempotent'); groups++;
    const unknown = expected.replace(after, after.replace('route(MAIN);', 'route(LOCAL_OPERATOR_MAIN);'));
    fs.writeFileSync(file, unknown, {mode: 0o600});
    assert.notEqual(apply(false).status, 0, 'An unrecognized operator-edited target must fail closed');
    assert.equal(fs.readFileSync(file, 'utf8'), unknown, 'Operator-edited source was not overwritten'); groups++;
} finally {
    fs.rmSync(scratch, {recursive: true});
}

// Source control-flow invariants, not a simulated successful authentication:
// authorized registered/trusted sources still enter MAIN; unmatched requests
// still take the existing Kazoo digest route, whose failure branches remain.
assert(expected.includes(after + '\n\n    routes(HANDLE_AUTHORIZATION);'));
assert.equal(expected.replace(after, before), authorization);
assert(expected.includes('if(!is_present_hf("Proxy-Authorization")) {\n        route(MAIN);'));
assert(expected.includes('if (isflagset(FLAG_INTERNALLY_SOURCED)) {\n        route(MAIN);'));
const digest = authorization.slice(authorization.indexOf('route[KZ_AUTHORIZATION_CHECK_RESPONSE_PASSWORD]'),
    authorization.indexOf('route[HANDLE_AUTHORIZATION]'));
assert(expected.includes(digest) && digest.includes('pv_auth_check(')
    && digest.includes('if ($var(retcode) != 1)') && digest.includes('auth_challenge(')
    && digest.includes('send_reply("403", "Forbidden");'));
assert(expected.includes('setflag(FLAG_REQUEST_AUTHORIZED_BY_KAZOO);\n\n    consume_credentials();'));
assert.equal(expected.match(/consume_credentials\(\);/g).length,
    authorization.match(/consume_credentials\(\);/g).length - 1); groups++;
assert(registrar.includes('$xavp(regcfg=>match_received) = $su;\n'
    + '    if (registered("location","$avp(auth-uri)", 2, 1) == 1)'));
assert(trusted.includes('route[AUTHORIZATION_CHECK_TRUSTED]')
    && trusted.includes('if (isflagset(FLAG_TRUSTED_SOURCE))'));
const mainRoute = main.slice(main.indexOf('route[MAIN]'), main.indexOf('    #!ifdef MESSAGE_ROLE', main.indexOf('route[MAIN]')));
assert(mainRoute.includes('route(AUTHORIZATION);\n        remove_hf("Authorization");\n'
    + '        remove_hf("Proxy-Authorization");'), 'Both credential headers remain stripped after authorization and before forwarding'); groups++;
const configure = installer.match(/^configure_kazoo_kamailio\(\) \{[\s\S]*?^\}/m)?.[0];
assert(configure);
const hook = 'apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-registered-source-credentials.patch"';
assert.equal(configure.split(hook).length, 2, 'Exactly one installer hook');
assert(configure.indexOf('sync_git ') < configure.indexOf('kamailio-registration-sequences.patch')
    && configure.indexOf('kamailio-registration-sequences.patch') < configure.indexOf(hook)
    && configure.indexOf(hook) < configure.indexOf('run rsync -a'), 'Patch follows pinned sync and precedes runtime config copy'); groups++;
assert.equal(spawnSync('bash', ['-n', path.join(__dirname, 'install-kazoo5.sh')]).status, 0); groups++;
console.log('PASS ' + groups + ' Kamailio registered-source credential groups: pinned replay/reverse/idempotence, operator-edit refusal, auth and header-stripping preservation, installer ordering; no SIP/API/runtime changes');
