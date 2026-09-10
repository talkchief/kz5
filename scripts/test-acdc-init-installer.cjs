'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const body=source.match(/^verify_acdc_initialization_ready\(\) \{[\s\S]*?^\}/m)[0];
function check(t,responses){
    const root=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-init-installer-'));
    t.after(()=>fs.rmSync(root,{recursive:true}));fs.writeFileSync(root+'/responses',responses.join('\n')+'\n');
    return cp.spawnSync('/usr/bin/bash',['-c',`set -euo pipefail
DRY_RUN=false
KAZOO_START_TIMEOUT=1
KAZOO_RUNTIME_COOKIE_FILE=/fixture/cookie
KAZOO_NODE_NAME_TYPE=-sname
KAZOO_HOSTNAME=fixture
verify_cookie_copy(){ [[ $* == '/fixture/cookie kazoo' ]]; }
find_erl_call(){ echo /fixture/erl_call; }
log(){ echo "$*"; }
die(){ echo "$*" >&2; exit 1; }
sleep(){ /usr/bin/sleep 0.02; }
timeout(){ [[ $* == '10 runuser --user kazoo -- /fixture/erl_call -sname kazoo_apps@fixture -a acdc_init startup_status []' ]] || exit 99;
 head -n 1 '${root}/responses'; sed -i '1d' '${root}/responses'; }
${body}
verify_acdc_initialization_ready`],{encoding:'utf8',timeout:4000});
}
test('installer waits through pending/unavailable and accepts only ready',t=>{
    const r=check(t,['pending','unavailable','ready']);assert.equal(r.status,0,r.stderr);
    assert(r.stdout.includes('PASS all supervised'));
});
test('failed job immediately refuses deployment success',t=>{
    const r=check(t,['failed','ready']);assert.notEqual(r.status,0);assert(r.stderr.includes('job failed'));
});
test('missing or malformed readiness cannot count as running',t=>{
    const r=check(t,['{ok,ready}','true','unknown']);assert.notEqual(r.status,0);
    assert(r.stderr.includes('pending or unavailable'));
});
test('normal apps verification invokes the native initialization gate',()=>{
    assert(source.match(/^verify_kazoo_apps\(\) \{[\s\S]*?^\}/m)[0].includes('verify_acdc_initialization_ready'));
});
