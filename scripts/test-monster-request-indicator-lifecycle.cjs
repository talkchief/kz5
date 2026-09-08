'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const vm = require('node:vm'), cp = require('node:child_process');
const input = process.argv[2];
assert(input, 'Supply pinned Monster UI src/apps/core/app.js');
const before = fs.readFileSync(input, 'utf8');
const patch = path.join(__dirname, 'patches/monster-ui-request-indicator-lifecycle.patch');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-request-indicator.'));
function fixture(source) {
    const block = source.split('\t\tonRequestStart: function(args) {')[1].split('\t\tinitializeShortcuts:')[0];
    assert(block, 'Actual request indicator handlers not found');
    let clock = 0, next = 0, active = false;
    const timers = new Map();
    const handlers = vm.runInNewContext('({onRequestStart: function(args) {' + block + '})', {
        Math, _: {get: (obj, key, fallback) => obj[key] === undefined ? fallback : obj[key]},
        setTimeout: (fn, delay) => {const id = ++next; timers.set(id, {fn, at: clock + delay}); return id;},
        clearTimeout: id => timers.delete(id)
    });
    handlers.request = {counter: 0, active: false}; handlers.indicator = {};
    const indicator = {hasClass: () => active, addClass: () => {active = true;}, removeClass: () => {active = false;}};
    function tick(ms) {
        const end = clock + ms;
        for (;;) {
            const pending = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
            if (!pending) break;
            clock = pending[1].at; timers.delete(pending[0]); pending[1].fn();
        }
        clock = end;
    }
    return {handlers, tick, active: () => active,
        start: (bypass = false) => handlers.onRequestStart({indicator, bypassProgressIndicator: bypass}),
        end: (bypass = false) => handlers.onRequestEnd({indicator, bypassProgressIndicator: bypass})};
}
try {
    const old = fixture(before);
    old.end(); old.tick(300);
    assert.equal(old.handlers.request.counter, -1, 'Reproduce unmatched completion underflow');
    old.start(); old.end(); old.tick(500);
    assert.equal(old.active(), true, 'Reproduce stuck top blue line');
    const target = path.join(scratch, 'src/apps/core/app.js');
    fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, before);
    cp.execFileSync('git', ['apply', '--check', patch], {cwd: scratch});
    cp.execFileSync('git', ['apply', patch], {cwd: scratch});
    cp.execFileSync('git', ['apply', '--reverse', '--check', patch], {cwd: scratch});
    const after = fs.readFileSync(target, 'utf8');
    const f = fixture(after);
    f.end(); f.tick(300); assert.equal(f.handlers.request.counter, 0); assert.equal(f.active(), false);
    f.start(); f.start(); f.tick(250); assert.equal(f.active(), true);
    f.end(); f.tick(100); assert.equal(f.active(), true); assert.equal(f.handlers.request.counter, 1);
    f.end(); f.end(); f.tick(500); assert.equal(f.active(), false); assert.equal(f.handlers.request.counter, 0);
    f.start(true); f.end(true); f.tick(300); assert.equal(f.active(), false); assert.equal(f.handlers.request.counter, 0);
    f.start(); f.tick(20); f.end(); f.tick(300); assert.equal(f.active(), false);
    f.start(); f.tick(250); f.end(); f.tick(10); f.start(); f.tick(100); assert.equal(f.active(), true);
    f.end(); f.tick(300); assert.equal(f.active(), false);
    f.handlers.request.counter = -1; f.start(); f.tick(250);
    assert.equal(f.handlers.request.counter, 1); assert.equal(f.active(), true);
    f.end(); f.tick(300); assert.equal(f.active(), false); assert.equal(f.handlers.request.active, false);
    const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
    assert(installer.includes('monster-ui-request-indicator-lifecycle.patch:patches/monster-ui-request-indicator-lifecycle.patch'));
    assert(installer.includes('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-request-indicator-lifecycle.patch"'));
    console.log('PASS before-fix stuck indicator, unmatched/duplicate end, overlap, bypass, fast completion, replacement, underflow recovery and installer wiring');
} finally {fs.rmSync(scratch, {recursive: true, force: true});}
