#!/usr/bin/env node
'use strict';
// Exact main development broker; one new marked vhost/message, never a real
// Kazoo queue or subscriber. Finally removes only this run's generated vhost.
const fs=require('fs'),cp=require('child_process'),os=require('os'),crypto=require('crypto'),assert=require('assert/strict'),readline=require('readline');
const broker=require('./kazoo-maintenance-broker.cjs');
async function main(){
    assert.equal(process.getuid(),0);assert.deepEqual(process.argv.slice(2),['--live']);
    assert.equal(os.hostname(),'dev-testing');assert(Object.values(os.networkInterfaces()).flat().some(x=>x.address==='10.1.0.44'));
    const config=require('./kazoo-maintenance-callbacks.cjs').deployment();
    assert.equal(config.KAZOO_AMQP_HOST,'10.1.0.44');assert.equal(config.KAZOO_AMQP_PORT,'5672');
    const lock='/etc/kazoo/monitor-acceptance.lock',st=fs.lstatSync(lock);assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&(st.mode&511)===384);
    const fd=fs.openSync(lock,fs.constants.O_RDWR|fs.constants.O_NOFOLLOW);assert.equal(cp.spawnSync('flock',['-n','3'],{stdio:['ignore','ignore','ignore',fd]}).status,0);
    const vhost='kz5-maintenance-probe-'+crypto.randomBytes(8).toString('hex'),node='rabbit@dev-testing';
    const root=fs.mkdtempSync('/var/log/kazoo-broker-acceptance-');fs.chmodSync(root,0o700);process.umask(0o077);
    const save=(name,value)=>fs.writeFileSync(root+'/'+name,JSON.stringify(value)+'\n',{mode:0o600});
    const receipt={status:'RUNNING',vhost,checks:[],cleanup:false};save('receipt.json',receipt);
    const ctl=args=>cp.execFileSync('/usr/sbin/runuser',['-u','rabbitmq','--','/usr/lib/rabbitmq/bin/rabbitmqctl','-q','-n',node,...args],
        {cwd:'/var/lib/rabbitmq',timeout:20000,maxBuffer:1024*1024,encoding:'utf8',stdio:['ignore','pipe','pipe']});
    let child,created=false,passed=false;
    try{
        const before=JSON.parse(ctl(['list_vhosts','name','--formatter=json']));assert(!before.some(x=>x.name===vhost));
        // Mark intent before mutation; never automatically retry an uncertain create.
        created=true;ctl(['add_vhost',vhost]);ctl(['set_permissions','-p',vhost,config.KAZOO_RABBITMQ_USER,'.*','.*','.*']);
        const error=fs.openSync(root+'/client.stderr','wx',0o600);
        try{child=cp.spawn('/usr/local/lib/kazoo-push-bridge/current/venv/bin/python',['-I',__dirname+'/test-fixtures/maintenance-broker-client.py'],{stdio:['pipe','pipe',error,fd]});}finally{fs.closeSync(error);}
        const lines=readline.createInterface({input:child.stdout})[Symbol.asyncIterator]();
        async function response(expected){let timer;try{const item=await Promise.race([lines.next(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Fixture client timeout')),15000);})]);assert(!item.done);assert.equal(item.value,expected);}finally{clearTimeout(timer);}}
        child.stdin.write(JSON.stringify({host:config.KAZOO_AMQP_HOST,user:config.KAZOO_RABBITMQ_USER,password:config.KAZOO_RABBITMQ_PASSWORD,vhost})+'\n');await response('READY');
        const command=async name=>{child.stdin.write(name+'\n');await response('OK');};
        async function observe(label){const r=await broker.collect(broker.native(),node,vhost);save(label+'.json',r);assert.equal(r.queues.length,1);assert.equal(r.queues[0].name,'owned-probe');return r;}
        let r=await observe('empty');assert.equal(r.broker_work_empty,true);receipt.checks.push('empty-native');
        await command('publish');r=await observe('ready');assert.equal(r.counts.messages_ready,1);assert.equal(r.broker_work_empty,false);receipt.checks.push('queued-message-blocks');
        await command('get');r=await observe('unacknowledged');assert.equal(r.counts.messages_ready,0);assert.equal(r.counts.messages_unacknowledged,1);assert.equal(r.counts.channel_unacknowledged,1);assert.equal(r.broker_work_empty,false);receipt.checks.push('delivered-unacknowledged-message-blocks');
        await command('ack');r=await observe('settled');assert.equal(r.broker_work_empty,true);receipt.checks.push('acknowledged-native-empty');
        await command('close');passed=true;
    }finally{
        if(child){child.stdin.end();if(child.exitCode===null){await new Promise(resolve=>{const timer=setTimeout(()=>{child.kill('SIGTERM');resolve();},5000);child.once('exit',()=>{clearTimeout(timer);resolve();});});}}
        if(created){
            try{ctl(['delete_vhost',vhost]);const after=JSON.parse(ctl(['list_vhosts','name','--formatter=json']));assert(!after.some(x=>x.name===vhost));receipt.cleanup=true;}catch(_){receipt.cleanup=false;}
        }
        receipt.status=passed&&receipt.cleanup?'PASS':'FAIL';save('receipt.json',receipt);fs.closeSync(fd);
        console.log(JSON.stringify({status:receipt.status,receipt:root+'/receipt.json',checks:receipt.checks,cleanup:receipt.cleanup}));
    }
    assert.equal(receipt.status,'PASS');
}
if(require.main===module)main().catch(()=>{console.error('BROKER_LIVE_ACCEPTANCE_REFUSED_OR_FAILED');process.exitCode=1;});
