'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const root = process.env.KZ5_BROWSER_TOOLS;
assert(root && path.isAbsolute(root));
assert.equal(process.version, 'v22.23.2');
assert.equal(require(path.join(root, 'node_modules/playwright/package.json')).version, '1.62.1');
(async () => {
    const {chromium} = require(path.join(root, 'node_modules/playwright'));
    const browser = await chromium.launch({headless: true,
        args: ['--no-sandbox', '--disable-dev-shm-usage']});
    try {
        assert.equal(browser.version(), '151.0.7922.34');
        const page = await browser.newPage();
        await page.route('**/*', route => route.abort());
        await page.setContent('<title>Kazoo browser smoke</title><button>Ready</button>');
        assert.equal(await page.title(), 'Kazoo browser smoke');
        assert.equal(await page.locator('button').innerText(), 'Ready');
        console.log('PASS: private Node 22.23.2 / Playwright 1.62.1 / Chromium 151.0.7922.34; offline DOM smoke');
    } finally { await browser.close(); }
})().catch(() => {console.error('Browser toolchain smoke failed'); process.exitCode = 1;});
