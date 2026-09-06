#!/usr/bin/env node
'use strict';
// Node-only fixture coverage for the isolated browser harness. Never launches a browser.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), assert = require('node:assert/strict');
const h = require('./test-monster-artifact-browser.cjs');
process.umask(0o077);
const temp = fs.mkdtempSync(path.join(os.tmpdir(),'monster-artifact-browser-harness.'));
const H = h.hash('fixture'), SOURCE = h.hash('original-source'), clone = value => JSON.parse(JSON.stringify(value));
const inputs = {version:1,repo_root:temp + '/repo',artifact_root:temp + '/artifact',
    build_receipt:{path:temp + '/build.json',sha256:H,format:'guarded-build-v1'},
    readback_receipt:{path:temp + '/readback.json',sha256:H,format:'guarded-readback-v1'},artifact_sha256:H,
    toolchain:{node_sha256:H,playwright_root:temp + '/tools/playwright',playwright_package_sha256:H,browser_executable:temp + '/tools/browser',browser_sha256:H},
    output_root:temp + '/outputs',require_acdc:true};
const report = {status:'passed',deployed:false,artifact_sha256:H,source_sha256:SOURCE,configuration_sha256:H,preloads:['core','auth','acdc']};
function wrapper(mode) {
    const fixed = {source_sha256:SOURCE,gulp_sha256:H}, fingerprint = {text:'original-input=fixture\n',sha256:h.hash('original-input=fixture\n')};
    return {mode,status:'passed',source:temp + '/source',commands:[{exit_code:0,signal:null,spawn_error:null,finished:'2026-01-01T00:00:00.000Z'}],
        inputs_before:clone(fixed),inputs:clone(fixed),fingerprint_before:clone(fingerprint),fingerprint_after:clone(fingerprint),helpers_before:{'builder.cjs':H},helpers_after:{'builder.cjs':H}};
}
function evidence() { return {build:wrapper('build'),readback:{...wrapper('readback'),actual_build_receipt_sha256:H,artifact:clone(report)}}; }
const preloads = ['core','auth','acdc'], before = {'index.html':H,'js/main.js':H,'js/config.js':H,'VERSION':H,
    'apps/acdc/app.js':H,'apps/acdc/views/state.html':H,'apps/core/VERSION':H,'apps/auth/style/app.css':H,'apps/core/submodules/alerts/alerts.js':H};
function request(url, method = 'GET', headers = {}, payload) { return {url,method,headers,...(payload === undefined ? {} : {body:JSON.stringify(payload)})}; }
function state(api = 'http://api.fixture.invalid/custom/v2/') { return h.mockState(api,'9.8.7-fixture'); }
function endpoint(s, suffix = '') { return s.origin + s.queueStatus + suffix; }
function probe(s) { h.planRequest(request(endpoint(s,'?runtime_only=true&queue_id=' + h.IDS.queue + '&action=login')),before,preloads,s); return s; }
function payload(version = '9.8.7-fixture') { return {data:{action:'login',queue_id:h.IDS.queue,runtime_only:true,ui_metadata:{version,ui:'monster-ui'}}}; }
let groups = 0;
function test(name, fn) { fn(); groups++; console.log('PASS ' + name); }
(async () => { try {
    let completeHeaders = 0;
    const raw = await h.browserRequest({url:() => h.ORIGIN + '/',method:() => 'GET',postData:() => null,
        headers:() => ({}),allHeaders:async () => { completeHeaders++; return {cookie:'synthetic-fixture'}; }});
    assert.equal(completeHeaders,1); assert.throws(() => h.planRequest(raw,before,preloads,null),/credentials/);
    const source = fs.readFileSync(path.join(__dirname,'test-monster-artifact-browser.cjs'),'utf8');
    assert(source.includes('planRequest(await browserRequest(request),before,evidence.preloads,state)'));
    groups++; console.log('PASS browser adapter uses complete headers, including a Cookie missing from summary headers');
    test('import is browser-free; explicit exact input schema', () => {
        assert(!Object.keys(require.cache).some(file => /node_modules\/playwright/.test(file)));
        assert.deepEqual(h.validateInputs(clone(inputs)),inputs);
        for (const change of [x => x.extra = true,x => delete x.version,x => x.version = 2,x => x.require_acdc = 'true',
            x => x.artifact_root = 'relative',x => x.repo_root += '/..',x => x.artifact_sha256 = 'bad',
            x => x.build_receipt.format = '/arbitrary/json/pointer',x => x.toolchain.extra = 'bad',x => x.toolchain.browser_executable = '/']) {
            const value = clone(inputs); change(value); assert.throws(() => h.validateInputs(value));
        }
    });
    test('output cannot overlap any evidence/artifact/repository/tool input', () => {
        for (const output of [inputs.artifact_root,inputs.artifact_root + '/out',temp,inputs.repo_root + '/out',inputs.build_receipt.path,
            inputs.toolchain.playwright_root + '/out',inputs.toolchain.browser_executable]) {
            assert.throws(() => h.validateInputs({...clone(inputs),output_root:output}),/overlap/i);
        }
        const value = clone(inputs); value.readback_receipt.path = value.build_receipt.path; assert.throws(() => h.validateInputs(value),/distinct/);
    });
    test('guard requires exact limits and a distinct OS network namespace', () => {
        const member = '0::/system.slice/kazoo-validation-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.service';
        h.validateGuard(member,clone(h.LIMITS),'net:[12]','net:[10]');
        assert.throws(() => h.validateGuard('0::/',h.LIMITS,'net:[12]','net:[10]'),/guard/);
        assert.throws(() => h.validateGuard(member,h.LIMITS,'net:[10]','net:[10]'),/namespace/);
        assert.throws(() => h.validateGuard(member,h.LIMITS,'unknown','net:[10]'),/namespace/);
        for (const key of Object.keys(h.LIMITS)) { const limits = clone(h.LIMITS); limits[key] = 'unexpected'; assert.throws(() => h.validateGuard(member,limits,'net:[12]','net:[10]'),/limits/); }
    });
    test('guarded original compilation and readback bindings remain distinct from new verification', () => {
        const {build,readback} = evidence(), bound = h.bindEvidence(inputs,build,readback);
        assert.equal(bound.original_compilation.source_sha256,SOURCE);
        assert.deepEqual(bound.original_compilation.fingerprint,build.fingerprint_before);
        assert.deepEqual(bound.original_compilation.helpers,build.helpers_before);
        assert.equal(bound.acdc_selected,true); assert.deepEqual(bound.preloads,['acdc','auth','core']);
        assert(!Object.hasOwn(bound.original_compilation,'current_verification_inputs'));
    });
    test('original failed/incomplete/changed build receipts are never adopted as success', () => {
        for (const change of [x => x.status = 'running',x => x.mode = 'stage',x => x.commands = [],x => x.commands[0].exit_code = 1,
            x => x.commands[0].signal = 'SIGKILL',x => delete x.commands[0].finished,x => x.inputs.source_sha256 = H,
            x => x.fingerprint_after.sha256 = H,x => {x.fingerprint_before.sha256 = H;x.fingerprint_after.sha256 = H;},x => x.helpers_before = null,
            x => {x.helpers_before = {};x.helpers_after = {};},x => x.helpers_after['builder.cjs'] = SOURCE,
            x => delete x.helpers_after['builder.cjs'],x => x.helpers_after['added.cjs'] = H]) {
            const {build,readback} = evidence(); change(build); assert.throws(() => h.bindEvidence(inputs,build,readback));
        }
    });
    test('readback must match original build, source, artifact and canonical selection', () => {
        for (const change of [x => x.status = 'failed',x => x.actual_build_receipt_sha256 = SOURCE,x => x.source += '-other',
            x => x.artifact.source_sha256 = H,x => x.artifact.artifact_sha256 = SOURCE,x => x.artifact.deployed = true,
            x => x.artifact.preloads = ['core','auth'],x => x.artifact.preloads.push('acdc'),x => x.artifact.preloads = ['core','acdc']]) {
            const {build,readback} = evidence(); change(readback); assert.throws(() => h.bindEvidence(inputs,build,readback));
        }
    });
    test('direct production/artifact result adapters and explicit non-ACDC selection', () => {
        const direct = clone(inputs); direct.build_receipt.format = 'production-result'; direct.readback_receipt.format = 'artifact-result'; direct.require_acdc = false;
        const build = {status:'production_build_completed',deployed:false,profile:'fixture-profile',inputs:{source:SOURCE}};
        const r = {...clone(report),preloads:['core','auth']}, bound = h.bindEvidence(direct,build,r);
        assert.equal(bound.acdc_selected,false); assert.equal(bound.original_compilation.fingerprint,null);
        assert.deepEqual(bound.original_compilation.inputs,build.inputs);
        assert.throws(() => h.bindEvidence({...direct,require_acdc:true},build,r),/ACDC/);
        assert.throws(() => h.bindEvidence(direct,{...build,status:'running'},r));
        assert.throws(() => h.bindEvidence(direct,{...build,inputs:{source:H}},r),/source/);
    });
    test('evidence digests and regular-file identity gate actual files', () => {
        const file = temp + '/evidence.json'; fs.writeFileSync(file,'{"status":"fixture"}\n',{mode:0o600});
        const digest = h.fileHash(file); assert.deepEqual(h.readJson(file,digest),{status:'fixture'});
        assert.throws(() => h.readJson(file,H),/hash/); fs.appendFileSync(file,' '); assert.throws(() => h.readJson(file,digest),/hash/);
        fs.chmodSync(file,0o644); assert.throws(() => h.readJson(file),/Unsafe/); fs.chmodSync(file,0o600);
        fs.symlinkSync(file,temp + '/link.json'); assert.throws(() => h.readJson(temp + '/link.json'),/Symlink/);
        fs.linkSync(file,temp + '/hard.json'); assert.throws(() => h.readJson(temp + '/hard.json'),/Unsafe/);
        assert.equal(fs.readFileSync(file,'utf8'),'{"status":"fixture"}\n ');
    });
    test('symlink/writable ancestors reject without following or changing originals', () => {
        const real = temp + '/real'; fs.mkdirSync(real,{mode:0o700}); fs.writeFileSync(real + '/safe.json','{}',{mode:0o600});
        fs.symlinkSync(real,temp + '/ancestor'); assert.throws(() => h.readJson(temp + '/ancestor/safe.json'),/Symlink/);
        fs.chmodSync(real,0o777); assert.throws(() => h.readJson(real + '/safe.json'),/Writable/); fs.chmodSync(real,0o700);
        assert.equal(fs.readFileSync(real + '/safe.json','utf8'),'{}');
    });
    test('API routing derives HTTPS, port, nested prefix and same-origin bases', () => {
        for (const base of ['https://api.fixture.invalid:9443/nested/v2/',h.ORIGIN + '/api/v2/','/v2/']) {
            const s = state(base), path = [...s.listings.keys()][0], plan = h.planRequest(request(s.origin + path + '?paginate=false'),before,preloads,s);
            assert.equal(plan.entry.kind,'synthetic_backend_mock'); assert.equal(plan.response.status,200);
        }
        for (const value of ['https://u:p@api.fixture.invalid/v2/','https://api.fixture.invalid/v2/?token=x','file:///tmp/','https://api.fixture.invalid/v2/#x','https://api.fixture.invalid/v2','https://api.fixture.invalid/%2f/']) assert.throws(() => h.apiBase(value));
    });
    test('version comes from actual VERSION data, not a deployment constant', () => {
        assert.equal(h.versionFrom(Buffer.from('\n9.8.7-fixture\ntag\n')),'9.8.7-fixture');
        assert.throws(() => h.versionFrom(Buffer.from(''))); assert.throws(() => h.versionFrom(Buffer.from('<invalid>')));
        const s = probe(state()), plan = h.planRequest(request(endpoint(s),'POST',{},payload()),before,preloads,s);
        assert.equal(plan.mutation.payload.data.ui_metadata.version,'9.8.7-fixture');
        const wrong = probe(state()); assert.throws(() => h.planRequest(request(endpoint(wrong),'POST',{},payload('different')),before,preloads,wrong),/payload/);
    });
    test('artifact route is exact bytes only; traversal and preload fallbacks reject', () => {
        assert.equal(h.planRequest(request(h.ORIGIN + '/'),before,preloads,null).file,'index.html');
        assert.equal(h.planRequest(request(h.ORIGIN + '/js/main.js?bust=123'),before,preloads,null).file,'js/main.js');
        assert.equal(h.planRequest(request(h.ORIGIN + '/apps/core/submodules/alerts/alerts.js'),before,preloads,null).file,'apps/core/submodules/alerts/alerts.js');
        for (const target of ['/missing.js','/apps/acdc/app.js','/apps/acdc/views/state.html','/apps/core/VERSION','/apps/auth/style/app.css',
            '/dir/../index.html','/%2e%2e/index.html','/dir%2f..%2findex.html','/js/main.js?token=hidden','/js/main.js?v=a&v=b','/js/main.js?_=bad']) {
            assert.throws(() => h.planRequest(request(h.ORIGIN + target),before,preloads,null));
        }
        assert.throws(() => h.planRequest(request(h.ORIGIN + '/js/main.js','PUT'),before,preloads,null),/mutation/);
    });
    test('API needs post-boot fixture state; unknown origins/accounts and credential URLs reject', () => {
        const s = state(); assert.throws(() => h.planRequest(request(endpoint(s)),before,preloads,null));
        for (const url of [endpoint(s).replace(h.IDS.account,'e'.repeat(32)),endpoint(s).replace(h.IDS.agent,'f'.repeat(32)),
            'http://other.fixture.invalid/resource','http://u:p@monster-artifact.invalid/']) assert.throws(() => h.planRequest(request(url),before,preloads,s));
    });
    test('no credentials, except exact undefined literal only on synthetic API routes', () => {
        const s = state(); assert.equal(h.planRequest(request(endpoint(s),'GET',{'x-auth-token':'undefined'}),before,preloads,s).entry.mock_undefined_auth_header,true);
        for (const headers of [{'x-auth-token':'real-looking-token'},{authorization:''},{cookie:''},{origin:'https://foreign.fixture.invalid'}]) {
            assert.throws(() => h.planRequest(request(endpoint(s),'GET',headers),before,preloads,s));
        }
        assert.throws(() => h.planRequest(request(h.ORIGIN + '/','GET',{'x-auth-token':'undefined'}),before,preloads,s));
    });
    test('explicit cosmetic font omission never permits general external traffic', () => {
        const exact = 'https://fonts.googleapis.com/css?family=Source+Sans+Pro:300,400,600,700';
        assert.equal(h.planRequest(request(exact),before,preloads,null).entry.kind,'cosmetic_external_mock');
        for (const url of [exact + '&token=x',exact.replace('/css?','/css2?'),'https://fonts.gstatic.com/font.woff2']) assert.throws(() => h.planRequest(request(url),before,preloads,null));
        assert.throws(() => h.planRequest(request(exact,'POST'),before,preloads,null));
    });
    test('preflight only permits exact synthetic GET/selected POST and known headers', () => {
        const s = state(), headers = {origin:h.ORIGIN,'access-control-request-method':'POST','access-control-request-headers':'content-type,x-auth-token'};
        assert.equal(h.planRequest(request(endpoint(s),'OPTIONS',headers),before,preloads,s).response.status,204);
        for (const changed of [{...headers,'access-control-request-method':'DELETE'},{...headers,'access-control-request-headers':'authorization'}]) assert.throws(() => h.planRequest(request(endpoint(s),'OPTIONS',changed),before,preloads,s));
        const list = s.origin + [...s.listings.keys()][0] + '?paginate=false'; assert.throws(() => h.planRequest(request(list,'OPTIONS',headers),before,preloads,s));
    });
    test('only one exact selected runtime-only Login mutation; no legacy/roster/global actions', () => {
        for (const change of [p => delete p.data.runtime_only,p => p.data.runtime_only = false,p => p.data.action = 'logout',p => p.data.queue_id = h.IDS.otherQueue,p => p.data.extra = true]) {
            const p = payload(), s = probe(state()); change(p); assert.throws(() => h.planRequest(request(endpoint(s),'POST',{},p),before,preloads,s),/payload/); assert.equal(s.posted,false);
        }
        for (const suffix of ['/status','/roster']) { const s = probe(state()); assert.throws(() => h.planRequest(request(endpoint(s).replace('/queue_status',suffix),'POST',{},payload()),before,preloads,s)); }
        const s = probe(state()); assert.equal(h.planRequest(request(endpoint(s),'POST',{},payload()),before,preloads,s).response.status,202);
        assert.throws(() => h.planRequest(request(endpoint(s),'POST',{},payload()),before,preloads,s),/repeated/);
        for (const verb of ['PUT','PATCH','DELETE']) assert.throws(() => h.planRequest(request(endpoint(state()),verb,{},payload()),before,preloads,state()));
    });
    test('only an exact selected runtime GET permits the first Login POST', () => {
        const s = state(), reject = () => {
            assert.equal(s.runtimeProbeSeen,false); assert.throws(() => h.planRequest(request(endpoint(s),'POST',{},payload()),before,preloads,s),/probe/); assert.equal(s.posted,false);
        };
        reject(); h.planRequest(request(h.ORIGIN + '/'),before,preloads,s); reject();
        h.planRequest(request(endpoint(s)),before,preloads,s); reject(); // Legacy membership inventory is not runtime proof.
        const list = s.origin + [...s.listings.keys()][0] + '?paginate=false'; h.planRequest(request(list),before,preloads,s); reject();
        h.planRequest(request(endpoint(s),'OPTIONS',{'access-control-request-method':'POST'}),before,preloads,s); reject();
        assert.throws(() => h.planRequest(request(endpoint(s,'?runtime_only=true&queue_id=' + h.IDS.otherQueue + '&action=login')),before,preloads,s)); reject();
        probe(s); assert.equal(s.runtimeProbeSeen,true); assert.equal(h.planRequest(request(endpoint(s),'POST',{},payload()),before,preloads,s).response.status,202);
    });
    test('pending acknowledgement and read-only confirmation are separate from agent availability', () => {
        const s = state(), runtime = '?runtime_only=true&queue_id=' + h.IDS.queue + '&action=login';
        let plan = h.planRequest(request(endpoint(s,runtime)),before,preloads,s); assert.equal(JSON.parse(plan.response.body).data.confirmed,false); assert.equal(s.posted,false);
        plan = h.planRequest(request(endpoint(s),'POST',{},payload()),before,preloads,s); const pending = JSON.parse(plan.response.body).data;
        assert.equal(pending.state,'pending'); assert.equal(pending.runtime_observed,false); assert.equal(pending.confirmed,false);
        h.planRequest(request(endpoint(s,runtime)),before,preloads,s); assert.equal(s.pendingPollSeen,true); s.allowConfirmed = true;
        const confirmed = JSON.parse(h.planRequest(request(endpoint(s,runtime)),before,preloads,s).response.body).data;
        assert.equal(confirmed.state,'confirmed'); assert.equal(confirmed.agent_status,'paused'); assert.equal(confirmed.queue_id,h.IDS.queue);
        const global = s.origin + [...s.listings.keys()].find(p => p.endsWith('/status'));
        assert.equal(JSON.parse(h.planRequest(request(global),before,preloads,s).response.body).data[h.IDS.agent],'ready');
    });
    test('every late page/console/route/request/WebSocket error fails the result', () => {
        const clean = {route_errors:[],page_errors:[],request_failures:[],websockets:[],console:[]}; h.cleanRun(clean);
        for (const key of ['route_errors','page_errors','request_failures','websockets']) { const r = clone(clean); r[key].push('fixture'); assert.throws(() => h.cleanRun(r)); }
        const error = clone(clean); error.console.push({type:'error',text:'fixture'}); assert.throws(() => h.cleanRun(error));
        const warning = clone(clean); warning.console.push({type:'warning',text:'recorded'}); h.cleanRun(warning);
    });
    test('new result directory does not overwrite retained failed/incomplete evidence', () => {
        fs.mkdirSync(inputs.output_root,{mode:0o700}); const first = h.newOutput(inputs.output_root), second = h.newOutput(inputs.output_root);
        assert.notEqual(first,second); const old = first + '/receipt.json'; h.saveReceipt(old,{status:'running'}); const running = h.fileHash(old);
        h.saveReceipt(second + '/receipt.json',{status:'failed',error:'fixture'}); assert.equal(h.fileHash(old),running);
        const failed = h.fileHash(second + '/receipt.json'); const third = h.newOutput(inputs.output_root); h.saveReceipt(third + '/receipt.json',{status:'passed'});
        assert.equal(h.fileHash(second + '/receipt.json'),failed); assert.equal(fs.statSync(old).mode & 0o777,0o600);
    });
    test('diagnostics remove URL credentials/query tokens without suppressing error records', () => {
        const cleaned = h.clean('Failure https://user:pass@fixture.invalid/path?token=hidden password=hidden');
        assert(cleaned.includes('Failure')); assert(!cleaned.includes('pass@') && !cleaned.includes('token=hidden') && !cleaned.includes('password=hidden'));
    });
    console.log('PASS ' + groups + ' isolated artifact-browser harness groups (no browser/network/live backend)');
} finally {
    assert(path.dirname(temp) === os.tmpdir() && path.basename(temp).startsWith('monster-artifact-browser-harness.'));
    fs.rmSync(temp,{recursive:true,force:true});
} })().catch(error => { console.error(error); process.exitCode = 1; });
