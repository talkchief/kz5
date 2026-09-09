'use strict';
const assert = require('node:assert/strict');

module.exports = async function(page, origin, account) {
    assert.equal(origin, 'https://kz5-dev.talkchief.io');
    assert.equal(account, 'adecbb84fbe9e06902a76731914d1943');
    const path = '/v2/accounts/' + account + '/devices', checks = [], issues = [];
    let fault = null, count = 0, release, phase = 'initial';
    page.on('pageerror', error => issues.push(error.name));
    const routeHandler = async route => {
        const request = route.request();
        if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method())) {
            issues.push('unexpected-account-write'); return route.abort();
        }
        if (fault && request.method() === 'GET' && new URL(request.url()).pathname === path && count++ === 0) {
            if (fault === '503') return route.fulfill({status: 503, contentType: 'application/json',
                body: JSON.stringify({status: 'error', error: '503', message: 'browser-read-fixture', data: {}})});
            const response = await route.fetch(); assert.equal(response.status(), 200);
            await new Promise(resolve => { release = async () => {
                try { await route.fulfill({response}); } catch (_) { /* XHR timeout abort */ }
                resolve();
            }; });
            return;
        }
        await route.continue();
    };
    async function idle() {
        await page.waitForFunction(() => monster.apps.core.request.counter === 0 &&
            !document.querySelector('.progress-indicator.active') &&
            !document.querySelector('.left-menu .category.loading'), null, {timeout: 22000});
    }
    async function retryAndRecover() {
        fault = null;
        await page.locator('.smartpbx-load-retry:visible').click();
        await page.locator('#myoffice_container:visible').waitFor({timeout: 22000});
        await idle();
    }
    await page.route(origin + '/v2/accounts/**', routeHandler);
    try {
        await page.goto(origin + '/#/apps/voip', {waitUntil: 'domcontentloaded'});
        await page.locator('#myoffice_container:visible').waitFor({timeout: 22000}); await idle();
        phase = 'stalled-dashboard-read'; fault = 'hold'; count = 0;
        await page.locator('.left-menu #myOffice').click();
        await page.locator('.smartpbx-load-retry:visible').waitFor({timeout: 22000});
        assert(release); await idle(); checks.push('stalled-read-times-out-and-unlocks-menu-and-blue-bar');
        await retryAndRecover(); checks.push('explicit-retry-restores-dashboard');
        const dashboard = await page.locator('#myoffice_container').elementHandle();
        await release(); release = null; await page.waitForTimeout(750);
        assert(await dashboard.evaluate(el => el === document.querySelector('#myoffice_container')));
        await idle(); checks.push('late-response-cannot-replace-recovered-dashboard');
        phase = 'failed-dashboard-read'; fault = '503'; count = 0;
        await page.locator('.left-menu #myOffice').click();
        await page.locator('.smartpbx-load-retry:visible').waitFor({timeout: 22000});
        await idle(); checks.push('503-shows-error-and-unlocks-menu-and-blue-bar');
        await retryAndRecover(); checks.push('retry-after-503-restores-dashboard');
        phase = 'navigation-during-read'; fault = 'hold'; count = 0;
        // Initial app entry leaves navigation available while reads are pending.
        await page.reload({waitUntil: 'domcontentloaded'});
        for (let i = 0; i < 100 && !release; i++) await page.waitForTimeout(100);
        assert(release);
        fault = null;
        await page.locator('.left-menu #devices').click();
        await page.locator('#devices_container:visible').waitFor({timeout: 10000});
        const content = await page.locator('.right-content').innerHTML();
        await release(); release = null; await page.waitForTimeout(750);
        await idle();
        assert.equal(await page.locator('.right-content').innerHTML(), content);
        assert.equal(await page.locator('#myoffice_container').count(), 0);
        checks.push('late-dashboard-read-cannot-overwrite-devices-navigation');
        await page.locator('.left-menu #myOffice').click();
        await page.locator('#myoffice_container:visible').waitFor({timeout: 22000}); await idle();
        assert.deepEqual(issues, []);
        console.log(JSON.stringify({status: 'PASS', checks, scope: 'SmartPBX browser-only GET faults; real auth/reads; account writes blocked'}));
    } catch (error) {
        console.error(JSON.stringify({status: 'FAIL', phase, checks, issues,
            state: await page.evaluate(() => ({counter: window.monster?.apps.core.request.counter,
                indicator: !!document.querySelector('.progress-indicator.active'),
                locked: document.querySelectorAll('.left-menu .category.loading').length,
                retry: !!document.querySelector('.smartpbx-load-retry')})).catch(() => ({}))}));
        throw error;
    } finally {
        if (release) await release();
        await page.unroute(origin + '/v2/accounts/**', routeHandler);
    }
};
