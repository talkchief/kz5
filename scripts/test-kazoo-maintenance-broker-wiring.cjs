'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const source=fs.readFileSync(__dirname+'/install-kazoo5.sh','utf8');
const extract=name=>{const m=source.match(new RegExp('^'+name+'\\(\\) \\{[\\s\\S]*?^\\}','m'));assert(m);return m[0];};
function fixture(t){
    const root=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-broker-wiring-'));t.after(()=>fs.rmSync(root,{recursive:true}));
    const script=`set -euo pipefail
SCRIPT_DIR=${JSON.stringify(__dirname)}
DRY_RUN=false
MONSTER_UI_NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
die(){ exit 1; }
log(){ :; }
run(){ "$@"; }
install_nodejs_toolchain(){ echo node-installed >> ${JSON.stringify(root+'/calls')}; }
${['validate_config_directory','install_broker_maintenance_tools','verify_broker_maintenance_tools'].map(extract).join('\n').replaceAll('/usr/local/libexec',root+'/libexec')}
`;
    return {root,run:tail=>cp.spawnSync('bash',['-c',script+'\n'+tail],{encoding:'utf8'})};
}
test('actual broker helper installer ships self-contained source and verifies executable syntax',t=>{
    const f=fixture(t),r=f.run('install_broker_maintenance_tools; verify_broker_maintenance_tools');assert.equal(r.status,0,r.stderr);
    assert(fs.readFileSync(f.root+'/libexec/kazoo5-maintenance-broker').equals(fs.readFileSync(__dirname+'/kazoo-maintenance-broker.cjs')));
    assert.equal(fs.statSync(f.root+'/libexec/kazoo5-maintenance-broker').mode&511,0o755);
});
test('missing and modified installed broker helper refuse verification',t=>{
    const f=fixture(t);assert.notEqual(f.run('verify_broker_maintenance_tools').status,0);
    assert.equal(f.run('install_broker_maintenance_tools').status,0);
    fs.appendFileSync(f.root+'/libexec/kazoo5-maintenance-broker','\n// drift');assert.notEqual(f.run('verify_broker_maintenance_tools').status,0);
});
test('standalone broker installs the required Node runtime when its major differs',t=>{
    const f=fixture(t);assert.equal(f.run('MONSTER_UI_NODE_MAJOR=0; install_broker_maintenance_tools').status,0);
    assert.equal(fs.readFileSync(f.root+'/calls','utf8').trim(),'node-installed');
});
test('full RabbitMQ install and verification invoke helper deployment and verification',()=>{
    assert(extract('install_rabbitmq').includes('install_broker_maintenance_tools\n    verify_rabbitmq'));
    assert(extract('verify_rabbitmq').includes('verify_broker_maintenance_tools'));
});
