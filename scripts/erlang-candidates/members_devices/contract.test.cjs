'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {buildSpec,overlay,ENDPOINT}=require('./openapi-overlay.cjs');
const {ACCOUNT,apiTarget,validators,runReadOnly}=require('./live-readonly.cjs');
const copy=v=>JSON.parse(JSON.stringify(v)),now=Date.now(),first='1'.padStart(32,'0'),deviceId='a'.repeat(32);
const snapshot={complete:true,reason:'complete',started_at_ms:now-10,observed_at_ms:now,expiry_available:true,
    source:'cluster_registrar_detail',semantics:'registration_not_call_reachability'};
const registration={status:'online',reason:'registered',registrable:true,observed_at_ms:now,expires_at_ms:now+60000};
const device={id:deviceId,name:null,type:'sip_device',enabled:true,registration};
const member={id:first,name:null,first_name:'Member',last_name:null,enabled:true,devices:[device],devices_complete:true,device_count:1};
const data={items:[member],count:1,page_size:25,has_more:false,next_cursor:null,total_members:null,
    device_inventory:{complete:true,limit:1000,count:1,reason:'complete'},registration_snapshot:snapshot};
function omitNull(v){if(Array.isArray(v))return v.map(omitNull);if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).filter(([,x])=>x!==null).map(([k,x])=>[k,omitNull(x)]));return v;}
test('members overlay is source-bound and read-only; generation does not mutate published files',()=>{
    const before=fs.readFileSync(path.join(__dirname,'../../assets/api-docs/openapi.json'));
    const spec=buildSpec(),fragment=overlay(),op=spec.paths[ENDPOINT].get;
    assert.deepEqual(Object.keys(spec.paths[ENDPOINT]),['get']);assert.equal(op['x-implementation-status'],'implemented-source-reviewed');
    assert.equal(op['x-source-sha256'],crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'../../../applications/crossbar/src/modules/cb_members.erl'))).digest('hex'));
    assert.equal(op['x-required-integration'].built_in_custom_route,'members');assert(op['x-required-integration'].preserve_existing_custom_routes);
    assert.deepEqual(op['x-required-integration'].scopes_rechecked,['members:GET','users:GET','devices:GET']);
    assert.deepEqual(op.security,[{CrossbarToken:[]}]);assert.equal(fragment.paths[ENDPOINT].get.operationId,'getAccountMembersDevices');
    assert.deepEqual(fs.readFileSync(path.join(__dirname,'../../assets/api-docs/openapi.json')),before);
});
test('full nulls and Crossbar-omitted null properties are both valid',()=>{
    const {page}=validators();assert(page(copy(data)),JSON.stringify(page.errors));assert(page(omitNull(data)),JSON.stringify(page.errors));
    const noDevices=copy(data);noDevices.items[0].devices=[];noDevices.items[0].device_count=0;noDevices.device_inventory.count=0;
    noDevices.registration_snapshot={...snapshot,complete:false,reason:'not_requested',expiry_available:false};assert(page(noDevices));
});
test('permanent, expired and malformed-expiry registration branches match implementation',()=>{
    const {page}=validators();
    for(const r of [{...registration,status:'online',reason:'registered_permanent',expires_at_ms:null},
        {...registration,status:'offline',reason:'registration_expired',expires_at_ms:null},
        {...registration,status:'offline',reason:'not_registered',expires_at_ms:null},
        {...registration,status:'unknown',reason:'expiry_unavailable',expires_at_ms:null},
        {...registration,status:'unknown',reason:'non_registration_auth',registrable:false,expires_at_ms:null}]) {
        const value=copy(data);value.items[0].devices[0].registration=r;assert(page(value),JSON.stringify(page.errors));assert(page(omitNull(value)));
    }
    for(const r of [{...registration,status:'offline'}, {...registration,reason:'registered_permanent'},
        {...registration,status:'unknown',reason:'expiry_unavailable'}, {...registration,expires_at_ms:null},
        {...registration,registrable:false},{...registration,status:'online',reason:'registration_unavailable'}]) {
        const value=copy(data);value.items[0].devices[0].registration=r;assert.equal(page(value),false);
    }
});
test('overflow is explicitly incomplete, never an invented empty complete device catalog',()=>{
    const {page}=validators(),overflow=copy(data);
    overflow.device_inventory={complete:false,limit:1000,count:null,reason:'limit_exceeded'};
    overflow.items[0]={...overflow.items[0],devices:[],devices_complete:false,device_count:null};
    overflow.registration_snapshot={...snapshot,complete:false,reason:'not_requested',expiry_available:false};
    assert(page(overflow),JSON.stringify(page.errors));assert(page(omitNull(overflow)));
    for(const mutate of [x=>{x.device_inventory.count=0;},x=>{x.items[0].device_count=0;},x=>{x.items[0].devices=[device];},x=>{x.device_inventory.reason='complete';}]) {
        const invalid=copy(overflow);mutate(invalid);assert.equal(page(invalid),false);
    }
});
test('schema forbids raw device/user/registrar fields and invalid continuation states',()=>{
    const {page}=validators();
    for(const mutate of [x=>{x.items[0].password='secret';},x=>{x.items[0].devices[0].sip={password:'secret'};},
        x=>{x.items[0].devices[0].registration.Contact='private';},x=>{x.items[0].queues=[];},
        x=>{x.has_more=true;},x=>{x.next_cursor='opaque';},x=>{x.page_size=101;},x=>{x.total_members=31;},
        x=>{x.registration_snapshot.complete=false;}]) {
        const bad=copy(data);mutate(bad);assert.equal(page(bad),false);
    }
});
function fake() {
    const users=Array.from({length:31},(_,n)=>({id:String(n+1).padStart(32,'0'),enabled:true,name:'Legacy summary'}));
    const devices=[{id:deviceId,owner_id:first,device_type:'sip_device',enabled:true}],requests=[];
    const control={leak:false,seconds:false,expired:false,omit:false,drift:false,partial:false,anonymousAllowed:false,negativeAllowed:false};
    let userReads=0;
    const response=(payload,status=200)=>({status,body:{status:status===200?'success':'error',data:payload},cacheControl:'no-store',startedAt:now-20,finishedAt:now+20});
    const io={now:()=>now+25,get:async(relative,anonymous=false)=>{
        requests.push([relative,anonymous]);apiTarget('GET',relative,anonymous);
        if(anonymous)return response({},control.anonymousAllowed?200:401);
        if(relative==='users?paginate=false') {userReads++;return response(control.drift&&userReads>1?users.map((u,n)=>n===0?{...u,enabled:false}:u):copy(users));}
        if(relative==='devices?paginate=false')return response(copy(devices));
        if(relative==='devices/status')return control.partial?response({},503):response([{device_id:deviceId,registrable:true,registered:true}]);
        const url=new URL('http://local/'+relative),cursor=url.searchParams.get('cursor');
        if(url.searchParams.get('page_size')!=='25'||cursor&&cursor!=='next')return response({},control.negativeAllowed?200:400);
        const selected=cursor?users.slice(25):users.slice(0,25);
        const d=copy(data);d.items=selected.map(u=>({...copy(member),id:u.id,devices:u.id===first?[copy(device)]:[],device_count:u.id===first?1:0}));
        d.count=d.items.length;d.has_more=!cursor;d.next_cursor=cursor?null:'next';
        if(control.omit&&cursor){d.items.pop();d.count--;}
        if(control.seconds){d.registration_snapshot.started_at_ms=Math.floor(now/1000);d.registration_snapshot.observed_at_ms=Math.floor(now/1000);}
        if(control.partial){d.registration_snapshot={...snapshot,complete:false,reason:'registration_unavailable',expiry_available:false};
            for(const m of d.items)for(const dev of m.devices)dev.registration={...registration,status:'unknown',reason:'registration_unavailable',expires_at_ms:null};}
        if(d.items[0]?.devices[0]&&control.leak)d.items[0].devices[0].sip={password:'NEVER_OUTPUT'};
        if(d.items[0]?.devices[0]&&control.expired)d.items[0].devices[0].registration.expires_at_ms=now-1000;
        return response(d);
    }};
    return {io,control,requests};
}
test('read-only harness proves31 users including30 device-less members over two pages',async()=>{
    const f=fake(),result=await runReadOnly(f.io);
    assert.equal(result.member_count,31);assert.equal(result.zero_device_member_count,30);assert.equal(result.page_count,2);
    assert.deepEqual(result.member_device_status_counts,{online:1,offline:0,unknown:0});assert.equal(result.live_data_writes,0);
    assert.equal(result.registration_snapshots_complete,true);assert.equal(result.registry_reference_complete,true);
    assert(f.requests.some(([r])=>r.includes('cursor=not_a_cursor')));assert.equal(result.account_id,ACCOUNT);
});
test('harness rejects leaked credentials, omitted members, second-based timestamps and expired-online claims',async()=>{
    for(const key of ['leak','omit','seconds','expired','drift','anonymousAllowed','negativeAllowed']) {
        const f=fake();f.control[key]=true;await assert.rejects(()=>runReadOnly(f.io),undefined,key);
    }
});
test('partial registrar evidence is reported unknown and explicitly not marked available',async()=>{
    const f=fake();f.control.partial=true;const result=await runReadOnly(f.io);
    assert.equal(result.registration_snapshots_complete,false);assert.equal(result.registry_reference_complete,false);
    assert.deepEqual(result.member_device_status_counts,{online:0,offline:0,unknown:1});
});
test('runtime allowlist cannot mutate users/devices or access a different account',()=>{
    assert.equal(apiTarget('PUT','user_auth'),'http://127.0.0.1:8000/v2/user_auth');
    for(const [method,url] of [['POST','members/devices'],['PUT','users'],['DELETE','devices/'+deviceId],
        ['GET','../accounts/'+'b'.repeat(32)+'/members/devices'],['GET','devices/'+deviceId]])assert.throws(()=>apiTarget(method,url));
});
