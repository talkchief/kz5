#!/usr/bin/env node
'use strict';
// Temporary, independently buildable UI layer for the deployed legacy editor.
// It must not consume the staged aggregate-editor source or publish readiness.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict'), {execFileSync} = require('node:child_process');
const BASE = '57560824fc7457c0e506c3bbd416c64ec9be4562';
const INPUT_HASHES = {
    'app.js': 'df09ad88a554fe8f466e7e6219a61d748c26c80fdaa4f501c75275b8d4897475',
    'views/queue-form.html': '84e31bcdc6a3b5fbe792d993de29e2c794e4d53c156ca0e07b485f9526a30751',
    'i18n/en-US.json': '50c218d025b1e5debd4340ee9030acae5e562797e32a89d30bf1ee05ebb310c0'
};
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
function replaceOne(source, before, after) {
    assert.equal(source.split(before).length, 2, 'Baseline overlay anchor missing or ambiguous');
    return source.replace(before, after);
}
function overlay(files) {
    for (const [name, hash] of Object.entries(INPUT_HASHES)) assert.equal(digest(files[name]), hash, 'Unexpected baseline ' + name);
    const result = {...files};
    let source = files['app.js'].toString('utf8');
    source = replaceOne(source, "\t\t\tform.data('original-caller-id-source', source);", `\t\t\t// Keep removed recording controls private; PATCH omits their fields.
\t\t\tform.data('preserved-prompt-overrides', _.cloneDeep({
\t\t\t\tannouncements: _.get(queue, 'announcements.media'),
\t\t\t\tcallback: _.get(queue, 'callback.media'),
\t\t\t\treturn_confirmation_prompt: _.get(queue, 'callback.return_confirmation_prompt')
\t\t\t}));
\t\t\tform.data('original-caller-id-source', source);`);
    source = replaceOne(source, "\t\t\t\tcallback: {\n\t\t\t\t\tenabled: false,", `\t\t\t\tcallback: {
\t\t\t\t\tenabled: false,
\t\t\t\t\tannouncement: { enabled: true, initial_delay: 30, interval: 60 },`);
    source = replaceOne(source, `'[name="callback.enabled"], [name="callback.caller_id_source"]'`,
        `'[name="callback.enabled"], [name="callback.caller_id_source"], [name="callback.announcement.enabled"]'`);
    source = replaceOne(source, "\t\t\t\tcustom = form.find('[name=\"callback.caller_id_source\"]').val() === 'custom',", `\t\t\t\tannouncementEnabled = form.find('[name="callback.announcement.enabled"]').is(':checked'),
\t\t\t\tcustom = form.find('[name="callback.caller_id_source"]').val() === 'custom',`);
    source = replaceOne(source, "\t\t\tform.find('.acdc-callback-number').prop('required', enabled && custom);", `\t\t\tform.find('.acdc-callback-number').prop('required', enabled && custom);
\t\t\tform.find('.acdc-callback-announcement-timing').prop('disabled', !enabled || !announcementEnabled);`);
    source = replaceOne(source, "\t\t\t\tcallbackMedia = {},\n\t\t\t\tcallbackMediaKeys = ['offer', 'menu', 'number_readback', 'confirmation', 'success', 'returned_confirmation'],\n", '');
    source = replaceOne(source, "\t\t\t\t\tenabled: form.find('[name=\"callback.enabled\"]').is(':checked'),", `\t\t\t\t\tenabled: form.find('[name="callback.enabled"]').is(':checked'),
\t\t\t\t\tannouncement: { enabled: form.find('[name="callback.announcement.enabled"]').is(':checked') },`);
    const oldMedia = `\t\t\t\t\t\twait_time_announcements_enabled: form.find('[name="announcements.wait_time_announcements_enabled"]').is(':checked'),
\t\t\t\t\t\tmedia: {
\t\t\t\t\t\t\tyou_are_at_position: $.trim(form.find('[name="announcements.media.you_are_at_position"]').val()),
\t\t\t\t\t\t\tin_the_queue: $.trim(form.find('[name="announcements.media.in_the_queue"]').val()),
\t\t\t\t\t\t\tthe_estimated_wait_time_is: $.trim(form.find('[name="announcements.media.the_estimated_wait_time_is"]').val()),
\t\t\t\t\t\t\tincrease_in_call_volume: $.trim(form.find('[name="announcements.media.increase_in_call_volume"]').val())
\t\t\t\t\t\t}`;
    source = replaceOne(source, oldMedia, "\t\t\t\t\t\twait_time_announcements_enabled: form.find('[name=\"announcements.wait_time_announcements_enabled\"]').is(':checked')");
    source = replaceOne(source, `\t\t\t_.each(callbackMediaKeys, function(key) {
\t\t\t\tvar value = optionalMedia('callback.media.' + key);

\t\t\t\tif (value !== undefined) {
\t\t\t\t\tcallbackMedia[key] = value;
\t\t\t\t}
\t\t\t});
\t\t\tif (!_.isEmpty(callbackMedia)) {
\t\t\t\tcallbackConfig.media = callbackMedia;
\t\t\t}`, `\t\t\t// These timings are independent of position/wait announcements.
\t\t\t// Omitted inactive fields preserve the existing schedule on PATCH.
\t\t\tif (callbackConfig.enabled && callbackConfig.announcement.enabled) {
\t\t\t\tcallbackConfig.announcement.initial_delay = integerValue('callback.announcement.initial_delay');
\t\t\t\tcallbackConfig.announcement.interval = integerValue('callback.announcement.interval');
\t\t\t}
\t\t\t// Never emit removed prompt fields: create uses backend defaults, and
\t\t\t// PATCH preserves custom media, including legacy return confirmation.`);
    source = replaceOne(source, `\t\t\tif (isEdit) {
\t\t\t\t// PATCH null removes the obsolete field after its value has been
\t\t\t\t// normalized into callback.media.returned_confirmation.
\t\t\t\tcallbackConfig.return_confirmation_prompt = null;
\t\t\t}
`, '');
    assert(!/queues\/[^'\n]*editor|acdc\.queues\.editor/.test(source), 'Aggregate editor must remain outside baseline');
    result['app.js'] = Buffer.from(source);
    let template = files['views/queue-form.html'].toString('utf8');
    const lines = template.split('\n'), removed = lines.filter(line => /name="(?:announcements\.media\.|callback\.media\.)/.test(line));
    assert.equal(removed.length, 10, 'Expected exactly four announcement and six callback recording selectors');
    template = lines.filter(line => !removed.includes(line) && !/i18n\.acdc\.(?:announcements\.promptsTitle|callbacks\.mediaTitle)/.test(line)).join('\n');
    const enabledLine = lines.find(line => /class="acdc-callback-enabled"/.test(line));
    template = replaceOne(template, enabledLine, enabledLine + `
\t\t\t<label class="acdc-check acdc-callback-settings"><input type="checkbox" name="callback.announcement.enabled"{{#if queue.callback.announcement.enabled}} checked{{/if}}> <span>{{i18n.acdc.fields.callbackAnnouncementEnabled}}</span></label>
\t\t\t<label class="acdc-field acdc-callback-settings"><span>{{i18n.acdc.fields.callbackAnnouncementInitialDelay}}</span><input class="acdc-callback-announcement-timing" type="number" name="callback.announcement.initial_delay" min="1" max="3600" value="{{queue.callback.announcement.initial_delay}}" required><small>{{i18n.acdc.callbacks.announcementTimingHelp}}</small></label>
\t\t\t<label class="acdc-field acdc-callback-settings"><span>{{i18n.acdc.fields.callbackAnnouncementInterval}}</span><input class="acdc-callback-announcement-timing" type="number" name="callback.announcement.interval" min="15" max="3600" value="{{queue.callback.announcement.interval}}" required><small>{{i18n.acdc.callbacks.announcementDisabledHelp}}</small></label>`);
    template = replaceOne(template, '\t\t\t<div class="acdc-form-subsection acdc-field-wide"><h3>{{i18n.acdc.announcements.title}}</h3><p>{{i18n.acdc.announcements.description}}</p></div>',
        '\t\t\t<div class="acdc-form-subsection acdc-field-wide"><h3>{{i18n.acdc.announcements.title}}</h3><p>{{i18n.acdc.announcements.description}}</p><p>{{i18n.acdc.announcements.baselinePromptHelp}}</p></div>');
    result['views/queue-form.html'] = Buffer.from(template);
    const i18n = JSON.parse(files['i18n/en-US.json']);
    i18n.acdc.announcements.baselinePromptHelp = 'Standard prompts are selected by the server. Existing custom queue and callback recordings are preserved when you save; changing the language does not replace them. Only verified installed language packs can be selected.';
    Object.assign(i18n.acdc.fields, {
        callbackAnnouncementEnabled: 'Announce the callback option while callers wait',
        callbackAnnouncementInitialDelay: 'First callback announcement delay (seconds)',
        callbackAnnouncementInterval: 'Callback announcement interval (seconds)'
    });
    Object.assign(i18n.acdc.callbacks, {
        announcementTimingHelp: 'Schedule the callback option separately from queue-position and estimated-wait announcements. Their timing settings are unchanged.',
        announcementDisabledHelp: 'Turning this announcement off silences the callback offer only. Callers can still use the callback entry key while virtual callback is enabled.'
    });
    result['i18n/en-US.json'] = Buffer.from(JSON.stringify(i18n, null, '\t') + '\n');
    // A separately loaded production app must provide its own version file;
    // otherwise Monster falls back to a timestamp after an avoidable HTTP404.
    result.VERSION = Buffer.from('1.0.0-baseline.5756082\n');
    return result;
}
function readBaseline(repository = path.resolve(__dirname, '..')) {
    const names = execFileSync('git', ['ls-tree', '-rz', '--name-only', BASE, 'monster-ui/acdc'], {cwd: repository}).toString().split('\0').filter(Boolean);
    assert(names.length > 10 && names.length < 100);
    return Object.fromEntries(names.map(name => [name.slice('monster-ui/acdc/'.length), execFileSync('git', ['show', BASE + ':' + name], {cwd: repository})]));
}
function dependency(name, dependencyRoot) {
    return require(require.resolve(name, {paths: [dependencyRoot]}));
}
function compile(files, dependencyRoot) {
    const handlebars = dependency('handlebars', dependencyRoot), uglify = dependency('uglify-js', dependencyRoot);
    const sass = dependency('node-sass', dependencyRoot);
    let code = files['app.js'].toString() + '\nmonster.cache.templates.acdc = monster.cache.templates.acdc || {};\nmonster.cache.templates.acdc._main = monster.cache.templates.acdc._main || {};\n';
    for (const name of Object.keys(files).filter(name => /^views\/[^/]+\.html$/.test(name)).sort()) {
        code += 'monster.cache.templates.acdc._main[' + JSON.stringify(path.basename(name, '.html')) + '] = Handlebars.template(' + handlebars.precompile(files[name].toString()) + ');\n';
    }
    const minified = uglify.minify(code); assert(!minified.error, 'Baseline minification failed');
    const dist = Object.fromEntries(Object.entries(files).filter(([name]) => /^(?:metadata|i18n)\//.test(name)));
    dist['app.js'] = Buffer.from(minified.code + '\n');
    dist['style/app.css'] = sass.renderSync({data: files['style/app.scss'].toString(), outputStyle: 'compressed'}).css;
    dist['app-build-config.json'] = Buffer.from('{"version":"standard"}\n');
    dist.VERSION = files.VERSION;
    assert(!Object.hasOwn(dist, 'language-capabilities.json'));
    return {dist, versions: {node: process.versions.node, handlebars: handlebars.VERSION, uglify: dependency('uglify-js/package.json', dependencyRoot).version,
        sass: dependency('node-sass/package.json', dependencyRoot).version}};
}
function build(parent, dependencyRoot) {
    assert(path.isAbsolute(parent) && fs.lstatSync(parent).isDirectory() && !fs.lstatSync(parent).isSymbolicLink());
    const source = overlay(readBaseline()), compiled = compile(source, dependencyRoot);
    const destination = fs.mkdtempSync(path.join(parent, 'monster-acdc-baseline-'));
    fs.chmodSync(destination, 0o700);
    const hashes = {};
    for (const [prefix, files] of [['src/apps/acdc', source], ['dist/apps/acdc', compiled.dist]]) {
        for (const [name, bytes] of Object.entries(files)) {
            const relative = prefix + '/' + name, filename = path.join(destination, relative);
            assert(filename.startsWith(destination + '/') && !relative.includes('..'));
            fs.mkdirSync(path.dirname(filename), {recursive: true});
            fs.writeFileSync(filename, bytes, {flag: 'wx', mode: 0o644}); hashes[relative] = digest(bytes);
        }
    }
    const manifest = {schema_version: 1, release_type: 'temporary-legacy-editor-overlay', base_commit: BASE,
        overlay_sha256: digest(fs.readFileSync(__filename)),
        aggregate_editor_included: false, language_readiness_published: false, live_deployment_performed: false,
        build_dependencies: compiled.versions, files: hashes};
    fs.writeFileSync(path.join(destination, 'baseline-build.json'), JSON.stringify(manifest, null, 2) + '\n', {flag: 'wx', mode: 0o600});
    return destination;
}
if (require.main === module) {
    const [parent = '/usr/local/src/kazoo5-installer', dependencyRoot = '/usr/local/src/kazoo5-installer/monster-ui'] = process.argv.slice(2);
    assert(process.argv.length <= 4, 'Usage: build-acdc-baseline-ui.cjs [PRIVATE_PARENT] [EXISTING_MONSTER_DEPENDENCIES]');
    console.log(build(parent, dependencyRoot));
}
module.exports = {BASE, INPUT_HASHES, overlay, readBaseline, compile, build, digest};
