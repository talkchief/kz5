'use strict';
// Execute the actual installer functions against private filesystem/service
// adapters. Native packet filtering is tested separately in a network namespace.
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const source=fs.readFileSync(path.join(__dirname,'install-kazoo5.sh'),'utf8');
function fixture(t){
    const root=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-fence-wiring-'));
    t.after(()=>fs.rmSync(root,{recursive:true}));
    const names=['maintenance_fence_service','install_service_maintenance_fence','verify_service_maintenance_fence','service_enable_restart','validate_config_directory'];
    const body=names.map(n=>{const m=source.match(new RegExp('^'+n+'\\(\\) \\{[\\s\\S]*?^\\}','m'));assert(m,n);return m[0];}).join('\n')
        .replaceAll('/usr/local/libexec',root+'/libexec').replaceAll('/etc/systemd/system',root+'/units')
        .replaceAll('/usr/bin/node','guard_node');
    const script=`set -euo pipefail
SCRIPT_DIR=${JSON.stringify(__dirname)}
DRY_RUN=false
MONSTER_UI_NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
die(){ echo REFUSED >&2; exit 1; }
log(){ :; }
dnf_install(){ echo "packages $*" >> '${root}/calls'; }
install_nodejs_toolchain(){ echo node-toolchain >> '${root}/calls'; }
guard_node(){ echo "guard $*" >> '${root}/calls'; [[ \${GUARD_FAIL:-false} != true ]] && { [[ $1 != *kazoo5-maintenance-media ]] || [[ \${MEDIA_FAIL:-false} != true ]]; }; }
run(){ "$@"; }
install_service_address_gate(){ :; }
write_file(){ mkdir -p "$(dirname "$2")"; install -m "$1" /dev/stdin "$2"; }
systemctl(){
 if [[ $1 == show ]]; then
  if [[ \${WRONG_GATE:-false} == true ]]; then echo 'argv[]=wrong'; else
   printf 'argv[]=guard_node ${root}/libexec/kazoo5-maintenance-fence --boot-guard ;'
   if [[ $2 == kazoo-freeswitch.service && \${MISSING_MEDIA:-false} != true ]]; then
    printf ' argv[]=guard_node ${root}/libexec/kazoo5-maintenance-media --boot-guard ;'
   fi
  fi
 else echo "systemctl $*" >> '${root}/calls'; fi
}
${body}
`;
    return {root,run:(tail)=>cp.spawnSync('/usr/bin/bash',['-c',script+'\n'+tail],{encoding:'utf8'}),
        calls:()=>fs.existsSync(root+'/calls')?fs.readFileSync(root+'/calls','utf8'):''};
}
test('all four ingress roles install dependencies, immutable helper and privileged boot guard before restart',t=>{
    const f=fixture(t);
    for(const unit of ['kazoo-apps.service','kazoo-freeswitch.service','kazoo-kamailio.service','nginx.service']){
        const r=f.run(`service_enable_restart ${unit}\nverify_service_maintenance_fence ${unit}`);
        assert.equal(r.status,0,r.stderr);
        const config=fs.readFileSync(f.root+'/units/'+unit+'.d/35-kazoo-maintenance-fence.conf','utf8');
        assert(config.includes('ExecStartPre=+guard_node '+f.root+'/libexec/kazoo5-maintenance-fence --boot-guard'));
        assert(config.includes('After=nftables.service firewalld.service'));
    }
    assert.equal(fs.readFileSync(f.root+'/libexec/kazoo5-maintenance-fence','utf8'),fs.readFileSync(__dirname+'/kazoo-maintenance-fence.cjs','utf8'));
    assert.equal((f.calls().match(/packages nftables iproute util-linux/g)||[]).length,4);
    assert.equal(fs.readFileSync(f.root+'/libexec/kazoo5-maintenance-media','utf8'),fs.readFileSync(__dirname+'/kazoo-maintenance-media.cjs','utf8'));
    assert(fs.readFileSync(f.root+'/units/kazoo-freeswitch.service.d/36-kazoo-maintenance-media.conf','utf8').includes('ExecStartPre=+guard_node '+f.root+'/libexec/kazoo5-maintenance-media --boot-guard'));
    assert(f.calls().includes('packages binutils'));
    assert(f.calls().indexOf('--boot-guard')<f.calls().indexOf('systemctl restart'));
});
test('database, broker, controller and unrelated services get no ingress hook',t=>{
    const f=fixture(t);
    for(const unit of ['couchdb.service','rabbitmq-server.service','haproxy.service','kazoo-ecallmgr.service','sshd.service']){
        assert.equal(f.run(`install_service_maintenance_fence ${unit}\nverify_service_maintenance_fence ${unit}`).status,0);
    }
    assert.equal(f.calls(),'');assert(!fs.existsSync(f.root+'/units'));
});
test('unsafe fence state refuses before service enable or restart',t=>{
    const f=fixture(t),r=f.run('GUARD_FAIL=true service_enable_restart kazoo-apps.service');
    assert.notEqual(r.status,0);assert(!f.calls().includes('systemctl'));
});
test('missing effective guard and changed installed source fail verification',t=>{
    const f=fixture(t);assert.equal(f.run('install_service_maintenance_fence kazoo-apps.service').status,0);
    assert.notEqual(f.run('WRONG_GATE=true verify_service_maintenance_fence kazoo-apps.service').status,0);
    fs.appendFileSync(f.root+'/libexec/kazoo5-maintenance-fence','\n// changed\n');
    assert.notEqual(f.run('verify_service_maintenance_fence kazoo-apps.service').status,0);
});
test('service acceptance includes maintenance verification',()=>{
    const body=source.match(/^assert_service\(\) \{[\s\S]*?^\}/m)[0];
    assert(body.includes('verify_service_maintenance_fence "$unit"'));
});
test('unsafe media state refuses before enabling or restarting FreeSWITCH',t=>{
    const f=fixture(t);assert.notEqual(f.run('MEDIA_FAIL=true service_enable_restart kazoo-freeswitch.service').status,0);
    assert(!f.calls().includes('systemctl'));
});
test('media helper drift, missing boot hook or invalid native state fail verification',t=>{
    const f=fixture(t);assert.equal(f.run('service_enable_restart kazoo-freeswitch.service').status,0);
    assert.notEqual(f.run('MISSING_MEDIA=true verify_service_maintenance_fence kazoo-freeswitch.service').status,0);
    assert.notEqual(f.run('MEDIA_FAIL=true verify_service_maintenance_fence kazoo-freeswitch.service').status,0);
    fs.appendFileSync(f.root+'/libexec/kazoo5-maintenance-media','\n// changed\n');
    assert.notEqual(f.run('verify_service_maintenance_fence kazoo-freeswitch.service').status,0);
});
test('normal FreeSWITCH builds include the durable core patch and invalidate the previous build marker',()=>{
    const prepare=source.match(/^prepare_freeswitch_source\(\) \{[\s\S]*?^\}/m)[0];
    const fingerprint=source.match(/^freeswitch_build_fingerprint\(\) \{[\s\S]*?^\}/m)[0];
    assert(prepare.includes('patches/freeswitch-durable-media-admission.patch'));
    assert(fingerprint.includes('durable-media-admission-v1'));
});
