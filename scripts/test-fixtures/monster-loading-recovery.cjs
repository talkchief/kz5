'use strict';
const assert = require('node:assert/strict');

module.exports = async function loadingRecovery(page, origin, account) {
    assert.equal(origin, 'https://kz5-dev.talkchief.io');
    assert.equal(account, 'adecbb84fbe9e06902a76731914d1943');
    const livePath = '/v2/accounts/' + account + '/queues/live';
    const devicePath = '/v2/accounts/' + account + '/devices';
    let phase = 'initial', fault = null, faultCount = 0, release, heldDone;
    const issues = [], checks = [];
    page.on('pageerror', e => issues.push('pageerror-' + e.name));
    async function idle() {
        await page.waitForFunction(() => window.monster?.apps.core.request.counter === 0 &&
            !document.querySelector('.progress-indicator.active'), null, {timeout: 15000});
    }
    async function routeHandler(route) {
        const request = route.request(), url = new URL(request.url());
        if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method())) {
            issues.push('unexpected-account-write'); return route.abort();
        }
        if (fault && url.pathname === fault.path && faultCount === 0 && request.method() === 'GET') {
            faultCount++;
            if (fault.kind === '503') return route.fulfill({status: 503, contentType: 'application/json',
                body: JSON.stringify({status: 'error', error: '503', message: 'development-browser-outage-fixture', data: {}})});
            const response = await route.fetch();
            assert.equal(response.status(), 200);
            heldDone = new Promise(resolve => {
                release = async () => {
                    try { await route.fulfill({response}); }
                    catch (_) { /* The read watchdog may already have aborted this browser request. */ }
                    resolve();
                };
            });
            await heldDone;
            return;
        }
        await route.continue();
    }
    await page.route(origin + '/v2/accounts/**', routeHandler);
    try {
        await idle();
        phase = 'acdc-503'; fault = {path: livePath, kind: '503'}; faultCount = 0;
        await page.goto(origin + '/#/apps/acdc', {waitUntil: 'domcontentloaded'});
        await page.locator('.acdc-retry:visible').waitFor({timeout: 20000});
        assert.equal(faultCount, 1); await idle();
        checks.push('acdc-503-visible-retry-and-idle-indicator');
        fault = null;
        await page.locator('.acdc-retry:visible').click();
        await page.locator('.acdc-live-dashboard:visible').waitFor({timeout: 20000});
        await idle(); checks.push('acdc-503-retry-recovers');

        phase = 'acdc-stalled-read'; fault = {path: livePath, kind: 'hold'}; faultCount = 0;
        // Full document reload clears the old dashboard snapshot; auth remains native.
        await page.reload({waitUntil: 'domcontentloaded'});
        await page.locator('.acdc-retry:visible').waitFor({timeout: 25000});
        assert.equal(faultCount, 1); assert(release); await idle();
        checks.push('acdc-stall-watchdog-visible-retry-and-idle-indicator');
        fault = null;
        await page.locator('.acdc-retry:visible').click();
        await page.locator('.acdc-live-dashboard:visible').waitFor({timeout: 20000});
        await idle();
        const fresh = await page.evaluate(() => monster.apps.acdc.appFlags.acdc.liveDashboardSnapshot.receivedAt);
        await release(); await heldDone; release = null;
        await page.waitForTimeout(750);
        assert.equal(await page.evaluate(() => monster.apps.acdc.appFlags.acdc.liveDashboardSnapshot.receivedAt), fresh);
        assert.equal(await page.locator('.acdc-retry:visible').count(), 0);
        await idle(); checks.push('acdc-late-delivery-does-not-replace-recovered-view');

        phase = 'smartpbx-503'; fault = {path: devicePath, kind: '503'}; faultCount = 0;
        await page.goto(origin + '/#/apps/voip', {waitUntil: 'domcontentloaded'});
        await page.waitForFunction(() => window.monster?.apps.voip && document.querySelector('.right-content'), null, {timeout: 20000});
        await page.waitForTimeout(3000);
        assert.equal(faultCount, 1); await idle();
        checks.push('smartpbx-503-idle-global-indicator');
        // Do not turn an error into an empty-data success. Recovery is explicit navigation.
        fault = null;
        await page.goto(origin + '/#/apps/acdc', {waitUntil: 'domcontentloaded'});
        await page.locator('.acdc-live-dashboard:visible').waitFor({timeout: 20000});
        await page.goto(origin + '/#/apps/voip', {waitUntil: 'domcontentloaded'});
        await page.locator('#myoffice_container:visible').waitFor({timeout: 20000});
        await idle(); checks.push('smartpbx-navigation-recovers-after-503');
        assert.deepEqual(issues, []);
        console.log(JSON.stringify({status: 'PASS', checks, scope: 'browser-only injected GET failures/stall; real login and successful API reads; no server outage, calls or account writes'}));
    } catch (error) {
        const state = await page.evaluate(() => ({counter: window.monster?.apps.core.request.counter,
            global_indicator: !!document.querySelector('.progress-indicator.active'),
            acdc_retry: document.querySelectorAll('.acdc-retry').length,
            acdc_loading: document.querySelectorAll('.acdc-state .fa-spinner').length,
            smartpbx_content: !!document.querySelector('#myoffice_container')})).catch(() => ({}));
        console.error(JSON.stringify({status: 'FAIL', phase, checks, faultCount, issues, state}));
        throw error;
    } finally {
        if (release) { await release(); await heldDone; }
        await page.unroute(origin + '/v2/accounts/**', routeHandler);
    }
};
