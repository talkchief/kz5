'use strict';
// Synthetic state and extracted real shell entry points; no live credentials,
// database, provider, service or SIP operations.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const {spawnSync} = require('node:child_process');
const {LEGACY, selectedAccount, validateState, ensureLock} = require('./test-fixtures/callback-fixture-account.cjs');
const candidate = '8'.repeat(32), other = '9'.repeat(32);
const state = account => ({ACCEPTANCE_ACCOUNT_ID:account, ACCEPTANCE_ACCOUNT_NAME:'Kazoo5 Acceptance 123456abcdef',
    ACCEPTANCE_REALM:'acceptance-123456abcdef.invalid', ACCEPTANCE_CALLER_EXTENSION:'1001',
    ACCEPTANCE_CALLER_SIP_USERNAME:'acceptance1001', ACCEPTANCE_QUEUE_EXTENSION:'2000',
    ACCEPTANCE_QUEUE_ID:'a'.repeat(32), ACCEPTANCE_QUEUE_CALLFLOW_ID:'b'.repeat(32)});
const q = s => "'" + s.replaceAll("'", "'\\''") + "'";
const extract = (source, name) => {
    const match = source.match(new RegExp('^' + name + '\\(\\) \\{\\n[\\s\\S]*?^\\}', 'm'));
    assert(match, 'Missing actual shell function ' + name); return match[0];
};
assert.equal(selectedAccount({}), LEGACY);
for (const account of [LEGACY, candidate]) assert.equal(validateState(state(account), account), account);
for (const id of ['', null, 'A'.repeat(32), candidate+'\n', 'adecbb84fbe9e06902a76731914d1943',
    '302ae5a70c403124f764cbc54229cfcd', 'd8520ce3f29c5b6db692289e782c92af'])
    assert.throws(() => selectedAccount({KAZOO_CALLBACK_TEST_ACCOUNT_ID:id}));
for (const change of [{ACCEPTANCE_ACCOUNT_ID:other}, {ACCEPTANCE_ACCOUNT_NAME:'Talkchief'},
    {ACCEPTANCE_REALM:'acceptance-abcdef123456.invalid'}, {ACCEPTANCE_CALLER_EXTENSION:'1000'},
    {ACCEPTANCE_CALLER_SIP_USERNAME:'admin'}, {ACCEPTANCE_QUEUE_EXTENSION:'2001'}, {ACCEPTANCE_QUEUE_ID:'bad'}])
    assert.throws(() => validateState({...state(candidate), ...change}, candidate));
const retry = fs.readFileSync(process.argv[2] || path.join(__dirname, 'test-acdc-callback-retry.sh'), 'utf8');
function args(options) {
    const input = `set -Eeuo pipefail
CALLBACK_PREPARE=false CALLBACK_LIVE=false KEEP_FIXTURE=false RETRY_REFERENCE='' RETRY_REGISTRATION_MODE=confirm-current
CALLBACK_TEST_TRANSPORT=external RETRY_LANGUAGE=en-us RETRY_LANGUAGE_EXPLICIT=false RETRY_LANGUAGE_ARGS=()
RETRY_ACCOUNT_ID=${LEGACY} RETRY_ACCOUNT_EXPLICIT=false retry_script_dir=/synthetic
export KAZOO_CALLBACK_TEST_ACCOUNT_ID=${other}
die(){ exit 65; }; validate_protected_file(){ :; }
node(){ printf '%s\\n' '{"voice_family":"gemini-sulafat","language":"en-us"}'; }
${extract(retry, 'retry_args')}
retry_args --prepare-only --confirmation-reference ${q(__filename)} ${options.map(q).join(' ')}
printf '%s\\n' "$RETRY_ACCOUNT_ID" "\${KAZOO_CALLBACK_TEST_ACCOUNT_ID:-missing}"
`;
    return spawnSync('bash', ['-s'], {input, encoding:'utf8'});
}
// This fails on the old tenant-pinned script, which rejects the new option.
const portable = args(['--fixture-account', candidate]);
assert.equal(portable.status, 0, 'Explicit new fixture must be accepted: '+portable.stderr);
assert.equal(portable.stdout.trim(), candidate+'\n'+candidate);
assert.equal(args([]).stdout.trim(), LEGACY+'\n'+LEGACY, 'Ambient identity must not select a tenant');
for (const options of [['--fixture-account'], ['--fixture-account', 'bad'],
    ['--fixture-account',candidate,'--fixture-account',other]]) assert.equal(args(options).status,65);
const fixture = fs.readFileSync(path.join(__dirname,'test-acdc-callback-fixture.sh'),'utf8');
const verify = extract(fixture,'verify_retry_account_identity');
function ownership({master=other, actual=candidate, realm=state(candidate).ACCEPTANCE_REALM,
    privateOk=true, resourceOk=true, saved=candidate, queue='a'.repeat(32)}={}) {
    const scratch = fs.mkdtempSync('/tmp/kazoo-callback-identity.');
    try {
        fs.writeFileSync(path.join(scratch,'test-kazoo-call-provision.sh'),
            '#!/bin/bash\n[[ "$1" == --verify-only && $# == 1 ]] || exit 90\nexit '+(resourceOk?'0':'1')+'\n', {mode:0o700});
        const input=`set -Eeuo pipefail
ACCEPTANCE_ACCOUNT_ID=${candidate} MASTER_ACCOUNT_ID=${master}
ACCEPTANCE_ACCOUNT_NAME=${q(state(candidate).ACCEPTANCE_ACCOUNT_NAME)} ACCEPTANCE_QUEUE_ID=${'a'.repeat(32)}
FIXTURE_ACCOUNT_ID=${saved} FIXTURE_ORIGINAL_QUEUE=${q(JSON.stringify({id:queue,name:'Acceptance Queue 2000'}))}
ACCEPTANCE_STATE_FILE=/etc/kazoo/acceptance-secrets.env callback_fixture_dir=${q(scratch)}
fixture_die(){ exit 65; }
node(){ return ${privateOk?0:1}; }
api_request(){ [[ $1 == GET ]] || exit 91; printf '%s\\n' ${q(JSON.stringify({data:{id:actual,name:state(candidate).ACCEPTANCE_ACCOUNT_NAME,realm}}))}; }
${verify}
verify_retry_account_identity
`;
        return spawnSync('bash',['-s'],{input,encoding:'utf8'});
    } finally {fs.rmSync(scratch,{recursive:true,force:true});}
}
assert.equal(ownership().status,0);
for (const change of [{master:candidate},{actual:other},{realm:'production.invalid'},
    {privateOk:false},{resourceOk:false},{saved:other},{queue:'c'.repeat(32)}])
    assert.equal(ownership(change).status,65,'Unsafe ownership accepted: '+JSON.stringify(change));
const main = extract(fixture,'main_fixture');
assert(main.indexOf('verify_retry_account_identity') > main.indexOf('authenticate_master'));
assert(main.indexOf('verify_retry_account_identity') < main.indexOf('setup_fixture'));
const locks = fs.mkdtempSync('/tmp/kazoo-callback-lock.');
try {
    const file=path.join(locks,'lock');ensureLock(file);
    fs.writeFileSync(file,'existing lock contents');const inode=fs.statSync(file).ino;
    ensureLock(file);assert.equal(fs.statSync(file).ino,inode);assert.equal(fs.readFileSync(file,'utf8'),'existing lock contents');
    fs.symlinkSync(file,path.join(locks,'symlink'));assert.throws(()=>ensureLock(path.join(locks,'symlink')));
    fs.linkSync(file,path.join(locks,'hardlink'));assert.throws(()=>ensureLock(file));
    const unsafe=path.join(locks,'unsafe');fs.writeFileSync(unsafe,'',{mode:0o644});assert.throws(()=>ensureLock(unsafe));
} finally {fs.rmSync(locks,{recursive:true,force:true});}
console.log('PASS explicit fixture selection, ambient isolation, protected-state identity and seven live-ownership refusal paths; no live I/O');
