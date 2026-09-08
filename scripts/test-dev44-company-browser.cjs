'use strict';
// Fixed development-host acceptance; no call, SIP registration or queue login.
// On .44 read protected installer settings. Remote test runners may supply the
// same {account,username,password} on stdin; never on argv or in tracked files.
const fs = require('node:fs'), assert = require('node:assert/strict');
const ORIGIN = 'https://kz5-dev.talkchief.io';
const MASTER = 'adecbb84fbe9e06902a76731914d1943';
const COMPANY = 'd8520ce3f29c5b6db692289e782c92af';
const usersOnly = process.argv.slice(2).join(' ') === '--callflows-users';
const queueFormOnly = process.argv.slice(2).join(' ') === '--queue-create-form';
const queueSave = process.argv.slice(2).join(' ') === '--queue-create-save --allow-fixture-writes';

function privateText(file) {
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
        const s = fs.fstatSync(fd);
        assert(s.isFile() && s.uid === 0 && s.nlink === 1 && !(s.mode & 0o077) && s.size < 65536);
        return fs.readFileSync(fd, 'utf8');
    } finally {fs.closeSync(fd);}
}
function envFields(text) {
    const result = {};
    for (const line of text.split('\n')) {
        if (!line || line.startsWith('#')) continue;
        const i = line.indexOf('='); assert(i > 0);
        const key = line.slice(0, i); assert(!Object.hasOwn(result, key));
        result[key] = line.slice(i + 1);
    }
    return result;
}
function credentials() {
    let result;
    if (process.argv.slice(2).join(' ') === '--credentials-stdin') {
        const input = fs.readFileSync(0, 'utf8'); assert(input.length < 65536);
        result = JSON.parse(input);
    } else {
        assert(process.argv.length === 2 || usersOnly || queueFormOnly || queueSave);
        const auth = envFields(privateText('/etc/kazoo/installer-secrets.env'));
        const config = envFields(privateText('/etc/kazoo/deployment.env'));
        result = {account: Buffer.from(config.KAZOO_MASTER_ACCOUNT_NAME, 'base64').toString('utf8'),
            username: auth.KAZOO_MASTER_ADMIN_USER, password: auth.KAZOO_MASTER_ADMIN_PASSWORD};
    }
    assert(result.account === 'KazooMaster' && result.username === 'admin'
        && typeof result.password === 'string' && result.password.length > 0);
    return result;
}

(async () => {
    const auth = credentials();
    const {chromium} = require(process.env.KZ5_PLAYWRIGHT_ROOT || 'playwright');
    const browser = await chromium.launch({headless: true,
        ...(process.env.KZ5_BROWSER_EXECUTABLE ? {executablePath: process.env.KZ5_BROWSER_EXECUTABLE} : {}),
        args: ['--no-sandbox', '--disable-dev-shm-usage', '--host-resolver-rules=MAP kz5-dev.talkchief.io 10.1.0.44']});
    let phase = 'login';
    try {
        const page = await browser.newPage(), issues = [];
        page.on('pageerror', error => issues.push('javascript-exception-' + error.name));
        page.on('response', r => {if (r.status() >= 400 && r.url().startsWith(ORIGIN)) issues.push('http-' + r.status());});
        page.on('requestfailed', r => {if (r.url().startsWith(ORIGIN)) issues.push(r.failure().errorText);});
        page.on('request', r => {if (r.url().startsWith('http:')) issues.push('insecure-request');});
        assert.equal((await page.goto(ORIGIN, {waitUntil: 'networkidle', timeout: 45000})).status(), 200);
        await page.locator('#login').fill(auth.username);
        await page.locator('#password').fill(auth.password);
        await page.locator('#account_name').fill(auth.account);
        await page.locator('button.login').click();
        await page.waitForFunction(id => window.monster && monster.apps.auth.accountId === id, MASTER, {timeout: 30000});
        await page.waitForTimeout(5000);
        async function checkCallflowsUsers(accountId, expectedCount) {
            const prefix = 'callflows-users-' + (accountId === MASTER ? 'master' : 'company');
            phase = prefix + '-navigation';
            await page.goto(ORIGIN + '/#/apps/callflows', {waitUntil: 'domcontentloaded'});
            phase = prefix + '-users-button';
            const users = page.locator('.entity-element[data-type="user"]:visible');
            await users.waitFor({state: 'visible', timeout: 30000});
            const entitlement = page.waitForResponse(r => new URL(r.url()).pathname ===
                '/v2/accounts/' + accountId + '/entitlements', {timeout: 20000});
            await users.click();
            phase = prefix + '-entitlements-response';
            const response = await entitlement;
            assert.equal(response.status(), 200);
            const body = await response.json();
            assert.equal(body.status, 'success');
            assert.equal(typeof body.data.capabilities, 'object');
            phase = prefix + '-list-render';
            try {
                // Callflows positions its child panels independently; the wrapper
                // can have zero height while the actual controls/rows are visible.
                await page.locator('.entity-edition .list-add:visible').waitFor({timeout: 15000});
            } catch (error) {
                console.log(JSON.stringify({phase, issues, layout: await page.evaluate(() =>
                    Array.from(document.querySelectorAll('.entity-edition')).map(element => ({
                        display: getComputedStyle(element).display,
                        width: element.getBoundingClientRect().width,
                        height: element.getBoundingClientRect().height,
                        rows: element.querySelectorAll('.list-element[data-id]').length
                    })))}));
                throw error;
            }
            await page.waitForTimeout(2000);
            const actualCount = await page.locator('.entity-edition .list-element[data-id]:visible').count();
            console.log(JSON.stringify({phase, expected_users: expectedCount, visible_users: actualCount}));
            assert.equal(actualCount, expectedCount);
            phase = prefix + '-indicator-errors';
            assert.equal(await page.evaluate(() => monster.apps.core.request.counter), 0);
            assert.equal(await page.locator('.progress-indicator.active').count(), 0);
            assert.deepEqual(issues, []);
        }
        if (usersOnly) {
            const masterUsers = await page.evaluate(async id => {
                const r = await fetch('/v2/accounts/' + id + '/users?paginate=false',
                    {headers: {'X-Auth-Token': monster.apps.auth.getAuthToken()}});
                if (r.status !== 200) throw Error('User collection failed');
                return (await r.json()).data.length;
            }, MASTER);
            await checkCallflowsUsers(MASTER, masterUsers);
        }
        phase = 'master-acdc';
        const masterLive = page.waitForResponse(r => new URL(r.url()).pathname === '/v2/accounts/' + MASTER + '/queues/live');
        await page.goto(ORIGIN + '/#/apps/acdc', {waitUntil: 'domcontentloaded'});
        assert.equal((await masterLive).status(), 200);
        await page.waitForTimeout(2000);
        if (queueSave) {
            phase = 'isolated-queue-browser-save';
            await require('./test-fixtures/queue-browser-save.cjs')(page, issues);
            return;
        }
        if (queueFormOnly) {
            phase = 'queue-create-form';
            // Check the reported create/default-validation/storage-loading path;
            // no mutation, synthetic HTTP success or account configuration change.
            await page.route(ORIGIN + '/v2/accounts/**', async route => {
                if (!['GET', 'HEAD', 'OPTIONS'].includes(route.request().method())) {
                    issues.push('unexpected-mutation'); await route.abort();
                } else { await route.continue(); }
            });
            const storageRequests = [];
            page.on('request', request => {
                if (/\/storage(?:[/?]|$)/.test(new URL(request.url()).pathname)) storageRequests.push(request.method());
            });
            await page.locator('.acdc-live-add:visible').first().click();
            const form = page.locator('.acdc-queue-form:visible');
            await form.waitFor({timeout: 30000});
            await form.locator('[name="name"]').fill('Queue form validation draft - never saved');
            assert.equal(await form.evaluate(element => element.checkValidity()), true);
            assert.deepEqual(await form.locator('[name="announcements.language"] option').evaluateAll(
                options => options.map(option => option.value).sort()), ['ar-sa', 'en-us', 'es-es', 'fr-fr', 'he-il']);
            assert.deepEqual(storageRequests, []);
            assert.deepEqual(issues, []);
            assert.equal(await page.evaluate(() => monster.apps.core.request.counter), 0);
            assert.equal(await page.locator('.progress-indicator.active').count(), 0);
            await form.locator('.acdc-cancel').click();
            await form.waitFor({state: 'hidden', timeout: 15000});
            console.log(JSON.stringify({status: 'PASS', queue_create_form: true, default_validation: true,
                five_languages: true, storage_requests: 0, inactive_global_indicator: true,
                scope: 'actual Add queue form; local draft and cancel; no save'}));
            return;
        }
        phase = 'account-selector';
        await page.locator('#main_topbar_account_toggle_link').click();
        const row = page.locator('.account-list-element[data-id="' + COMPANY + '"]');
        await row.waitFor({state: 'visible', timeout: 15000});
        assert.equal((await row.locator('.account-name').innerText()).trim(), 'Talkchief (Development copy)');
        const companyLive = page.waitForResponse(r => new URL(r.url()).pathname === '/v2/accounts/' + COMPANY + '/queues/live');
        await row.locator('.account-name').click();
        await page.waitForFunction(id => monster.apps.auth.currentAccount.id === id, COMPANY, {timeout: 20000});
        const live = await companyLive;
        assert.equal(live.status(), 200); assert.equal((await live.json()).data.queues.length, 4);
        await page.waitForTimeout(3000);
        phase = 'company-collections';
        const counts = await page.evaluate(async id => {
            const token = monster.apps.acdc.getAuthToken(), counts = {};
            for (const resource of ['users', 'devices', 'queues', 'callflows']) {
                const r = await fetch('/v2/accounts/' + id + '/' + resource + '?paginate=false', {headers: {'X-Auth-Token': token}});
                const body = await r.json();
                if (r.status !== 200 || body.status !== 'success' || !Array.isArray(body.data)) throw Error('Collection failed');
                counts[resource] = body.data.length;
            }
            return counts;
        }, COMPANY);
        assert.deepEqual(counts, {users: 15, devices: 82, queues: 4, callflows: 89});
        if (usersOnly) {
            await page.route(ORIGIN + '/v2/accounts/**', route =>
                ['GET', 'HEAD', 'OPTIONS'].includes(route.request().method()) ? route.continue() : route.abort());
            await checkCallflowsUsers(COMPANY, counts.users);
            console.log(JSON.stringify({status: 'PASS', callflows_users: ['master', 'copied-company'],
                company_users: counts.users, entitlements_http: 200, inactive_global_indicator: true,
                scope: 'actual Users clicks; private-route HTTPS; no user or entitlement writes'}));
            return;
        }
        for (const app of ['voip', 'acdc']) {
            phase = 'company-' + app;
            await page.goto(ORIGIN + '/#/apps/' + app, {waitUntil: 'domcontentloaded'});
            await page.waitForTimeout(10000);
            assert.equal(await page.evaluate(() => monster.apps.auth.currentAccount.id), COMPANY);
            assert.equal(await page.evaluate(() => monster.apps.core.request.counter), 0);
            assert.equal(await page.locator('.progress-indicator.active').count(), 0);
            if (app === 'acdc') assert.equal(await page.locator('.acdc-live-queue-card:visible').count(), 4);
            assert.deepEqual(issues, []);
        }
        phase = 'queue-language-read-only';
        // Inspect the real deployed editor without allowing this copied tenant
        // to be changed. Language selections below are local drafts; never save.
        await page.route(ORIGIN + '/v2/accounts/' + COMPANY + '/**', async route => {
            if (!['GET', 'HEAD', 'OPTIONS'].includes(route.request().method())) {
                issues.push('unexpected-company-mutation');
                await route.abort();
            } else {await route.continue();}
        });
        await page.locator('.acdc-open-live-queue:visible').first().click();
        await page.locator('.acdc-live-edit:visible').click();
        const form = page.locator('.acdc-queue-form:visible');
        await form.waitFor({state: 'visible', timeout: 30000});
        const language = form.locator('select[name="announcements.language"]');
        assert.equal(await language.count(), 1);
        const languageValues = ['ar-sa', 'en-us', 'es-es', 'fr-fr', 'he-il'];
        assert.deepEqual(await language.locator('option').evaluateAll(options =>
            options.map(option => option.value).sort()), languageValues);
        assert.equal(await language.locator('option:disabled').count(), 0);
        for (const value of languageValues) {
            await language.selectOption(value);
            assert.equal(await language.inputValue(), value);
        }
        assert.equal(await form.locator('[name="announcements.interval"]').count(), 1);
        assert.equal(await form.locator('[name="callback.announcement.interval"]').count(), 1);
        await form.locator('.acdc-cancel').click();
        await form.waitFor({state: 'hidden', timeout: 15000});
        await page.waitForTimeout(2000);
        assert.deepEqual(issues, []);
        assert.equal(await page.evaluate(() => monster.apps.core.request.counter), 0);
        assert.equal(await page.locator('.progress-indicator.active').count(), 0);
        console.log(JSON.stringify({status: 'PASS', account_picker: true, collections: counts,
            smartpbx: true, acdc_queue_cards: 4, inactive_global_indicator: true,
            queue_language_options: languageValues, separate_announcement_interval_controls: true,
            queue_editor_inspection: 'local draft selections only; no save permitted',
            scope: 'private-route HTTPS browser with certificate verification; inspection copy only, no calls'}));
    } catch (error) {
        console.error('Development company browser check failed at ' + phase + '; credentials and customer data withheld.');
        process.exitCode = 1;
    } finally {await browser.close();}
})().catch(() => {console.error('Development browser setup failed; private inputs withheld.'); process.exitCode = 1;});
