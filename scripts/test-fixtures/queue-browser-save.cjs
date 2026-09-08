'use strict';
// Actual UI Save on the protected fixture only. No injected API response/payload.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const fixture = require('./callback-fixture-account.cjs');
const ACCOUNT = '8310dc3170a18de37f205d0da172df65';
const ORIGIN = 'https://kz5-dev.talkchief.io';
module.exports = async function queueBrowserSave(page, issues) {
    const state = fixture.readState('/etc/kazoo/acceptance-secrets.env');
    assert.equal(fixture.validateState(state, ACCOUNT), ACCOUNT);
    const parent = '/var/log/kazoo-acceptance';
    const st = fs.lstatSync(parent);
    assert(st.isDirectory() && !st.isSymbolicLink() && st.uid === 0 && !(st.mode & 0o022));
    const dir = fs.mkdtempSync(path.join(parent, 'browser-queue-save.'));
    fs.chmodSync(dir, 0o700);
    const receipt = {account: ACCOUNT, marker: 'UI Save acceptance ' + crypto.randomBytes(8).toString('hex'),
        status: 'pending', queue_id: null, intents: [], readbacks: [], retained: true};
    const persist = () => fs.writeFileSync(path.join(dir, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {mode: 0o600});
    persist();
    console.log('Protected queue-save evidence: ' + dir);
    const api = async suffix => page.evaluate(async ({account, suffix}) => {
        const response = await fetch('/v2/accounts/' + account + suffix, {
            headers: {'X-Auth-Token': monster.apps.acdc.getAuthToken()}});
        if (response.status !== 200) throw Error('Readback failed');
        const body = await response.json();
        if (body.status !== 'success') throw Error('Readback not successful');
        return body.data;
    }, {account: ACCOUNT, suffix});
    const account = await api('');
    assert.equal(account.name, state.ACCEPTANCE_ACCOUNT_NAME);
    assert.equal(account.realm, state.ACCEPTANCE_REALM);
    const baseline = (await api('/queues?paginate=false')).map(queue => queue.id).sort();
    await page.locator('#main_topbar_account_toggle_link').click();
    await page.locator('.account-list-element[data-id="' + ACCOUNT + '"] .account-name').click();
    await page.waitForFunction(id => monster.apps.auth.currentAccount.id === id && monster.apps.acdc.accountId === id,
        ACCOUNT, {timeout: 20000});
    await page.locator('.acdc-live-add:visible').first().waitFor({timeout: 20000});
    let pending;
    await page.route(ORIGIN + '/v2/accounts/**', async route => {
        const request = route.request();
        if (['GET', 'HEAD', 'OPTIONS'].includes(request.method())) return route.continue();
        try {
            assert(pending && pending.sent === false, 'Unexpected or duplicate write');
            const endpoint = '/v2/accounts/' + ACCOUNT + '/queues/' +
                (receipt.queue_id ? receipt.queue_id + '/editor' : 'editor');
            assert.equal(new URL(request.url()).pathname, endpoint);
            assert.equal(request.method(), receipt.queue_id ? 'PATCH' : 'PUT');
            const data = request.postDataJSON().data;
            assert.deepEqual(Object.keys(data).sort(), ['queue', 'request_id', 'revisions', 'roster', 'route']);
            assert.equal(data.queue.name, receipt.marker);
            assert.equal(data.queue.callback.enabled, false);
            assert.equal(data.queue.announcements.language, pending.language);
            assert.equal(data.queue.announcements.interval, 17);
            assert.equal(data.queue.callback.announcement.interval, 30);
            assert.deepEqual(data.roster, []);
            assert.deepEqual(data.route, {extension: ''});
            assert(/^[a-f0-9]{32}$/.test(data.request_id));
            pending.request_id = data.request_id; pending.sent = true;
            pending.body_sha256 = crypto.createHash('sha256').update(request.postData()).digest('hex');
            persist();
            await route.continue();
        } catch (_) {
            issues.push('unapproved-browser-write'); receipt.status = 'write-refused'; persist();
            await route.abort();
        }
    });
    try {
        await page.locator('.acdc-live-add:visible').first().click();
        for (const language of ['en-us', 'he-il', 'ar-sa', 'fr-fr', 'es-es']) {
            if (receipt.queue_id) await page.locator('.acdc-edit-queue[data-id="' + receipt.queue_id + '"]:visible').click();
            const form = page.locator('.acdc-queue-form:visible');
            await form.waitFor({timeout: 30000});
            await form.locator('[name="name"]').fill(receipt.marker);
            await form.locator('[name="announcements.language"]').selectOption(language);
            await form.locator('[name="announcements.interval"]').fill('17');
            // Exercise real controls, then leave callbacks disabled on this
            // deliberately unassigned/non-dialable fixture queue.
            await form.locator('[name="callback.enabled"]').check();
            await form.locator('[name="callback.announcement.interval"]').fill('30');
            await form.locator('[name="callback.enabled"]').uncheck();
            assert.equal(await form.locator('[name="route_extension"]').inputValue(), '');
            assert.equal(await form.evaluate(element => element.checkValidity()), true);
            pending = {language, sent: false, state: 'in_flight'};
            receipt.intents.push(pending); persist();
            const responsePromise = page.waitForResponse(response => {
                const request = response.request();
                return ['PUT', 'PATCH'].includes(request.method()) &&
                    new URL(response.url()).pathname.endsWith('/editor');
            }, {timeout: 30000});
            await form.locator('[type="submit"]').click();
            const response = await responsePromise;
            assert.equal(response.status(), receipt.queue_id ? 200 : 201);
            const body = await response.json(), result = body.data;
            assert.equal(body.status, 'success');
            assert.equal(result.state, 'complete');
            assert(/^[a-f0-9]{32}$/.test(result.queue_id));
            if (receipt.queue_id) assert.equal(result.queue_id, receipt.queue_id);
            receipt.queue_id = result.queue_id;
            pending.state = 'complete'; pending.operation_id = result.operation_id; persist();
            await form.waitFor({state: 'hidden', timeout: 20000});
            const saved = await api('/queues/' + receipt.queue_id);
            assert.equal(saved.name, receipt.marker);
            assert.equal(saved.callback.enabled, false);
            assert.equal(saved.announcements.language, language);
            assert.equal(saved.announcements.interval, 17);
            assert.equal(saved.callback.announcement.interval, 30);
            assert.deepEqual(saved.agents || [], []);
            assert.deepEqual(issues, []);
            receipt.readbacks.push(language); persist();
        }
        // Freshly reopen the real form, not just API readback.
        await page.locator('.acdc-edit-queue[data-id="' + receipt.queue_id + '"]:visible').click();
        const finalForm = page.locator('.acdc-queue-form:visible');
        await finalForm.waitFor({timeout: 20000});
        assert.equal(await finalForm.locator('[name="announcements.language"]').inputValue(), 'es-es');
        assert.equal(await finalForm.locator('[name="announcements.interval"]').inputValue(), '17');
        assert.equal(await finalForm.locator('[name="callback.announcement.interval"]').inputValue(), '30');
        await finalForm.locator('.acdc-cancel').click();
        const after = (await api('/queues?paginate=false')).map(queue => queue.id).sort();
        assert.deepEqual(after, [...baseline, receipt.queue_id].sort());
        assert.equal(await page.evaluate(() => monster.apps.core.request.counter), 0);
        assert.equal(await page.locator('.progress-indicator.active').count(), 0);
        assert.deepEqual(issues, []);
        receipt.status = 'PASS'; persist();
        console.log(JSON.stringify({status: 'PASS', actual_ui_saves: 5, languages: receipt.readbacks,
            separate_intervals: [17, 30], final_form_reopened: true, queue_id: receipt.queue_id,
            retained: 'one empty-roster, no-extension, callbacks-disabled fixture queue', evidence: dir}));
    } catch (error) {
        receipt.status = 'FAIL'; persist();
        // Never resend ambiguous writes or delete an uncertain result.
        console.error('Queue browser save failed; no automatic retry/cleanup; evidence: ' + dir);
        throw error;
    }
};
