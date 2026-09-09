'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {assertInstalledSources} = require('./test-acdc-native-maintenance.cjs');
const old = 'a'.repeat(40), next = 'b'.repeat(40);
test('accept matching successfully collected install source', () => {
    assertInstalledSources({source: next, installedSource: next}, {source: next, installedSource: next});
});
test('source synchronization alone never proves deployment', () => {
    assert.throws(() => assertInstalledSources({source: next, installedSource: old}, {source: next, installedSource: next}));
    assert.throws(() => assertInstalledSources({source: next, installedSource: next}, {source: next, installedSource: old}));
});
test('missing install attestation and mismatched node sources fail closed', () => {
    assert.throws(() => assertInstalledSources({source: next}, {source: next, installedSource: next}));
    assert.throws(() => assertInstalledSources({source: old, installedSource: old}, {source: next, installedSource: next}));
    assert.throws(() => assertInstalledSources({source: 'invalid', installedSource: 'invalid'}, {source: 'invalid', installedSource: 'invalid'}));
});
