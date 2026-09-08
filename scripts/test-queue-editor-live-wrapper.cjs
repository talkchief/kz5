'use strict';
// Actual shell entry with synthetic identity/runtime adapters and a private
// real flock file. No live API, secrets or canonical acceptance state reads.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const source=fs.readFileSync(path.join(__dirname,'test-acdc-queue-editor-live.sh'),'utf8');
const directory=fs.mkdtempSync(path.join(os.tmpdir(),'queue-editor-wrapper.'));
const lock=path.join(directory,'lock'),q=s=>"'"+s.replaceAll("'","'\\''")+"'";
try {
    fs.writeFileSync(lock,'existing owner evidence\n',{mode:0o600});
    const inode=fs.statSync(lock).ino;
    const fn=source.match(/^editor_main\(\) \{\n[\s\S]*?^\}/m)?.[0];assert(fn);
    assert(fn.includes('exec {editor_lock_fd}<>/etc/kazoo/monitor-acceptance.lock'));
    const selected='8'.repeat(32),args=['run-languages','--fixture-account',selected,'--extension','2097',
        '--run-dir','/var/log/kazoo-acceptance/synthetic','--allow-fixture-writes'];
    function script(argv,refuse=false) {
        return `set -Eeuo pipefail
editor_dir=/synthetic
export KAZOO_CALLBACK_TEST_ACCOUNT_ID=${'9'.repeat(32)} KAZOO_TEST_QUEUE_EDITOR_EXTENSION=2099 KAZOO_ACCEPTANCE_STATE_FILE=/wrong
node(){
 [[ ! -v KAZOO_ACCEPTANCE_STATE_FILE ]] || return 90
 if [[ $1 == */callback-fixture-account.cjs ]]; then [[ ${refuse} == false ]]; return; fi
 printf '%s %s %s %s %s\\n' "$KAZOO_CALLBACK_TEST_ACCOUNT_ID" "$KAZOO_TEST_QUEUE_EDITOR_EXTENSION" "$2" "$3" "$4"
}
${fn.replace('/etc/kazoo/monitor-acceptance.lock',lock)}
editor_main ${argv.map(q).join(' ')}
`;
    }
    const run=(argv,refuse=false)=>spawnSync('bash',['-s'],{input:script(argv,refuse),encoding:'utf8'});
    const ok=run(args);assert.equal(ok.status,0,ok.stderr);
    assert.equal(ok.stdout.trim(),selected+' 2097 run-languages --allow-fixture-writes /var/log/kazoo-acceptance/synthetic');
    for(const bad of [[],args.slice(0,-1),args.concat('--allow-fixture-writes'),args.concat('--extension','2096'),
        ['run','--fixture-account','bad'],['run','--extension','2000'],['unknown'],
        ['run','--run-dir','/etc'],['run','--fixture-account']])assert.equal(run(bad).status,64);
    assert.notEqual(run(args,true).status,0,'Identity refusal must stop before runtime');
    const held=spawnSync('flock',['-n',lock,'bash','-s'],{input:script(args),encoding:'utf8'});
    assert.notEqual(held.status,0,'Held shared lock must stop runtime');assert.equal(held.stdout,'');
    assert.equal(fs.statSync(lock).ino,inode);assert.equal(fs.readFileSync(lock,'utf8'),'existing owner evidence\n');
    console.log('PASS editor wrapper explicit account/extension/arming, ambient isolation, refusal, real flock exclusion and inode preservation');
} finally {fs.rmSync(directory,{recursive:true,force:true});}
