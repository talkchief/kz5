'use strict';
// Package/deploy only one allowlisted custom component from a completed gulp
// build-app stage. The shared production AMD bundle changes only at the exact
// named define() call for this app. Other apps, config, templates, and CSS are
// never rebuilt or copied. Backups permit exact rollback.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const acorn = require('/usr/local/src/kazoo5-installer/monster-ui/node_modules/acorn');
const [app, stage, backup] = process.argv.slice(2);
assert(['acdc', 'callflows'].includes(app), 'Only acdc or callflows may be deployed');
assert(stage && backup && path.isAbsolute(stage) && path.isAbsolute(backup), 'Absolute stage/backup paths required');
assert(fs.statSync(backup).isDirectory() && fs.readdirSync(backup).length === 0, 'Backup must be an empty private directory');
const web = '/var/www/html/monster-ui';
const mainPath = path.join(web, 'js/main.js'), configPath = path.join(web, 'build-config.json');
const appPath = path.join(web, 'apps', app), builtApp = path.join(stage, 'dist/apps', app);
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
function snapshot(root, ignore) {
    const files = {};
    function visit(directory, relative = '') {
        for (const entry of fs.readdirSync(directory).sort()) {
            const name = relative ? relative + '/' + entry : entry;
            if (ignore && ignore(name)) continue;
            const target = path.join(directory, entry), stat = fs.lstatSync(target);
            assert(!stat.isSymbolicLink(), 'Refusing web component symlink');
            if (stat.isDirectory()) visit(target, name);
            else if (stat.isFile()) files[name] = sha(fs.readFileSync(target));
        }
    }
    visit(root); return files;
}
function publicModes(root) {
    fs.chmodSync(root, 0o755);
    for (const entry of fs.readdirSync(root)) {
        const file = path.join(root, entry), stat = fs.lstatSync(file);
        assert(!stat.isSymbolicLink(), 'Refusing built component symlink');
        if (stat.isDirectory()) publicModes(file);
        else fs.chmodSync(file, 0o644);
    }
}
const source = fs.readFileSync(mainPath, 'utf8'), configSource = fs.readFileSync(configPath, 'utf8');
const tree = acorn.parse(source, {ecmaVersion: 2018}), definitions = [], stack = [tree];
while (stack.length) {
    const node = stack.pop();
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier' && node.callee.name === 'define'
        && node.arguments[0] && node.arguments[0].type === 'Literal'
        && node.arguments[0].value === `apps/${app}/app`) definitions.push(node);
    for (const value of Object.values(node)) {
        if (Array.isArray(value)) {
            for (const child of value) if (child && typeof child.type === 'string') stack.push(child);
        } else if (value && typeof value.type === 'string') stack.push(value);
    }
}
assert(definitions.length <= 1, 'Ambiguous duplicate embedded app definitions');
assert(definitions.length === 1 || fs.existsSync(path.join(appPath, 'app.js')), 'No embedded or standalone app to update');
const span = definitions[0];
const nextMain = span ? source.slice(0, span.start) + 'void 0' + source.slice(span.end) : source;
acorn.parse(nextMain, {ecmaVersion: 2018});
acorn.parse(fs.readFileSync(path.join(builtApp, 'app.js'), 'utf8'), {ecmaVersion: 2018});
const config = JSON.parse(configSource);
for (const key of ['preloadApps', 'preloadedApps']) {
    if (Array.isArray(config[key])) config[key] = config[key].filter(name => name !== app);
}
const nextConfig = JSON.stringify(config);
const unaffected = relative => relative === 'js/main.js' || relative === 'build-config.json' || relative === `apps/${app}`;
const before = snapshot(web, unaffected);
const stagedHash = snapshot(builtApp);
fs.copyFileSync(mainPath, path.join(backup, 'main.js'));
fs.copyFileSync(configPath, path.join(backup, 'build-config.json'));
fs.cpSync(appPath, path.join(backup, app), {recursive: true, errorOnExist: true});
const stagedDirectory = fs.mkdtempSync(path.join(web, 'apps', `.${app}-deploy-`));
fs.cpSync(builtApp, stagedDirectory, {recursive: true});
publicModes(stagedDirectory);
assert.deepEqual(snapshot(stagedDirectory), stagedHash, 'Built component staging differs');
// Detect concurrent edits before making any live replacement.
assert.equal(fs.readFileSync(mainPath, 'utf8'), source, 'Shared AMD bundle changed during staging');
assert.equal(fs.readFileSync(configPath, 'utf8'), configSource, 'Build configuration changed during staging');
assert.deepEqual(snapshot(web, relative => unaffected(relative) || relative === 'apps/' + path.basename(stagedDirectory)), before,
    'Another web component changed while preparing this deployment');
// Generated build artifacts are mechanically transformed; preserve all bytes
// outside the named AMD define() expression and all unrelated preload entries.
fs.writeFileSync(path.join(backup, 'next-main.js'), nextMain, {mode: 0o600});
fs.writeFileSync(path.join(backup, 'next-build-config.json'), nextConfig, {mode: 0o600});
fs.renameSync(appPath, path.join(backup, `${app}-original`));
fs.renameSync(stagedDirectory, appPath);
fs.writeFileSync(mainPath, nextMain, {mode: 0o644});
fs.writeFileSync(configPath, nextConfig, {mode: 0o644});
fs.chmodSync(mainPath, 0o644); fs.chmodSync(configPath, 0o644);
assert.deepEqual(snapshot(web, unaffected), before, 'An unrelated web artifact changed during deployment');
assert.deepEqual(snapshot(appPath), stagedHash, 'Deployed component does not match built stage');
const manifest = {component: app, deployed_at: new Date().toISOString(), stage, rollback_directory: backup,
    embedded_amd_definitions_removed: definitions.length, shared_main_before_sha256: sha(source),
    shared_main_after_sha256: sha(nextMain), untouched_files_verified: Object.keys(before).length,
    build_config_before_sha256: sha(configSource), build_config_after_sha256: sha(nextConfig), files: stagedHash};
fs.writeFileSync(path.join(backup, 'component-manifest.json'), JSON.stringify(manifest, null, 2) + '\n', {mode: 0o600});
const manifestPath = `/usr/local/share/kazoo5-installer/monster-ui-${app}-component.json`;
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', {mode: 0o644});
console.log(JSON.stringify({result: 'PASS', component: app, manifest: manifestPath, backup,
    unchanged_other_files: manifest.untouched_files_verified, removed_amd_definitions: definitions.length,
    component_files: Object.keys(stagedHash).length}));
