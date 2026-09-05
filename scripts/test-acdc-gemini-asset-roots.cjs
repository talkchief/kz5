#!/usr/bin/env node
'use strict';

// Read-only filesystem virtualization: installed prefixes are never created or
// changed. All approved audio bytes come from the checked-in pack next to this
// test. Generation writes, process execution and network access are forbidden.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict');
const sourceDir = __dirname;
const original = require('./import-acdc-gemini-voices.cjs');
const locales = require('./generate-acdc-gemini-samples.cjs').LOCALES;
const packNames = ['acdc-gemini-fixed-20260905', 'acdc-gemini-completion-20260905'];
const actualRoots = packNames.map(name => path.join(sourceDir, 'assets', name));
const compact = plan => plan.map(p => [p.id, p.sha256, p.md5, p.bytes.length, p.transcript_sha256]);
const expected = compact(original.loadPlan(...actualRoots, locales));
const failIO = name => () => { throw new Error(`Forbidden offline side effect: ${name}`); };
const matches = code => error => error.code === code;

function sandbox(prefix, faults = {}, baseline = false) {
  const virtualRoots = packNames.map(name => path.join(prefix, 'scripts/assets', name));
  const opened = new Map(), reads = [];
  function mapped(file) {
    assert.equal(typeof file, 'string', 'Only explicit file paths are allowed');
    const index = virtualRoots.findIndex(root => file === root || file.startsWith(root + '/'));
    assert(index >= 0, 'Read outside virtual checked-in assets');
    assert.equal(path.resolve(file), file, 'Unnormalized asset path');
    return actualRoots[index] + file.slice(virtualRoots[index].length);
  }
  const vfs = new Proxy({constants: fs.constants,
    lstatSync(file) {
      const stat = fs.lstatSync(mapped(file));
      if (faults.symlink?.(file)) return Object.assign(Object.create(stat), {isSymbolicLink: () => true});
      return stat;
    },
    realpathSync(file) {
      const actual = fs.realpathSync(mapped(file));
      assert.equal(actual, mapped(file), 'Physical checked-in asset uses a symlink');
      return faults.redirect?.(file) ? file + '-elsewhere' : file;
    },
    openSync(file, flags) {
      assert.equal(flags, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW, 'Write or unguarded open forbidden');
      const fd = fs.openSync(mapped(file), flags); opened.set(fd, file); reads.push(file); return fd;
    },
    fstatSync(fd) { assert(opened.has(fd)); return fs.fstatSync(fd); },
    readFileSync(fd) {
      assert(opened.has(fd), 'Reader must use its already-verified descriptor');
      const bytes = fs.readFileSync(fd); return faults.bytes ? faults.bytes(opened.get(fd), bytes) : bytes;
    },
    closeSync(fd) { assert(opened.has(fd)); opened.delete(fd); return fs.closeSync(fd); }
  }, {get(target, name) { return name in target ? target[name] : failIO(`fs.${String(name)}`); }});
  const cache = new Map();
  function load(filename) {
    filename = path.resolve(sourceDir, filename);
    assert.equal(path.dirname(filename), sourceDir);
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = {exports: {}}; cache.set(filename, module);
    let source = fs.readFileSync(filename, 'utf8').replace(/^#![^\n]*\n/, '');
    if (baseline && filename.endsWith('/generate-acdc-gemini-completion-pack.cjs')) {
      const start = source.indexOf('  // Reading checked-in assets');
      const end = source.indexOf("  const manifest = JSON.parse", start);
      assert(start >= 0 && end > start, 'Candidate-only reader delta not found');
      source = source.slice(0, start) + '  fixed.directoryTarget(directory, true);\n' + source.slice(end);
    }
    function isolatedRequire(name) {
      if (name.startsWith('./')) return load(name);
      if (name === 'node:fs') return vfs;
      if (['node:http', 'node:https', 'node:child_process'].includes(name))
        return new Proxy({}, {get: (_target, method) => failIO(`${name}.${String(method)}`)});
      return require(name);
    }
    const compiled = vm.runInThisContext(`(function(require,module,exports,__dirname,__filename){\n${source}\n})`, {filename});
    compiled(isolatedRequire, module, module.exports, sourceDir, filename);
    return module.exports;
  }
  return {roots: virtualRoots, reads, opened, load};
}

async function main() {
  assert.equal(expected.length, 165);
  for (const prefix of ['/opt/kazoo', '/usr/share/kazoo-source']) {
    const baseline = sandbox(prefix, {}, true);
    assert.throws(() => baseline.load('./import-acdc-gemini-voices.cjs').loadPlan(...baseline.roots, locales),
      matches('LIVE_OUTPUT_FORBIDDEN'));
    assert.equal(baseline.opened.size, 0);
    const env = sandbox(prefix), importer = env.load('./import-acdc-gemini-voices.cjs');
    assert.deepEqual(compact(importer.loadPlan(...env.roots, locales)), expected);
    assert.equal(env.opened.size, 0);
    assert(env.reads.some(file => file.endsWith('.wav')));
    assert.equal(importer.publicPlan(importer.loadPlan(...env.roots, locales)).runtime_ready, false);
    const fixed = env.load('./generate-acdc-gemini-fixed-pack.cjs');
    const completion = env.load('./generate-acdc-gemini-completion-pack.cjs');
    assert.throws(() => fixed.directoryTarget(env.roots[0], true), matches('LIVE_OUTPUT_FORBIDDEN'));
    await assert.rejects(fixed.generatePack({generate: true, concurrency: 1, output: env.roots[0], resume: true}),
      matches('LIVE_OUTPUT_FORBIDDEN'));
    await assert.rejects(completion.generate({generate: true, output: env.roots[1], resume: true,
      fixedPack: env.roots[0]}), matches('LIVE_OUTPUT_FORBIDDEN'));
    console.log(`PASS ${prefix}: baseline rejected import; candidate verifies identical165 assets; generators still refuse writes`);
  }
  const prefix = '/opt/kazoo', completionRoot = path.join(prefix, 'scripts/assets', packNames[1]);
  const cases = [
    ['symlink asset root', {symlink: file => file === completionRoot}, 'INVALID_ASSET_DIRECTORY'],
    ['symlink ancestor', {redirect: file => file === completionRoot}, 'INVALID_ASSET_DIRECTORY'],
    ['symlink audio', {symlink: file => file.endsWith('.wav')}, 'INVALID_OWNED_FILE'],
    ['symlink audio parent', {redirect: file => /\/(en-us|ar-sa|he-il|es-es|fr-fr)$/.test(file)}, 'SYMLINK_PARENT_FORBIDDEN'],
    ['changed completion owner', {bytes: (file, bytes) => {
      if (file !== path.join(completionRoot, 'manifest.json')) return bytes;
      const manifest = JSON.parse(bytes); manifest.owner = 'foreign-owner'; return Buffer.from(JSON.stringify(manifest));
    }}, 'UNOWNED_COMPLETION_PACK'],
    ['changed WAV bytes', {bytes: (file, bytes) => {
      if (!file.endsWith('.wav')) return bytes;
      const changed = Buffer.from(bytes); changed[changed.length - 1] ^= 1; return changed;
    }}, 'AUDIO_HASH_MISMATCH']
  ];
  for (const [label, faults, code] of cases) {
    const env = sandbox(prefix, faults);
    assert.throws(() => env.load('./import-acdc-gemini-voices.cjs').loadPlan(...env.roots, locales), matches(code), label);
    assert.equal(env.opened.size, 0, label); console.log(`PASS rejects ${label}`);
  }
  const env = sandbox(prefix), reader = env.load('./generate-acdc-gemini-completion-pack.cjs');
  for (const directory of ['scripts/assets', completionRoot + '/../' + packNames[1], completionRoot + '/'])
    assert.throws(() => reader.readManifest(directory), matches('ABSOLUTE_ASSET_DIRECTORY_REQUIRED'));
  console.log('PASS relative/unnormalized asset roots rejected; all tests read-only and provider-free');
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });
