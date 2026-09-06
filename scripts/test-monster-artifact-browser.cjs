#!/usr/bin/env node
'use strict';
// Isolated actual-artifact browser test. No live target, credentials, build or deployment mode.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const owned = require('./deploy-owned-monster.cjs');
const ORIGIN = 'http://monster-artifact.invalid';
const IDS = Object.freeze({account:'a'.repeat(32), agent:'b'.repeat(32), queue:'c'.repeat(32), otherQueue:'d'.repeat(32)});
const LIMITS = Object.freeze({'memory.max':'402653184','memory.swap.max':'0','memory.oom.group':'1','pids.max':'128','cpu.max':'50000 100000'});
const MIME = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.gif':'image/gif','.woff':'font/woff','.woff2':'font/woff2','.ttf':'font/ttf','.eot':'application/vnd.ms-fontobject','.ico':'image/x-icon'};
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const same = (a,b) => owned.canonical(a) === owned.canonical(b);
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function keys(value, expected) { assert(object(value) && same(Object.keys(value).sort(), [...expected].sort()), 'Unexpected input fields'); }
function sha(value) { assert(typeof value === 'string' && /^[a-f0-9]{64}$/.test(value), 'Invalid SHA-256'); return value; }
function absolute(value) { assert(typeof value === 'string' && path.isAbsolute(value) && path.normalize(value) === value && value !== '/' && !/[\x00-\x1f]/.test(value), 'Invalid absolute path'); return value; }
function overlaps(a,b) { return a === b || a.startsWith(b + '/') || b.startsWith(a + '/'); }
function safeFile(file, maxBytes, privateFile = false) {
    owned.safePath(file); const st = fs.lstatSync(file);
    assert(st.isFile() && st.nlink === 1 && st.size <= maxBytes && (!privateFile || !(st.mode & 0o077)), 'Unsafe or oversized evidence/file');
    return st;
}
function fileHash(file) {
    safeFile(file, 512 * 1024 * 1024);
    const digest = crypto.createHash('sha256'), fd = fs.openSync(file,'r'), buffer = Buffer.alloc(1024 * 1024);
    try { let size; while ((size = fs.readSync(fd,buffer,0,buffer.length,null))) digest.update(buffer.subarray(0,size)); }
    finally { fs.closeSync(fd); } return digest.digest('hex');
}
function readJson(file, expected) {
    safeFile(file, 8 * 1024 * 1024, true); const bytes = fs.readFileSync(file);
    if (expected) assert(hash(bytes) === expected, 'Evidence hash mismatch');
    return JSON.parse(bytes.toString('utf8'));
}
function validateInputs(input) {
    keys(input,['version','repo_root','artifact_root','build_receipt','readback_receipt','artifact_sha256','toolchain','output_root','require_acdc']);
    assert(input.version === 1 && typeof input.require_acdc === 'boolean','Unsupported input version/selection');
    for (const name of ['repo_root','artifact_root','output_root']) absolute(input[name]); sha(input.artifact_sha256);
    for (const [name,formats] of [['build_receipt',['production-result','guarded-build-v1']],['readback_receipt',['artifact-result','guarded-readback-v1']]]) {
        keys(input[name],['path','sha256','format']); absolute(input[name].path); sha(input[name].sha256); assert(formats.includes(input[name].format),'Unknown receipt format');
    }
    keys(input.toolchain,['node_sha256','playwright_root','playwright_package_sha256','browser_executable','browser_sha256']);
    for (const name of ['node_sha256','playwright_package_sha256','browser_sha256']) sha(input.toolchain[name]);
    for (const name of ['playwright_root','browser_executable']) absolute(input.toolchain[name]);
    for (const other of [input.repo_root,input.artifact_root,input.build_receipt.path,input.readback_receipt.path,input.toolchain.playwright_root,input.toolchain.browser_executable]) {
        assert(!overlaps(input.output_root,other),'Output overlaps a protected input');
    }
    assert(input.build_receipt.path !== input.readback_receipt.path,'Receipts must be distinct');
    return input;
}
function validateGuard(membership, limits, netns, hostNetns) {
    assert(/^0::\/system.slice\/kazoo-validation-[a-f0-9-]{36}\.service$/.test(membership), 'Validation guard required');
    assert(same(limits,LIMITS), 'Unexpected resource guard limits');
    assert(/^net:\[\d+\]$/.test(netns) && /^net:\[\d+\]$/.test(hostNetns) && netns !== hostNetns, 'A separate unshare --net namespace is required');
}
function wrapper(report, mode) {
    assert(object(report) && report.mode === mode && report.status === 'passed', 'Guarded receipt is not terminal success');
    absolute(report.source);
    assert(Array.isArray(report.commands) && report.commands.length > 0 && report.commands.every(c => c.exit_code === 0 && c.signal === null && c.spawn_error === null && typeof c.finished === 'string'), 'Unsuccessful/incomplete receipt command');
    assert(object(report.inputs_before) && same(report.inputs_before,report.inputs), 'Original source inputs changed');
    assert(object(report.fingerprint_before) && same(report.fingerprint_before,report.fingerprint_after), 'Original fingerprint changed');
    assert(typeof report.fingerprint_before.text === 'string' && hash(report.fingerprint_before.text) === sha(report.fingerprint_before.sha256), 'Invalid original fingerprint digest');
    assert(object(report.helpers_before) && object(report.helpers_after) && Object.keys(report.helpers_before).length > 0
        && Object.keys(report.helpers_after).length > 0, 'Missing original helper bindings');
    for (const value of Object.values(report.helpers_before)) sha(value);
    for (const value of Object.values(report.helpers_after)) sha(value);
    assert(same(report.helpers_before,report.helpers_after), 'Original invocation helpers changed');
    return sha(report.inputs.source_sha256);
}
function bindEvidence(input, build, readback) {
    let original, report;
    if (input.build_receipt.format === 'guarded-build-v1') {
        const sourceHash = wrapper(build,'build');
        original = {source_sha256:sourceHash,inputs:build.inputs,fingerprint:build.fingerprint_before,helpers:build.helpers_before};
    } else {
        assert(object(build) && build.status === 'production_build_completed' && build.deployed === false && object(build.inputs), 'Production result is not successful');
        original = {source_sha256:sha(build.inputs.source),inputs:build.inputs,profile:build.profile,fingerprint:null,helpers:null};
    }
    if (input.readback_receipt.format === 'guarded-readback-v1') {
        const sourceHash = wrapper(readback,'readback');
        assert(readback.actual_build_receipt_sha256 === input.build_receipt.sha256, 'Readback references a different original build');
        assert(sourceHash === original.source_sha256, 'Readback wrapper source differs from build');
        if (input.build_receipt.format === 'guarded-build-v1') assert(build.source === readback.source, 'Original source roots differ');
        report = readback.artifact;
    } else report = readback;
    assert(object(report) && report.status === 'passed' && report.deployed === false, 'Artifact readback is not successful');
    assert(sha(report.artifact_sha256) === input.artifact_sha256, 'Readback artifact mismatch');
    assert(sha(report.source_sha256) === original.source_sha256, 'Original build/readback source mismatch');
    sha(report.configuration_sha256);
    const preloads = owned.preloadedApps({preloadedApps:report.preloads});
    assert(preloads.includes('core') && preloads.includes('auth'), 'Core/auth preload required for boot');
    assert(!input.require_acdc || preloads.includes('acdc'), 'Required ACDC is not selected');
    return {original_compilation:original,artifact_report:report,preloads:[...preloads].sort(),acdc_selected:preloads.includes('acdc')};
}
function versionFrom(bytes) {
    const version = bytes.toString('utf8').split(/\r?\n/).map(s => s.trim()).find(Boolean);
    assert(typeof version === 'string' && /^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$/.test(version),'Invalid artifact version'); return version;
}
function apiBase(value) {
    assert(typeof value === 'string' && value.length <= 2048,'Missing runtime API URL'); const url = new URL(value,ORIGIN);
    assert(['http:','https:'].includes(url.protocol) && !url.username && !url.password && !url.search && !url.hash && url.pathname.endsWith('/'), 'Invalid runtime API URL');
    assert(!/%(?:2f|5c|00|2e)/i.test(url.pathname) && !url.pathname.includes('\\'), 'Unsafe runtime API prefix'); return url;
}
function safeUrl(value) { try { const u = new URL(value); return u.origin + u.pathname; } catch { return '[invalid-url]'; } }
function clean(value) { return String(value).replace(/\b(?:https?|wss?):\/\/[^\s"'<>]+/g,safeUrl)
    .replace(/\b(?:auth[_-]?token|authorization|password|credentials|cookie|secret)\b["'\s]*[:=][^,}\n]*/gi,'[credential-redacted]').slice(0,1500); }
function query(url) {
    const pairs = [...url.searchParams]; assert(new Set(pairs.map(([key]) => key)).size === pairs.length,'Duplicate request query');
    return Object.fromEntries(pairs.filter(([key,value]) => { if (key === '_') { assert(/^\d{1,16}$/.test(value),'Invalid cache nonce'); return false; } return true; }));
}
function mockState(api, version) {
    const base = apiBase(api), accountPath = base.pathname + 'accounts/' + IDS.account;
    return {origin:base.origin,version,queueStatus:accountPath + '/agents/' + IDS.agent + '/queue_status',posted:false,allowConfirmed:false,pendingPollSeen:false,runtimeProbeSeen:false,
        listings:new Map([[accountPath + '/agents',[{id:IDS.agent,first_name:'Synthetic',last_name:'Agent',enabled:true,queues:[IDS.queue,IDS.otherQueue]}]],
            [accountPath + '/agents/status',{[IDS.agent]:'ready'}],[accountPath + '/agents/stats',{[IDS.agent]:{answered_calls:0,missed_calls:0,total_calls:0}}],
            [accountPath + '/queues',[{id:IDS.queue,name:'Synthetic Queue One'},{id:IDS.otherQueue,name:'Synthetic Queue Two'}]]])};
}
function proof(confirmed, observed = true) { return {account_id:IDS.account,agent_id:IDS.agent,queue_id:IDS.queue,action:'login',runtime_only:true,state:confirmed?'confirmed':'pending',confirmed,
    runtime_member:confirmed,runtime_observed:observed,agent_status:confirmed?'paused':observed?'ready':'unknown'}; }
async function browserRequest(request) {
    // The summary headers() API omits security/cookie headers. Guard the full set.
    return {url:request.url(),method:request.method(),headers:await request.allHeaders(),body:request.postData()};
}
function planRequest(request, before, preloads, state) {
    const rawPath = request.url.replace(/^[a-z]+:\/\/[^/?#]+/i,'').split(/[?#]/)[0];
    assert(!decodeURIComponent(rawPath).split('/').some(part => part === '.' || part === '..') && !request.url.includes('\\'),'Unsafe request path');
    const url = new URL(request.url), method = request.method, headers = request.headers || {}, args = query(url);
    assert(!url.username && !url.password && !url.hash, 'Request contains forbidden URL fields');
    const api = state && url.origin === state.origin && (state.listings.has(url.pathname) || url.pathname === state.queueStatus);
    assert(!Object.hasOwn(headers,'authorization') && !Object.hasOwn(headers,'cookie'),'Unexpected credentials');
    assert(!Object.hasOwn(headers,'origin') || headers.origin === ORIGIN,'Unexpected request origin header');
    const undefinedHeader = headers['x-auth-token'] !== undefined;
    assert(!undefinedHeader || (api && headers['x-auth-token'] === 'undefined'),'Unexpected auth header');
    const entry = {method,url:safeUrl(url.href)};
    if (api) {
        entry.kind = 'synthetic_backend_mock'; entry.mock_undefined_auth_header = undefinedHeader;
        const list = state.listings.has(url.pathname), membership = !list && Object.keys(args).length === 0;
        assert(same(args,list ? /\/(agents|queues)$/.test(url.pathname) ? {paginate:'false'} : {} : membership ? {} : {runtime_only:'true',queue_id:IDS.queue,action:'login'}),'Unexpected API query');
        entry.query = args;
        const cors = {'access-control-allow-origin':ORIGIN,'access-control-allow-methods':'GET,POST,OPTIONS','access-control-allow-headers':'Content-Type,X-Auth-Token,X-Request-ID','access-control-allow-credentials':'true','cache-control':'no-store'};
        if (method === 'OPTIONS') {
            const next = headers['access-control-request-method'];
            assert(next === 'GET' || (next === 'POST' && !list && membership),'Unexpected preflight method');
            assert((headers['access-control-request-headers'] || '').toLowerCase().split(',').map(s => s.trim()).filter(Boolean).every(name => ['content-type','x-auth-token','x-request-id'].includes(name)), 'Unexpected preflight header');
            return {entry,response:{status:204,headers:cors,body:''}};
        }
        let data, status = 200, mutation;
        if (method === 'POST') {
            assert(!list && membership && !state.posted,'Unexpected or repeated Login mutation');
            assert(state.runtimeProbeSeen,'Selected runtime GET probe must precede Login');
            const payload = JSON.parse(request.body || 'null');
            assert(same(payload,{data:{action:'login',queue_id:IDS.queue,runtime_only:true,ui_metadata:{version:state.version,ui:'monster-ui'}}}),'Unexpected Login payload');
            state.posted = true; data = proof(false,false); status = 202; mutation = {method,path:url.pathname,payload,intercepted_only:true};
        } else {
            assert(method === 'GET','Unexpected API mutation');
            if (list) data = state.listings.get(url.pathname);
            else if (membership) data = [IDS.queue,IDS.otherQueue];
            else { state.runtimeProbeSeen = true; data = proof(state.posted && state.allowConfirmed); if (state.posted && !state.allowConfirmed) state.pendingPollSeen = true; }
        }
        entry.mock_status = status; if (data && data.state) entry.mock_state = data.state;
        return {entry,mutation,response:{status,headers:cors,contentType:'application/json',body:JSON.stringify({status:'success',data})}};
    }
    if (url.origin === ORIGIN) {
        assert(method === 'GET','Unexpected artifact mutation');
        const relative = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname.slice(1));
        assert(!relative.split('/').some(part => !part || part === '.' || part === '..') && !/[\\\x00-\x1f]/.test(relative),'Unsafe artifact request');
        assert(Object.hasOwn(before,relative),'Missing exact artifact file');
        const parts = relative.split('/');
        assert(!(parts[0] === 'apps' && preloads.includes(parts[1]) && (parts[2] === 'VERSION' || parts[2] === 'app.js' || parts[2] === 'views' || (parts[2] === 'style' && parts[3] === 'app.css'))),'Unexpected preload/template fallback');
        assert(Object.entries(args).every(([key,value]) => ['v','bust'].includes(key) && /^[A-Za-z0-9.+_-]{1,128}$/.test(value)), 'Unexpected static query');
        return {entry:{...entry,kind:'exact_artifact',file:relative,sha256:before[relative]},file:relative};
    }
    if (['http://fonts.googleapis.com','https://fonts.googleapis.com'].includes(url.origin) && url.pathname === '/css') {
        assert(method === 'GET' && same(args,{family:'Source Sans Pro:300,400,600,700'}),'Unexpected external font request');
        return {entry:{...entry,kind:'cosmetic_external_mock'},response:{status:200,contentType:'text/css',body:'/* Isolated mock: external font stylesheet omitted. */'}};
    }
    throw Error('Unapproved request origin/path');
}
function cleanRun(receipt) {
    for (const name of ['route_errors','page_errors','request_failures','websockets']) assert(receipt[name].length === 0,'Browser failure: ' + name);
    assert(!receipt.console.some(entry => entry.type === 'error'),'Browser console errors');
}
function newOutput(root) { owned.protectedDirectory(root); return fs.mkdtempSync(path.join(root,'monster-artifact-browser.')); }
function saveReceipt(file, receipt) { fs.writeFileSync(file,JSON.stringify(receipt,null,2) + '\n',{mode:0o600}); }
async function assertGlobalReady(host) { const status = host.locator('.acdc-status'); assert.equal(await status.textContent(),'ready'); assert.equal(await status.innerText(),'READY'); }
async function queueFixture(page, receipt, state, checkpoint, output) {
    const loaded = await page.evaluate(({account,agent}) => new Promise((resolve,reject) => {
        const m = require('monster'), $ = require('jquery');
        if (m.apps.auth.appFlags.isAuthentified) return reject(Error('Unexpected authenticated context'));
        // Explicit mock boundary, after the actual login screenshot: only remove
        // the absolute login overlay and supply an in-memory synthetic identity.
        $('#auth_app_container').remove();
        Object.assign(m.apps.auth,{accountId:account,userId:agent,currentAccount:{id:account,name:'SYNTHETIC ACCOUNT'},originalAccount:{id:account,name:'SYNTHETIC ACCOUNT'},currentUser:{id:agent,first_name:'Synthetic',last_name:'Agent'}});
        const host = $('<section id="isolated-acdc-fixture">').append($('<h1>').text('ISOLATED FIXTURE — mocked backend, no authentication')).append('<div class="fixture-app"></div>').prependTo('body');
        m.apps.load('acdc',(error,app) => {
            if (error) return reject(Error(String(error)));
            try { app.appFlags.acdc.currentTab = 'agents'; app.render(host.find('.fixture-app'));
                const t = m.cache.templates.acdc._main;
                resolve({accountId:app.accountId,appName:app.name,templates:['state','agents','agent-queue-login','agent-queue-sessions'].map(key => [key,typeof t[key]])});
            } catch (e) { reject(e); }
        });
    }),IDS);
    assert(loaded.accountId === IDS.account && loaded.appName === 'acdc' && loaded.templates.every(([,type]) => type === 'function'),'Bundled ACDC/template mismatch'); checkpoint('actual_bundled_acdc_loaded_with_mock_identity',loaded);
    const host = page.locator('#isolated-acdc-fixture'), login = host.locator('.acdc-agent-queue-login[data-id="' + IDS.agent + '"]');
    await login.waitFor({state:'visible'}); await assertGlobalReady(host); assert.equal(receipt.mock_mutations.length,0); await login.click();
    const dialog = page.locator('.acdc-queue-login-dialog'), select = dialog.locator('.acdc-login-queue'), submit = dialog.locator('.acdc-confirm-queue-login');
    await dialog.waitFor({state:'visible'}); await page.waitForFunction(() => document.querySelector('.acdc-login-queue')?.options.length === 3);
    assert.equal(await select.inputValue(),''); assert(await submit.isDisabled()); assert.equal(receipt.mock_mutations.length,0); checkpoint('explicit_selection_required_without_mutation');
    await select.selectOption(IDS.queue); await page.waitForFunction(() => document.querySelector('.acdc-confirm-queue-login')?.disabled === false);
    assert.equal(receipt.mock_mutations.length,0); checkpoint('runtime_probe_before_explicit_mock_login');
    const pendingRead = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === state.queueStatus && new URL(response.url()).searchParams.get('runtime_only') === 'true' && state.posted);
    await submit.click(); await pendingRead; await page.waitForFunction(() => document.querySelector('.acdc-login-message')?.textContent.includes('pending'));
    assert(state.posted && state.pendingPollSeen); assert(await submit.isDisabled()); await assertGlobalReady(host); checkpoint('accepted_mock_login_remains_pending'); state.allowConfirmed = true;
    await page.waitForFunction(() => document.querySelector('.acdc-login-message')?.textContent === 'Queue membership confirmed');
    const sessions = host.locator('.acdc-agent-queue-sessions');
    assert((await sessions.locator('.confirmed').innerText()).includes('Synthetic Queue One')); assert((await sessions.locator('.unconfirmed').innerText()).includes('Synthetic Queue Two'));
    await assertGlobalReady(host); assert(await submit.isDisabled());
    const finalState = await page.evaluate(({agent,queue}) => { const m = require('monster'); return {session:m.apps.acdc.agentQueueSession(agent,queue),authenticated:!!m.apps.auth.appFlags.isAuthentified,tokenPresent:!!m.util.getAuthToken()}; },IDS);
    assert(finalState.session.state === 'confirmed' && finalState.session.agentStatus === 'paused' && !finalState.authenticated && !finalState.tokenPresent,'Queue membership/auth boundary mismatch');
    assert.equal(receipt.mock_mutations.length,1); checkpoint('membership_confirmation_is_not_availability',finalState);
    await page.screenshot({path:path.join(output,'mock-queue-membership-confirmed.png'),fullPage:true});
}
async function queueEditorRecoveryFixture(page, receipt, checkpoint, output) {
    // PRIVATE CANDIDATE: real preloaded app, helpers and compiled templates;
    // only monster.request is replaced. This is not backend/auth acceptance.
    const selected = ['e'.repeat(32),'f'.repeat(32)], networkStart = receipt.requests.length;
    receipt.queue_editor_recovery = {status:'running',scope:'actual bundled queue editor with in-memory API mock',cases:[],requests:[],request_restored:false};
    let installed = false;
    try {
        const loaded = await page.evaluate(ids => {
            const m = require('monster'), $ = require('jquery'), app = m.apps.acdc;
            const check = (value,message) => { if (!value) throw Error(message); };
            const clone = value => JSON.parse(JSON.stringify(value));
            check(!window.__acdcArtifactRecovery,'Recovery fixture already installed');
            check(app && app.accountId === ids.account && !m.apps.auth.appFlags.isAuthentified && !m.util.getAuthToken(),'Unexpected recovery identity/auth context');
            const templates = m.cache.templates.acdc._main;
            for (const name of ['state','queue-form','queues']) check(typeof templates[name] === 'function','Missing bundled editor template: ' + name);
            const methods = Object.fromEntries(['getTemplate','renderQueueForm','bindQueueForm','saveQueue','request','requestQueueEditor','renderQueues'].map(name => [name,app[name]]));
            app.closeAgentQueueLogin();
            $('#isolated-acdc-fixture > h1').text('ISOLATED EDITOR FIXTURE — in-memory API mock, no authentication or backend');
            const f = {originalRequest:m.request,originalAccount:app.accountId,originalTab:app.appFlags.acdc.currentTab,
                app,templates:{state:templates.state,'queue-form':templates['queue-form'],queues:templates.queues},methods,
                requests:[],deferred:[],label:null,allowWriteSuccess:false,holdNextRead:false};
            f.snapshot = () => {
                const users = [ids.agent,'e'.repeat(32),'f'.repeat(32)].map((id,n) => ({id,first_name:'Synthetic',last_name:'Editor Agent ' + (n + 1),enabled:true}));
                const queue = app.defaultQueue(); queue.name = 'Synthetic queue before recovery'; queue.announcements.language = 'en-us';
                queue.announcements.media.you_are_at_position = 'legacy-position'; queue.callback.media.offer = 'legacy-callback';
                const required = app.requiredLanguagePromptIds();
                const language_capabilities = {schema_version:1,generated_at:'2026-09-05T19:00:00Z',languages:{}};
                for (const locale of app.announcementLocales) language_capabilities.languages[locale] = {
                    ready:locale === 'en-us',position:locale === 'en-us',wait_time:locale === 'en-us',callback:locale === 'en-us',
                    native_speaker_review:false,numbers:'native_say',number_range:[0,999999999],numeric_prompt_count:0,
                    required_prompt_ids:required,source_catalog_sha256:'1'.repeat(64),installed_media_sha256:'2'.repeat(64)};
                return {queue,users,roster:users.map(u => u.id),media:[],numbers:[],
                    system_media:required.map(id => ({id:'en-us/' + id,name:id,language:'en-us',has_attachments:true})),
                    language_capabilities,callflows:{summaries:[],routes:[]},
                    catalogs:Object.fromEntries(['users','media','numbers','system_media','callflows'].map(name => [name,{complete:true,reason:'complete',
                        count:name === 'users' ? users.length : name === 'system_media' ? required.length : 0,limit:500}])),
                    revisions:{queue:'1-initial',users:Object.fromEntries(users.map(u => [u.id,'1-user'])),callflows:{}}};
            };
            f.partial = () => ({message:'operation_incomplete_reload_before_recovery',data:{queue_id:ids.queue,
                operation_id:'acdc_queue_editor_' + '0'.repeat(64),state:'partial',phase:'roster',
                committed:[{phase:'queue',ids:[ids.queue]}],in_flight:[],remaining:['roster','route','finalize_extensions'],
                extension_claims:[],atomic:false,reload_required:true}});
            f.submit = () => {
                const form = app.getContentContainer().find('.acdc-queue-form')[0];
                check(form,'Expected actual bundled editor form');
                const valid = form.checkValidity();
                if (valid) form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
                return valid;
            };
            f.open = label => {
                check(f.deferred.length === 0,'Unresolved read from preceding case');
                f.label = label; f.start = f.requests.length; f.allowWriteSuccess = false; f.holdNextRead = false;
                f.next = f.snapshot(); app.accountId = ids.account; app.appFlags.acdc.currentTab = 'queues';
                app.renderQueueForm(ids.queue);
                check(f.submit(),'Synthetic editor form is invalid');
                f.view = app.getContentContainer().find('.acdc-queue-editor');
                f.pending = f.view.data('editor-pending'); f.pendingJson = JSON.stringify(f.pending);
                check(f.view.length === 1 && f.pending && f.pending.body,'Partial write did not retain the editor/pending receipt');
                f.holdNextRead = true;
            };
            f.resolve = error => {
                check(f.deferred.length === 1,'Expected exactly one deferred recovery GET');
                const options = f.deferred.shift();
                if (error) options.error({message:'Synthetic recovery GET unavailable'});
                else options.success({status:'success',data:clone(f.next)});
            };
            f.observe = () => ({requests:clone(f.requests.slice(f.start)),deferred:f.deferred.length,
                samePending:f.view.data('editor-pending') === f.pending,
                unchangedPending:JSON.stringify(f.view.data('editor-pending')) === f.pendingJson,
                sameView:app.getContentContainer().find('.acdc-queue-editor')[0] === f.view[0],
                recoveryPending:Boolean(f.view.data('editor-recovery-pending'))});
            m.request = options => {
                check(options && typeof options.success === 'function' && typeof options.error === 'function','Invalid in-memory API callback contract');
                const resource = options.resource, data = clone(options.data);
                check(data.accountId === ids.account,'In-memory editor request escaped synthetic account');
                check(['acdc.editor.get','acdc.editor.update','acdc.queues.list','acdc.queues.stats'].includes(resource),'Unapproved in-memory resource: ' + resource);
                const allowedKeys = resource === 'acdc.editor.get' ? ['accountId','queueId']
                    : resource === 'acdc.editor.update' ? ['accountId','data','queueId'] : ['accountId'];
                check(JSON.stringify(Object.keys(data).sort()) === JSON.stringify(allowedKeys.sort()),'Unexpected synthetic request fields');
                f.requests.push({case:f.label,resource,data,kind:'in_memory_editor_api_mock',live:false});
                if (resource === 'acdc.editor.get') {
                    check(data.queueId === ids.queue,'Unexpected editor queue');
                    if (f.holdNextRead) {
                        check(f.deferred.length === 0,'Overlapping recovery GET');
                        f.holdNextRead = false; f.deferred.push(options); return;
                    }
                    return options.success({status:'success',data:clone(f.next)});
                }
                if (resource === 'acdc.editor.update') {
                    check(data.queueId === ids.queue && /^[a-f0-9]{32}$/.test(data.data.request_id),'Invalid synthetic editor write');
                    if (!f.allowWriteSuccess) return options.error(f.partial());
                    return options.success({status:'success',data:{state:'complete',queue_id:ids.queue,atomic:false,reload_required:true}});
                }
                check(f.allowWriteSuccess,'Queue navigation occurred before explicit successful save');
                options.success({status:'success',data:resource === 'acdc.queues.list' ? [{id:ids.queue,name:f.next.queue.name}] : {stats:[]}});
            };
            window.__acdcArtifactRecovery = f;
            return {appName:app.name,templates:Object.keys(f.templates),mock:'monster.request only',authenticated:false};
        },IDS);
        installed = true; checkpoint('actual_bundled_queue_editor_mock_installed',loaded);
        const host = page.locator('#isolated-acdc-fixture');
        const observe = () => page.evaluate(() => window.__acdcArtifactRecovery.observe());
        const begin = async label => {
            await page.evaluate(label => window.__acdcArtifactRecovery.open(label),label);
            assert.equal(await host.locator('.acdc-queue-form').count(),1);
            assert.match(await host.locator('.acdc-form-error').textContent(),/Some changes may already be saved/);
            await host.locator('.acdc-editor-recovery').click();
            const held = await observe();
            assert.deepEqual(held.requests.map(r => r.resource),['acdc.editor.get','acdc.editor.update','acdc.editor.get']);
            assert.equal(held.deferred,1); assert(held.sameView && held.samePending && held.unchangedPending && held.recoveryPending);
            assert(await host.locator('[type="submit"]').isDisabled()); assert(await host.locator('.acdc-editor-recovery').isDisabled());
            for (const selector of ['[name="name"]','.acdc-roster','[name="route_extension"]']) assert.equal(await host.locator(selector).isDisabled(),false);
            const valid = await page.evaluate(() => {
                const f = window.__acdcArtifactRecovery, valid = f.submit();
                require('jquery')('.acdc-editor-recovery').triggerHandler('click');
                return valid;
            });
            assert(valid); assert.deepEqual(await observe(),held,'Identical Save or duplicate recovery overlapped the held GET');
        };
        const edit = async (name,extension) => {
            await host.locator('[name="name"]').fill(name);
            // Keep the real Chosen widget. Set its underlying native select and
            // dispatch the normal change event; no widget/template replacement.
            await host.locator('.acdc-roster').selectOption(selected,{force:true});
            await host.locator('[name="route_extension"]').fill(extension);
        };
        const assertDraft = async (name,extension) => {
            assert.equal(await host.locator('[name="name"]').inputValue(),name);
            assert.deepEqual(await host.locator('.acdc-roster').evaluate(e => [...e.selectedOptions].map(o => o.value)),selected);
            assert.equal(await host.locator('[name="route_extension"]').inputValue(),extension);
        };
        const passed = name => { receipt.queue_editor_recovery.cases.push(name); checkpoint('bundled_editor_' + name); };

        await begin('deferred-success');
        await edit('Latest edits while bundled recovery GET is pending','2096');
        assert(await page.evaluate(() => window.__acdcArtifactRecovery.submit()));
        assert.equal((await observe()).requests.length,3,'Changed Save must also wait for the held read');
        await page.evaluate(() => {
            const f = window.__acdcArtifactRecovery;
            f.next.queue.name = 'Server state before latest draft'; f.next.roster = [f.next.users[0].id];
            f.next.revisions.queue = '2-reloaded';
            f.next.revisions.users = Object.fromEntries(f.next.users.map(u => [u.id,'2-reloaded-user']));
            f.allowWriteSuccess = true; f.resolve(false);
        });
        await assertDraft('Latest edits while bundled recovery GET is pending','2096');
        assert.equal((await observe()).requests.length,3,'Recovery GET must not implicitly write or navigate');
        assert.equal(await host.locator('[type="submit"]').isDisabled(),false);
        await page.screenshot({path:path.join(output,'mock-editor-recovered-latest-draft.png'),fullPage:true});
        await host.locator('[type="submit"]').click();
        const saved = await observe(), writes = saved.requests.filter(r => r.resource === 'acdc.editor.update');
        assert.equal(writes.length,2);
        assert.equal(writes[1].data.data.queue.name,'Latest edits while bundled recovery GET is pending');
        assert.deepEqual(writes[1].data.data.roster,selected); assert.deepEqual(writes[1].data.data.route,{extension:'2096'});
        assert.equal(writes[1].data.data.revisions.queue,'2-reloaded');
        assert.deepEqual(writes[1].data.data.revisions.users,Object.fromEntries([IDS.agent,...selected].map(id => [id,'2-reloaded-user'])));
        assert.notEqual(writes[1].data.data.request_id,writes[0].data.data.request_id);
        assert.deepEqual(saved.requests.map(r => r.resource),['acdc.editor.get','acdc.editor.update','acdc.editor.get','acdc.editor.update','acdc.queues.list','acdc.queues.stats']);
        passed('deferred_success_latest_draft_fresh_revisions_explicit_save');

        await begin('deferred-failure');
        await edit('Latest draft before bundled recovery failure','2098');
        await page.evaluate(() => window.__acdcArtifactRecovery.resolve(true));
        await assertDraft('Latest draft before bundled recovery failure','2098');
        assert.match(await host.locator('.acdc-form-error').textContent(),/Saved state could not be verified/);
        const failed = await observe();
        assert(failed.sameView && failed.samePending && failed.unchangedPending && !failed.recoveryPending);
        assert.equal(failed.requests.length,3); assert.equal(failed.deferred,0);
        assert.equal(await host.locator('[type="submit"]').isDisabled(),false);
        assert.equal(await host.locator('.acdc-editor-recovery').isDisabled(),false);
        assert(await page.evaluate(() => window.__acdcArtifactRecovery.submit()));
        assert.equal((await observe()).requests.length,3,'Changed draft must not reuse the pending partial-write receipt');
        await page.evaluate(() => { window.__acdcArtifactRecovery.holdNextRead = true; });
        await host.locator('.acdc-editor-recovery').click();
        const retried = await observe();
        assert.equal(retried.deferred,1); assert.equal(retried.requests.length,4);
        assert.equal(retried.requests.filter(r => r.resource === 'acdc.editor.update').length,1);
        await page.evaluate(() => window.__acdcArtifactRecovery.resolve(false));
        await assertDraft('Latest draft before bundled recovery failure','2098');
        assert.equal((await observe()).requests.length,4);
        passed('failed_get_preserves_draft_pending_receipt_and_explicit_retry');

        for (const departure of ['replacement','account','detached']) {
            await begin('stale-' + departure);
            await edit('Latest draft before ' + departure,'2099');
            const late = await page.evaluate(({departure,queue}) => {
                const f = window.__acdcArtifactRecovery, app = f.app, $ = require('jquery');
                if (departure === 'replacement') {
                    app.renderQueueForm(queue);
                    app.getContentContainer().find('[name="name"]').val('Replacement editor stays visible');
                } else if (departure === 'account') app.accountId = '9'.repeat(32);
                else { f.view.detach(); app.getContentContainer().text('Original bundled editor was detached'); }
                const content = app.getContentContainer()[0], html = content.innerHTML;
                const currentView = $(content).find('.acdc-queue-editor')[0], generation = app.appFlags.acdc.requestGeneration;
                // A real replacement may clean jQuery data from the removed
                // form. The late reply must preserve that post-departure state.
                const previousPending = f.view.data('editor-pending'), previousPendingJson = JSON.stringify(previousPending);
                f.resolve(false);
                return {unchanged:content.innerHTML === html && $(content).find('.acdc-queue-editor')[0] === currentView,
                    generationUnchanged:app.appFlags.acdc.requestGeneration === generation,
                    stalePendingUnchanged:f.view.data('editor-pending') === previousPending && JSON.stringify(f.view.data('editor-pending')) === previousPendingJson,
                    ...f.observe()};
            },{departure,queue:IDS.queue});
            assert(late.unchanged && late.generationUnchanged && late.stalePendingUnchanged);
            assert.equal(late.deferred,0); assert.equal(late.requests.length,departure === 'replacement' ? 4 : 3);
            assert.equal(late.requests.filter(r => r.resource === 'acdc.editor.update').length,1);
            passed('late_get_ignored_after_' + departure);
        }
        assert.equal(receipt.queue_editor_recovery.cases.length,5);
        assert(!receipt.requests.slice(networkStart).some(r => r.kind === 'synthetic_backend_mock'),'Editor mock escaped into browser API transport');
    } catch (error) {
        receipt.queue_editor_recovery.status = 'failed'; throw error;
    } finally {
        if (installed) {
            const cleanup = await page.evaluate(() => {
                const f = window.__acdcArtifactRecovery, m = require('monster'), app = f.app;
                m.request = f.originalRequest;
                app.accountId = f.originalAccount; app.appFlags.acdc.currentTab = f.originalTab;
                ++app.appFlags.acdc.requestGeneration; f.deferred.length = 0;
                const result = {requests:f.requests,request_restored:m.request === f.originalRequest,
                    bundled_methods_unchanged:Object.entries(f.methods).every(([name,method]) => app[name] === method),
                    bundled_templates_unchanged:Object.entries(f.templates).every(([name,template]) => m.cache.templates.acdc._main[name] === template),
                    authenticated:!!m.apps.auth.appFlags.isAuthentified,token_present:!!m.util.getAuthToken()};
                delete window.__acdcArtifactRecovery; return result;
            });
            Object.assign(receipt.queue_editor_recovery,cleanup);
            assert(cleanup.request_restored && cleanup.bundled_methods_unchanged && cleanup.bundled_templates_unchanged);
            assert(!cleanup.authenticated && !cleanup.token_present);
            checkpoint('bundled_editor_mock_restored');
        }
    }
    receipt.queue_editor_recovery.status = 'passed';
}
async function main(argv) {
    assert(argv.length === 2 && argv[0] === '--inputs','Usage: test-monster-artifact-browser.cjs --inputs /absolute/private/inputs.json');
    assert(process.getuid() === 0,'Root-owned artifact evidence required'); process.umask(0o077);
    const inputFile = absolute(argv[1]), input = validateInputs(readJson(inputFile));
    assert(path.join(input.repo_root,'scripts',path.basename(__filename)) === __filename,'Repository root must contain this running script');
    assert(!overlaps(input.output_root,inputFile) && !overlaps(input.output_root,process.execPath),'Output overlaps input manifest/Node');
    for (const dir of [input.repo_root,input.artifact_root,input.output_root,input.toolchain.playwright_root]) owned.protectedDirectory(dir);
    const membership = fs.readFileSync('/proc/self/cgroup','utf8').trim(), cg = '/sys/fs/cgroup' + membership.slice(3);
    assert(/^0::\/system.slice\/kazoo-validation-[a-f0-9-]{36}\.service$/.test(membership),'Validation guard required');
    const limit = name => fs.readFileSync(path.join(cg,name),'utf8').trim(), limits = Object.fromEntries(Object.keys(LIMITS).map(name => [name,limit(name)]));
    const netns = fs.readlinkSync('/proc/self/ns/net'), hostNetns = fs.readlinkSync('/proc/1/ns/net'); validateGuard(membership,limits,netns,hostNetns);
    const output = newOutput(input.output_root), receiptFile = path.join(output,'receipt.json');
    const receipt = {version:1,status:'running',scope:'actual artifact boot/rendering with explicitly mocked backend; not live acceptance',started:new Date().toISOString(),artifact:input.artifact_root,output,membership,limits,netns,host_netns:hostNetns,
        actual_boot:false,authenticated:false,live_backend:false,published:false,acdc_fixture:'not_started',
        mocks:['Synthetic in-memory identity after actual unauthenticated boot; login overlay removed only for labelled mock host',
            'Fixed synthetic API listings and one intercepted runtime-only queue POST; confirmation is membership, not availability',
            'Only literal undefined auth header on synthetic API routes; no token, cookie or real authentication',
            'External Google Fonts stylesheet omitted; artifact-local assets unchanged'],
        requests:[],mock_mutations:[],console:[],page_errors:[],route_errors:[],request_failures:[],websockets:[],checkpoints:[]};
    const save = () => saveReceipt(receiptFile,receipt), checkpoint = (name,details = {}) => { receipt.checkpoints.push({name,at:new Date().toISOString(),...details}); save(); };
    let browser, page, before, state = null, verificationFiles;
    save();
    try {
        verificationFiles = [inputFile,__filename,path.join(__dirname,'deploy-owned-monster.cjs'),process.execPath,path.join(input.toolchain.playwright_root,'package.json'),input.toolchain.browser_executable,input.build_receipt.path,input.readback_receipt.path];
        receipt.current_verification_inputs = {file_sha256:Object.fromEntries(verificationFiles.map(file => [file,fileHash(file)])),node_version:process.version};
        const actual = receipt.current_verification_inputs.file_sha256;
        assert(actual[process.execPath] === input.toolchain.node_sha256 && Number(process.versions.node.split('.')[0]) >= 20,'Browser Node toolchain mismatch');
        assert(actual[path.join(input.toolchain.playwright_root,'package.json')] === input.toolchain.playwright_package_sha256 && actual[input.toolchain.browser_executable] === input.toolchain.browser_sha256,'Browser toolchain hash mismatch');
        const build = readJson(input.build_receipt.path,input.build_receipt.sha256), readback = readJson(input.readback_receipt.path,input.readback_receipt.sha256), evidence = bindEvidence(input,build,readback);
        // These are original build-time inputs, never replaced with today's verifier hashes.
        receipt.original_compilation_evidence = {receipt_sha256:input.build_receipt.sha256,...evidence.original_compilation};
        receipt.original_readback_sha256 = input.readback_receipt.sha256;
        before = owned.snapshot(input.artifact_root); receipt.artifact_sha256 = hash(JSON.stringify(before));
        assert(receipt.artifact_sha256 === input.artifact_sha256,'Actual artifact tree hash mismatch');
        for (const file of ['index.html','js/main.js','js/templates.js','js/config.js','build-config.json','VERSION','css/style.css']) assert(Object.hasOwn(before,file),'Missing required artifact file');
        assert(before['js/config.js'] === evidence.artifact_report.configuration_sha256,'Artifact configuration binding mismatch');
        const config = JSON.parse(fs.readFileSync(path.join(input.artifact_root,'build-config.json')));
        assert(config.type === 'production' && same([...owned.preloadedApps(config)].sort(),evidence.preloads),'Artifact preload binding mismatch');
        const version = versionFrom(fs.readFileSync(path.join(input.artifact_root,'VERSION')));
        const {chromium} = require(input.toolchain.playwright_root);
        browser = await chromium.launch({executablePath:input.toolchain.browser_executable,headless:true,timeout:30000,args:['--disable-background-networking','--no-proxy-server','--js-flags=--max-old-space-size=128']});
        receipt.browser_version = browser.version();
        const context = await browser.newContext({viewport:{width:1440,height:1100},locale:'en-US',serviceWorkers:'block'});
        await context.route('**/*',async route => {
            const request = route.request(); let entry;
            try {
                const plan = planRequest(await browserRequest(request),before,evidence.preloads,state);
                entry = plan.entry; receipt.requests.push(entry); if (plan.mutation) receipt.mock_mutations.push(plan.mutation);
                if (plan.file) {
                    const file = path.join(input.artifact_root,plan.file); safeFile(file,20 * 1024 * 1024); const bytes = fs.readFileSync(file);
                    assert(hash(bytes) === before[plan.file],'Served artifact bytes changed'); entry.bytes = bytes.length;
                    await route.fulfill({status:200,contentType:MIME[path.extname(file)] || 'text/plain',body:bytes});
                } else await route.fulfill(plan.response);
            } catch (error) {
                if (!entry) { entry = {method:request.method(),url:safeUrl(request.url())}; receipt.requests.push(entry); }
                entry.kind = 'rejected'; receipt.route_errors.push(clean(error.message)); save(); await route.abort('blockedbyclient');
            }
        });
        await context.routeWebSocket('**/*',socket => { receipt.websockets.push(safeUrl(socket.url())); socket.close(); });
        page = await context.newPage(); page.setDefaultTimeout(15000); page.setDefaultNavigationTimeout(25000);
        page.on('console',msg => receipt.console.push({type:msg.type(),text:clean(msg.text()),location:safeUrl(msg.location().url)}));
        page.on('pageerror',error => receipt.page_errors.push(clean(error.message)));
        page.on('requestfailed',request => receipt.request_failures.push({url:safeUrl(request.url()),error:clean(request.failure()?.errorText)}));
        await page.goto(ORIGIN + '/', {waitUntil:'domcontentloaded'});
        await page.locator('input#login').waitFor({state:'visible'}); await page.locator('input#password').waitFor({state:'visible'});
        const boot = await page.evaluate(() => { const m = require('monster'); return {preloads:m.config.developerFlags.build.preloadedApps,legacy:Object.hasOwn(m.config.developerFlags.build,'preloadApps'),
            version:m.util.getVersion(),api:m.config.api.default,fetchFromApi:m.config.whitelabel.fetchFromApi,authenticated:!!m.apps.auth.appFlags.isAuthentified,coreLoaded:!!m.apps.core,authLoaded:!!m.apps.auth}; });
        assert(same([...boot.preloads].sort(),evidence.preloads) && !boot.legacy && !boot.authenticated && boot.coreLoaded && boot.authLoaded,'Actual boot/preload/authentication mismatch');
        assert(boot.version === version && boot.fetchFromApi === false,'Unsupported version or pre-auth remote branding profile'); const api = apiBase(boot.api);
        assert.equal(receipt.mock_mutations.length,0); assert(!receipt.requests.some(r => r.kind === 'synthetic_backend_mock'),'Boot unexpectedly used backend fixture');
        receipt.actual_boot = true; checkpoint('actual_unauthenticated_boot_and_canonical_preloads',{...boot,api:api.href});
        await page.screenshot({path:path.join(output,'actual-unauthenticated-boot.png'),fullPage:true});
        if (evidence.acdc_selected) {
            state = mockState(api.href,version); await queueFixture(page,receipt,state,checkpoint,output);
            await queueEditorRecoveryFixture(page,receipt,checkpoint,output); receipt.acdc_fixture = 'passed';
        }
        else { receipt.acdc_fixture = 'not_selected'; checkpoint('acdc_fixture_not_selected'); }
        for (const file of ['index.html','js/main.js','js/templates.js','js/config.js','build-config.json','css/style.css']) assert(receipt.requests.some(r => r.file === file && r.sha256 === before[file]),'Required artifact not consumed');
        cleanRun(receipt); receipt.status = 'passed';
    } catch (error) {
        receipt.status = 'failed'; receipt.error = clean(error.message); process.exitCode = 1;
        if (page) try { await page.screenshot({path:path.join(output,'failure.png'),fullPage:true,timeout:5000}); } catch (e) { receipt.screenshot_error = clean(e.message); }
    } finally {
        if (browser) try { await browser.close(); } catch (e) { receipt.cleanup_error = clean(e.message); receipt.status = 'failed'; process.exitCode = 1; }
        try {
            if (before) { receipt.artifact_after_sha256 = hash(JSON.stringify(owned.snapshot(input.artifact_root))); assert(receipt.artifact_after_sha256 === input.artifact_sha256,'Artifact preservation failed'); }
            if (receipt.current_verification_inputs) for (const file of verificationFiles) assert(fileHash(file) === receipt.current_verification_inputs.file_sha256[file],'Verification/evidence inputs changed');
            if (receipt.status === 'passed') cleanRun(receipt); // Include close events without skipping preservation hashes.
        } catch (e) { receipt.preservation_error = clean(e.message); receipt.status = 'failed'; process.exitCode = 1; }
        receipt.finished = new Date().toISOString(); receipt.cgroup_final = Object.fromEntries(['memory.peak','memory.events','cpu.stat'].map(name => [name,limit(name)]));
        receipt.screenshots = Object.fromEntries(fs.readdirSync(output).filter(name => name.endsWith('.png')).map(name => [name,fileHash(path.join(output,name))])); save();
        console.log(JSON.stringify({status:receipt.status,receipt:receiptFile,sha256:fileHash(receiptFile),actual_boot:receipt.actual_boot,acdc_fixture:receipt.acdc_fixture,live_backend:false,published:false}));
    }
}
if (require.main === module) main(process.argv.slice(2)).catch(error => { console.error('FAIL artifact browser preflight: ' + clean(error.message)); process.exitCode = 1; });
module.exports = {ORIGIN,IDS,LIMITS,hash,fileHash,readJson,safeFile,validateInputs,validateGuard,bindEvidence,versionFrom,apiBase,mockState,browserRequest,planRequest,proof,cleanRun,newOutput,saveReceipt,clean,main};
