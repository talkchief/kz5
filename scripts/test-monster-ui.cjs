// Browser acceptance test; use a separate Node >=20/Playwright test workspace.
const fs = require('node:fs');
const { chromium } = require(process.env.KAZOO_PLAYWRIGHT_MODULE || 'playwright');

function readProtectedFile(filePath, label) {
    const stat = fs.lstatSync(filePath);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.uid !== 0 || (stat.mode & 0o777) !== 0o600) {
        throw new Error(`${label} must be a root-owned 0600 regular file`);
    }
    return fs.readFileSync(filePath, 'utf8');
}

function readPlainSecrets(filePath) {
    const contents = readProtectedFile(filePath, 'Master credentials');
    const result = {};
    for (const rawLine of contents.split('\n')) {
        const line = rawLine.trim();
        if (!line || line.startsWith('#')) continue;
        const split = line.indexOf('=');
        if (split < 1) throw new Error('Malformed master credentials file');
        result[line.slice(0, split)] = line.slice(split + 1);
    }
    return result;
}

function readBase64State(filePath) {
    const contents = readProtectedFile(filePath, 'Acceptance state');
    const result = {};
    for (const rawLine of contents.split('\n')) {
        const line = rawLine.trim();
        if (!line || line.startsWith('#')) continue;
        const split = line.indexOf('=');
        if (split < 1) throw new Error('Malformed acceptance state file');
        const key = line.slice(0, split);
        const encoded = line.slice(split + 1);
        if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
            throw new Error(`Invalid base64 value in acceptance state for ${key}`);
        }
        const decoded = Buffer.from(encoded, 'base64');
        if (decoded.toString('base64') !== encoded) {
            throw new Error(`Non-canonical base64 value in acceptance state for ${key}`);
        }
        result[key] = decoded.toString('utf8');
    }
    return result;
}

function validateAcceptanceState(state) {
    const idPattern = /^[a-f0-9]{32}$/;
    const count = Number.parseInt(state.ACCEPTANCE_AGENT_COUNT, 10);
    if (!idPattern.test(state.ACCEPTANCE_ACCOUNT_ID || '')) {
        throw new Error('Acceptance state does not contain a valid account ID');
    }
    if (!/^Kazoo5 Acceptance [a-f0-9]{12}$/.test(state.ACCEPTANCE_ACCOUNT_NAME || '')) {
        throw new Error('Acceptance state does not contain the isolated account name');
    }
    if (!/^acceptance-[a-f0-9]{12}\.invalid$/.test(state.ACCEPTANCE_REALM || '')) {
        throw new Error('Acceptance state does not contain the isolated account realm');
    }
    if (count !== 30) {
        throw new Error(`Browser acceptance requires exactly 30 provisioned agents; found ${Number.isNaN(count) ? 0 : count}`);
    }
    const agentIds = [];
    for (let index = 1; index <= count; index += 1) {
        const id = state[`ACCEPTANCE_AGENT_${index}_USER_ID`];
        if (!idPattern.test(id || '')) throw new Error(`Acceptance agent ${index} has no valid user ID`);
        agentIds.push(id);
    }
    if (new Set(agentIds).size !== count) throw new Error('Acceptance agent user IDs are not unique');
    if (!idPattern.test(state.ACCEPTANCE_QUEUE_ID || '')
        || !idPattern.test(state.ACCEPTANCE_QUEUE_CALLFLOW_ID || '')
        || !/^\d{1,36}$/.test(state.ACCEPTANCE_QUEUE_EXTENSION || '')) {
        throw new Error('Acceptance state does not contain a valid external queue route');
    }
    return {
        account: {
            id: state.ACCEPTANCE_ACCOUNT_ID,
            name: state.ACCEPTANCE_ACCOUNT_NAME,
            realm: state.ACCEPTANCE_REALM
        },
        agentIds,
        queue: {
            id: state.ACCEPTANCE_QUEUE_ID,
            callflowId: state.ACCEPTANCE_QUEUE_CALLFLOW_ID,
            extension: state.ACCEPTANCE_QUEUE_EXTENSION
        }
    };
}

function isApiPath(response, accountId, suffix, method) {
    const url = new URL(response.url());
    return url.pathname === `/v2/accounts/${accountId}${suffix}` && response.request().method() === method;
}

async function writeQueueForValidation(page, queueId, data, resource) {
    return page.evaluate(({ queueId: qid, payload, requestResource }) => new Promise(resolve => {
        const monster = window.require('monster');
        const app = monster.apps.acdc;
        if (requestResource === 'acdc.queues.post') {
            app.requests[requestResource] = {
                url: 'accounts/{accountId}/queues/{queueId}',
                verb: 'POST',
                generateError: false
            };
            monster._defineRequest(requestResource, app.requests[requestResource], app);
        }
        app.request(requestResource, {
            queueId: qid,
            data: payload
        }, error => resolve({ rejected: Boolean(error) }));
    }), { queueId, payload: data, requestResource: resource });
}

async function waitForAcdcContent(page, selector) {
    const locator = page.locator(selector);
    try {
        await locator.waitFor({ state: 'visible', timeout: 30000 });
    } catch (error) {
        const state = await page.locator(selector).evaluateAll(elements => elements.map(element => {
            const wrapper = element.closest('#acdc_wrapper');
            const content = element.closest('#monster_content');
            return {
                connected: element.isConnected,
                display: getComputedStyle(element).display,
                visibility: getComputedStyle(element).visibility,
                wrapperDisplay: wrapper ? getComputedStyle(wrapper).display : 'missing',
                contentDisplay: content ? getComputedStyle(content).display : 'missing'
            };
        }));
        throw new Error(`ACDC selector was not visible: ${JSON.stringify(state)}; ${error.message}`);
    }
    if (await page.locator('#acdc_wrapper .acdc-retry').count()) {
        throw new Error('ACDC rendered an API error state');
    }
}

async function closeMyAccountIfOpen(page, settleMs = 1500) {
    await page.waitForTimeout(settleMs);
    const myAccount = page.locator('#myaccount');
    const isOpen = await myAccount.evaluate(element => element.classList.contains('myaccount-open'));
    if (!isOpen) {
        await page.evaluate(() => window.require('jquery')(document).off('focusin.dialog'));
        return false;
    }
    await page.locator('#monster_content').waitFor({ state: 'hidden', timeout: 30000 });
    await page.evaluate(() => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            monster.pub('myaccount.hide');
            resolve();
        }, reject);
    }));
    await page.locator('#monster_content').waitFor({ state: 'visible', timeout: 10000 });
    await page.evaluate(() => window.require('jquery')(document).off('focusin.dialog'));
    return true;
}

async function confirmMonsterDialog(page) {
    const button = page.locator('.monster-confirm #confirm_button');
    await button.waitFor({ state: 'visible', timeout: 10000 });
    // Monster UI 4.x ships jQuery UI 1.10.3. Its modal focus trap can outlive
    // a dialog during the 200 ms destroy animation and dereference removed
    // widget data. Disable only that test-page focus trap before closing; this
    // does not change confirmation callbacks or production source behavior.
    await page.evaluate(() => {
        const jquery = window.require('jquery');
        jquery(document).off('focusin.dialog');
    });
    await button.click();
    await button.waitFor({ state: 'detached', timeout: 10000 });
}

async function loadAcdcApp(page) {
    await page.evaluate(() => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            monster.routing.goTo('apps/acdc');
            resolve();
        }, error => reject(new Error(error && error.message ? error.message : 'Unable to load Monster')));
    }));
    await waitForAcdcContent(page, '#acdc_wrapper .acdc-summary-grid');
}

async function selectRoster(page, agentIds) {
    // Operate the visible Chosen widget as a user would, not its hidden select.
    const search = page.locator('.acdc-queue-form .chosen-container .chosen-choices input');
    for (const agentId of agentIds) {
        const label = await page.locator(`.acdc-roster option[value="${agentId}"]`).textContent();
        await search.click();
        await search.fill('');
        await search.pressSequentially(label.trim());
        await page.locator('.acdc-queue-form .chosen-results .active-result')
            .filter({ hasText: label.trim() }).first().click();
    }
}

async function getAgentStatus(page, agentId) {
    return page.evaluate(id => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            const app = monster.apps.acdc;
            app.request('acdc.agents.statuses', {}, (error, statuses) => {
                if (error) reject(new Error('Could not refresh the reserved agent status'));
                else resolve(app.normalizeStatuses(statuses)[id] || 'unknown');
            });
        }, () => reject(new Error('Monster is unavailable while reading agent status')));
    }), agentId);
}

async function waitForAgentStatus(page, agentId, expectedStatuses) {
    const deadline = Date.now() + 30000;
    let status = 'unknown';
    while (Date.now() < deadline) {
        status = await getAgentStatus(page, agentId);
        if (expectedStatuses.includes(status)) return status;
        await new Promise(resolve => setTimeout(resolve, 250));
    }
    throw new Error(`Reserved agent did not reach the expected state (last state: ${status})`);
}

async function setAgentStatusFromUi(page, accountId, agentId, action, expectedStatuses) {
    const actionButton = page.locator(`.acdc-agent-action[data-id="${agentId}"][data-status="${action}"]`);
    await actionButton.waitFor({ state: 'visible', timeout: 30000 });
    if (action === 'pause') {
        await actionButton.locator('xpath=ancestor::tr').locator('.acdc-pause-timeout').fill('5');
    }
    const responsePromise = page.waitForResponse(
        response => isApiPath(response, accountId, `/agents/${agentId}/status`, 'POST'),
        { timeout: 30000 }
    );
    await actionButton.click();
    const response = await responsePromise;
    if (!response.ok()) throw new Error(`Agent ${action} action failed (HTTP ${response.status()})`);
    await waitForAgentStatus(page, agentId, expectedStatuses);
}

async function forceAgentLogout(page, agentId) {
    return page.evaluate(id => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            const app = monster.apps.acdc;
            app.request('acdc.agents.setStatus', {
                agentId: id,
                data: { status: 'logout' }
            }, error => {
                if (error) reject(new Error('Could not restore the reserved agent to logged out'));
                else resolve();
            });
        }, () => reject(new Error('Monster is unavailable during agent cleanup')));
    }), agentId);
}

async function getCallflowSignature(page, callflowId) {
    return page.evaluate(id => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            monster.apps.acdc.request('acdc.callflows.get', { callflowId: id }, (error, route) => {
                if (error) {
                    reject(new Error('Could not verify the external ACDC route'));
                    return;
                }
                resolve(JSON.stringify({
                    id: route.id,
                    name: route.name,
                    numbers: route.numbers,
                    flags: route.flags || [],
                    flow: route.flow
                }));
            });
        }, () => reject(new Error('Monster is unavailable while reading callflow')));
    }), callflowId);
}

async function getManagedRouteDiagnostics(page, queueId) {
    return page.evaluate(id => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            const app = monster.apps.acdc;
            app.loadAcdcCallflowInventory((error, inventory) => {
                if (error) {
                    reject(new Error('Could not inspect the stale browser route'));
                    return;
                }
                const routes = inventory.routes.filter(route => app.isAcdcQueueReference(route.flow, id));
                resolve(routes.map(route => ({
                    strict: app.isStrictManagedRoute(route, id),
                    idString: typeof route.id === 'string' && route.id.length > 0,
                    numberShape: Array.isArray(route.numbers) && route.numbers.length === 1
                        && typeof route.numbers[0] === 'string' && /^\+?[0-9*#]+$/.test(route.numbers[0]),
                    flagsMatch: JSON.stringify(route.flags) === JSON.stringify([
                        app.managedRouteFlag,
                        app.managedRouteQueueFlagPrefix + id
                    ]),
                    flowKeys: route.flow && Object.keys(route.flow).sort().join(',') === 'children,data,module',
                    dataKeys: route.flow && route.flow.data
                        && Object.keys(route.flow.data).join(',') === 'id',
                    queueMatches: route.flow && route.flow.data && route.flow.data.id === id,
                    childrenEmpty: route.flow && route.flow.children
                        && Object.keys(route.flow.children).length === 0,
                    patternsEmpty: route.patterns === undefined
                        || (Array.isArray(route.patterns) && route.patterns.length === 0)
                })));
            });
        }, () => reject(new Error('Monster is unavailable while diagnosing managed routes')));
    }), queueId);
}

async function removeQueueForCleanup(page, queueId) {
    return page.evaluate(id => new Promise((resolve, reject) => {
        window.require(['monster'], monster => {
            const app = monster.apps.acdc;
            if (!app || typeof app.request !== 'function' || typeof app.loadAcdcCallflowInventory !== 'function') {
                reject(new Error('ACDC app is unavailable for fixture cleanup'));
                return;
            }
            app.loadAcdcCallflowInventory((inventoryError, inventory) => {
                if (inventoryError) {
                    reject(new Error('Could not verify ACDC routes during fixture cleanup'));
                    return;
                }
                const references = inventory.routes.filter(route => app.isAcdcQueueReference(route.flow, id));
                const owned = references.filter(route => app.isStrictManagedRoute(route, id));
                const external = references.filter(route => !owned.some(candidate => candidate.id === route.id));
                if (external.length || owned.length > 1) {
                    reject(new Error('Refusing fixture cleanup because the queue has unowned or ambiguous routes'));
                    return;
                }
                const deleteQueue = () => app.request('acdc.queues.delete', {
                    queueId: id,
                    data: {}
                }, error => {
                    if (error) reject(new Error('Could not remove the isolated browser queue fixture'));
                    else resolve();
                });
                if (!owned.length) {
                    deleteQueue();
                    return;
                }
                app.request('acdc.callflows.delete', {
                    callflowId: owned[0].id,
                    data: {}
                }, error => {
                    if (error) reject(new Error('Could not remove the app-owned route during fixture cleanup'));
                    else deleteQueue();
                });
            });
        }, () => reject(new Error('Monster is unavailable for fixture cleanup')));
    }), queueId);
}

(async () => {
    const secretsPath = process.env.KAZOO_INSTALLER_SECRETS || '/etc/kazoo/installer-secrets.env';
    const acceptancePath = process.env.KAZOO_ACCEPTANCE_STATE_FILE || '/etc/kazoo/acceptance-secrets.env';
    const secrets = readPlainSecrets(secretsPath);
    const acceptance = validateAcceptanceState(readBase64State(acceptancePath));
    if (!secrets.KAZOO_MASTER_ADMIN_PASSWORD) throw new Error('Master credentials file has no administrator password');

    const browser = await chromium.launch({ headless: true });
    const pageErrors = [];
    const deadline = setTimeout(() => browser.close().catch(() => {}), 240000);
    let page;
    let createdQueueId;
    let createdRouteId;
    let expectedValidationQueueId;
    let reservedAgentNeedsLogout = false;
    let agentStatusTested = false;
    let primaryError;
    let browserStage = 'startup';
    try {
        page = await browser.newPage();
        const failedResponses = [];
        page.on('pageerror', error => pageErrors.push(`${browserStage}: ${error.message}`));
        page.on('response', response => {
            // No whitelabel has been provisioned: these optional lookups use
            // Monster UI's built-in branding fallback when Crossbar returns 404.
            if (response.status() < 400) return;
            const url = new URL(response.url());
            if (response.status() === 404 && url.pathname.startsWith('/v2/whitelabel/')) return;
            // The isolated deployment has no Braintree billing customer. The
            // built-in My Account plugin treats this optional lookup as empty.
            if (response.status() === 404
                && /^\/v2\/accounts\/[a-f0-9]{32}\/braintree\/customer$/.test(url.pathname)) return;
            // Deliberately malformed queue PATCH/POST requests below prove
            // that Crossbar enforces the announcement schema. Only their
            // tagged HTTP 400 responses are expected failures.
            if (response.status() === 400
                && expectedValidationQueueId
                && ['PATCH', 'POST'].includes(response.request().method())
                && url.pathname === `/v2/accounts/${acceptance.account.id}/queues/${expectedValidationQueueId}`) return;
            failedResponses.push(`${response.status()} ${url.origin}${url.pathname}`);
        });
        await page.goto(process.env.KAZOO_TEST_UI_URL || 'http://127.0.0.1/', {
            waitUntil: 'networkidle', timeout: 60000
        });
        await page.locator('#login').fill(secrets.KAZOO_MASTER_ADMIN_USER || 'admin');
        await page.locator('#password').fill(secrets.KAZOO_MASTER_ADMIN_PASSWORD);
        await page.locator('#account_name').fill(process.env.KAZOO_TEST_ACCOUNT_NAME || 'KazooMaster');
        const authResponse = page.waitForResponse(response => {
            return new URL(response.url()).pathname === '/v2/user_auth' && response.request().method() === 'PUT';
        }, { timeout: 30000 });
        await page.getByRole('button', { name: 'Sign in', exact: true }).click();
        browserStage = 'login';
        const auth = await authResponse;
        const authBody = await auth.json();
        if (!auth.ok() || authBody.status !== 'success') throw new Error(`Browser login failed (HTTP ${auth.status()})`);
        await page.locator('#login').waitFor({ state: 'hidden', timeout: 30000 });
        await page.waitForLoadState('networkidle', { timeout: 30000 });
        await page.waitForFunction(() => {
            const monster = window.require('monster');
            return monster.apps.auth.appsStore !== undefined;
        }, undefined, { timeout: 30000 });

        const catalog = await page.evaluate(() => new Promise((resolve, reject) => {
            window.require(['monster'], monster => {
                const metadata = monster.util.getAppStoreMetadata('acdc');
                const assignedApps = monster.apps.auth.currentUser.appList || [];
                const assigned = Boolean(metadata && assignedApps.some(item => {
                    if (typeof item === 'string') return item === metadata.id;
                    return item && (item.id === metadata.id || item.name === 'acdc');
                }));
                resolve({
                    assigned,
                    metadataName: metadata && metadata.name,
                    masqueradable: metadata && metadata.masqueradable === true,
                    availableApps: Object.values(monster.apps.auth.appsStore || {}).map(app => app.name),
                    assignedCount: assignedApps.length
                });
            }, error => reject(new Error(error && error.message ? error.message : 'Unable to inspect app catalog')));
        }));
        if (!catalog.assigned || catalog.metadataName !== 'acdc'
            || !catalog.availableApps.includes('acdc')) {
            throw new Error(`ACDC is not assigned and visible in the administrator app catalog: ${JSON.stringify(catalog)}`);
        }
        if (!catalog.masqueradable) throw new Error('ACDC app metadata does not permit child-account masquerading');
        // Some Monster builds open My Account after login and some leave the
        // normal content visible. If it did open, allow its transitionend side
        // effect to settle before closing it so a late handler cannot hide ACDC.
        await closeMyAccountIfOpen(page);
        browserStage = 'masquerade';

        await page.evaluate(account => new Promise((resolve, reject) => {
            window.require(['monster'], monster => {
                const timer = window.setTimeout(() => reject(new Error('Timed out entering the acceptance account')), 10000);
                monster.pub('core.triggerMasquerading', {
                    account,
                    callback: () => {
                        window.clearTimeout(timer);
                        resolve();
                    }
                });
            }, error => reject(new Error(error && error.message ? error.message : 'Unable to masquerade')));
        }), acceptance.account);
        const activeAccountId = await page.evaluate(() => new Promise((resolve, reject) => {
            window.require(['monster'], monster => resolve(monster.apps.auth.currentAccount.id), reject);
        }));
        if (activeAccountId !== acceptance.account.id) throw new Error('Monster did not enter the isolated acceptance account');

        // Masquerading may refresh My Account. If it opens again, allow its
        // transition to complete before closing it through the public event.
        await closeMyAccountIfOpen(page);

        await loadAcdcApp(page);
        browserStage = 'dashboard';

        // Exercise an explicit dashboard refresh and wait for all primary stats reads.
        const dashboardRefresh = [
            page.waitForResponse(response => isApiPath(response, acceptance.account.id, '/queues/stats', 'GET'), { timeout: 30000 }),
            page.waitForResponse(response => isApiPath(response, acceptance.account.id, '/agents/stats', 'GET'), { timeout: 30000 }),
            page.waitForResponse(response => isApiPath(response, acceptance.account.id, '/acdc_call_stats', 'GET'), { timeout: 30000 })
        ];
        await page.locator('#acdc_wrapper .acdc-refresh').click();
        const refreshed = await Promise.all(dashboardRefresh);
        if (refreshed.some(response => !response.ok())) throw new Error('One or more ACDC dashboard statistics requests failed');
        await waitForAcdcContent(page, '#acdc_wrapper .acdc-summary-grid');

        // The final provisioned agent is reserved for this browser-only state test.
        await page.locator('.acdc-tab[data-tab="agents"]').click();
        await waitForAcdcContent(page, '.acdc-agent-table');
        const agentRows = page.locator('.acdc-agent-table tbody tr');
        const agentRowCount = await agentRows.count();
        if (agentRowCount !== 30) {
            throw new Error(`ACDC agent table did not render exactly 30 agents (found ${agentRowCount})`);
        }
        for (const agentId of acceptance.agentIds) {
            if (await page.locator(`.acdc-agent-action[data-id="${agentId}"]`).count() === 0) {
                throw new Error('ACDC agent table is missing one of the isolated acceptance agents');
            }
        }

        const reservedAgentId = acceptance.agentIds[29];
        if (process.env.KAZOO_SKIP_AGENT_STATUS !== '1') {
            reservedAgentNeedsLogout = true;
            await setAgentStatusFromUi(page, acceptance.account.id, reservedAgentId, 'login', ['logged_in', 'ready']);
            await setAgentStatusFromUi(page, acceptance.account.id, reservedAgentId, 'pause', ['pause', 'paused']);
            await setAgentStatusFromUi(page, acceptance.account.id, reservedAgentId, 'resume', ['logged_in', 'ready']);
            await setAgentStatusFromUi(page, acceptance.account.id, reservedAgentId, 'logout', ['logout', 'logged_out']);
            reservedAgentNeedsLogout = false;
            agentStatusTested = true;
        }

        const unique = `${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
        const initialName = `Browser Acceptance ${unique}`;
        const editedName = `Browser Acceptance Edited ${unique}`;
        const initialExtension = `8${Date.now().toString().slice(-5)}`;
        const editedExtension = `7${Date.now().toString().slice(-5)}`;
        const rosterIds = acceptance.agentIds.slice(0, 2).sort();
        const externalRouteBefore = await getCallflowSignature(page, acceptance.queue.callflowId);

        await page.locator('.acdc-tab[data-tab="queues"]').click();
        browserStage = 'queue-create';
        await waitForAcdcContent(page, '.acdc-add-queue');
        const staleBrowserRows = page.locator('.acdc-table tbody tr').filter({ hasText: 'Browser Acceptance ' });
        if (await staleBrowserRows.count()) {
            const staleQueueId = await staleBrowserRows.first().locator('.acdc-edit-queue').getAttribute('data-id');
            const diagnostics = await getManagedRouteDiagnostics(page, staleQueueId);
            throw new Error(`A stale browser fixture was present before creation: ${JSON.stringify(diagnostics)}`);
        }
        await page.locator('.acdc-add-queue').click();
        await waitForAcdcContent(page, '.acdc-queue-form');
        await page.locator('.acdc-queue-form [name="name"]').fill(initialName);
        await page.locator('.acdc-queue-form [name="strategy"]').selectOption('round_robin');
        await page.locator('.acdc-queue-form [name="ring_simultaneously"]').fill('2');
        await page.locator('.acdc-queue-form [name="moh"]').fill('local_stream://default');
        await page.locator('.acdc-preconnect-announcement').fill('prompt://queue-you-are-next');
        await page.locator('.acdc-position-announcements').check();
        await page.locator('.acdc-wait-announcements').check();
        await page.locator('.acdc-announcement-interval').fill('45');
        await page.locator('.acdc-announcement-language').fill('en-us');
        await page.locator('.acdc-route-extension').fill(initialExtension);
        await selectRoster(page, rosterIds);

        const createResponsePromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, '/queues', 'PUT'),
            { timeout: 30000 }
        );
        const createRosterPromise = page.waitForResponse(response => {
            const url = new URL(response.url());
            return new RegExp(`^/v2/accounts/${acceptance.account.id}/queues/[a-f0-9]{32}/roster$`).test(url.pathname)
                && response.request().method() === 'POST';
        }, { timeout: 30000 });
        const createRoutePromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, '/callflows', 'PUT'),
            { timeout: 30000 }
        );
        await page.locator('.acdc-queue-form button[type="submit"]').click();
        const createResponse = await createResponsePromise;
        const createBody = await createResponse.json();
        createdQueueId = createBody && createBody.data && (createBody.data.id || createBody.data._id);
        if (!createResponse.ok() || !/^[a-f0-9]{32}$/.test(createdQueueId || '')) {
            throw new Error(`ACDC queue creation failed (HTTP ${createResponse.status()})`);
        }
        const createdAnnouncements = createBody.data && createBody.data.announcements;
        browserStage = 'queue-validation';
        if (createBody.data.moh !== 'local_stream://default'
            || createBody.data.announce !== 'prompt://queue-you-are-next'
            || !createdAnnouncements
            || createdAnnouncements.interval !== 45
            || createdAnnouncements.language !== 'en-us'
            || createdAnnouncements.position_announcements_enabled !== true
            || createdAnnouncements.wait_time_announcements_enabled !== true
            || createdAnnouncements.media.you_are_at_position !== 'queue-you_are_at_position'
            || createdAnnouncements.media.in_the_queue !== 'queue-in_the_queue'
            || createdAnnouncements.media.the_estimated_wait_time_is !== 'queue-the_estimated_wait_time_is'
            || createdAnnouncements.media.increase_in_call_volume !== 'queue-increase_in_call_volume') {
            throw new Error('Crossbar did not retain the complete valid announcement payload');
        }
        const createRosterResponse = await createRosterPromise;
        if (!createRosterResponse.ok()) throw new Error(`ACDC queue roster creation failed (HTTP ${createRosterResponse.status()})`);
        const createRouteResponse = await createRoutePromise;
        const createRouteBody = await createRouteResponse.json();
        createdRouteId = createRouteBody && createRouteBody.data && (createRouteBody.data.id || createRouteBody.data._id);
        if (!createRouteResponse.ok() || !/^[a-f0-9]{32}$/.test(createdRouteId || '')) {
            throw new Error(`ACDC managed route creation failed (HTTP ${createRouteResponse.status()})`);
        }
        const createdRouteIsStrict = await page.evaluate(({ route, queueId }) => {
            const monster = window.require('monster');
            return monster.apps.acdc.isStrictManagedRoute(route, queueId);
        }, { route: createRouteBody.data, queueId: createdQueueId });
        if (!createdRouteIsStrict) throw new Error('Created ACDC route did not retain its strict ownership shape');
        const initialRow = page.locator(`.acdc-edit-queue[data-id="${createdQueueId}"]`).locator('xpath=ancestor::tr');
        await initialRow.getByText(initialName, { exact: true }).waitFor({ state: 'visible', timeout: 30000 });

        await page.locator(`.acdc-edit-queue[data-id="${createdQueueId}"]`).click();
        await waitForAcdcContent(page, '.acdc-queue-form');
        const initiallySelected = await page.locator('.acdc-roster option:checked').evaluateAll(options => options.map(option => option.value).sort());
        if (JSON.stringify(initiallySelected) !== JSON.stringify(rosterIds)) {
            throw new Error('Created ACDC queue did not retain the exact two-agent roster');
        }
        if (await page.locator('.acdc-route-extension').inputValue() !== initialExtension) {
            throw new Error('Created ACDC queue did not retain its managed internal extension');
        }
        if (await page.locator('[name="moh"]').inputValue() !== 'local_stream://default'
            || await page.locator('.acdc-preconnect-announcement').inputValue() !== 'prompt://queue-you-are-next'
            || !(await page.locator('.acdc-position-announcements').isChecked())
            || !(await page.locator('.acdc-wait-announcements').isChecked())
            || await page.locator('.acdc-announcement-interval').inputValue() !== '45'
            || await page.locator('.acdc-announcement-language').inputValue() !== 'en-us') {
            throw new Error('Created ACDC announcement controls did not retain their values');
        }
        const invalidAnnouncementPayloads = [
            { announcements: { language: 'EN-us' } },
            { announcements: { interval: 14 } },
            { announcements: { media: { you_are_at_position: 42 } } },
            { announce: 42 }
        ];
        expectedValidationQueueId = createdQueueId;
        try {
            for (const { method, resource } of [
                { method: 'PATCH', resource: 'acdc.queues.update' },
                { method: 'POST', resource: 'acdc.queues.post' }
            ]) {
                for (const invalidPayload of invalidAnnouncementPayloads) {
                    const responsePromise = page.waitForResponse(
                        response => isApiPath(response, acceptance.account.id, `/queues/${createdQueueId}`, method),
                        { timeout: 30000 }
                    );
                    const validationPromise = writeQueueForValidation(
                        page, createdQueueId, invalidPayload, resource
                    );
                    const [validationResponse, validation] = await Promise.all([responsePromise, validationPromise]);
                    if (validationResponse.status() !== 400 || !validation.rejected) {
                        throw new Error(`Crossbar accepted an invalid ${method} announcement payload ${JSON.stringify(invalidPayload)}: HTTP ${validationResponse.status()}`);
                    }
                }
            }
        } finally {
            expectedValidationQueueId = undefined;
        }
        await page.locator('.acdc-queue-form [name="name"]').fill(editedName);
        await page.locator('.acdc-queue-form [name="strategy"]').selectOption('most_idle');
        await page.locator('.acdc-queue-form [name="agent_ring_timeout"]').fill('20');
        await page.locator('.acdc-position-announcements').uncheck();
        await page.locator('.acdc-preconnect-announcement').fill('prompt://queue-agent-ready');
        await page.locator('.acdc-announcement-interval').fill('60');
        await page.locator('.acdc-announcement-language').fill('');
        await page.locator('.acdc-route-extension').fill(editedExtension);

        const updateResponsePromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, `/queues/${createdQueueId}`, 'PATCH'),
            { timeout: 30000 }
        );
        const updateRosterPromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, `/queues/${createdQueueId}/roster`, 'POST'),
            { timeout: 30000 }
        );
        const updateRoutePromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, `/callflows/${createdRouteId}`, 'PATCH'),
            { timeout: 30000 }
        );
        await page.locator('.acdc-queue-form button[type="submit"]').click();
        browserStage = 'queue-update';
        const [updateResponse, updateRosterResponse, updateRouteResponse] = await Promise.all([
            updateResponsePromise,
            updateRosterPromise,
            updateRoutePromise
        ]);
        if (!updateResponse.ok() || !updateRosterResponse.ok() || !updateRouteResponse.ok()) {
            throw new Error('ACDC queue, roster, or managed route update failed');
        }
        const editedRow = page.locator(`.acdc-edit-queue[data-id="${createdQueueId}"]`).locator('xpath=ancestor::tr');
        await editedRow.getByText(editedName, { exact: true }).waitFor({ state: 'visible', timeout: 30000 });

        await page.locator(`.acdc-edit-queue[data-id="${createdQueueId}"]`).click();
        await waitForAcdcContent(page, '.acdc-queue-form');
        if (await page.locator('[name="strategy"]').inputValue() !== 'most_idle'
            || await page.locator('[name="agent_ring_timeout"]').inputValue() !== '20'
            || await page.locator('.acdc-route-extension').inputValue() !== editedExtension
            || await page.locator('[name="moh"]').inputValue() !== 'local_stream://default'
            || await page.locator('.acdc-preconnect-announcement').inputValue() !== 'prompt://queue-agent-ready'
            || await page.locator('.acdc-position-announcements').isChecked()
            || !(await page.locator('.acdc-wait-announcements').isChecked())
            || await page.locator('.acdc-announcement-interval').inputValue() !== '60'
            || await page.locator('.acdc-announcement-language').inputValue() !== '') {
            throw new Error('Edited ACDC queue settings did not persist');
        }
        const editedRoster = await page.locator('.acdc-roster option:checked').evaluateAll(options => options.map(option => option.value).sort());
        if (JSON.stringify(editedRoster) !== JSON.stringify(rosterIds)) {
            throw new Error('Edited ACDC queue did not retain the exact two-agent roster');
        }
        await page.locator('.acdc-cancel').first().click();
        await waitForAcdcContent(page, `.acdc-delete-queue[data-id="${createdQueueId}"]`);

        await page.locator(`.acdc-delete-queue[data-id="${createdQueueId}"]`).click();
        browserStage = 'managed-delete';
        const deleteResponsePromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, `/queues/${createdQueueId}`, 'DELETE'),
            { timeout: 30000 }
        );
        const deleteRoutePromise = page.waitForResponse(
            response => isApiPath(response, acceptance.account.id, `/callflows/${createdRouteId}`, 'DELETE'),
            { timeout: 30000 }
        );
        await confirmMonsterDialog(page);
        const [deleteResponse, deleteRouteResponse] = await Promise.all([deleteResponsePromise, deleteRoutePromise]);
        if (!deleteResponse.ok() || !deleteRouteResponse.ok()) {
            throw new Error(`ACDC queue or managed route deletion failed (HTTP ${deleteResponse.status()}/${deleteRouteResponse.status()})`);
        }
        await page.locator(`.acdc-delete-queue[data-id="${createdQueueId}"]`).waitFor({ state: 'detached', timeout: 30000 });
        createdQueueId = undefined;
        createdRouteId = undefined;

        const externalRouteAfter = await getCallflowSignature(page, acceptance.queue.callflowId);
        if (externalRouteAfter !== externalRouteBefore) {
            throw new Error('The externally provisioned ACDC route changed during managed route CRUD');
        }

        // Prove the UI refuses deletion when an externally managed route refers
        // to the queue. Route-level guards make this check non-destructive even
        // if a future regression tries the forbidden DELETE.
        let externalMutationAttempted = false;
        const blockExternalMutation = async route => {
            if (route.request().method() === 'DELETE') {
                externalMutationAttempted = true;
                await route.abort();
                return;
            }
            await route.continue();
        };
        const externalQueuePattern = `**/v2/accounts/${acceptance.account.id}/queues/${acceptance.queue.id}`;
        const externalCallflowPattern = `**/v2/accounts/${acceptance.account.id}/callflows/${acceptance.queue.callflowId}`;
        await page.route(externalQueuePattern, blockExternalMutation);
        await page.route(externalCallflowPattern, blockExternalMutation);
        try {
            const inventoryListPromise = page.waitForResponse(
                response => isApiPath(response, acceptance.account.id, '/callflows', 'GET'),
                { timeout: 30000 }
            );
            const externalRouteReadPromise = page.waitForResponse(
                response => isApiPath(response, acceptance.account.id, `/callflows/${acceptance.queue.callflowId}`, 'GET'),
                { timeout: 30000 }
            );
            await page.locator(`.acdc-delete-queue[data-id="${acceptance.queue.id}"]`).click();
            browserStage = 'external-delete-refusal';
            await confirmMonsterDialog(page);
            const [inventoryListResponse, externalRouteReadResponse] = await Promise.all([
                inventoryListPromise,
                externalRouteReadPromise
            ]);
            if (!inventoryListResponse.ok() || !externalRouteReadResponse.ok()) {
                throw new Error('Could not verify the externally routed queue before refusing deletion');
            }
            await new Promise(resolve => setTimeout(resolve, 750));
            if (externalMutationAttempted) {
                throw new Error('ACDC attempted to mutate an externally provisioned queue or route');
            }
            await page.locator(`.acdc-delete-queue[data-id="${acceptance.queue.id}"]`)
                .waitFor({ state: 'visible', timeout: 10000 });
        } finally {
            await page.unroute(externalQueuePattern, blockExternalMutation);
            await page.unroute(externalCallflowPattern, blockExternalMutation);
        }

        if (pageErrors.length) throw new Error(`Browser JavaScript errors: ${pageErrors.join('; ')}`);
        if (failedResponses.length) throw new Error(`Browser request failures: ${failedResponses.join('; ')}`);
        console.log(`PASS: Monster UI sign-in, ACDC catalog/load/masquerade, dashboard refresh, 30 agents, ${agentStatusTested ? 'agent status controls, ' : ''}announcement validation/CRUD, managed-route CRUD, and external-route deletion refusal`);
    } catch (error) {
        primaryError = error;
        if (pageErrors.length) primaryError.message += `; JavaScript errors: ${pageErrors.join('; ')}`;
    } finally {
        clearTimeout(deadline);
        if (page && reservedAgentNeedsLogout) {
            try {
                await forceAgentLogout(page, acceptance.agentIds[29]);
                await waitForAgentStatus(page, acceptance.agentIds[29], ['logout', 'logged_out']);
            } catch (cleanupError) {
                if (primaryError) primaryError.message += `; ${cleanupError.message}`;
                else primaryError = cleanupError;
            }
        }
        if (page && createdQueueId) {
            try {
                await removeQueueForCleanup(page, createdQueueId);
            } catch (cleanupError) {
                if (primaryError) primaryError.message += `; ${cleanupError.message}`;
                else primaryError = cleanupError;
            }
        }
        await browser.close();
    }
    if (primaryError) throw primaryError;
})().catch(error => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
});
