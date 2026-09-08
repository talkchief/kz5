'use strict';
// P0-22: real selected-queue Login, failed proof GET, read-only recovery, logout.
const fs = require('node:fs'), assert = require('node:assert/strict');
const fixture = require('./callback-fixture-account.cjs');
const ACCOUNT = '8310dc3170a18de37f205d0da172df65', ORIGIN = 'https://kz5-dev.talkchief.io';
module.exports = async function queueLoginBrowser(page, issues) {
    const state = fixture.readState('/etc/kazoo/acceptance-secrets.env');
    fixture.validateState(state, ACCOUNT);
    const agent = state.ACCEPTANCE_AGENT_1_USER_ID, queue = state.ACCEPTANCE_QUEUE_ID;
    assert(/^[a-f0-9]{32}$/.test(agent) && /^[a-f0-9]{32}$/.test(queue));
    const parent = '/var/log/kazoo-acceptance', stat = fs.lstatSync(parent);
    assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && !(stat.mode & 0o022));
    const dir = fs.mkdtempSync(parent + '/queue-login-browser.'); fs.chmodSync(dir, 0o700);
    const receipt = {account: ACCOUNT, agent, queue, phase: 'preflight', writes: [], status: 'pending'};
    const persist = () => fs.writeFileSync(dir + '/receipt.json', JSON.stringify(receipt, null, 2) + '\n', {mode: 0o600});
    persist(); console.log('Queue login evidence: ' + dir);
    const api = async suffix => page.evaluate(async ({account, suffix}) => {
        const response = await fetch('/v2/accounts/' + account + suffix,
            {headers: {'X-Auth-Token': monster.apps.acdc.getAuthToken()}});
        if (response.status !== 200) throw Error('Read failed');
        const body = await response.json(); if (body.status !== 'success') throw Error('Read failed');
        return body.data;
    }, {account: ACCOUNT, suffix});
    const statuses = async () => {
        const result = [];
        for (let i = 1; i <= Number(state.ACCEPTANCE_AGENT_COUNT); i++) {
            const id = state['ACCEPTANCE_AGENT_' + i + '_USER_ID'];
            assert(/^[a-f0-9]{32}$/.test(id));
            const data = await api('/agents/' + id + '/status');
            result.push({id, status: typeof data === 'string' ? data : data.status});
        }
        assert.equal(result.length, 30); return result;
    };
    const account = await api(''); assert.equal(account.name, state.ACCEPTANCE_ACCOUNT_NAME);
    assert.equal(account.realm, state.ACCEPTANCE_REALM);
    const before = await statuses();
    assert(before.every(row => ['logout', 'logged_out'].includes(row.status)), 'Requires idle logged-out fixture agents');
    const memberships = await api('/agents/' + agent + '/queue_status');
    assert(Array.isArray(memberships) && memberships.includes(queue));
    receipt.before = before; persist();
    await page.locator('#main_topbar_account_toggle_link').click();
    await page.locator('.account-list-element[data-id="' + ACCOUNT + '"] .account-name').click();
    await page.waitForFunction(id => monster.apps.auth.currentAccount.id === id && monster.apps.acdc.accountId === id,
        ACCOUNT, {timeout: 20000});
    let action = null, injectFailure = false, failedRequest = null;
    await page.route(ORIGIN + '/v2/accounts/**', async route => {
        const request = route.request(), url = new URL(request.url());
        if (['GET', 'HEAD', 'OPTIONS'].includes(request.method())) {
            if (injectFailure && request.method() === 'GET' &&
                url.pathname === '/v2/accounts/' + ACCOUNT + '/agents/' + agent + '/queue_status' &&
                url.searchParams.get('runtime_only') === 'true' && url.searchParams.get('queue_id') === queue) {
                injectFailure = false; failedRequest = request;
                await route.abort('failed'); return;
            }
            return route.continue();
        }
        try {
            assert(action && !action.sent, 'Unexpected or duplicate agent write');
            assert.equal(request.method(), 'POST');
            assert.equal(url.pathname, '/v2/accounts/' + ACCOUNT + '/agents/' + agent +
                (action.type === 'login' ? '/queue_status' : '/status'));
            const data = request.postDataJSON().data;
            if (action.type === 'login') {
                assert.equal(data.action, 'login'); assert.equal(data.queue_id, queue);
                assert.equal(data.runtime_only, true);
            } else { assert.equal(data.status, 'logout'); }
            action.sent = true; persist(); await route.continue();
        } catch (_) { issues.push('unexpected-agent-mutation'); await route.abort(); }
    });
    try {
        receipt.phase = 'login-dialog'; persist();
        await page.locator('.acdc-tab[data-tab="agents"]').click();
        await page.locator('.acdc-agent-queue-login[data-id="' + agent + '"]:visible').click();
        const dialog = page.locator('.acdc-queue-login-dialog:visible');
        const choices = dialog.locator('.acdc-login-queue');
        await choices.selectOption(queue);
        await page.waitForFunction(() => !document.querySelector('.acdc-confirm-queue-login').disabled,
            null, {timeout: 20000});
        action = {type: 'login', sent: false}; receipt.writes.push(action); receipt.phase = 'login'; persist();
        await dialog.locator('.acdc-confirm-queue-login').click();
        await page.waitForFunction(() => document.querySelector('.acdc-login-message')?.textContent ===
            monster.apps.acdc.i18n.active().acdc.agents.queueConfirmed, null, {timeout: 20000});
        assert(action.sent); assert.deepEqual(issues, []);
        const proof = await api('/agents/' + agent + '/queue_status?runtime_only=true&queue_id=' + queue + '&action=login');
        assert.equal(proof.confirmed, true); assert.equal(proof.runtime_member, true);
        receipt.login_confirmed = true; receipt.phase = 'failed-read'; persist();
        const failureOffset = issues.length;
        injectFailure = true;
        await dialog.locator('.acdc-check-queue-login').click();
        await page.waitForFunction(() => document.querySelector('.acdc-login-message')?.textContent ===
            monster.apps.acdc.i18n.active().acdc.agents.queueProofUnavailable, null, {timeout: 15000});
        assert(failedRequest && !injectFailure);
        assert.deepEqual(issues.slice(failureOffset), [failedRequest.failure().errorText]);
        issues.splice(failureOffset, 1); // Only the exact deliberately aborted request.
        assert.equal(await dialog.locator('.acdc-confirm-queue-login').isDisabled(), true);
        receipt.phase = 'read-recovery'; persist();
        await dialog.locator('.acdc-check-queue-login').click();
        await page.waitForFunction(() => document.querySelector('.acdc-login-message')?.textContent ===
            monster.apps.acdc.i18n.active().acdc.agents.queueConfirmed, null, {timeout: 20000});
        assert.equal(receipt.writes.length, 1); receipt.read_recovery = true; persist();
        await dialog.locator('.acdc-cancel-queue-login').click();
        receipt.phase = 'restore-selected-agent';
        action = {type: 'logout', sent: false}; receipt.writes.push(action); persist();
        await page.locator('.acdc-action-logout[data-id="' + agent + '"]:visible').click();
        let after;
        for (let attempt = 0; attempt < 10; attempt++) {
            after = await statuses();
            if (after.every(row => ['logout', 'logged_out'].includes(row.status))) break;
            await page.waitForTimeout(500);
        }
        assert(action.sent);
        assert.deepEqual(after, before);
        assert.deepEqual(await api('/agents/' + agent + '/queue_status'), memberships);
        assert.deepEqual(issues, []);
        receipt.status = 'PASS'; receipt.phase = 'complete'; receipt.after = after; persist();
        console.log(JSON.stringify({status: 'PASS', real_login_confirmed: true, failed_read_recovered: true,
            login_posts: 1, selected_agent_logged_out: true, unchanged_other_agents: 29,
            unchanged_memberships: true, intentional_failed_gets: 1, evidence: dir}));
    } catch (error) {
        receipt.status = 'FAIL'; persist();
        console.error('Queue login check failed at ' + receipt.phase + '; retained evidence: ' + dir);
        throw error;
    }
};
