#!/usr/bin/env node
'use strict';
// Read-only Crossbar requests (except normal login authentication). Output is
// an exclusive root-only evidence file, never credentials or a restore plan.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const {validateState, ACCOUNT, PROTECTED_DEVICE, PROTECTED_USER} = require('./provision-live-test-agents.cjs');
const ID = /^[a-f0-9]{32}$/;
function check(ok, message) { if (!ok) throw Error(message); }
function projectMembership(agent, response, protectedUser) {
    check(response?.status==='success','Queue membership envelope is not successful');
    const present = Object.hasOwn(response,'data'), membership = response.data;
    if (agent.index === 'protected') {
        check(protectedUser?.id === PROTECTED_USER, 'Protected user identity missing in membership proof');
        if (!present) {
            check(!Object.hasOwn(protectedUser,'queues'), 'Missing protected queue_status contradicts user document');
            return {membership_kind:'absent',queue_memberships:null};
        }
        check(Array.isArray(protectedUser.queues) && Array.isArray(membership) &&
            JSON.stringify([...protectedUser.queues].sort())===JSON.stringify([...membership].sort()),
            'Protected queue_status contradicts user document');
    }
    check(present && Array.isArray(membership) && membership.every(id=>typeof id==='string' && ID.test(id)) &&
        new Set(membership).size===membership.length, `Invalid queue membership response at agent ${agent.index}`);
    return {membership_kind:'present',queue_memberships:[...membership].sort()};
}
function privateText(file) {
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {const s = fs.fstatSync(fd); check(s.isFile() && s.uid === 0 && s.gid === 0 && (s.mode & 0o777) === 0o600, 'Protected input permissions invalid');
        return fs.readFileSync(fd, 'utf8');} finally {fs.closeSync(fd);}
}
function checkpoint(state) {
    const runtime = fs.lstatSync('/run/kazoo-live-test-agents');
    check(runtime.isDirectory() && !runtime.isSymbolicLink() && runtime.uid === 0 && runtime.gid === 0 &&
        (runtime.mode & 0o777) === 0o700, 'Runtime directory ownership/mode invalid');
    check(privateText('/run/kazoo-live-test-agents/preserve-agent-status').trim() === state.deployment_id, 'Preserve marker does not match deployment');
    const run = (file,args) => cp.execFileSync(file,args,{encoding:'utf8',timeout:5000,maxBuffer:1048576,stdio:['ignore','pipe','pipe']});
    const unit = Object.fromEntries(run('systemctl',['show','kazoo-live-test-agents.service','-p','MainPID','-p','Restart','-p','ExecStopPost',
        '-p','RuntimeDirectoryPreserve','-p','KillMode']).trim().split('\n').map(line => [line.slice(0,line.indexOf('=')),line.slice(line.indexOf('=')+1)]));
    check(/^\d+$/.test(unit.MainPID) && Number(unit.MainPID)>1, 'Missing supervisor main PID');
    check(unit.Restart === 'on-failure' && unit.RuntimeDirectoryPreserve === 'restart' && unit.KillMode === 'mixed' &&
        /argv\[\]=\/usr\/bin\/bash \/opt\/kz5\/scripts\/run-live-test-agents\.sh --cleanup ;/.test(unit.ExecStopPost), 'Unit restart/cleanup contract changed');
    let children = [];
    try {children = run('ps',['--ppid',unit.MainPID,'-o','pid=,comm=']).trim().split('\n').filter(Boolean).map(line => {
        const [pid,name] = line.trim().split(/\s+/); check(/^\d+$/.test(pid) && /^[A-Za-z0-9_.-]+$/.test(name), 'Invalid child inventory');return {pid:Number(pid),name};});}
    catch (error) {if (error.status !== 1) throw Error('Could not read complete supervisor child inventory');}
    const sipp = children.filter(child => child.name === 'sipp');
    const sockets = run('ss',['-H','-lunp']).trim().split('\n').filter(Boolean).flatMap(line => {
        const fields = line.trim().split(/\s+/), address = fields[3], match = /^(.*):(171[0-2][0-9])$/.exec(address || '');
        if (!match) return [];
        const pids = [...line.matchAll(/pid=(\d+)/g)].map(m => Number(m[1]));
        return [{port:Number(match[2]),owned:match[1] === '127.0.0.40' && pids.length === 1 && sipp.some(p => p.pid === pids[0])}];
    });
    const channels = JSON.parse(run('/usr/local/freeswitch/bin/fs_cli',['-x','show channels as json']));
    const zero = channels && !Array.isArray(channels) && typeof channels === 'object' && channels.row_count === 0 &&
        Object.keys(channels).every(key=>['row_count','rows'].includes(key)) &&
        (!Object.hasOwn(channels,'rows') || (Array.isArray(channels.rows) && channels.rows.length === 0));
    check(zero, 'Complete zero-call evidence not available');
    check(sockets.every(socket => socket.owned), 'A test-phone port is owned by a different process or address');
    return {observed_at:new Date().toISOString(),main_pid:Number(unit.MainPID),child_processes:children,
        sipp_children:sipp.length,phone_sockets:sockets,zero_calls:true,preserve_marker_matches:true,
        runtime_mode:'0700',marker_mode:'0600',restart_contract_verified:true,
        zero_child_restart_preconditions:sipp.length === 0 && sockets.length === 0};
}
async function main(args) {
    if (args.length === 1 && args[0] === '--dry-run') {
        console.log('Read-only plan: authenticate pinned MASTER account; snapshot exact queue roster plus latest reported status and queue memberships for30 owned agents and protected MicroSIP owner. No SIP/service/roster/status writes.'); return;
    }
    if (args.length === 2 && args[0] === '--checkpoint-before') {
        check(process.getuid() === 0 && /^[1-9][0-9]+$/.test(args[1]), 'Use --checkpoint-before EXPECTED_MAIN_PID');
        const state = validateState(JSON.parse(privateText('/etc/kazoo/live-test-agents.json'))), evidence = checkpoint(state);
        check(evidence.main_pid===Number(args[1]) && evidence.zero_child_restart_preconditions, 'Exact original PID/zero-child restart conditions no longer hold');
        console.log(JSON.stringify(evidence));return;
    }
    if (args.length === 3 && args[0] === '--compare') {
        const before=JSON.parse(privateText(path.resolve(args[1]))),after=JSON.parse(privateText(path.resolve(args[2])));
        const stable=s=>({account_id:s.account_id,queue_id:s.queue_id,deployment_id:s.deployment_id,roster:s.roster,agents:s.agents});
        check(before.schema_version===1 && after.schema_version===1 && before.account_id===ACCOUNT && after.account_id===ACCOUNT &&
            JSON.stringify(stable(before))===JSON.stringify(stable(after)), 'Roster or reported agent state/membership changed; do not restore automatically');
        console.log('PASS exact roster and31 reported agent statuses/memberships unchanged; no restore performed');return;
    }
    check(process.getuid() === 0 && args.length === 2 && args[0] === '--snapshot', 'Use --snapshot /root-owned-0700-directory/phone-snapshot-NAME.json');
    const output = path.resolve(args[1]), parent = path.dirname(output), st = fs.lstatSync(parent);
    check(st.isDirectory() && !st.isSymbolicLink() && st.uid === 0 && (st.mode & 0o777) === 0o700 &&
        fs.realpathSync(parent) === parent && /^phone-snapshot-[A-Za-z0-9-]+\.json$/.test(path.basename(output)), 'Snapshot output must be in a canonical root-only0700 directory');
    check(!fs.existsSync(output), 'Snapshot output already exists');
    const state = validateState(JSON.parse(privateText('/etc/kazoo/live-test-agents.json')));
    const runtime = checkpoint(state);
    const markerMatches = privateText('/run/kazoo-live-test-agents/preserve-agent-status').trim() === state.deployment_id;
    check(markerMatches && ID.test(state.queue_id), 'Missing matching preserve-agent-status marker or queue');
    const credentials = new Map(privateText('/etc/kazoo/installer-secrets.env').split('\n').filter(l => l && !l.startsWith('#')).map(l => {
        const n = l.indexOf('='); check(n > 0, 'Malformed protected credentials'); return [l.slice(0,n),l.slice(n+1)];}));
    const user = credentials.get('KAZOO_MASTER_ADMIN_USER'), password = credentials.get('KAZOO_MASTER_ADMIN_PASSWORD'), realm = credentials.get('KAZOO_MASTER_ACCOUNT_REALM');
    check(user && password && realm === state.realm, 'Missing or wrong-account credentials');
    let token;
    const deadline=Date.now()+120000;
    async function request(method, resource, data) {
        check((method === 'PUT' && resource === 'user_auth') || (method === 'GET' && resource.startsWith(`accounts/${ACCOUNT}`)), 'Disallowed snapshot method/scope');
        check(Date.now()<deadline,'Snapshot overall deadline expired');
        const response = await fetch(`http://127.0.0.1:8000/v2/${resource}`, {method,redirect:'error',signal:AbortSignal.timeout(Math.max(1,Math.min(15000,deadline-Date.now()))),
            headers: {'Content-Type':'application/json', ...(token ? {'X-Auth-Token':token} : {})},
            body: data === undefined ? undefined : JSON.stringify({data})}).catch(()=>{throw Error('Snapshot API transport/redirect failed');});
        check(response.ok, `Snapshot API ${method} failed HTTP${response.status}`);
        const chunks=[];let size=0;
        for await (const chunk of response.body) {size+=chunk.length;check(size<=65536,'Snapshot API response too large');chunks.push(chunk);}
        const result=JSON.parse(Buffer.concat(chunks).toString('utf8'));check(result.status==='success','Snapshot API did not report success');return result;
    }
    const auth = await request('PUT', 'user_auth', {credentials:crypto.createHash('md5').update(`${user}:${password}`).digest('hex'), method:'md5', realm});
    check(auth.data?.account_id === ACCOUNT && typeof auth.auth_token === 'string', 'Authentication scope mismatch'); token = auth.auth_token;
    const account = (await request('GET',`accounts/${ACCOUNT}`)).data;
    check(account.id === ACCOUNT && account.realm === state.realm, 'Snapshot account scope mismatch');
    const base = `accounts/${ACCOUNT}`;
    const roster = (await request('GET',`${base}/queues/${state.queue_id}/roster`)).data;
    check(Array.isArray(roster) && roster.every(id => ID.test(id)) && new Set(roster).size === roster.length, 'Invalid exact roster response');
    const agents = [];
    for (const agent of [...state.agents, {index:'protected',user_id:PROTECTED_USER,device_id:PROTECTED_DEVICE}]) {
        const data = (await request('GET',`${base}/agents/${agent.user_id}/status`)).data;
        const status = typeof data === 'string' ? data : data?.status;
        check(typeof status === 'string' && /^[a-z_]{1,32}$/.test(status), 'Unknown reported agent status shape');
        const membership = await request('GET',`${base}/agents/${agent.user_id}/queue_status`);
        const protectedDoc = agent.index==='protected' ? (await request('GET',`${base}/users/${PROTECTED_USER}`)).data : undefined;
        agents.push({index:agent.index,user_id:agent.user_id,device_id:agent.device_id,reported_status:status,
            ...projectMembership(agent,membership,protectedDoc)});
    }
    const snapshot = {schema_version:1,observed_at:new Date().toISOString(),account_id:ACCOUNT,queue_id:state.queue_id,
        deployment_id:state.deployment_id,preserve_marker_matches:true,roster:[...roster].sort(),agents,runtime,
        status_source:'GET agents/{id}/status: latest reported status; not SIP registration or guaranteed transport-independent runtime state',
        mutation_policy:'No roster, agent status, registration or service writes. Evidence only; never automatically restore this snapshot.'};
    const fd = fs.openSync(output, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW,0o600);
    try {fs.writeFileSync(fd,JSON.stringify(snapshot,null,2)+'\n');fs.fsyncSync(fd);} finally {fs.closeSync(fd);}
    console.log(JSON.stringify({snapshot:output,roster_count:roster.length,roster_owned_indices:roster.map(id=>state.agents.find(a=>a.user_id===id)?.index??'other'),
        agents:agents.length,status_counts:agents.reduce((m,a)=>(m[a.reported_status]=(m[a.reported_status]||0)+1,m),{}),preserve_marker_matches:true,mutations:false}));
}
if (require.main===module) main(process.argv.slice(2)).catch(error => {console.error(`Snapshot failed: ${error instanceof SyntaxError ? 'invalid protected JSON' : error.message}`);process.exitCode=1;});
module.exports={projectMembership};
