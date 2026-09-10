'use strict';
// Explicit main development runtime. Never an arbitrary remote/PSTN target.
const fs=require('node:fs'),os=require('node:os'),cp=require('node:child_process');
const assert=require('node:assert/strict');

function validate(host,addresses,config,master) {
    assert.equal(host,'dev-testing');
    assert(addresses.includes('10.1.0.44'));
    assert.equal(config.KAZOO_ROOT,'/opt/kz5');
    assert.equal(config.KAZOO_COUCHDB_HOST,'10.1.0.44');
    assert.equal(config.KAZOO_AMQP_HOST,'10.1.0.44');
    assert.equal(config.KAZOO_PUBLIC_HOSTNAME,'kz5-dev.talkchief.io');
    assert(/^[a-f0-9]{32}$/.test(master));
    return {master,proxy:'10.1.0.44'};
}
function masterIdentity(result) {
    assert(!result.error&&result.status===0,'Cannot read local master account identity');
    const match=/^\{ok,<<"([a-f0-9]{32})">>\}\s*$/.exec(result.stdout);
    assert(match,'Unexpected local master identity reply');
    return match[1];
}
function prepare() {
    assert.equal(process.getuid(),0);
    const file='/etc/kazoo/deployment.env',st=fs.lstatSync(file);
    assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&st.nlink===1&&(st.mode&511)===384);
    const config={};
    for(const line of fs.readFileSync(file,'utf8').split('\n')) {
        if(!line||line.startsWith('#'))continue;
        const at=line.indexOf('='),key=line.slice(0,at),value=line.slice(at+1);
        assert(at>0&&/^[A-Z][A-Z0-9_]+$/.test(key)&&!Object.hasOwn(config,key));
        assert(/^[A-Za-z0-9+/]*={0,2}$/.test(value));
        config[key]=Buffer.from(value,'base64').toString();
    }
    const host=os.hostname(),addresses=Object.values(os.networkInterfaces()).flat().map(n=>n.address);
    // Refuse host/config drift before local authenticated RPC, not after it.
    validate(host,addresses,config,'0'.repeat(32));
    const result=cp.spawnSync('/usr/local/bin/sup',['-e','-n','kazoo_apps','kapps_util','get_master_account_id'],
        {encoding:'utf8',timeout:15000,maxBuffer:4096,stdio:['ignore','pipe','pipe']});
    return validate(host,addresses,config,masterIdentity(result));
}
module.exports={validate,masterIdentity,prepare};
