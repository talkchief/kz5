'use strict';
// Private candidate acceptance. GETs only after existing MASTER authentication.
// Importing does not read secrets, fetch, authenticate, or write files.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {buildSpec,ENDPOINT}=require('./openapi-overlay.cjs');
const Ajv=require('../../api-docs-tooling/node_modules/ajv');
const ACCOUNT='302ae5a70c403124f764cbc54229cfcd',EXPECTED_MEMBERS=31;
const id=v=>typeof v==='string'&&/^[a-f0-9]{32}$/.test(v);
const canonical=v=>JSON.stringify(v,(_k,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])):x);
const hash=v=>crypto.createHash('sha256').update(canonical(v)).digest('hex');
const sortedEntries=map=>[...map].sort(([a],[b])=>a.localeCompare(b));
function validators() {
    const spec=buildSpec(),ajv=new Ajv({strict:false,validateFormats:false});
    return {spec,page:ajv.compile({components:spec.components,$ref:'#/components/schemas/MemberDevicesPage'})};
}
function apiTarget(method,relative,anonymous=false) {
    assert(method==='GET'||method==='PUT'&&relative==='user_auth','Only authentication may write');
    assert(relative==='user_auth'||relative===''||relative==='users?paginate=false'||relative==='devices?paginate=false'
        ||relative==='devices/status'||/^members\/devices(?:\?(?:page_size|cursor|paginate)=[A-Za-z0-9_.%=-]+(?:&(?:page_size|cursor)=[A-Za-z0-9_.%=-]+)*)?$/.test(relative),'Out-of-scope read');
    assert(!anonymous||method==='GET'&&relative==='members/devices','Only anonymous endpoint negative is allowed');
    return 'http://127.0.0.1:8000/v2/'+(relative==='user_auth'?relative:'accounts/'+ACCOUNT+(relative?'/'+relative:''));
}
function catalog(response,label) {
    assert(response.status===200&&response.body.status==='success'&&Array.isArray(response.body.data)
        &&response.body.data.length<=1000&&!response.body.next_start_key,'Incomplete legacy '+label+' catalog');
    const map=new Map();for(const row of response.body.data){assert(id(row.id)&&!map.has(row.id),'Invalid/duplicate '+label+' ID');map.set(row.id,row);}
    return map;
}
function statusMap(response,devices) {
    if(response.status===503)return null;
    assert(response.status===200&&response.body.status==='success'&&Array.isArray(response.body.data)&&response.body.data.length<=1000,'Invalid registry reference');
    const map=new Map();for(const row of response.body.data) {
        assert(id(row.device_id)&&devices.has(row.device_id)&&!map.has(row.device_id)&&typeof row.registrable==='boolean','Registry reference identity mismatch');
        assert(row.registered===undefined||typeof row.registered==='boolean','Invalid registry reference status');map.set(row.device_id,row);
    }
    assert(map.size===devices.size,'Registry reference omitted devices');return map;
}
function evaluatePage(response,validate,users,devices,seen,now) {
    assert(response.status===200&&response.body.status==='success','Members endpoint unavailable');
    assert(/(?:^|,)\s*no-store\s*(?:,|$)/i.test(response.cacheControl||''),'Fresh endpoint must return no-store');
    const data=response.body.data;assert(validate(data),'Response violates private members schema');
    assert(data.count===data.items.length&&data.items.length<=data.page_size,'Member page count mismatch');
    assert(data.device_inventory.complete===true&&data.device_inventory.count===devices.size,'Unexpected incomplete/mismatched account device inventory');
    const snapshot=data.registration_snapshot;
    assert(snapshot.observed_at_ms>=snapshot.started_at_ms&&snapshot.started_at_ms>=response.startedAt-2000
        &&snapshot.observed_at_ms<=response.finishedAt+2000&&now-snapshot.observed_at_ms<60000,'Stale/invalid observation timestamp');
    let previous='';
    for(const member of data.items) {
        assert(users.has(member.id)&&!seen.has(member.id)&&member.id>previous,'Unknown, duplicate, or unordered member');previous=member.id;
        assert(member.enabled===(users.get(member.id).enabled!==false),'Member enabled state changed');
        assert(member.devices_complete===true&&member.device_count===member.devices.length,'Member device completeness/count mismatch');
        const expected=[...devices.values()].filter(d=>d.owner_id===member.id).map(d=>d.id).sort();
        assert(hash(member.devices.map(d=>d.id).sort())===hash(expected),'Member device association mismatch');
        for(const device of member.devices) {
            const reference=devices.get(device.id),registration=device.registration;
            assert(device.enabled===(reference.enabled!==false),'Device enabled state mismatch');
            if(reference.device_type!==undefined)assert(device.type===reference.device_type,'Device type mismatch');
            assert(registration.observed_at_ms===snapshot.observed_at_ms,'Device status observation differs from snapshot');
            if(registration.status==='online'&&registration.reason==='registered')assert(registration.expires_at_ms>snapshot.observed_at_ms,'Expired binding reported online');
            if(!snapshot.complete)assert(registration.status==='unknown','Incomplete registrar evidence cannot prove online or offline');
        }
        seen.set(member.id,member);
    }
    return data;
}
async function runReadOnly(io) {
    const {spec,page}=validators(),checks=[];
    const anonymous=await io.get('members/devices',true);assert([401,403].includes(anonymous.status),'Anonymous request not rejected');checks.push('anonymous_rejected');
    const users=catalog(await io.get('users?paginate=false'),'users'),devices=catalog(await io.get('devices?paginate=false'),'devices');
    assert(users.size===EXPECTED_MEMBERS,'Expected MASTER31-member baseline changed');
    const beforeStatus=statusMap(await io.get('devices/status'),devices),seen=new Map(),snapshots=[],cursors=new Set();
    let cursor,previousLast='';
    for(let n=0;n<3;n++) {
        const relative='members/devices?page_size=25'+(cursor?'&cursor='+encodeURIComponent(cursor):'');
        const response=await io.get(relative),data=evaluatePage(response,page,users,devices,seen,io.now());
        if(data.items.length)assert(data.items[0].id>previousLast,'Member ordering regressed across pages');
        previousLast=data.items.at(-1)?.id||previousLast;snapshots.push(data.registration_snapshot);
        if(!data.has_more){cursor=undefined;break;}
        assert(data.next_cursor&&!cursors.has(data.next_cursor)&&data.items.length>0,'Invalid/repeated continuation');
        cursor=data.next_cursor;cursors.add(cursor);
    }
    assert(!cursor&&seen.size===users.size,'Member pagination incomplete');
    assert(hash([...seen.keys()].sort())===hash([...users.keys()].sort()),'A member, possibly device-less, was omitted');checks.push('all_members_and_owned_devices');
    const zeroMembers=[...users.keys()].filter(u=>![...devices.values()].some(d=>d.owner_id===u));
    assert(zeroMembers.every(u=>seen.get(u).device_count===0&&seen.get(u).devices.length===0),'Device-less members missing');checks.push('zero_device_members_preserved');
    for(const query of ['cursor=not_a_cursor','page_size=0','page_size=101','page_size=1.5','paginate=false']) {
        assert((await io.get('members/devices?'+query)).status===400,'Malformed query not rejected');
    }
    const wrongAccountCursor=Buffer.from(JSON.stringify([1,'7807ad61761269a1ccec833dde63f621','1'.repeat(32)])).toString('base64url');
    assert((await io.get('members/devices?cursor='+wrongAccountCursor)).status===400,'Different-account cursor not rejected');checks.push('malformed_and_cross_account_cursors_rejected');
    const afterStatus=statusMap(await io.get('devices/status'),devices);
    const usersAfter=catalog(await io.get('users?paginate=false'),'users'),devicesAfter=catalog(await io.get('devices?paginate=false'),'devices');
    assert(hash(sortedEntries(users))===hash(sortedEntries(usersAfter))&&hash(sortedEntries(devices))===hash(sortedEntries(devicesAfter)),'Catalog changed during read-only acceptance; retry after review');checks.push('catalogs_unchanged');
    let statusReferenceComplete=beforeStatus!==null&&afterStatus!==null;
    if(statusReferenceComplete) {
        assert(hash(sortedEntries(beforeStatus))===hash(sortedEntries(afterStatus)),'Registrations changed during acceptance; comparison is inconclusive');
        for(const member of seen.values())for(const device of member.devices) {
            const registration=device.registration,reference=afterStatus.get(device.id);
            if(registration.status==='online')assert(reference.registered===true,'Online status disagrees with stable cluster registry');
            if(registration.status==='offline'&&registration.reason==='not_registered')assert(reference.registered===false,'Offline absence disagrees with stable registry');
            // Summary reference may include expired rows awaiting cleanup. The
            // detailed expiry branch is source/unit-tested, not independently
            // proven by that summary. Never disguise this coverage boundary.
        }
        checks.push('stable_registry_reference_checked');
    }
    const statuses={online:0,offline:0,unknown:0};for(const member of seen.values())for(const d of member.devices)statuses[d.registration.status]++;
    return {result:'PASS',profile:'members_devices_readonly',account_id:ACCOUNT,checks,member_count:seen.size,
        zero_device_member_count:zeroMembers.length,device_catalog_count:devices.size,member_device_status_counts:statuses,
        page_count:snapshots.length,registration_snapshots_complete:snapshots.every(s=>s.complete),registry_reference_complete:statusReferenceComplete,
        observed_at_ms:snapshots.map(s=>s.observed_at_ms),catalog_sha256:hash({users:sortedEntries(users),devices:sortedEntries(devices)}),
        source_sha256:spec.paths[ENDPOINT].get['x-source-sha256'],live_data_writes:0,authentication_only_write:true,
        coverage_limits:['MASTER-admin auth; restricted-token scope not proven','No SIP calls or registration changes',
            'Exact expiry values source/unit-tested; live independent reference is correlated registrar summary']};
}
function protectedSecrets() {
    const file='/etc/kazoo/installer-secrets.env',s=fs.lstatSync(file);
    assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===384&&s.size<65536,'Protected existing credentials required');
    return Object.fromEntries(fs.readFileSync(file,'utf8').split('\n').filter(l=>l&&!l.startsWith('#')).map(line=>{
        const n=line.indexOf('=');assert(n>0);const key=line.slice(0,n);let value=line.slice(n+1);assert(/^[A-Z][A-Z0-9_]*$/.test(key));
        if(value.startsWith("'")){assert(value.endsWith("'")&&!value.slice(1,-1).includes("'"));value=value.slice(1,-1);}
        else if(value.startsWith('"'))value=JSON.parse(value);assert(!/[\r\n]/.test(value));return [key,value];
    }));
}
async function runtime(arm,run) {
    assert(arm==='--allow-authentication-only'&&path.isAbsolute(run),'Explicit authentication-only flag and private receipt directory required');
    const stat=fs.lstatSync(run);assert(stat.isDirectory()&&!stat.isSymbolicLink()&&stat.uid===0&&(stat.mode&511)===448
        &&fs.realpathSync(run)===run&&run.startsWith('/var/log/kazoo-acceptance/'),'Private root-owned0700 directory required');
    const out=path.join(run,'members-devices-readonly.json');assert(!fs.existsSync(out),'Never overwrite an acceptance receipt');
    const secrets=protectedSecrets();let token;
    async function request(method,relative,data,anonymous=false) {
        const url=apiTarget(method,relative,anonymous),startedAt=Date.now();
        const response=await fetch(url,{method,headers:{'Content-Type':'application/json',...(!anonymous&&token?{'X-Auth-Token':token}:{})},
            ...(data===undefined?{}:{body:JSON.stringify({data})}),redirect:'error',signal:AbortSignal.timeout(20000)});
        const bytes=Buffer.from(await response.arrayBuffer());assert(bytes.length<4*1024*1024,'Oversized response');
        return {status:response.status,body:JSON.parse(bytes.toString()),startedAt,finishedAt:Date.now(),cacheControl:response.headers.get('cache-control')};
    }
    const auth=await request('PUT','user_auth',{credentials:crypto.createHash('md5').update((secrets.KAZOO_MASTER_ADMIN_USER||'admin')+':'+secrets.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex'),method:'md5',realm:secrets.KAZOO_MASTER_ACCOUNT_REALM});
    assert([200,201].includes(auth.status)&&auth.body.data?.account_id===ACCOUNT&&auth.body.auth_token,'Expected existing MASTER authentication');token=auth.body.auth_token;
    const account=await request('GET','');assert(account.status===200&&account.body.data.id===ACCOUNT&&account.body.data.realm===secrets.KAZOO_MASTER_ACCOUNT_REALM,'MASTER account identity mismatch');
    const receipt=await runReadOnly({get:(relative,anonymous)=>request('GET',relative,undefined,anonymous),now:()=>Date.now()});
    fs.writeFileSync(out,JSON.stringify(receipt,null,2)+'\n',{mode:384,flag:'wx'});console.log(JSON.stringify(receipt));
}
module.exports={ACCOUNT,EXPECTED_MEMBERS,apiTarget,validators,catalog,statusMap,evaluatePage,runReadOnly};
if(require.main===module)runtime(...process.argv.slice(2)).catch(error=>{
    console.error('Members read-only acceptance FAIL ('+(error.code==='ERR_ASSERTION'?'guard_or_contract':error.name==='TimeoutError'?'timeout':'runtime')+'); no live data writes permitted.');process.exitCode=1;
});
